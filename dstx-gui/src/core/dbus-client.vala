/*
 * dbus-client.vala - D-Bus client for communication with dstx-dbus-bridge
 *
 * Copyright (C) 2026 André Lameira
 *
 * This program is free software: you can redistribute it and/or modify
 * it under the terms of the GNU General Public License as published by
 * the Free Software Foundation, either version 3 of the License, or
 * (at your option) any later version.
 *
 * This program is distributed in the hope that it will be useful,
 * but WITHOUT ANY WARRANTY; without even the implied warranty of
 * MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
 * GNU General Public License for more details.
 *
 * You should have received a copy of the GNU General Public License
 * along with this program.  If not, see <https://www.gnu.org/licenses/>.
 *
 * RESPONSIBILITIES:
 * - Manage D-Bus connection to dstx-dbus-bridge
 * - Provide async methods for controller operations (LED, rumble, sticks, triggers, keybinds, layouts, emulation)
 * - Handle D-Bus signals (controller events, telemetry, button/axis updates)
 * - Profile management and core service control
 */

// src/core/dbus-client.vala

using Dstx.Models;

namespace Dstx.Core {
    public class DBusClient : Object {
        private const string DBUS_NAME = "org.dstx.Bridge";
        private const string DBUS_PATH = "/org/dstx/Bridge";
        private const string DBUS_INTERFACE = "org.dstx.Bridge";
        
        private DBusConnection? connection;
        private DstxDBus? proxy;
        
        private bool _is_connected = false;
        
        public bool is_connected {
            get { return _is_connected; }
            private set {
                if (_is_connected != value) {
                    _is_connected = value;
                    if (value) {
                        message("DBusClient: Connection established");
                    }
                }
            }
        }
        
        public signal void daemon_status_changed(bool alive);
        public signal void controller_connected(uint8 slot);
        public signal void controller_disconnected(uint8 slot);
        public signal void controller_updated(uint8 slot);
        
        public signal void telemetry_update(uint8 slot, int16 lx, int16 ly, int16 rx, int16 ry,
                                            int16 lt, int16 rt, int16 hatx, int16 haty, uint16 buttons);
        public signal void button_update(uint8 slot, uint16 buttons);
        public signal void axis_update(uint8 slot, int16 lx, int16 ly, int16 rx, int16 ry,
                                       int16 lt, int16 rt, int16 hatx, int16 haty);
        
        private bool _daemon_alive = false;
        public bool daemon_alive {
            get { return _daemon_alive; }
            private set {
                if (_daemon_alive != value) {
                    _daemon_alive = value;
                    daemon_status_changed(value);
                }
            }
        }
        
        private uint signal_subscription_id = 0;
        
        public DBusClient() {
            message("DBusClient: Initializing...");
            connect_to_dbus.begin();
        }
        
        private async void connect_to_dbus() {
            try {
                message("DBusClient: Connecting to system bus...");
                connection = yield Bus.get(BusType.SYSTEM);
                
                message("DBusClient: Creating proxy for %s %s", DBUS_NAME, DBUS_PATH);
                proxy = yield connection.get_proxy<DstxDBus>(
                    DBUS_NAME,
                    DBUS_PATH,
                    DBusProxyFlags.NONE,
                    null
                );
                
                if (proxy != null) {
                    message("DBusClient: D-Bus proxy created successfully");
                    is_connected = true;
                    
                    if (signal_subscription_id != 0) {
                        connection.signal_unsubscribe(signal_subscription_id);
                    }
                    
                    signal_subscription_id = connection.signal_subscribe(
                        DBUS_NAME,
                        DBUS_INTERFACE,
                        null,
                        DBUS_PATH,
                        null,
                        DBusSignalFlags.NONE,
                        on_dbus_signal
                    );
                    
                    message("DBusClient: Subscribed to signals (subscription_id=%u)", signal_subscription_id);
                    
                    daemon_alive = true;
                    message("DBusClient: D-Bus connection established (bridge active)");
                }
                
            } catch (Error e) {
                warning("DBusClient: Error connecting to D-Bus: %s", e.message);
                is_connected = false;
                daemon_alive = false;
                
                Timeout.add_seconds(5, () => {
                    message("DBusClient: Attempting to reconnect...");
                    connect_to_dbus.begin();
                    return Source.REMOVE;
                });
            }
        }
        
        private void on_dbus_signal(DBusConnection connection,
                                    string? sender_name,
                                    string object_path,
                                    string interface_name,
                                    string signal_name,
                                    Variant parameters) {
            if (parameters == null) {
                warning("DBusClient: parameters are null for signal %s", signal_name);
                return;
            }
            
            try {
                switch (signal_name) {
                    case "ControllerConnected":
                        if (parameters.n_children() > 0) {
                            Variant slot_variant = parameters.get_child_value(0);
                            if (slot_variant.is_of_type(VariantType.BYTE)) {
                                uint8 slot = slot_variant.get_byte();
                                controller_connected(slot);
                            }
                        }
                        break;
                        
                    case "ControllerDisconnected":
                        if (parameters.n_children() > 0) {
                            Variant slot_variant = parameters.get_child_value(0);
                            if (slot_variant.is_of_type(VariantType.BYTE)) {
                                uint8 slot = slot_variant.get_byte();
                                controller_disconnected(slot);
                            }
                        }
                        break;
                        
                    case "ControllerUpdated":
                        if (parameters.n_children() > 0) {
                            Variant slot_variant = parameters.get_child_value(0);
                            if (slot_variant.is_of_type(VariantType.BYTE)) {
                                uint8 slot = slot_variant.get_byte();
                                controller_updated(slot);
                            }
                        }
                        break;
                        
                    case "DaemonStatusChanged":
                        if (parameters.n_children() > 0) {
                            Variant alive_variant = parameters.get_child_value(0);
                            if (alive_variant.is_of_type(VariantType.BOOLEAN)) {
                                bool alive = alive_variant.get_boolean();
                                daemon_alive = alive;
                            }
                        }
                        break;
                    
                    case "TelemetryUpdate":
                        if (parameters.n_children() >= 10) {
                            uint8 slot = parameters.get_child_value(0).get_byte();
                            int16 lx = (int16)parameters.get_child_value(1).get_int16();
                            int16 ly = (int16)parameters.get_child_value(2).get_int16();
                            int16 rx = (int16)parameters.get_child_value(3).get_int16();
                            int16 ry = (int16)parameters.get_child_value(4).get_int16();
                            int16 lt = (int16)parameters.get_child_value(5).get_int16();
                            int16 rt = (int16)parameters.get_child_value(6).get_int16();
                            int16 hatx = (int16)parameters.get_child_value(7).get_int16();
                            int16 haty = (int16)parameters.get_child_value(8).get_int16();
                            uint16 buttons = parameters.get_child_value(9).get_uint16();
                            telemetry_update(slot, lx, ly, rx, ry, lt, rt, hatx, haty, buttons);
                        }
                        break;
                        
                    case "ButtonUpdate":
                        if (parameters.n_children() >= 2) {
                            uint8 slot = parameters.get_child_value(0).get_byte();
                            uint16 buttons = parameters.get_child_value(1).get_uint16();
                            button_update(slot, buttons);
                        }
                        break;
                        
                    case "AxisUpdate":
                        if (parameters.n_children() >= 9) {
                            uint8 slot = parameters.get_child_value(0).get_byte();
                            int16 lx = (int16)parameters.get_child_value(1).get_int16();
                            int16 ly = (int16)parameters.get_child_value(2).get_int16();
                            int16 rx = (int16)parameters.get_child_value(3).get_int16();
                            int16 ry = (int16)parameters.get_child_value(4).get_int16();
                            int16 lt = (int16)parameters.get_child_value(5).get_int16();
                            int16 rt = (int16)parameters.get_child_value(6).get_int16();
                            int16 hatx = (int16)parameters.get_child_value(7).get_int16();
                            int16 haty = (int16)parameters.get_child_value(8).get_int16();
                            axis_update(slot, lx, ly, rx, ry, lt, rt, hatx, haty);
                        }
                        break;
                        
                    default:
                        break;
                }
            } catch (Error e) {
                warning("DBusClient: Error processing signal %s: %s", signal_name, e.message);
            }
        }
        
        // ==================== READ METHODS ====================
        
        public async uint8[] get_controllers() throws Error {
            if (proxy == null) {
                warning("DBusClient: Proxy is null, attempting to reconnect...");
                yield connect_to_dbus();
                if (proxy == null) {
                    throw new DBusError.FAILED("D-Bus not connected");
                }
            }
            
            try {
                message("DBusClient: Calling GetControllers...");
                var result = yield proxy.get_controllers();
                message("DBusClient: GetControllers returned %d slots", result.length);
                return result;
            } catch (Error e) {
                warning("DBusClient: Error in get_controllers: %s", e.message);
                throw e;
            }
        }
        
        public async Controller get_controller_info(uint8 slot) throws Error {
            if (connection == null) throw new DBusError.FAILED("D-Bus not connected");
            
            var controller = new Controller((int)slot);
            
            try {
                var result = yield connection.call(
                    DBUS_NAME,
                    DBUS_PATH,
                    DBUS_INTERFACE,
                    "GetControllerInfo",
                    new Variant("(y)", slot),
                    null,
                    DBusCallFlags.NONE,
                    -1,
                    null
                );
                
                if (result == null) {
                    warning("DBusClient: null result for slot %d", slot);
                    return controller;
                }
                
                uint32[] values = {};
                for (size_t i = 0; i < result.n_children(); i++) {
                    var child = result.get_child_value(i);
                    if (child.is_of_type(VariantType.UINT32)) {
                        values += child.get_uint32();
                    } else if (child.is_of_type(VariantType.INT32)) {
                        values += (uint32)child.get_int32();
                    }
                }
                
                controller.update_from_dbus_arguments(values);
                
            } catch (Error e) {
                warning("DBusClient: Error in get_controller_info: %s", e.message);
            }
            
            return controller;
        }
        
        public async ControllerDetailedInfo? get_detailed_controller_info(uint8 slot) throws Error {
            if (connection == null) {
                warning("DBusClient: connection is null");
                throw new DBusError.FAILED("D-Bus not connected");
            }
            
            message("DBusClient: Fetching detailed information for slot %d", slot);
            
            try {
                var result = yield connection.call(
                    DBUS_NAME,
                    DBUS_PATH,
                    DBUS_INTERFACE,
                    "GetDetailedInfo",
                    new Variant("(y)", slot),
                    new VariantType("(sssa(ss))"),
                    DBusCallFlags.NONE,
                    -1,
                    null
                );
                
                if (result == null) {
                    warning("DBusClient: Call returned null");
                    return null;
                }
                
                var info = new ControllerDetailedInfo();
                
                if (result.n_children() >= 1) {
                    var child0 = result.get_child_value(0);
                    if (child0.is_of_type(VariantType.STRING)) {
                        info.product_name = child0.get_string();
                    }
                }
                
                if (result.n_children() >= 2) {
                    var child1 = result.get_child_value(1);
                    if (child1.is_of_type(VariantType.STRING)) {
                        info.serial = child1.get_string();
                    }
                }
                
                if (result.n_children() >= 3) {
                    var child2 = result.get_child_value(2);
                    if (child2.is_of_type(VariantType.STRING)) {
                        info.driver = child2.get_string();
                    }
                }
                
                if (result.n_children() >= 4) {
                    var child3 = result.get_child_value(3);
                    if (child3.is_of_type(VariantType.ARRAY)) {
                        VariantIter nodes_iter = child3.iterator();
                        Variant? node = null;
                        while ((node = nodes_iter.next_value()) != null) {
                            if (node.is_of_type(VariantType.TUPLE) && node.n_children() >= 2) {
                                string path = node.get_child_value(0).get_string();
                                string name = node.get_child_value(1).get_string();
                                info.add_input_node(path, name);
                            }
                        }
                    }
                }
                
                return info;
                
            } catch (Error e) {
                warning("DBusClient: Error in get_detailed_controller_info: %s", e.message);
                throw e;
            }
        }
        
        // ==================== METHOD: GET TELEMETRY ====================
        
        public async void get_telemetry(uint8 slot,
                                        out int16 lx, out int16 ly,
                                        out int16 rx, out int16 ry,
                                        out int16 lt, out int16 rt,
                                        out int16 hatx, out int16 haty,
                                        out uint16 buttons) throws Error {
            lx = ly = rx = ry = lt = rt = hatx = haty = 0;
            buttons = 0;
            
            if (connection == null) throw new DBusError.FAILED("D-Bus not connected");
            
            var result = yield connection.call(
                DBUS_NAME,
                DBUS_PATH,
                DBUS_INTERFACE,
                "GetTelemetry",
                new Variant("(y)", slot),
                new VariantType("(iiiiiiiiq)"),
                DBusCallFlags.NONE,
                -1,
                null
            );
            
            if (result != null && result.n_children() >= 9) {
                lx = (int16)result.get_child_value(0).get_int16();
                ly = (int16)result.get_child_value(1).get_int16();
                rx = (int16)result.get_child_value(2).get_int16();
                ry = (int16)result.get_child_value(3).get_int16();
                lt = (int16)result.get_child_value(4).get_int16();
                rt = (int16)result.get_child_value(5).get_int16();
                hatx = (int16)result.get_child_value(6).get_int16();
                haty = (int16)result.get_child_value(7).get_int16();
                buttons = result.get_child_value(8).get_uint16();
            }
        }
        
        // ==================== INVERSION METHODS ====================
        
        public async void set_invert_ly(uint8 slot, bool enable) throws Error {
            if (proxy == null) throw new DBusError.FAILED("D-Bus not connected");
            yield proxy.set_invert_ly(slot, enable);
        }
        
        public async void set_invert_ry(uint8 slot, bool enable) throws Error {
            if (proxy == null) throw new DBusError.FAILED("D-Bus not connected");
            yield proxy.set_invert_ry(slot, enable);
        }
        
        public async void get_invert_status(uint8 slot, out bool invert_ly, out bool invert_ry) throws Error {
            invert_ly = false;
            invert_ry = false;
            
            if (connection == null) throw new DBusError.FAILED("D-Bus not connected");
            
            var result = yield connection.call(
                DBUS_NAME,
                DBUS_PATH,
                DBUS_INTERFACE,
                "GetInvertStatus",
                new Variant("(y)", slot),
                new VariantType("(bb)"),
                DBusCallFlags.NONE,
                -1,
                null
            );
            
            if (result != null && result.n_children() >= 2) {
                invert_ly = result.get_child_value(0).get_boolean();
                invert_ry = result.get_child_value(1).get_boolean();
            }
        }
        
        // ==================== SENSITIVITY METHODS ====================
        
        public async void set_sensitivity_preset_left(uint8 slot, uint8 preset) throws Error {
            if (proxy == null) throw new DBusError.FAILED("D-Bus not connected");
            yield proxy.set_sensitivity_preset_left(slot, preset);
        }
        
        public async void set_sensitivity_preset_right(uint8 slot, uint8 preset) throws Error {
            if (proxy == null) throw new DBusError.FAILED("D-Bus not connected");
            yield proxy.set_sensitivity_preset_right(slot, preset);
        }
        
        public async void get_sensitivity_preset(uint8 slot, out uint8 left_preset, out uint8 right_preset) throws Error {
            left_preset = 0;
            right_preset = 0;
            
            if (connection == null) throw new DBusError.FAILED("D-Bus not connected");
            
            var result = yield connection.call(
                DBUS_NAME,
                DBUS_PATH,
                DBUS_INTERFACE,
                "GetSensitivityPreset",
                new Variant("(y)", slot),
                new VariantType("(yy)"),
                DBusCallFlags.NONE,
                -1,
                null
            );
            
            if (result != null && result.n_children() >= 2) {
                left_preset = result.get_child_value(0).get_byte();
                right_preset = result.get_child_value(1).get_byte();
            }
        }
        
        // ==================== LED CONFIGURATION METHODS ====================
        
        public async void set_led(uint8 slot, uint8 r, uint8 g, uint8 b) throws Error {
            if (proxy == null) throw new DBusError.FAILED("D-Bus not connected");
            yield proxy.set_led(slot, r, g, b);
        }
        
        public async void set_effect(uint8 slot, uint8 effect, uint8 speed, uint8 brightness) throws Error {
            if (proxy == null) throw new DBusError.FAILED("D-Bus not connected");
            yield proxy.set_effect(slot, effect, speed, brightness);
        }
        
        public async void set_led_reapply(uint8 slot, bool enable) throws Error {
            if (proxy == null) throw new DBusError.FAILED("D-Bus not connected");
            yield proxy.set_led_reapply(slot, enable);
        }
        
        public async void set_global_brightness(uint8 slot, uint8 brightness) throws Error {
            if (proxy == null) throw new DBusError.FAILED("D-Bus not connected");
            yield proxy.set_global_brightness(slot, brightness);
        }
        
        public async void set_player_leds(uint8 slot, uint8 mode) throws Error {
            if (proxy == null) throw new DBusError.FAILED("D-Bus not connected");
            yield proxy.set_player_leds(slot, mode);
        }
        
        // ==================== RUMBLE CONFIGURATION METHODS ====================
        
        public async void set_gain(uint8 slot, uint8 gain) throws Error {
            if (proxy == null) throw new DBusError.FAILED("D-Bus not connected");
            yield proxy.set_gain(slot, gain);
        }
        
        public async void set_rumble_active(uint8 slot, bool enable) throws Error {
            if (proxy == null) throw new DBusError.FAILED("D-Bus not connected");
            yield proxy.set_rumble_active(slot, enable);
        }
        
        // ==================== STICK CONFIGURATION METHODS ====================
        
        public async void set_deadzone(uint8 slot, uint8 deadzone) throws Error {
            if (proxy == null) throw new DBusError.FAILED("D-Bus not connected");
            yield proxy.set_deadzone(slot, deadzone);
        }
        
        // ==================== TRIGGER CONFIGURATION METHODS ====================
        
        /**
         * Sets the digital mode for L2/R2 triggers.
         * @param slot Slot number (0-3)
         * @param enable true for digital mode (on/off), false for analog (0-1023)
         */
        public async void set_triggers_digital(uint8 slot, bool enable) throws Error {
            if (proxy == null) throw new DBusError.FAILED("D-Bus not connected");
            yield proxy.set_triggers_digital(slot, enable);
        }
        
        /**
         * Gets the current digital mode status for triggers.
         * @param slot Slot number (0-3)
         * @return true if triggers are in digital mode, false if analog
         */
        public async bool get_triggers_digital(uint8 slot) throws Error {
            if (proxy == null) throw new DBusError.FAILED("D-Bus not connected");
            return yield proxy.get_triggers_digital(slot);
        }
        
        // ==================== KEYBIND METHODS (FULL) ====================
        
        public async uint8[] get_keymap(uint8 slot) throws Error {
            if (proxy == null) throw new DBusError.FAILED("D-Bus not connected");
            return yield proxy.get_keymap(slot);
        }
        
        public async void set_keybind(uint8 slot, uint8 physical, uint8 logical) throws Error {
            if (proxy == null) throw new DBusError.FAILED("D-Bus not connected");
            yield proxy.set_keybind(slot, physical, logical);
        }
        
        public async void reset_keybinds(uint8 slot) throws Error {
            if (proxy == null) throw new DBusError.FAILED("D-Bus not connected");
            yield proxy.reset_keybinds(slot);
        }
        
        /**
         * Resets all keybinds and layouts to the default state (via daemon flag).
         * @param slot Slot number (0-3)
         */
        public async void reset_all_keybinds(uint8 slot) throws Error {
            if (proxy == null) throw new DBusError.FAILED("D-Bus not connected");
            yield proxy.reset_all_keybinds(slot);
        }
        
        // ==================== LAYOUT METHODS (NEW) ====================
        
        /**
         * Applies Switch layout (swaps A/B and X/Y).
         * @param slot Slot number (0-3)
         */
        public async void apply_switch_layout(uint8 slot) throws Error {
            if (proxy == null) throw new DBusError.FAILED("D-Bus not connected");
            yield proxy.apply_switch_layout(slot);
        }
        
        /**
         * Applies Xbox layout (restores A/B/X/Y identity).
         * @param slot Slot number (0-3)
         */
        public async void apply_xbox_layout(uint8 slot) throws Error {
            if (proxy == null) throw new DBusError.FAILED("D-Bus not connected");
            yield proxy.apply_xbox_layout(slot);
        }
        
        // ==================== EMULATION METHODS ====================
        
        public async void set_emulate(uint8 slot, bool enable) throws Error {
            if (proxy == null) throw new DBusError.FAILED("D-Bus not connected");
            yield proxy.set_emulate(slot, enable);
        }
        
        public async void set_uhid(uint8 slot, bool enable) throws Error {
            if (proxy == null) throw new DBusError.FAILED("D-Bus not connected");
            yield proxy.set_uhid(slot, enable);
        }
        
        public async void set_debounce(uint8 slot, bool enable) throws Error {
            if (proxy == null) throw new DBusError.FAILED("D-Bus not connected");
            yield proxy.set_debounce(slot, enable);
        }
        
        // ==================== CORE (SERVICE) CONTROL METHODS ====================
        
        public async int32 start_core_service() throws Error {
            if (proxy == null) throw new DBusError.FAILED("D-Bus not connected");
            return yield proxy.start_core_service();
        }
        
        public async int32 stop_core_service() throws Error {
            if (proxy == null) throw new DBusError.FAILED("D-Bus not connected");
            return yield proxy.stop_core_service();
        }
        
        public async int32 restart_core_service() throws Error {
            if (proxy == null) throw new DBusError.FAILED("D-Bus not connected");
            return yield proxy.restart_core_service();
        }
        
        public async bool is_core_service_active() throws Error {
            if (proxy == null) throw new DBusError.FAILED("D-Bus not connected");
            return yield proxy.is_core_service_active();
        }
        
        public async bool is_core_service_enabled() throws Error {
            if (proxy == null) throw new DBusError.FAILED("D-Bus not connected");
            return yield proxy.is_core_service_enabled();
        }
        
        public async int32 enable_core_service() throws Error {
            if (proxy == null) throw new DBusError.FAILED("D-Bus not connected");
            return yield proxy.enable_core_service();
        }
        
        public async int32 disable_core_service() throws Error {
            if (proxy == null) throw new DBusError.FAILED("D-Bus not connected");
            return yield proxy.disable_core_service();
        }
        
        // ==================== VERSIONING METHOD ====================
        
        public async string get_core_version() throws Error {
            if (proxy == null) throw new DBusError.FAILED("D-Bus not connected");
            return yield proxy.get_core_version();
        }
        
        // ==================== PROFILE MANAGEMENT METHODS ====================
        
        /**
         * Lists all available profiles.
         * @return String containing profile names separated by newline
         */
        public async string list_profiles() throws Error {
            if (proxy == null) throw new DBusError.FAILED("D-Bus not connected");
            return yield proxy.list_profiles();
        }
        
        /**
         * Loads a profile by name.
         * @param profile_name Name of the profile to load
         */
        public async void load_profile(string profile_name) throws Error {
            if (proxy == null) throw new DBusError.FAILED("D-Bus not connected");
            yield proxy.load_profile(profile_name);
        }
        
        /**
         * Saves the current configuration to a profile.
         * @param profile_name Profile name (creates or overwrites)
         */
        public async void save_profile(string profile_name) throws Error {
            if (proxy == null) throw new DBusError.FAILED("D-Bus not connected");
            yield proxy.save_profile(profile_name);
        }
        
        /**
         * Deletes an existing profile.
         * @param profile_name Name of the profile to delete
         */
        public async void delete_profile(string profile_name) throws Error {
            if (proxy == null) throw new DBusError.FAILED("D-Bus not connected");
            yield proxy.delete_profile(profile_name);
        }
        
        /**
         * Configures automatic saving.
         * @param enable Enable/disable auto-save
         * @param delay_ms Debounce delay in milliseconds
         * @return Status message returned by the daemon
         */
        public async string set_auto_save(bool enable, int32 delay_ms) throws Error {
            if (proxy == null) throw new DBusError.FAILED("D-Bus not connected");
            return yield proxy.set_auto_save(enable, delay_ms);
        }
        
        // ==================== AUTO-SAVE AND ACTIVE PROFILE CONFIGURATION METHODS ====================
        
        /**
         * Gets the current auto-save status (enabled/disabled and delay).
         * @param enabled true if enabled
         * @param delay_ms current delay in ms
         */
        public async void get_auto_save_status(out bool enabled, out int32 delay_ms) throws Error {
            if (proxy == null) throw new DBusError.FAILED("D-Bus not connected");
            yield proxy.get_auto_save_status(out enabled, out delay_ms);
        }
        
        /**
         * Gets the name of the currently active profile.
         * @return Profile name (e.g., "default", "racing")
         */
        public async string get_current_profile() throws Error {
            if (proxy == null) throw new DBusError.FAILED("D-Bus not connected");
            return yield proxy.get_current_profile();
        }
    }
}
