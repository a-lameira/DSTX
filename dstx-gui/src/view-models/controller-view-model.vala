/*
 * controller-view-model.vala - ViewModel for controller state and signals
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
 * - Maintain a copy of controller state (sticks, buttons, settings, keymap)
 * - Connect to controller signals and update internal state
 * - Emit semantic signals (sticks_changed, triggers_changed, etc.) to UI
 * - Throttle high-frequency updates to avoid excessive UI refreshes
 * - Manage lifecycle of controller binding
 */

// src/view-models/controller-view-model.vala

using Dstx.Models;

namespace Dstx.ViewModels {
    /**
     * This class is GTK-independent and can be tested in isolation.
     */
    public class ControllerViewModel : Object {
        // ==================== MODEL ====================
        private Controller _controller;
        private uint64 _controller_version = 0;
        
        // ==================== INTERNAL STATE ====================
        private bool[] _button_states;
        private int16 _lx;
        private int16 _ly;
        private int16 _rx;
        private int16 _ry;
        private int16 _lt;
        private int16 _rt;
        private bool _l2;
        private bool _r2;
        private uint8 _deadzone;
        private bool _emulate_active;
        private int _battery;
        private bool _is_bluetooth;
        private bool _rumble_active;
        private uint8 _rumble_gain;
        private bool _is_uhid;
        private uint8 _sensitivity_left_preset;
        private uint8 _sensitivity_right_preset;
        private bool _invert_ly;
        private bool _invert_ry;
        private bool _debounce_enabled;
        
        // Keymap: mapping from physical buttons (0..PHY_BTN_COUNT-1) to logical
        private uint8[] _keymap;
        private const int PHY_BTN_COUNT = 18;
        
        // ==================== CHANGE SUMMARY ====================
        private bool _sticks_dirty = false;
        private bool _triggers_dirty = false;
        private bool _buttons_dirty = false;
        private uint _flush_timeout = 0;
        private const uint FLUSH_DELAY_MS = 16;  // ~60fps
        
        // ==================== SIGNALS ====================
        public signal void sticks_changed(int16 lx, int16 ly, int16 rx, int16 ry);
        public signal void triggers_changed(int16 lt, int16 rt);
        public signal void buttons_changed(bool[] states);
        public signal void deadzone_changed(uint8 value);
        public signal void emulation_mode_changed(bool enabled);
        public signal void battery_changed(int percent);
        public signal void connection_changed(bool is_bluetooth);
        public signal void rumble_config_changed(bool active, uint8 gain);
        public signal void uhid_mode_changed(bool enabled);
        public signal void sensitivity_presets_changed(uint8 left, uint8 right);
        public signal void invert_y_changed(bool left, bool right);
        public signal void debounce_changed(bool enabled);
        public signal void keymap_changed();        // notifies that the keymap has changed
        public signal void layout_mode_changed(int mode); // signal for layout change
        
        // Generic signal for any update
        public signal void any_update();
        
        // ==================== PUBLIC PROPERTIES ====================
        public Controller controller {
            get { return _controller; }
        }
        
        public uint64 controller_version {
            get { return _controller_version; }
        }
        
        public bool[] button_states {
            get { return _button_states; }
        }
        
        public int16 lx { get { return _lx; } }
        public int16 ly { get { return _ly; } }
        public int16 rx { get { return _rx; } }
        public int16 ry { get { return _ry; } }
        public int16 lt { get { return _lt; } }
        public int16 rt { get { return _rt; } }
        public bool l2 { get { return _l2; } }
        public bool r2 { get { return _r2; } }
        
        public uint8 deadzone { get { return _deadzone; } }
        public bool emulate_active { get { return _emulate_active; } }
        public int battery { get { return _battery; } }
        public bool is_bluetooth { get { return _is_bluetooth; } }
        public bool rumble_active { get { return _rumble_active; } }
        public uint8 rumble_gain { get { return _rumble_gain; } }
        public bool is_uhid { get { return _is_uhid; } }
        public uint8 sensitivity_left_preset { get { return _sensitivity_left_preset; } }
        public uint8 sensitivity_right_preset { get { return _sensitivity_right_preset; } }
        public bool invert_ly { get { return _invert_ly; } }
        public bool invert_ry { get { return _invert_ry; } }
        public bool debounce_enabled { get { return _debounce_enabled; } }
        
        /**
         * Current visual layout (0 = Xbox, 1 = Switch).
         * This property is explicitly set by the KeybindsDialog.
         */
        public int layout_mode { get; private set; default = 0; }
        
        // ==================== CONSTRUCTOR ====================
        public ControllerViewModel() {
            _button_states = new bool[PHY_BTN_COUNT];
            _keymap = new uint8[PHY_BTN_COUNT];
            reset_state();
        }
        
        private void reset_state() {
            _lx = _ly = _rx = _ry = _lt = _rt = 0;
            _l2 = false;
            _r2 = false;
            _deadzone = 0;
            _emulate_active = false;
            _battery = 0;
            _is_bluetooth = false;
            _rumble_active = true;
            _rumble_gain = 100;
            _is_uhid = false;
            _sensitivity_left_preset = 0;
            _sensitivity_right_preset = 0;
            _invert_ly = false;
            _invert_ry = false;
            _debounce_enabled = true;
            
            for (int i = 0; i < PHY_BTN_COUNT; i++) {
                _button_states[i] = false;
                _keymap[i] = 0;
            }
        }
        
        // ==================== BINDING TO MODEL ====================
        
        /**
         * Binds the ViewModel to a specific Controller.
         * Disconnects any previous binding and connects to the new Controller's signals.
         */
        public void bind(Controller controller) {
            if (_controller != null) {
                unbind();
            }
            
            _controller = controller;
            _controller_version = controller.version;
            
            // Copy initial state
            update_from_controller();
            
            // Connect to Controller notification signals
            connect_controller_signals();
            
            // Synchronize layout_mode and connect to its change signal
            layout_mode = controller.layout_mode;
            controller.notify["layout-mode"].connect(() => {
                layout_mode = controller.layout_mode;
                layout_mode_changed(layout_mode);
                any_update();
            });
        }
        
        /**
         * Disconnects from the current Controller.
         */
        public void unbind() {
            if (_controller == null) return;
            
            _controller = null;
            _controller_version = 0;
            reset_state();
            
            any_update();
        }
        
        /**
         * Updates internal state from the current Controller.
         */
        private void update_from_controller() {
            if (_controller == null) return;
            
            _lx = _controller.lx;
            _ly = _controller.ly;
            _rx = _controller.rx;
            _ry = _controller.ry;
            _lt = _controller.lt;
            _rt = _controller.rt;
            _l2 = _controller.l2;
            _r2 = _controller.r2;
            _deadzone = _controller.deadzone;
            _emulate_active = _controller.emulate_active;
            _battery = _controller.battery;
            _is_bluetooth = _controller.is_bluetooth;
            _rumble_active = _controller.rumble_active;
            _rumble_gain = _controller.rumble_gain;
            _is_uhid = _controller.is_uhid;
            _sensitivity_left_preset = _controller.sensitivity_left_preset;
            _sensitivity_right_preset = _controller.sensitivity_right_preset;
            _invert_ly = _controller.invert_ly;
            _invert_ry = _controller.invert_ry;
            _debounce_enabled = _controller.debounce_enabled;
            
            // Copy keymap
            bool keymap_changed = false;
            for (int i = 0; i < PHY_BTN_COUNT; i++) {
                uint8 new_val = _controller.keymap[i];
                if (_keymap[i] != new_val) {
                    _keymap[i] = new_val;
                    keymap_changed = true;
                }
            }
            if (keymap_changed) {
                Idle.add(emit_keymap_changed_signal);
            }
            
            // Update buttons
            update_button(BTN_CROSS, _controller.cross);
            update_button(BTN_CIRCLE, _controller.circle);
            update_button(BTN_SQUARE, _controller.square);
            update_button(BTN_TRIANGLE, _controller.triangle);
            update_button(BTN_L1, _controller.l1);
            update_button(BTN_R1, _controller.r1);
            update_button(BTN_L2, _controller.l2);
            update_button(BTN_R2, _controller.r2);
            update_button(BTN_SHARE, _controller.share);
            update_button(BTN_OPTIONS, _controller.options);
            update_button(BTN_PS, _controller.ps);
            update_button(BTN_L3, _controller.l3);
            update_button(BTN_R3, _controller.r3);
            update_button(BTN_TOUCH, _controller.touch_btn);
            update_button(BTN_DPAD_UP, _controller.dpad_up);
            update_button(BTN_DPAD_DOWN, _controller.dpad_down);
            update_button(BTN_DPAD_LEFT, _controller.dpad_left);
            update_button(BTN_DPAD_RIGHT, _controller.dpad_right);
        }
        
        // Helper method to emit keymap_changed signal (avoids context error)
        private bool emit_keymap_changed_signal() {
            keymap_changed();
            return Source.REMOVE;
        }
        
        private void update_button(int idx, bool pressed) {
            if (_button_states[idx] != pressed) {
                _button_states[idx] = pressed;
                _buttons_dirty = true;
                schedule_flush();
            }
        }
        
        // ==================== CONNECTING TO CONTROLLER SIGNALS ====================
        
        private void connect_controller_signals() {
            // Sticks and triggers (high-frequency telemetry)
            _controller.notify["lx"].connect(() => {
                _lx = _controller.lx;
                _sticks_dirty = true;
                schedule_flush();
            });
            _controller.notify["ly"].connect(() => {
                _ly = _controller.ly;
                _sticks_dirty = true;
                schedule_flush();
            });
            _controller.notify["rx"].connect(() => {
                _rx = _controller.rx;
                _sticks_dirty = true;
                schedule_flush();
            });
            _controller.notify["ry"].connect(() => {
                _ry = _controller.ry;
                _sticks_dirty = true;
                schedule_flush();
            });
            _controller.notify["lt"].connect(() => {
                _lt = _controller.lt;
                _triggers_dirty = true;
                schedule_flush();
            });
            _controller.notify["rt"].connect(() => {
                _rt = _controller.rt;
                _triggers_dirty = true;
                schedule_flush();
            });
            _controller.notify["l2"].connect(() => {
                _l2 = _controller.l2;
                _triggers_dirty = true;
                schedule_flush();
            });
            _controller.notify["r2"].connect(() => {
                _r2 = _controller.r2;
                _triggers_dirty = true;
                schedule_flush();
            });
            
            // Buttons
            _controller.notify["cross"].connect(() => update_button(BTN_CROSS, _controller.cross));
            _controller.notify["circle"].connect(() => update_button(BTN_CIRCLE, _controller.circle));
            _controller.notify["square"].connect(() => update_button(BTN_SQUARE, _controller.square));
            _controller.notify["triangle"].connect(() => update_button(BTN_TRIANGLE, _controller.triangle));
            _controller.notify["l1"].connect(() => update_button(BTN_L1, _controller.l1));
            _controller.notify["r1"].connect(() => update_button(BTN_R1, _controller.r1));
            _controller.notify["l2"].connect(() => update_button(BTN_L2, _controller.l2));
            _controller.notify["r2"].connect(() => update_button(BTN_R2, _controller.r2));
            _controller.notify["share"].connect(() => update_button(BTN_SHARE, _controller.share));
            _controller.notify["options"].connect(() => update_button(BTN_OPTIONS, _controller.options));
            _controller.notify["ps"].connect(() => update_button(BTN_PS, _controller.ps));
            _controller.notify["l3"].connect(() => update_button(BTN_L3, _controller.l3));
            _controller.notify["r3"].connect(() => update_button(BTN_R3, _controller.r3));
            _controller.notify["touch-btn"].connect(() => update_button(BTN_TOUCH, _controller.touch_btn));
            _controller.notify["dpad-up"].connect(() => update_button(BTN_DPAD_UP, _controller.dpad_up));
            _controller.notify["dpad-down"].connect(() => update_button(BTN_DPAD_DOWN, _controller.dpad_down));
            _controller.notify["dpad-left"].connect(() => update_button(BTN_DPAD_LEFT, _controller.dpad_left));
            _controller.notify["dpad-right"].connect(() => update_button(BTN_DPAD_RIGHT, _controller.dpad_right));
            
            // Configuration (low frequency, but propagate immediately)
            _controller.notify["deadzone"].connect(() => {
                _deadzone = _controller.deadzone;
                deadzone_changed(_deadzone);
                schedule_flush();
            });
            _controller.notify["emulate-active"].connect(() => {
                _emulate_active = _controller.emulate_active;
                emulation_mode_changed(_emulate_active);
                schedule_flush();
            });
            _controller.notify["battery"].connect(() => {
                _battery = _controller.battery;
                battery_changed(_battery);
                schedule_flush();
            });
            _controller.notify["is-bluetooth"].connect(() => {
                _is_bluetooth = _controller.is_bluetooth;
                connection_changed(_is_bluetooth);
                schedule_flush();
            });
            _controller.notify["rumble-active"].connect(() => {
                _rumble_active = _controller.rumble_active;
                rumble_config_changed(_rumble_active, _rumble_gain);
                schedule_flush();
            });
            _controller.notify["rumble-gain"].connect(() => {
                _rumble_gain = _controller.rumble_gain;
                rumble_config_changed(_rumble_active, _rumble_gain);
                schedule_flush();
            });
            _controller.notify["is-uhid"].connect(() => {
                _is_uhid = _controller.is_uhid;
                uhid_mode_changed(_is_uhid);
                schedule_flush();
            });
            _controller.notify["sensitivity-left-preset"].connect(() => {
                _sensitivity_left_preset = _controller.sensitivity_left_preset;
                sensitivity_presets_changed(_sensitivity_left_preset, _sensitivity_right_preset);
                schedule_flush();
            });
            _controller.notify["sensitivity-right-preset"].connect(() => {
                _sensitivity_right_preset = _controller.sensitivity_right_preset;
                sensitivity_presets_changed(_sensitivity_left_preset, _sensitivity_right_preset);
                schedule_flush();
            });
            _controller.notify["invert-ly"].connect(() => {
                _invert_ly = _controller.invert_ly;
                invert_y_changed(_invert_ly, _invert_ry);
                schedule_flush();
            });
            _controller.notify["invert-ry"].connect(() => {
                _invert_ry = _controller.invert_ry;
                invert_y_changed(_invert_ly, _invert_ry);
                schedule_flush();
            });
            _controller.notify["debounce-enabled"].connect(() => {
                _debounce_enabled = _controller.debounce_enabled;
                debounce_changed(_debounce_enabled);
                schedule_flush();
            });
        }
        
        // ==================== THROTTLE FOR HIGH-FREQUENCY SIGNALS ====================
        
        private void schedule_flush() {
            if (_flush_timeout != 0) return;
            
            _flush_timeout = Timeout.add(FLUSH_DELAY_MS, () => {
                flush_updates();
                _flush_timeout = 0;
                return Source.REMOVE;
            });
        }
        
        private void flush_updates() {
            bool emitted = false;
            
            if (_sticks_dirty) {
                sticks_changed(_lx, _ly, _rx, _ry);
                _sticks_dirty = false;
                emitted = true;
            }
            
            if (_triggers_dirty) {
                triggers_changed(_lt, _rt);
                _triggers_dirty = false;
                emitted = true;
            }
            
            if (_buttons_dirty) {
                buttons_changed(_button_states);
                _buttons_dirty = false;
                emitted = true;
            }
            
            if (emitted) {
                any_update();
            }
        }
        
        // ==================== HELPER METHODS ====================
        
        /**
         * Gets the state of a specific button.
         * @param button_id (e.g., BTN_CROSS)
         */
        public bool get_button_state(int button_id) {
            if (button_id < 0 || button_id >= _button_states.length) return false;
            return _button_states[button_id];
        }
        
        /**
         * Gets the logical index mapped to a physical button.
         * @param physical Physical button index (e.g., BTN_CROSS)
         * @return Logical index (1=A,2=B,3=X,4=Y, 0=none/others)
         */
        public uint8 get_logical_for_physical(int physical) {
            if (physical < 0 || physical >= PHY_BTN_COUNT) return 0;
            return _keymap[physical];
        }
        
        /**
         * Returns a copy of the current keymap.
         */
        public uint8[] get_keymap() {
            uint8[] copy = new uint8[PHY_BTN_COUNT];
            Memory.copy(copy, _keymap, PHY_BTN_COUNT);
            return copy;
        }
        
        /**
         * Updates the keymap from the controller (called externally when controller is reloaded).
         * Can be used after a `controller_updated` signal.
         */
        public void refresh_keymap() {
            if (_controller == null) return;
            bool changed = false;
            for (int i = 0; i < PHY_BTN_COUNT; i++) {
                uint8 new_val = _controller.keymap[i];
                if (_keymap[i] != new_val) {
                    _keymap[i] = new_val;
                    changed = true;
                }
            }
            if (changed) {
                keymap_changed();
                any_update();  // forces redraw
            }
        }
        
        /**
         * Forces immediate update of all signals (useful after rebind).
         */
        public void force_refresh() {
            sticks_changed(_lx, _ly, _rx, _ry);
            triggers_changed(_lt, _rt);
            buttons_changed(_button_states);
            deadzone_changed(_deadzone);
            emulation_mode_changed(_emulate_active);
            battery_changed(_battery);
            connection_changed(_is_bluetooth);
            rumble_config_changed(_rumble_active, _rumble_gain);
            uhid_mode_changed(_is_uhid);
            sensitivity_presets_changed(_sensitivity_left_preset, _sensitivity_right_preset);
            invert_y_changed(_invert_ly, _invert_ry);
            debounce_changed(_debounce_enabled);
            keymap_changed();
            layout_mode_changed(layout_mode);
            any_update();
        }
        
        // ==================== BUTTON CONSTANTS ====================
        public const int BTN_CROSS = 0;
        public const int BTN_CIRCLE = 1;
        public const int BTN_SQUARE = 2;
        public const int BTN_TRIANGLE = 3;
        public const int BTN_L1 = 4;
        public const int BTN_R1 = 5;
        public const int BTN_L2 = 6;
        public const int BTN_R2 = 7;
        public const int BTN_L3 = 8;
        public const int BTN_R3 = 9;
        public const int BTN_SHARE = 10;
        public const int BTN_OPTIONS = 11;
        public const int BTN_PS = 12;
        public const int BTN_TOUCH = 13;
        public const int BTN_DPAD_UP = 14;
        public const int BTN_DPAD_DOWN = 15;
        public const int BTN_DPAD_LEFT = 16;
        public const int BTN_DPAD_RIGHT = 17;
        
        // ==================== DESTRUCTOR ====================
        ~ControllerViewModel() {
            if (_flush_timeout != 0) {
                Source.remove(_flush_timeout);
                _flush_timeout = 0;
            }
            unbind();
        }
    }
}
