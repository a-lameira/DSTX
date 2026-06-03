/*
 * settings-controller.vala - Business logic for controller settings
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
 * - Manage controller configuration state and D-Bus calls
 * - Handle LED, rumble, sticks, triggers, emulation settings
 * - Version tracking to prevent bouncing updates
 * - Provide signals for UI notification
 * - Layout switching (Switch/Xbox)
 * - Global preferences (theme, language, auto-start, auto-save)
 * - System service control and version checking
 */

// src/managers/settings-controller.vala

using Dstx.Core;
using Dstx.Models;

namespace Dstx.Managers {
    /**
     * SettingsController - Business logic for controller settings
     *
     * Manages configuration state, calls D-Bus methods and notifies changes.
     * No direct dependency on GTK.
     * Version tracking to prevent bouncing.
     */
    public class SettingsController : Object {
        private unowned DBusClient dbus_client;
        private Controller? _current_controller = null;
        private uint64 _current_version = 0;

        // Stores the last sent version for each property (using uint64? for HashTable)
        private HashTable<string, uint64?> _last_sent_versions;

        // Flag to avoid concurrent LED operations (dynamic mode)
        private bool _led_color_operation_pending = false;

        // Signals to notify UI about configuration changes (including version)
        public signal void controller_changed(Controller controller);
        public signal void led_static_changed(bool is_static, uint64 version);
        public signal void effect_changed(uint8 effect, uint8 speed, uint8 brightness, uint64 version);
        public signal void led_color_changed(uint8 r, uint8 g, uint8 b, uint64 version);
        public signal void led_reapply_changed(bool enabled, uint64 version);
        public signal void player_leds_changed(uint8 mode, uint64 version);
        public signal void brightness_changed(uint8 value, uint64 version);
        public signal void rumble_active_changed(bool active, uint64 version);
        public signal void rumble_gain_changed(uint8 gain, uint64 version);
        public signal void deadzone_changed(uint8 deadzone, uint64 version);
        public signal void emulate_active_changed(bool active, uint64 version);
        public signal void emulation_mode_changed(bool is_uhid, uint64 version);
        public signal void debounce_changed(bool enabled, uint64 version);
        public signal void sensitivity_left_changed(uint8 preset, uint64 version);
        public signal void sensitivity_right_changed(uint8 preset, uint64 version);
        public signal void invert_ly_changed(bool enabled, uint64 version);
        public signal void invert_ry_changed(bool enabled, uint64 version);
        public signal void triggers_digital_changed(bool enabled, uint64 version);
        
        // Layout signals (no version, as they are actions, not persistent states)
        public signal void switch_layout_applied();
        public signal void xbox_layout_applied();

        // Properties
        public Controller? current_controller {
            get { return _current_controller; }
        }

        public SettingsController(DBusClient dbus_client) {
            this.dbus_client = dbus_client;
            _last_sent_versions = new HashTable<string, uint64?>(str_hash, str_equal);
        }

        // ==================== CURRENT CONTROLLER ====================

        public void set_current_controller(Controller controller) {
            if (_current_controller == controller) return;
            _current_controller = controller;
            _current_version = controller.version;
            controller_changed(controller);
        }

        /**
         * Updates internal state from a newer Controller.
         * Returns true if changes occurred and signals were emitted.
         * UI should compare the received version with the last sent version to avoid loops.
         */
        public bool update_from_controller(Controller controller) {
            if (_current_controller == null || _current_controller.slot != controller.slot)
                return false;
            if (controller.version <= _current_version)
                return false;

            _current_controller = controller;
            _current_version = controller.version;

            // Emit signals with current versions of each property
            led_static_changed(controller.led_static, controller.get_property_version("led-static"));
            effect_changed(controller.current_effect, controller.effect_speed, controller.global_brightness,
                           controller.get_property_version("current-effect"));
            led_color_changed(controller.led_base_r, controller.led_base_g, controller.led_base_b,
                              controller.get_property_version("led-base-r"));
            led_reapply_changed(controller.led_reapply, controller.get_property_version("led-reapply"));
            player_leds_changed(controller.player_leds, controller.get_property_version("player-leds"));
            brightness_changed(controller.global_brightness, controller.get_property_version("global-brightness"));
            rumble_active_changed(controller.rumble_active, controller.get_property_version("rumble-active"));
            rumble_gain_changed(controller.rumble_gain, controller.get_property_version("rumble-gain"));
            deadzone_changed(controller.deadzone, controller.get_property_version("deadzone"));
            emulate_active_changed(controller.emulate_active, controller.get_property_version("emulate-active"));
            emulation_mode_changed(controller.is_uhid, controller.get_property_version("is-uhid"));
            debounce_changed(controller.debounce_enabled, controller.get_property_version("debounce-enabled"));
            sensitivity_left_changed(controller.sensitivity_left_preset,
                                     controller.get_property_version("sensitivity-left-preset"));
            sensitivity_right_changed(controller.sensitivity_right_preset,
                                      controller.get_property_version("sensitivity-right-preset"));
            invert_ly_changed(controller.invert_ly, controller.get_property_version("invert-ly"));
            invert_ry_changed(controller.invert_ry, controller.get_property_version("invert-ry"));
            triggers_digital_changed(controller.triggers_digital, controller.get_property_version("triggers-digital"));

            return true;
        }

        // ==================== LED SETTINGS ====================

        public async void set_led_static(bool is_static) {
            if (_current_controller == null) return;
            if (_current_controller.led_static == is_static) return;

            uint64 version = _current_controller.get_property_version("led-static");
            _last_sent_versions.set("led-static", version);

            _current_controller.led_static = is_static;
            if (is_static) {
                yield dbus_client.set_effect((uint8)_current_controller.slot, 0, 0,
                                             _current_controller.global_brightness);
                yield dbus_client.set_led((uint8)_current_controller.slot,
                                          _current_controller.led_base_r,
                                          _current_controller.led_base_g,
                                          _current_controller.led_base_b);
                yield dbus_client.set_global_brightness((uint8)_current_controller.slot,
                                                        _current_controller.global_brightness);
            } else {
                uint8 effect = (_current_controller.current_effect == 0) ? 1 : _current_controller.current_effect;
                yield dbus_client.set_effect((uint8)_current_controller.slot, effect,
                                             _current_controller.effect_speed,
                                             _current_controller.global_brightness);
            }
        }

        public async void set_effect(uint8 effect, uint8 speed, uint8 brightness) {
            if (_current_controller == null) return;
            if (_current_controller.current_effect == effect &&
                _current_controller.effect_speed == speed &&
                _current_controller.global_brightness == brightness) return;

            uint64 version = _current_controller.get_property_version("current-effect");
            _last_sent_versions.set("current-effect", version);

            _current_controller.current_effect = effect;
            _current_controller.effect_speed = speed;
            _current_controller.global_brightness = brightness;
            yield dbus_client.set_effect((uint8)_current_controller.slot, effect, speed, brightness);
        }

        public async void set_led_color(uint8 r, uint8 g, uint8 b) {
            if (_current_controller == null) return;
            if (_current_controller.led_base_r == r &&
                _current_controller.led_base_g == g &&
                _current_controller.led_base_b == b) return;

            // Avoid concurrent LED operations
            if (_led_color_operation_pending) {
                yield sleep(50);
                set_led_color.begin(r, g, b);
                return;
            }

            _led_color_operation_pending = true;

            // Get current version of base color
            uint64 version = _current_controller.get_property_version("led-base-r");
            _last_sent_versions.set("led-base-r", version);
            _last_sent_versions.set("led-base-g", version);
            _last_sent_versions.set("led-base-b", version);

            if (_current_controller.led_static) {
                yield dbus_client.set_led((uint8)_current_controller.slot, r, g, b);
                _current_controller.led_base_r = r;
                _current_controller.led_base_g = g;
                _current_controller.led_base_b = b;
            } else {
                uint8 effect = (_current_controller.current_effect == 0) ? 1 : _current_controller.current_effect;
                yield dbus_client.set_led((uint8)_current_controller.slot, r, g, b);
                yield dbus_client.set_effect((uint8)_current_controller.slot, effect,
                                             _current_controller.effect_speed,
                                             _current_controller.global_brightness);
                _current_controller.led_base_r = r;
                _current_controller.led_base_g = g;
                _current_controller.led_base_b = b;
            }

            _led_color_operation_pending = false;
        }

        private async void sleep(uint ms) {
            var source = new TimeoutSource(ms);
            source.set_callback(() => {
                sleep.callback();
                return Source.REMOVE;
            });
            source.attach(null);
            yield;
        }

        public async void set_led_reapply(bool enabled) {
            if (_current_controller == null) return;
            if (_current_controller.led_reapply == enabled) return;

            uint64 version = _current_controller.get_property_version("led-reapply");
            _last_sent_versions.set("led-reapply", version);

            _current_controller.led_reapply = enabled;
            yield dbus_client.set_led_reapply((uint8)_current_controller.slot, enabled);
        }

        public async void set_player_leds(uint8 mode) {
            if (_current_controller == null) return;
            if (_current_controller.player_leds == mode) return;

            uint64 version = _current_controller.get_property_version("player-leds");
            _last_sent_versions.set("player-leds", version);

            _current_controller.player_leds = mode;
            yield dbus_client.set_player_leds((uint8)_current_controller.slot, mode);
        }

        public async void set_brightness(uint8 brightness) {
            if (_current_controller == null) return;
            if (_current_controller.global_brightness == brightness) return;

            uint64 version = _current_controller.get_property_version("global-brightness");
            _last_sent_versions.set("global-brightness", version);

            _current_controller.global_brightness = brightness;
            yield dbus_client.set_global_brightness((uint8)_current_controller.slot, brightness);
            if (!_current_controller.led_static) {
                uint8 effect = (_current_controller.current_effect == 0) ? 1 : _current_controller.current_effect;
                yield dbus_client.set_effect((uint8)_current_controller.slot, effect,
                                             _current_controller.effect_speed, brightness);
            }
        }

        // ==================== RUMBLE SETTINGS ====================

        public async void set_rumble_active(bool active) {
            if (_current_controller == null) return;
            if (_current_controller.rumble_active == active) return;

            uint64 version = _current_controller.get_property_version("rumble-active");
            _last_sent_versions.set("rumble-active", version);

            _current_controller.rumble_active = active;
            yield dbus_client.set_rumble_active((uint8)_current_controller.slot, active);
        }

        public async void set_rumble_gain(uint8 gain) {
            if (_current_controller == null) return;
            if (_current_controller.rumble_gain == gain) return;

            uint64 version = _current_controller.get_property_version("rumble-gain");
            _last_sent_versions.set("rumble-gain", version);

            _current_controller.rumble_gain = gain;
            yield dbus_client.set_gain((uint8)_current_controller.slot, gain);
        }

        // ==================== ANALOG STICKS ====================

        public async void set_deadzone(uint8 deadzone) {
            if (_current_controller == null) return;
            if (_current_controller.deadzone == deadzone) return;

            uint64 version = _current_controller.get_property_version("deadzone");
            _last_sent_versions.set("deadzone", version);

            _current_controller.deadzone = deadzone;
            yield dbus_client.set_deadzone((uint8)_current_controller.slot, deadzone);
        }

        public async void set_sensitivity_left(uint8 preset) {
            if (_current_controller == null) return;
            if (_current_controller.sensitivity_left_preset == preset) return;

            uint64 version = _current_controller.get_property_version("sensitivity-left-preset");
            _last_sent_versions.set("sensitivity-left-preset", version);

            _current_controller.sensitivity_left_preset = preset;
            yield dbus_client.set_sensitivity_preset_left((uint8)_current_controller.slot, preset);
        }

        public async void set_sensitivity_right(uint8 preset) {
            if (_current_controller == null) return;
            if (_current_controller.sensitivity_right_preset == preset) return;

            uint64 version = _current_controller.get_property_version("sensitivity-right-preset");
            _last_sent_versions.set("sensitivity-right-preset", version);

            _current_controller.sensitivity_right_preset = preset;
            yield dbus_client.set_sensitivity_preset_right((uint8)_current_controller.slot, preset);
        }

        public async void set_invert_ly(bool enabled) {
            if (_current_controller == null) return;
            if (_current_controller.invert_ly == enabled) return;

            uint64 version = _current_controller.get_property_version("invert-ly");
            _last_sent_versions.set("invert-ly", version);

            _current_controller.invert_ly = enabled;
            yield dbus_client.set_invert_ly((uint8)_current_controller.slot, enabled);
        }

        public async void set_invert_ry(bool enabled) {
            if (_current_controller == null) return;
            if (_current_controller.invert_ry == enabled) return;

            uint64 version = _current_controller.get_property_version("invert-ry");
            _last_sent_versions.set("invert-ry", version);

            _current_controller.invert_ry = enabled;
            yield dbus_client.set_invert_ry((uint8)_current_controller.slot, enabled);
        }

        // ==================== TRIGGERS ====================

        public async void set_triggers_digital(bool enable) throws Error {
            if (_current_controller == null) return;

            uint64 version = _current_controller.get_property_version("triggers-digital");
            _last_sent_versions.set("triggers-digital", version);

            yield dbus_client.set_triggers_digital((uint8)_current_controller.slot, enable);
            _current_controller.triggers_digital = enable;
        }

        // ==================== EMULATION ====================

        public async void set_emulate_active(bool active) {
            if (_current_controller == null) return;
            if (_current_controller.emulate_active == active) return;

            uint64 version = _current_controller.get_property_version("emulate-active");
            _last_sent_versions.set("emulate-active", version);

            _current_controller.emulate_active = active;
            yield dbus_client.set_emulate((uint8)_current_controller.slot, active);
        }

        public async void set_emulation_mode(bool is_uhid) {
            if (_current_controller == null) return;
            if (_current_controller.is_uhid == is_uhid) return;

            uint64 version = _current_controller.get_property_version("is-uhid");
            _last_sent_versions.set("is-uhid", version);

            _current_controller.is_uhid = is_uhid;
            yield dbus_client.set_uhid((uint8)_current_controller.slot, is_uhid);
        }

        public async void set_debounce(bool enabled) {
            if (_current_controller == null) return;
            if (_current_controller.debounce_enabled == enabled) return;

            uint64 version = _current_controller.get_property_version("debounce-enabled");
            _last_sent_versions.set("debounce-enabled", version);

            _current_controller.debounce_enabled = enabled;
            yield dbus_client.set_debounce((uint8)_current_controller.slot, enabled);
        }

        // ==================== LAYOUT METHODS ====================

        public async void apply_switch_layout() {
            if (_current_controller == null) return;
            try {
                yield dbus_client.apply_switch_layout((uint8)_current_controller.slot);
                switch_layout_applied();
            } catch (Error e) {
                warning("apply_switch_layout failed: %s", e.message);
            }
        }

        public async void apply_xbox_layout() {
            if (_current_controller == null) return;
            try {
                yield dbus_client.apply_xbox_layout((uint8)_current_controller.slot);
                xbox_layout_applied();
            } catch (Error e) {
                warning("apply_xbox_layout failed: %s", e.message);
            }
        }

        // ==================== GLOBAL PREFERENCES (SettingsManager) ====================

        public int get_theme_mode() {
            return SettingsManager.get_default().get_theme();
        }

        public void set_theme_mode(int mode) {
            var mgr = SettingsManager.get_default();
            if (mgr.get_theme() != mode) {
                mgr.set_theme(mode);
            }
        }

        public string get_custom_theme_id() {
            return SettingsManager.get_default().get_custom_theme();
        }

        public string get_custom_theme_name() {
            return SettingsManager.get_default().get_custom_theme_name();
        }

        public int get_custom_accent_index() {
            return SettingsManager.get_default().get_custom_accent_index();
        }

        public Gdk.RGBA get_custom_accent_color() {
            return SettingsManager.get_default().get_custom_accent_color();
        }

        public void save_custom_theme(string theme_id, string theme_name,
                                      Gdk.RGBA accent_color, int accent_index) {
            var mgr = SettingsManager.get_default();
            mgr.set_custom_theme(theme_id);
            mgr.set_custom_theme_name(theme_name);
            mgr.set_custom_accent_index(accent_index);
            mgr.set_custom_accent_color(accent_color);
            mgr.set_theme(3); // custom mode
        }

        public int get_language() {
            return SettingsManager.get_default().get_language();
        }

        public void set_language(int lang_id) {
            SettingsManager.get_default().set_language(lang_id);
        }

        // ==================== SYSTEMD SERVICE MANAGEMENT ====================

        public bool get_auto_start() {
            return SettingsManager.get_default().get_auto_start();
        }

        public async void set_auto_start(bool enabled) {
            var mgr = SettingsManager.get_default();
            if (mgr.get_auto_start() == enabled) return;

            bool success = false;
            if (enabled) {
                yield enable_core_service();
                success = true;
            } else {
                yield disable_core_service();
                success = true;
            }
            if (success) {
                mgr.set_auto_start(enabled);
            }
        }

        private async void enable_core_service() {
            try {
                yield dbus_client.enable_core_service();
            } catch (Error e) {
                warning("enable_core_service: %s", e.message);
            }
        }

        private async void disable_core_service() {
            try {
                yield dbus_client.disable_core_service();
            } catch (Error e) {
                warning("disable_core_service: %s", e.message);
            }
        }

        public async void start_service() {
            try {
                yield dbus_client.start_core_service();
            } catch (Error e) {
                warning("start_service: %s", e.message);
            }
        }

        public async void stop_service() {
            try {
                yield dbus_client.stop_core_service();
            } catch (Error e) {
                warning("stop_service: %s", e.message);
            }
        }

        public async void restart_service() {
            try {
                yield dbus_client.restart_core_service();
            } catch (Error e) {
                warning("restart_service: %s", e.message);
            }
        }

        public async bool is_service_active() {
            try {
                return yield dbus_client.is_core_service_active();
            } catch (Error e) {
                warning("is_service_active: %s", e.message);
                return false;
            }
        }

        public async bool is_service_enabled() {
            try {
                return yield dbus_client.is_core_service_enabled();
            } catch (Error e) {
                warning("is_service_enabled: %s", e.message);
                return false;
            }
        }

        // ==================== AUTO-SAVE ====================
        
        public async void get_auto_save_status(out bool enabled, out int32 delay_ms) throws Error {
            yield dbus_client.get_auto_save_status(out enabled, out delay_ms);
        }
        
        // ==================== VERSIONING ====================

        public async string get_current_core_version() {
            try {
                return yield dbus_client.get_core_version();
            } catch (Error e) {
                warning("get_current_core_version: %s", e.message);
                return "0.0.0";
            }
        }

        public string get_expected_core_version() {
            return SystemServiceManager.get_expected_version();
        }

        public bool is_core_outdated(string current_version) {
            return SystemServiceManager.is_outdated(current_version);
        }

        public async bool check_for_updates() {
            string current = yield get_current_core_version();
            return is_core_outdated(current);
        }

        // ==================== ACCESS TO LAST SENT VERSION ====================
        // Used by SettingsUIBuilder to compare with the version received in signals
        public uint64 get_last_sent_version(string property) {
            uint64? v = _last_sent_versions.lookup(property);
            return (v != null) ? v : 0;
        }
    }
}
