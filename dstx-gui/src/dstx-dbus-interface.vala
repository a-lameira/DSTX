/*
 * dstx-dbus-interface.vala - Complete D-Bus interface for DSTX GUI
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
 * - Define D-Bus interface for communication with dstx-dbus-bridge
 * - Provide methods for controller configuration, LED, rumble, sticks, triggers, keybinds, layouts, emulation, core service, profiles
 * - Declare signals for controller events and telemetry updates
 */

// src/dstx-dbus-interface.vala

[DBus (name = "org.dstx.Bridge")]
public interface DstxDBus : Object {
    // ==================== READ METHODS ====================
    
    [DBus (name = "GetControllers")]
    public abstract async uint8[] get_controllers() throws DBusError, IOError;
    
    [DBus (name = "GetControllerInfo")]
    public abstract async Variant get_controller_info(uint8 slot) throws DBusError, IOError;
    
    [DBus (name = "GetDetailedInfo")]
    public abstract async Variant get_detailed_info(uint8 slot) throws DBusError, IOError;
    
    [DBus (name = "GetTelemetry")]
    public abstract async Variant get_telemetry(uint8 slot) throws DBusError, IOError;
    
    [DBus (name = "GetInvertStatus")]
    public abstract async Variant get_invert_status(uint8 slot) throws DBusError, IOError;
    
    [DBus (name = "GetSensitivityPreset")]
    public abstract async Variant get_sensitivity_preset(uint8 slot) throws DBusError, IOError;
    
    // ==================== LED CONFIGURATION METHODS ====================
    
    [DBus (name = "SetLED")]
    public abstract async void set_led(uint8 slot, uint8 r, uint8 g, uint8 b) throws DBusError, IOError;
    
    [DBus (name = "SetEffect")]
    public abstract async void set_effect(uint8 slot, uint8 effect, uint8 speed, uint8 brightness) throws DBusError, IOError;
    
    [DBus (name = "SetLEDReapply")]
    public abstract async void set_led_reapply(uint8 slot, bool enable) throws DBusError, IOError;
    
    [DBus (name = "SetGlobalBrightness")]
    public abstract async void set_global_brightness(uint8 slot, uint8 brightness) throws DBusError, IOError;
    
    [DBus (name = "SetPlayerLEDs")]
    public abstract async void set_player_leds(uint8 slot, uint8 mode) throws DBusError, IOError;
    
    // ==================== RUMBLE CONFIGURATION METHODS ====================
    
    [DBus (name = "SetGain")]
    public abstract async void set_gain(uint8 slot, uint8 gain) throws DBusError, IOError;
    
    [DBus (name = "SetRumbleActive")]
    public abstract async void set_rumble_active(uint8 slot, bool enable) throws DBusError, IOError;
    
    // ==================== STICK CONFIGURATION METHODS ====================
    
    [DBus (name = "SetDeadzone")]
    public abstract async void set_deadzone(uint8 slot, uint8 deadzone) throws DBusError, IOError;
    
    [DBus (name = "SetSensitivityPresetLeft")]
    public abstract async void set_sensitivity_preset_left(uint8 slot, uint8 preset) throws DBusError, IOError;
    
    [DBus (name = "SetSensitivityPresetRight")]
    public abstract async void set_sensitivity_preset_right(uint8 slot, uint8 preset) throws DBusError, IOError;
    
    [DBus (name = "SetInvertLY")]
    public abstract async void set_invert_ly(uint8 slot, bool enable) throws DBusError, IOError;
    
    [DBus (name = "SetInvertRY")]
    public abstract async void set_invert_ry(uint8 slot, bool enable) throws DBusError, IOError;
    
    // ==================== TRIGGER CONFIGURATION METHODS ====================
    
    [DBus (name = "SetTriggersDigital")]
    public abstract async void set_triggers_digital(uint8 slot, bool enable) throws DBusError, IOError;
    
    [DBus (name = "GetTriggersDigital")]
    public abstract async bool get_triggers_digital(uint8 slot) throws DBusError, IOError;
    
    // ==================== KEYBIND METHODS (FULL) ====================
    
    [DBus (name = "GetKeymap")]
    public abstract async uint8[] get_keymap(uint8 slot) throws DBusError, IOError;
    
    [DBus (name = "SetKeybind")]
    public abstract async void set_keybind(uint8 slot, uint8 physical, uint8 logical) throws DBusError, IOError;
    
    [DBus (name = "ResetKeybinds")]
    public abstract async void reset_keybinds(uint8 slot) throws DBusError, IOError;
    
    [DBus (name = "ResetAllKeybinds")]
    public abstract async void reset_all_keybinds(uint8 slot) throws DBusError, IOError;
    
    // ==================== LAYOUT METHODS (NEW) ====================
    
    [DBus (name = "ApplySwitchLayout")]
    public abstract async void apply_switch_layout(uint8 slot) throws DBusError, IOError;
    
    [DBus (name = "ApplyXboxLayout")]
    public abstract async void apply_xbox_layout(uint8 slot) throws DBusError, IOError;
    
    // ==================== EMULATION METHODS ====================
    
    [DBus (name = "SetEmulate")]
    public abstract async void set_emulate(uint8 slot, bool enable) throws DBusError, IOError;
    
    [DBus (name = "SetUHID")]
    public abstract async void set_uhid(uint8 slot, bool enable) throws DBusError, IOError;
    
    [DBus (name = "SetDebounce")]
    public abstract async void set_debounce(uint8 slot, bool enable) throws DBusError, IOError;
    
    // ==================== CORE CONTROL METHODS ====================
    
    [DBus (name = "StartCoreService")]
    public abstract async int32 start_core_service() throws DBusError, IOError;
    
    [DBus (name = "StopCoreService")]
    public abstract async int32 stop_core_service() throws DBusError, IOError;
    
    [DBus (name = "RestartCoreService")]
    public abstract async int32 restart_core_service() throws DBusError, IOError;
    
    [DBus (name = "IsCoreServiceActive")]
    public abstract async bool is_core_service_active() throws DBusError, IOError;
    
    [DBus (name = "IsCoreServiceEnabled")]
    public abstract async bool is_core_service_enabled() throws DBusError, IOError;
    
    [DBus (name = "EnableCoreService")]
    public abstract async int32 enable_core_service() throws DBusError, IOError;
    
    [DBus (name = "DisableCoreService")]
    public abstract async int32 disable_core_service() throws DBusError, IOError;
                                       
    // ==================== VERSIONING METHOD ====================
    
    [DBus (name = "GetCoreVersion")]
    public abstract async string get_core_version() throws DBusError, IOError;
    
    // ==================== PROFILE MANAGEMENT METHODS ====================
    
    [DBus (name = "ListProfiles")]
    public abstract async string list_profiles() throws DBusError, IOError;
    
    [DBus (name = "LoadProfile")]
    public abstract async void load_profile(string profile_name) throws DBusError, IOError;
    
    [DBus (name = "SaveProfile")]
    public abstract async void save_profile(string profile_name) throws DBusError, IOError;
    
    [DBus (name = "DeleteProfile")]
    public abstract async void delete_profile(string profile_name) throws DBusError, IOError;
    
    [DBus (name = "SetAutoSave")]
    public abstract async string set_auto_save(bool enable, int32 delay_ms) throws DBusError, IOError;
    
    // ==================== AUTO-SAVE AND ACTIVE PROFILE CONFIGURATION METHODS ====================
    
    [DBus (name = "GetAutoSaveStatus")]
    public abstract async void get_auto_save_status(out bool enabled, out int32 delay_ms) throws DBusError, IOError;
    
    [DBus (name = "GetCurrentProfile")]
    public abstract async string get_current_profile() throws DBusError, IOError;
    
    // ==================== SIGNALS ====================
    
    [DBus (name = "ControllerConnected")]
    public signal void controller_connected(uint8 slot);
    
    [DBus (name = "ControllerDisconnected")]
    public signal void controller_disconnected(uint8 slot);
    
    [DBus (name = "ControllerUpdated")]
    public signal void controller_updated(uint8 slot);
    
    [DBus (name = "DaemonStatusChanged")]
    public signal void daemon_status_changed(bool alive);
    
    [DBus (name = "TelemetryUpdate")]
    public signal void telemetry_update(uint8 slot, int16 lx, int16 ly, int16 rx, int16 ry,
                                        int16 lt, int16 rt, int16 hatx, int16 haty, uint16 buttons);
    
    [DBus (name = "ButtonUpdate")]
    public signal void button_update(uint8 slot, uint16 buttons);
    
    [DBus (name = "AxisUpdate")]
    public signal void axis_update(uint8 slot, int16 lx, int16 ly, int16 rx, int16 ry,
                                   int16 lt, int16 rt, int16 hatx, int16 haty);
}
