/*
 * controller.vala - Controller model and data structures for DSTX GUI
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
 * - Define ControllerType enum and SensitivityPreset enum
 * - Represent controller state including LED, rumble, sticks, triggers, buttons, emulation, keymap
 * - Provide versioning and property-level change tracking
 * - Handle conversion from D-Bus arguments and telemetry updates
 */

// src/models/controller.vala

namespace Dstx.Models {
    public enum ControllerType {
        DS4 = 0,
        DUALSENSE = 1,
        NSW_PRO = 2;

        public string to_string() {
            switch (this) {
                case DS4: return "DualShock 4";
                case DUALSENSE: return "DualSense";
                case NSW_PRO: return "Nintendo Switch Pro";
                default: return "Unknown";
            }
        }
    }

    public enum SensitivityPreset {
        DEFAULT = 0,
        PRECISION = 1,
        RAPID = 2,
        SUAVE = 3,
        AGGRESSIVE = 4,
        SNIPER = 5,
        RACING = 6,
        FPS = 7;

        public string to_display_string() {
            switch (this) {
                case DEFAULT: return "Default (Linear)";
                case PRECISION: return "Precision";
                case RAPID: return "Rapid";
                case SUAVE: return "Smooth";
                case AGGRESSIVE: return "Aggressive";
                case SNIPER: return "Sniper";
                case RACING: return "Racing";
                case FPS: return "FPS";
                default: return "Default";
            }
        }

        public uint8 to_percent() {
            switch (this) {
                case PRECISION: return 50;
                case RAPID: return 150;
                case SUAVE: return 80;
                case AGGRESSIVE: return 120;
                case SNIPER: return 30;
                case RACING: return 100;
                case FPS: return 180;
                default: return 100;
            }
        }

        public static SensitivityPreset from_percent(uint8 percent) {
            if (percent <= 40) return SNIPER;
            if (percent <= 70) return PRECISION;
            if (percent <= 90) return SUAVE;
            if (percent <= 110) return DEFAULT;
            if (percent <= 140) return AGGRESSIVE;
            if (percent <= 170) return RAPID;
            return FPS;
        }
    }

    public class Controller : Object {
        public int slot { get; set; }
        public bool connected { get; set; }
        
        public ControllerType controller_type { get; set; }
        public bool is_bluetooth { get; set; }
        public string dev_path { get; set; default = ""; }
        public string product_name { get; set; default = ""; }
        public string serial { get; set; default = ""; }
        public string driver { get; set; default = ""; }
        
        private uint8 _led_r;
        private uint8 _led_g;
        private uint8 _led_b;
        private uint8 _led_base_r;
        private uint8 _led_base_g;
        private uint8 _led_base_b;
        private uint8 _global_brightness;
        private uint8 _player_leds;
        private bool _led_static;
        private bool _led_reapply;
        
        public uint8 led_r {
            get { return _led_r; }
            set { if (_led_r != value) { _led_r = value; bump_version("led-r"); } }
        }
        public uint8 led_g {
            get { return _led_g; }
            set { if (_led_g != value) { _led_g = value; bump_version("led-g"); } }
        }
        public uint8 led_b {
            get { return _led_b; }
            set { if (_led_b != value) { _led_b = value; bump_version("led-b"); } }
        }
        public uint8 led_base_r {
            get { return _led_base_r; }
            set { if (_led_base_r != value) { _led_base_r = value; bump_version("led-base-r"); } }
        }
        public uint8 led_base_g {
            get { return _led_base_g; }
            set { if (_led_base_g != value) { _led_base_g = value; bump_version("led-base-g"); } }
        }
        public uint8 led_base_b {
            get { return _led_base_b; }
            set { if (_led_base_b != value) { _led_base_b = value; bump_version("led-base-b"); } }
        }
        public uint8 global_brightness {
            get { return _global_brightness; }
            set { if (_global_brightness != value) { _global_brightness = value; bump_version("global-brightness"); } }
        }
        public uint8 player_leds {
            get { return _player_leds; }
            set { if (_player_leds != value) { _player_leds = value; bump_version("player-leds"); } }
        }
        public bool led_static {
            get { return _led_static; }
            set { if (_led_static != value) { _led_static = value; bump_version("led-static"); } }
        }
        public bool led_reapply {
            get { return _led_reapply; }
            set { if (_led_reapply != value) { _led_reapply = value; bump_version("led-reapply"); } }
        }
        
        private uint8 _rumble_gain;
        private uint8 _deadzone;
        private uint8 _rumble_weak;
        private uint8 _rumble_strong;
        private bool _rumble_active;
        
        public uint8 rumble_gain {
            get { return _rumble_gain; }
            set { if (_rumble_gain != value) { _rumble_gain = value; bump_version("rumble-gain"); } }
        }
        public uint8 deadzone {
            get { return _deadzone; }
            set { if (_deadzone != value) { _deadzone = value; bump_version("deadzone"); } }
        }
        public uint8 rumble_weak {
            get { return _rumble_weak; }
            set { if (_rumble_weak != value) { _rumble_weak = value; bump_version("rumble-weak"); } }
        }
        public uint8 rumble_strong {
            get { return _rumble_strong; }
            set { if (_rumble_strong != value) { _rumble_strong = value; bump_version("rumble-strong"); } }
        }
        public bool rumble_active {
            get { return _rumble_active; }
            set { if (_rumble_active != value) { _rumble_active = value; bump_version("rumble-active"); } }
        }
        
        private uint8 _sensitivity_left_preset;
        private uint8 _sensitivity_right_preset;
        
        public uint8 sensitivity_left_preset {
            get { return _sensitivity_left_preset; }
            set {
                if (value <= 7 && _sensitivity_left_preset != value) {
                    _sensitivity_left_preset = value;
                    bump_version("sensitivity-left-preset");
                }
            }
        }
        
        public uint8 sensitivity_right_preset {
            get { return _sensitivity_right_preset; }
            set {
                if (value <= 7 && _sensitivity_right_preset != value) {
                    _sensitivity_right_preset = value;
                    bump_version("sensitivity-right-preset");
                }
            }
        }
        
        public uint8 sensitivity_left {
            get { return preset_to_percent(_sensitivity_left_preset); }
            set { sensitivity_left_preset = percent_to_preset(value); }
        }
        
        public uint8 sensitivity_right {
            get { return preset_to_percent(_sensitivity_right_preset); }
            set { sensitivity_right_preset = percent_to_preset(value); }
        }
        
        private bool _invert_ly;
        private bool _invert_ry;
        
        public bool invert_ly {
            get { return _invert_ly; }
            set { if (_invert_ly != value) { _invert_ly = value; bump_version("invert-ly"); } }
        }
        public bool invert_ry {
            get { return _invert_ry; }
            set { if (_invert_ry != value) { _invert_ry = value; bump_version("invert-ry"); } }
        }
        
        public int16 lx { get; set; default = 0; }
        public int16 ly { get; set; default = 0; }
        public int16 rx { get; set; default = 0; }
        public int16 ry { get; set; default = 0; }
        public int16 lt { get; set; default = 0; }
        public int16 rt { get; set; default = 0; }
        public int hatx { get; set; default = 0; }
        public int haty { get; set; default = 0; }
        
        private bool _triggers_digital;
        public bool triggers_digital {
            get { return _triggers_digital; }
            set { if (_triggers_digital != value) { _triggers_digital = value; bump_version("triggers-digital"); } }
        }
        
                private int _layout_mode = 0; // 0 = Xbox, 1 = Switch
        public int layout_mode {
            get { return _layout_mode; }
            set {
                if (_layout_mode != value) {
                    _layout_mode = value;
                    notify_property("layout-mode");
                    bump_version("layout-mode");
                }
            }
        }
        
        public bool square { get; set; default = false; }
        public bool cross { get; set; default = false; }
        public bool circle { get; set; default = false; }
        public bool triangle { get; set; default = false; }
        public bool l1 { get; set; default = false; }
        public bool r1 { get; set; default = false; }
        public bool l2 { get; set; default = false; }
        public bool r2 { get; set; default = false; }
        public bool share { get; set; default = false; }
        public bool options { get; set; default = false; }
        public bool ps { get; set; default = false; }
        public bool l3 { get; set; default = false; }
        public bool r3 { get; set; default = false; }
        public bool touch_btn { get; set; default = false; }
        
        public bool dpad_up { get; set; default = false; }
        public bool dpad_down { get; set; default = false; }
        public bool dpad_left { get; set; default = false; }
        public bool dpad_right { get; set; default = false; }
        
        private bool _emulate_active;
        private bool _is_uhid;
        private bool _debounce_enabled;
        
        public bool emulate_active {
            get { return _emulate_active; }
            set { if (_emulate_active != value) { _emulate_active = value; bump_version("emulate-active"); } }
        }
        public bool is_uhid {
            get { return _is_uhid; }
            set { if (_is_uhid != value) { _is_uhid = value; bump_version("is-uhid"); } }
        }
        public bool debounce_enabled {
            get { return _debounce_enabled; }
            set { if (_debounce_enabled != value) { _debounce_enabled = value; bump_version("debounce-enabled"); } }
        }
        
        public int battery { get; set; default = 0; }
        
        private uint8[] _keymap;
        public uint8[] keymap {
            get { return _keymap; }
            set {
                if (_keymap == null || _keymap.length != value.length) {
                    _keymap = value;
                    bump_version("keymap");
                } else {
                    bool changed = false;
                    for (int i = 0; i < value.length; i++) {
                        if (_keymap[i] != value[i]) {
                            changed = true;
                            break;
                        }
                    }
                    if (changed) {
                        _keymap = value;
                        bump_version("keymap");
                    }
                }
            }
        }
        
        private uint8 _current_effect;
        private uint8 _effect_speed;
        private uint8 _effect_brightness;
        
        public uint8 current_effect {
            get { return _current_effect; }
            set { if (_current_effect != value) { _current_effect = value; bump_version("current-effect"); } }
        }
        public uint8 effect_speed {
            get { return _effect_speed; }
            set { if (_effect_speed != value) { _effect_speed = value; bump_version("effect-speed"); } }
        }
        public uint8 effect_brightness {
            get { return _effect_brightness; }
            set { if (_effect_brightness != value) { _effect_brightness = value; bump_version("effect-brightness"); } }
        }
        
        public uint64 version { get; private set; default = 0; }
        public uint64 last_update_time { get; private set; default = 0; }
        
        private HashTable<string, uint64?> property_versions;
        
        public Controller(int slot) {
            this.slot = slot;
            this.version = 0;
            this.last_update_time = get_monotonic_time();
            this.property_versions = new HashTable<string, uint64?>(str_hash, str_equal);
            _keymap = new uint8[18];
        }
        
        private Controller.copy_from(Controller other) {
            this.slot = other.slot;
            this.connected = other.connected;
            this.controller_type = other.controller_type;
            this.is_bluetooth = other.is_bluetooth;
            this.dev_path = other.dev_path;
            this.product_name = other.product_name;
            this.serial = other.serial;
            this.driver = other.driver;
            
            this.led_r = other.led_r;
            this.led_g = other.led_g;
            this.led_b = other.led_b;
            this.led_base_r = other.led_base_r;
            this.led_base_g = other.led_base_g;
            this.led_base_b = other.led_base_b;
            this.global_brightness = other.global_brightness;
            this.player_leds = other.player_leds;
            this.led_static = other.led_static;
            this.led_reapply = other.led_reapply;
            
            this.rumble_gain = other.rumble_gain;
            this.deadzone = other.deadzone;
            this.rumble_weak = other.rumble_weak;
            this.rumble_strong = other.rumble_strong;
            this.rumble_active = other.rumble_active;
            
            this.sensitivity_left_preset = other.sensitivity_left_preset;
            this.sensitivity_right_preset = other.sensitivity_right_preset;
            this.invert_ly = other.invert_ly;
            this.invert_ry = other.invert_ry;
            
            this.lx = other.lx;
            this.ly = other.ly;
            this.rx = other.rx;
            this.ry = other.ry;
            this.lt = other.lt;
            this.rt = other.rt;
            this.hatx = other.hatx;
            this.haty = other.haty;
            
            this.square = other.square;
            this.cross = other.cross;
            this.circle = other.circle;
            this.triangle = other.triangle;
            this.l1 = other.l1;
            this.r1 = other.r1;
            this.l2 = other.l2;
            this.r2 = other.r2;
            this.share = other.share;
            this.options = other.options;
            this.ps = other.ps;
            this.l3 = other.l3;
            this.r3 = other.r3;
            this.touch_btn = other.touch_btn;
            
            this.dpad_up = other.dpad_up;
            this.dpad_down = other.dpad_down;
            this.dpad_left = other.dpad_left;
            this.dpad_right = other.dpad_right;
            
            this.emulate_active = other.emulate_active;
            this.is_uhid = other.is_uhid;
            this.debounce_enabled = other.debounce_enabled;
            this.battery = other.battery;
            
            this.keymap = other.keymap;
            
            this.current_effect = other.current_effect;
            this.effect_speed = other.effect_speed;
            this.effect_brightness = other.effect_brightness;
            
            this.version = other.version;
            this.last_update_time = other.last_update_time;
            this.triggers_digital = other.triggers_digital;
            
            // Copy property_versions
            foreach (var key in other.property_versions.get_keys()) {
                this.property_versions.set(key, other.property_versions.lookup(key));
            }
        }
        
public void bump_version(string property) {
    uint64? old = property_versions.lookup(property);
    uint64 new_version = (old != null) ? old + 1 : 1;
    property_versions.set(property, new_version);
    this.version++;
}
        
        public void increment_version() {
    this.version++;
}

        public uint64 get_property_version(string property) {
            uint64? v = property_versions.lookup(property);
            return (v != null) ? v : 0;
        }
        
        public void set_all_property_versions(uint64 base_version) {
            property_versions.remove_all();
            string[] props = {
                "led-r", "led-g", "led-b", "led-base-r", "led-base-g", "led-base-b",
                "global-brightness", "player-leds", "led-static", "led-reapply",
                "rumble-gain", "deadzone", "rumble-weak", "rumble-strong", "rumble-active",
                "sensitivity-left-preset", "sensitivity-right-preset", "invert-ly", "invert-ry",
                "triggers-digital", "emulate-active", "is-uhid", "debounce-enabled",
                "current-effect", "effect-speed", "effect-brightness", "keymap"
            };
            foreach (string p in props) {
                property_versions.set(p, base_version);
            }
        }
        
        public Controller create_updated_from_dbus(uint32[] values) {
            var updated = new Controller.copy_from(this);
            updated.update_from_dbus_arguments(values);
            updated.version = this.version + 1;
            updated.last_update_time = get_monotonic_time();
            updated.set_all_property_versions(updated.version);
            return updated;
        }
        
        public Controller create_updated_with_property(string property, Variant value) {
            var updated = new Controller.copy_from(this);
            
            switch (property) {
                case "led-static":
                    updated.led_static = value.get_boolean();
                    break;
                case "current-effect":
                    updated.current_effect = value.get_byte();
                    break;
                case "effect-speed":
                    updated.effect_speed = value.get_byte();
                    break;
                case "global-brightness":
                    updated.global_brightness = value.get_byte();
                    break;
                case "led-base-r":
                    updated.led_base_r = value.get_byte();
                    break;
                case "led-base-g":
                    updated.led_base_g = value.get_byte();
                    break;
                case "led-base-b":
                    updated.led_base_b = value.get_byte();
                    break;
                case "led-reapply":
                    updated.led_reapply = value.get_boolean();
                    break;
                case "player-leds":
                    updated.player_leds = value.get_byte();
                    break;
                case "rumble-gain":
                    updated.rumble_gain = value.get_byte();
                    break;
                case "rumble-active":
                    updated.rumble_active = value.get_boolean();
                    break;
                case "deadzone":
                    updated.deadzone = value.get_byte();
                    break;
                case "emulate-active":
                    updated.emulate_active = value.get_boolean();
                    break;
                case "is-uhid":
                    updated.is_uhid = value.get_boolean();
                    break;
                case "debounce-enabled":
                    updated.debounce_enabled = value.get_boolean();
                    break;
                case "sensitivity-left-preset":
                    updated.sensitivity_left_preset = value.get_byte();
                    break;
                case "sensitivity-right-preset":
                    updated.sensitivity_right_preset = value.get_byte();
                    break;
                case "invert-ly":
                    updated.invert_ly = value.get_boolean();
                    break;
                case "invert-ry":
                    updated.invert_ry = value.get_boolean();
                    break;
                case "triggers-digital":
                    updated.triggers_digital = value.get_boolean();
                    break;
                default:
                    warning("Controller: Unknown property '%s'", property);
                    break;
            }
            
            updated.version = this.version + 1;
            updated.last_update_time = get_monotonic_time();
            updated.bump_version(property);
            return updated;
        }
        
        private uint8 preset_to_percent(uint8 preset) {
            switch (preset) {
                case 1: return 50;
                case 2: return 150;
                case 3: return 80;
                case 4: return 120;
                case 5: return 30;
                case 6: return 100;
                case 7: return 180;
                default: return 100;
            }
        }
        
        private uint8 percent_to_preset(uint8 percent) {
            if (percent <= 40) return 5;
            if (percent <= 70) return 1;
            if (percent <= 90) return 3;
            if (percent <= 110) return 0;
            if (percent <= 140) return 4;
            if (percent <= 170) return 2;
            return 7;
        }
        
        public void update_from_dbus_arguments(uint32[] values) {
            if (values.length < 52) {
                warning("Controller: Expected 52 values, received %lu", values.length);
                return;
            }

            this.controller_type = (ControllerType)values[0];
            this.is_bluetooth = (values[1] != 0);
            this.led_r = (uint8)values[2];
            this.led_g = (uint8)values[3];
            this.led_b = (uint8)values[4];
            this.led_base_r = (uint8)values[5];
            this.led_base_g = (uint8)values[6];
            this.led_base_b = (uint8)values[7];
            this.battery = (int)values[8];
            this.rumble_gain = (uint8)values[9];
            this.deadzone = (uint8)values[10];
            this.global_brightness = (uint8)values[11];
            this.player_leds = (uint8)values[12];
            this.emulate_active = (values[13] != 0);
            this.is_uhid = (values[14] != 0);
            this.triggers_digital = (values[15] != 0);
            this.debounce_enabled = (values[16] != 0);
            this.led_reapply = (values[17] != 0);
            this.rumble_active = (values[18] != 0);
            this.invert_ly = (values[19] != 0);
            this.invert_ry = (values[20] != 0);
            this.sensitivity_left_preset = (uint8)values[21];
            this.sensitivity_right_preset = (uint8)values[22];
            this.led_static = (values[23] != 0);
            this.current_effect = (uint8)values[24];
            this.effect_speed = (uint8)values[25];

            this.lx = (int16)values[26];
            this.ly = (int16)values[27];
            this.rx = (int16)values[28];
            this.ry = (int16)values[29];
            this.lt = (int16)values[30];
            this.rt = (int16)values[31];
            this.hatx = (int)values[32];
            this.haty = (int)values[33];

            this.square   = (values[34] != 0);
            this.cross    = (values[35] != 0);
            this.circle   = (values[36] != 0);
            this.triangle = (values[37] != 0);
            this.l1       = (values[38] != 0);
            this.r1       = (values[39] != 0);
            this.l2       = (values[40] != 0);
            this.r2       = (values[41] != 0);
            this.share    = (values[42] != 0);
            this.options  = (values[43] != 0);
            this.ps       = (values[44] != 0);
            this.l3       = (values[45] != 0);
            this.r3       = (values[46] != 0);
            this.touch_btn = (values[47] != 0);
            this.dpad_up   = (values[48] != 0);
            this.dpad_down = (values[49] != 0);
            this.dpad_left = (values[50] != 0);
            this.dpad_right = (values[51] != 0);

            this.connected = true;
        }
        
        public void update_from_telemetry(int16 new_lx, int16 new_ly,
                                          int16 new_rx, int16 new_ry,
                                          int16 new_lt, int16 new_rt,
                                          int16 new_hatx, int16 new_haty,
                                          uint16 buttons) {
            this.lx = new_lx;
            this.ly = new_ly;
            this.rx = new_rx;
            this.ry = new_ry;
            this.lt = new_lt;
            this.rt = new_rt;
            this.hatx = new_hatx;
            this.haty = new_haty;
            
            this.cross      = (buttons & (1 << 0)) != 0;
            this.circle     = (buttons & (1 << 1)) != 0;
            this.square     = (buttons & (1 << 2)) != 0;
            this.triangle   = (buttons & (1 << 3)) != 0;
            this.l1         = (buttons & (1 << 4)) != 0;
            this.r1         = (buttons & (1 << 5)) != 0;
            this.l2         = (buttons & (1 << 6)) != 0;
            this.r2         = (buttons & (1 << 7)) != 0;
            this.share      = (buttons & (1 << 8)) != 0;
            this.options    = (buttons & (1 << 9)) != 0;
            this.l3         = (buttons & (1 << 10)) != 0;
            this.r3         = (buttons & (1 << 11)) != 0;
            this.ps         = (buttons & (1 << 12)) != 0;
            this.touch_btn  = (buttons & (1 << 13)) != 0;
            
            this.dpad_up = (new_haty == -1);
            this.dpad_down = (new_haty == 1);
            this.dpad_left = (new_hatx == -1);
            this.dpad_right = (new_hatx == 1);
        }
        
        public void update_buttons_from_bitmap(uint16 buttons) {
            this.cross      = (buttons & (1 << 0)) != 0;
            this.circle     = (buttons & (1 << 1)) != 0;
            this.square     = (buttons & (1 << 2)) != 0;
            this.triangle   = (buttons & (1 << 3)) != 0;
            this.l1         = (buttons & (1 << 4)) != 0;
            this.r1         = (buttons & (1 << 5)) != 0;
            this.l2         = (buttons & (1 << 6)) != 0;
            this.r2         = (buttons & (1 << 7)) != 0;
            this.share      = (buttons & (1 << 8)) != 0;
            this.options    = (buttons & (1 << 9)) != 0;
            this.l3         = (buttons & (1 << 10)) != 0;
            this.r3         = (buttons & (1 << 11)) != 0;
            this.ps         = (buttons & (1 << 12)) != 0;
            this.touch_btn  = (buttons & (1 << 13)) != 0;
        }
        
        public void update_axes(int16 new_lx, int16 new_ly,
                                int16 new_rx, int16 new_ry,
                                int16 new_lt, int16 new_rt,
                                int16 new_hatx, int16 new_haty) {
            this.lx = new_lx;
            this.ly = new_ly;
            this.rx = new_rx;
            this.ry = new_ry;
            this.lt = new_lt;
            this.rt = new_rt;
            this.hatx = new_hatx;
            this.haty = new_haty;
            
            this.dpad_up = (new_haty == -1);
            this.dpad_down = (new_haty == 1);
            this.dpad_left = (new_hatx == -1);
            this.dpad_right = (new_hatx == 1);
        }
        
        public string to_string() {
            return "Controller(slot:%d, type:%s, version:%llu, sensL:%d, sensR:%d)".printf(
                slot, controller_type.to_string(), version,
                sensitivity_left_preset, sensitivity_right_preset);
        }
        
        public bool has_led() {
            return (controller_type == ControllerType.DS4 || 
                    controller_type == ControllerType.DUALSENSE);
        }
        
        public bool is_dualsense() {
            return controller_type == ControllerType.DUALSENSE;
        }
        
        public bool is_ds4() {
            return controller_type == ControllerType.DS4;
        }
        
        public bool is_nsw_pro() {
            return controller_type == ControllerType.NSW_PRO;
        }
        
        public int16 get_ly_adjusted() {
            return invert_ly ? (int16)(-ly) : ly;
        }
        
        public int16 get_ry_adjusted() {
            return invert_ry ? (int16)(-ry) : ry;
        }
        
        public int get_dpad_direction() {
            int dir = 0;
            if (dpad_up) dir = 1;
            if (dpad_right) dir = (dir == 1) ? 2 : 3;
            if (dpad_down) dir = (dir == 1) ? 8 : (dir == 2) ? 4 : 5;
            if (dpad_left) dir = (dir == 3) ? 2 : (dir == 5) ? 6 : 7;
            return dir;
        }
        
        public string get_sensitivity_left_name() {
            if (sensitivity_left_preset <= 7) {
                return ((SensitivityPreset)sensitivity_left_preset).to_display_string();
            }
            return "Default";
        }
        
        public string get_sensitivity_right_name() {
            if (sensitivity_right_preset <= 7) {
                return ((SensitivityPreset)sensitivity_right_preset).to_display_string();
            }
            return "Default";
        }
    }
}
