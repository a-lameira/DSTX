/*
 * settings-ui-builder.vala - Builds and manages the settings UI for controllers
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
 * - Build and update the settings UI for controller configuration
 * - Handle LED, rumble, stick, trigger, emulation, buttons settings
 * - Manage visibility and debouncing of UI controls
 * - Provide preferences dialog for global settings (language, appearance, service, auto-save)
 * - Integrate with SettingsController and ProfileManager
 */

// src/managers/settings-ui-builder.vala

using Dstx.Core;
using Dstx.Models;
using Dstx.Widgets;
using Gtk;

namespace Dstx.Managers {
    public class SettingsUIBuilder : Object {
        private unowned Gtk.ScrolledWindow? settings_scrolled;
        private DBusClient dbus_client;
        private SettingsController controller;
        private ProfileManager profile_manager;
        private unowned ControllerManager? controller_manager = null;
        private Gtk.Window? parent_window = null;

        private ulong config_changed_handler_id = 0;
        private ulong controller_updated_handler_id = 0;

        private uint gain_timeout = 0;
        private uint deadzone_timeout = 0;
        private uint brightness_timeout = 0;
        private uint speed_timeout = 0;
        private uint player_timeout = 0;

        private Adw.SpinRow? gain_row = null;
        private Adw.SpinRow? deadzone_row = null;
        private Adw.SpinRow? brightness_row = null;
        private Adw.SpinRow? player_row = null;
        private Adw.SwitchRow? emulate_switch = null;
        private Adw.SwitchRow? debounce_switch = null;
        private Adw.SwitchRow? rumble_active_switch = null;
        private Adw.ComboRow? emulation_mode_row = null;
        private Adw.ComboRow? led_mode_row = null;
        private Adw.ComboRow? effect_row = null;
        private Adw.SpinRow? speed_row = null;
        private Gtk.DrawingArea? color_preview = null;
        private Adw.ActionRow? color_row = null;
        private Adw.SwitchRow? reapply_switch = null;

        private Adw.ComboRow? sens_left_row = null;
        private Adw.ComboRow? sens_right_row = null;
        private Adw.SwitchRow? invert_ly_switch = null;
        private Adw.SwitchRow? invert_ry_switch = null;
        private Adw.SwitchRow? triggers_digital_switch = null;

        private Adw.PreferencesGroup? profile_group = null;
        private Adw.ActionRow? current_profile_row = null;

        private Adw.PreferencesGroup? rumble_group = null;
        private Adw.PreferencesGroup? led_group = null;
        private Adw.PreferencesGroup? emulation_group = null;
        private Adw.PreferencesGroup? stick_group = null;
        private Adw.PreferencesGroup? buttons_group = null;
        private Adw.PreferencesGroup? triggers_group = null;

        private Adw.ActionRow? stop_row = null;
        private Adw.ActionRow? start_row = null;
        private Gtk.Label? service_status_label = null;

        private bool updating_from_controller = false;
        private bool building_ui = false;
        private Gdk.RGBA current_color;
        private Gdk.RGBA current_base_rgb;
        private double current_saturation = 100.0;
        private Gdk.RGBA[] recent_colors = {};
        private Controller? current_controller = null;

        private Gtk.Button? flatpak_action_button = null;
        private Adw.ActionRow? flatpak_row = null;
        private bool flatpak_components_installed = false;

        private uint64 last_known_version = 0;

        private const string[] SENSITIVITY_PRESET_NAMES = {
            N_("Default"),
            N_("Precision"),
            N_("Rapid"),
            N_("Smooth"),
            N_("Aggressive"),
            N_("Sniper"),
            N_("Racing"),
            N_("FPS")
        };

        private const string[] EFFECT_NAMES = {
            N_("Breathing"),
            N_("Rainbow"),
            N_("Pulse"),
            N_("Blink"),
            N_("Wave"),
            N_("Battery"),
            N_("Triggers"),
            N_("Buttons")
        };

        public SettingsUIBuilder(DBusClient dbus_client, ProfileManager profile_manager,
                                 ControllerManager controller_manager,
                                 Gtk.ScrolledWindow? settings_scrolled) {
            this.settings_scrolled = settings_scrolled;
            this.dbus_client = dbus_client;
            this.profile_manager = profile_manager;
            this.controller_manager = controller_manager;
            this.controller = new SettingsController(dbus_client);
            connect_controller_signals();
            connect_controller_manager_signals();
        }

        // ==================== CURRENT PROFILE ====================
        private Adw.PreferencesGroup create_profile_group() {
            var group = new Adw.PreferencesGroup();
            group.set_title(_("Current Profile"));

            current_profile_row = new Adw.ActionRow();
            current_profile_row.set_title(_("Loading..."));
            current_profile_row.set_activatable(false);

            group.add(current_profile_row);
            return group;
        }

        public async void refresh_current_profile() {
            if (current_profile_row == null) return;
            try {
                string profile = yield dbus_client.get_current_profile();
                current_profile_row.set_title(profile);
            } catch (Error e) {
                current_profile_row.set_title(_("Error: %s").printf(e.message));
            }
        }

        // ==================== SIGNAL CONNECTIONS ====================
        private void connect_controller_signals() {
            controller.controller_changed.connect(on_controller_changed);
            controller.led_static_changed.connect(on_led_static_changed);
            controller.effect_changed.connect(on_effect_changed);
            controller.led_color_changed.connect(on_led_color_changed);
            controller.led_reapply_changed.connect(on_led_reapply_changed);
            controller.player_leds_changed.connect(on_player_leds_changed);
            controller.brightness_changed.connect(on_brightness_changed);
            controller.rumble_active_changed.connect(on_rumble_active_changed);
            controller.rumble_gain_changed.connect(on_rumble_gain_changed);
            controller.deadzone_changed.connect(on_deadzone_changed);
            controller.emulate_active_changed.connect(on_emulate_active_changed);
            controller.emulation_mode_changed.connect(on_emulation_mode_changed);
            controller.debounce_changed.connect(on_debounce_changed);
            controller.sensitivity_left_changed.connect(on_sensitivity_left_changed);
            controller.sensitivity_right_changed.connect(on_sensitivity_right_changed);
            controller.invert_ly_changed.connect(on_invert_ly_changed);
            controller.invert_ry_changed.connect(on_invert_ry_changed);
            controller.triggers_digital_changed.connect(on_triggers_digital_changed);
        }

        private void connect_controller_manager_signals() {
            if (controller_manager == null) return;
            config_changed_handler_id = controller_manager.controller_config_changed.connect((controller) => {
                if (current_controller != null && current_controller.slot == controller.slot) {
                    update_ui_from_controller(controller);
                }
            });
            controller_updated_handler_id = controller_manager.controller_updated.connect((controller) => {
                if (current_controller != null && current_controller.slot == controller.slot) {
                    update_ui_from_controller(controller);
                }
            });
        }

        // ==================== UI UPDATE WITH VERSIONING ====================
        private void update_ui_from_controller(Controller controller) {
            if (building_ui || updating_from_controller) return;
            if (controller.version <= last_known_version) return;
            last_known_version = controller.version;
            message("SettingsUIBuilder: update_ui_from_controller, version %llu", controller.version);

            updating_from_controller = true;

            // LED mode
            if (led_mode_row != null) {
                uint new_selected = controller.led_static ? 0 : 1;
                if (led_mode_row.get_selected() != new_selected) {
                    led_mode_row.set_selected(new_selected);
                }
                update_led_options_visibility(controller.led_static);
                if (!controller.led_static && effect_row != null) {
                    update_visibility_for_effect(effect_row.get_selected());
                }
            }

            // Effect
            if (effect_row != null && !controller.led_static) {
                uint new_index = (controller.current_effect >= 1 && controller.current_effect <= 8) ?
                                 controller.current_effect - 1 : 0;
                if (effect_row.get_selected() != new_index) {
                    effect_row.set_selected(new_index);
                }
                update_visibility_for_effect(new_index);
            }

            // Speed, brightness, reapply, player LEDs
            if (speed_row != null && speed_row.get_value() != controller.effect_speed)
                speed_row.set_value(controller.effect_speed);
            if (brightness_row != null && brightness_row.get_value() != controller.global_brightness)
                brightness_row.set_value(controller.global_brightness);
            if (reapply_switch != null && reapply_switch.get_active() != controller.led_reapply)
                reapply_switch.set_active(controller.led_reapply);
            if (player_row != null && player_row.get_value() != controller.player_leds)
                player_row.set_value(controller.player_leds);

            // LED color
            if (current_controller == null ||
                current_controller.led_base_r != controller.led_base_r ||
                current_controller.led_base_g != controller.led_base_g ||
                current_controller.led_base_b != controller.led_base_b) {
                
                current_color = Gdk.RGBA() {
                    red = controller.led_base_r / 255.0f,
                    green = controller.led_base_g / 255.0f,
                    blue = controller.led_base_b / 255.0f,
                    alpha = 1.0f
                };
                current_base_rgb = current_color;
                if (color_preview != null) color_preview.queue_draw();
            }

            // Rumble
            if (rumble_active_switch != null && rumble_active_switch.get_active() != controller.rumble_active) {
                rumble_active_switch.set_active(controller.rumble_active);
                if (gain_row != null) gain_row.visible = controller.rumble_active;
            }
            if (gain_row != null && gain_row.get_value() != controller.rumble_gain)
                gain_row.set_value(controller.rumble_gain);

            // Sticks
            if (deadzone_row != null && deadzone_row.get_value() != controller.deadzone)
                deadzone_row.set_value(controller.deadzone);
            if (sens_left_row != null && sens_left_row.get_selected() != controller.sensitivity_left_preset)
                sens_left_row.set_selected(controller.sensitivity_left_preset);
            if (sens_right_row != null && sens_right_row.get_selected() != controller.sensitivity_right_preset)
                sens_right_row.set_selected(controller.sensitivity_right_preset);
            if (invert_ly_switch != null && invert_ly_switch.get_active() != controller.invert_ly)
                invert_ly_switch.set_active(controller.invert_ly);
            if (invert_ry_switch != null && invert_ry_switch.get_active() != controller.invert_ry)
                invert_ry_switch.set_active(controller.invert_ry);
            if (triggers_digital_switch != null && triggers_digital_switch.get_active() != controller.triggers_digital) {
                message("SettingsUIBuilder: Updating triggers_digital_switch to %s", controller.triggers_digital.to_string());
                triggers_digital_switch.set_active(controller.triggers_digital);
            }
            if (debounce_switch != null && debounce_switch.get_active() != controller.debounce_enabled)
                debounce_switch.set_active(controller.debounce_enabled);

            // Emulation
            if (emulate_switch != null && emulate_switch.get_active() != controller.emulate_active) {
                emulate_switch.set_active(controller.emulate_active);
                update_emulation_dependent_visibility(controller.emulate_active);
                if (controller.emulate_active) update_rumble_visibility(controller.is_uhid);
            }
            if (emulation_mode_row != null && emulation_mode_row.get_selected() != (controller.is_uhid ? 1u : 0u)) {
                emulation_mode_row.set_selected(controller.is_uhid ? 1 : 0);
                if (controller.emulate_active) update_rumble_visibility(controller.is_uhid);
            }

            current_controller = controller;
            updating_from_controller = false;
        }

        // ==================== EVENT METHODS (CONTROLLER SIGNALS) ====================
        private void on_controller_changed(Controller controller) {
            current_controller = controller;
            last_known_version = controller.version;
            build_ui(controller);
        }

        private void on_led_static_changed(bool is_static, uint64 version) {
            if (building_ui) return;
            uint64 last_sent = controller.get_last_sent_version("led-static");
            if (version < last_sent) return;
            if (led_mode_row == null) return;
            message("SettingsUIBuilder: LED static changed to %s, version %llu", is_static.to_string(), version);
            update_led_options_visibility(is_static);
            if (!is_static && effect_row != null) {
                update_visibility_for_effect(effect_row.get_selected());
            }
            uint new_selected = is_static ? 0 : 1;
            if (led_mode_row.get_selected() != new_selected) {
                updating_from_controller = true;
                led_mode_row.set_selected(new_selected);
                updating_from_controller = false;
            }
        }

private void on_effect_changed(uint8 effect, uint8 speed, uint8 brightness, uint64 version) {
    // Do not process during UI construction
    if (building_ui) return;
    
    // If UI is already being updated by user action, ignore to avoid loop
    if (updating_from_controller) return;
    
    if (effect_row == null) return;
    
    uint new_index = (effect >= 1 && effect <= 8) ? effect - 1 : 0;
    bool changed = false;
    
    // Update effect index if different
    if (effect_row.get_selected() != new_index) {
        updating_from_controller = true;
        effect_row.set_selected(new_index);
        changed = true;
    }
    
    // Update speed
    if (speed_row != null && speed_row.get_value() != speed) {
        if (!changed) updating_from_controller = true;
        speed_row.set_value(speed);
        changed = true;
    }
    
    // Update brightness
    if (brightness_row != null && brightness_row.get_value() != brightness) {
        if (!changed) updating_from_controller = true;
        brightness_row.set_value(brightness);
        changed = true;
    }
    
    // Update visibility of widgets (color and speed) according to the new effect,
    // only if we are in dynamic mode.
    if (!current_controller.led_static) {
        update_visibility_for_effect(new_index);
    }
    
    if (changed) {
        updating_from_controller = false;
        // Force redraw of the effect row to ensure text is updated
        effect_row.queue_draw();
    }
}

        private void on_led_color_changed(uint8 r, uint8 g, uint8 b, uint64 version) {
            if (updating_from_controller || building_ui) return;
            uint64 last_sent = controller.get_last_sent_version("led-base-r");
            if (version < last_sent) return;
            current_color = Gdk.RGBA() { red = r / 255.0f, green = g / 255.0f, blue = b / 255.0f, alpha = 1.0f };
            current_base_rgb = current_color;
            if (color_preview != null) color_preview.queue_draw();
        }

        private void on_led_reapply_changed(bool enabled, uint64 version) {
            if (building_ui) return;
            uint64 last_sent = controller.get_last_sent_version("led-reapply");
            if (version < last_sent) return;
            if (reapply_switch == null) return;
            if (reapply_switch.get_active() == enabled) return;
            updating_from_controller = true;
            reapply_switch.set_active(enabled);
            updating_from_controller = false;
        }

        private void on_player_leds_changed(uint8 mode, uint64 version) {
            if (building_ui) return;
            uint64 last_sent = controller.get_last_sent_version("player-leds");
            if (version < last_sent) return;
            if (player_row == null) return;
            if (player_row.get_value() == mode) return;
            updating_from_controller = true;
            player_row.set_value(mode);
            updating_from_controller = false;
        }

        private void on_brightness_changed(uint8 value, uint64 version) {
            if (building_ui) return;
            uint64 last_sent = controller.get_last_sent_version("global-brightness");
            if (version < last_sent) return;
            if (brightness_row == null) return;
            if (brightness_row.get_value() == value) return;
            updating_from_controller = true;
            brightness_row.set_value(value);
            updating_from_controller = false;
        }

        private void on_rumble_active_changed(bool active, uint64 version) {
            if (building_ui) return;
            uint64 last_sent = controller.get_last_sent_version("rumble-active");
            if (version < last_sent) return;
            if (rumble_active_switch == null) return;
            if (gain_row != null) gain_row.visible = active;
            if (rumble_active_switch.get_active() != active) {
                updating_from_controller = true;
                rumble_active_switch.set_active(active);
                updating_from_controller = false;
            }
        }

        private void on_rumble_gain_changed(uint8 gain, uint64 version) {
            if (building_ui) return;
            uint64 last_sent = controller.get_last_sent_version("rumble-gain");
            if (version < last_sent) return;
            if (gain_row == null) return;
            if (gain_row.get_value() == gain) return;
            updating_from_controller = true;
            gain_row.set_value(gain);
            updating_from_controller = false;
        }

        private void on_deadzone_changed(uint8 deadzone, uint64 version) {
            if (building_ui) return;
            uint64 last_sent = controller.get_last_sent_version("deadzone");
            if (version < last_sent) return;
            if (deadzone_row == null) return;
            if (deadzone_row.get_value() == deadzone) return;
            updating_from_controller = true;
            deadzone_row.set_value(deadzone);
            updating_from_controller = false;
        }

        private void on_emulate_active_changed(bool active, uint64 version) {
            if (building_ui) return;
            uint64 last_sent = controller.get_last_sent_version("emulate-active");
            if (version < last_sent) return;
            if (emulate_switch == null) return;
            message("SettingsUIBuilder: Emulate active changed to %s, version %llu", active.to_string(), version);
            update_emulation_dependent_visibility(active);
            if (active && current_controller != null) update_rumble_visibility(current_controller.is_uhid);
            if (emulate_switch.get_active() != active) {
                updating_from_controller = true;
                emulate_switch.set_active(active);
                updating_from_controller = false;
            }
        }

        private void on_emulation_mode_changed(bool is_uhid, uint64 version) {
            if (building_ui) return;
            uint64 last_sent = controller.get_last_sent_version("is-uhid");
            if (version < last_sent) return;
            if (emulation_mode_row == null) return;
            message("SettingsUIBuilder: Emulation mode changed to UHID=%s, version %llu", is_uhid.to_string(), version);
            if (current_controller != null && current_controller.emulate_active) update_rumble_visibility(is_uhid);
            uint new_selected = is_uhid ? 1 : 0;
            if (emulation_mode_row.get_selected() != new_selected) {
                updating_from_controller = true;
                emulation_mode_row.set_selected(new_selected);
                updating_from_controller = false;
            }
        }

        private void on_debounce_changed(bool enabled, uint64 version) {
            if (building_ui) return;
            uint64 last_sent = controller.get_last_sent_version("debounce-enabled");
            if (version < last_sent) return;
            if (debounce_switch == null) return;
            if (debounce_switch.get_active() == enabled) return;
            updating_from_controller = true;
            debounce_switch.set_active(enabled);
            updating_from_controller = false;
        }

        private void on_sensitivity_left_changed(uint8 preset, uint64 version) {
            if (building_ui) return;
            uint64 last_sent = controller.get_last_sent_version("sensitivity-left-preset");
            if (version < last_sent) return;
            if (sens_left_row == null) return;
            if (sens_left_row.get_selected() == preset) return;
            updating_from_controller = true;
            sens_left_row.set_selected(preset);
            updating_from_controller = false;
        }

        private void on_sensitivity_right_changed(uint8 preset, uint64 version) {
            if (building_ui) return;
            uint64 last_sent = controller.get_last_sent_version("sensitivity-right-preset");
            if (version < last_sent) return;
            if (sens_right_row == null) return;
            if (sens_right_row.get_selected() == preset) return;
            updating_from_controller = true;
            sens_right_row.set_selected(preset);
            updating_from_controller = false;
        }

        private void on_invert_ly_changed(bool enabled, uint64 version) {
            if (building_ui) return;
            uint64 last_sent = controller.get_last_sent_version("invert-ly");
            if (version < last_sent) return;
            if (invert_ly_switch == null) return;
            if (invert_ly_switch.get_active() == enabled) return;
            updating_from_controller = true;
            invert_ly_switch.set_active(enabled);
            updating_from_controller = false;
        }

        private void on_invert_ry_changed(bool enabled, uint64 version) {
            if (building_ui) return;
            uint64 last_sent = controller.get_last_sent_version("invert-ry");
            if (version < last_sent) return;
            if (invert_ry_switch == null) return;
            if (invert_ry_switch.get_active() == enabled) return;
            updating_from_controller = true;
            invert_ry_switch.set_active(enabled);
            updating_from_controller = false;
        }
        
        private void on_triggers_digital_changed(bool enabled, uint64 version) {
            message("SettingsUIBuilder: triggers_digital_changed received: enabled=%s, version=%llu", enabled.to_string(), version);
            if (building_ui) return;
            uint64 last_sent = controller.get_last_sent_version("triggers-digital");
            if (version < last_sent) {
                message("SettingsUIBuilder: ignoring obsolete version (%llu < %llu)", version, last_sent);
                return;
            }
            if (triggers_digital_switch == null) return;
            if (triggers_digital_switch.get_active() == enabled) return;
            updating_from_controller = true;
            triggers_digital_switch.set_active(enabled);
            updating_from_controller = false;
        }

        // ==================== VISIBILITY METHODS ====================
private void update_led_options_visibility(bool is_static) {
    if (effect_row != null) effect_row.visible = !is_static;
    if (reapply_switch != null) reapply_switch.visible = is_static;
    if (speed_row != null) speed_row.visible = !is_static;
    // Do not change color_row here; it will be controlled by the effect.
    if (led_group != null) led_group.queue_draw();
    if (settings_scrolled != null) settings_scrolled.queue_resize();
}

        private void update_visibility_for_effect(uint effect_index) {
            if (current_controller == null) return;
            bool should_show_color = true, should_show_speed = true;
            switch (effect_index) {
                case 1:  // Rainbow
                    should_show_color = false;
                    should_show_speed = true;
                    break;
                case 4:  // Wave
                    should_show_color = false;
                    should_show_speed = true;
                    break;
                case 5:  // Battery
                    should_show_color = false;
                    should_show_speed = false;
                    break;
                case 6:  // Triggers
                    should_show_color = true;
                    should_show_speed = false;
                    break;
                case 7:  // Buttons
                    should_show_color = true;
                    should_show_speed = false;
                    break;
                default:
                    should_show_color = true;
                    should_show_speed = true;
                    break;
            }
            if (!current_controller.led_static) {
                if (color_row != null) color_row.visible = should_show_color;
                if (speed_row != null) speed_row.visible = should_show_speed;
                message("SettingsUIBuilder: Effect visibility updated (color=%s, speed=%s)", 
                        should_show_color.to_string(), should_show_speed.to_string());
            } else {
                // In static mode, color should be visible and speed invisible
                if (color_row != null) color_row.visible = true;
                if (speed_row != null) speed_row.visible = false;
            }
            if (settings_scrolled != null) settings_scrolled.queue_resize();
        }

        private void update_emulation_dependent_visibility(bool emulate_active) {
            if (emulation_mode_row != null) emulation_mode_row.visible = emulate_active;
            if (rumble_group != null) rumble_group.visible = emulate_active;
            if (stick_group != null) stick_group.visible = emulate_active;
            if (buttons_group != null) buttons_group.visible = emulate_active;
            if (triggers_group != null) triggers_group.visible = emulate_active;
            if (settings_scrolled != null) settings_scrolled.queue_resize();
            message("SettingsUIBuilder: Emulation dependent visibility updated (active=%s)", emulate_active.to_string());
        }

        private void update_rumble_visibility(bool is_uhid) {
            if (rumble_group != null && current_controller != null && current_controller.emulate_active) {
                rumble_group.visible = !is_uhid;
                if (settings_scrolled != null) settings_scrolled.queue_resize();
                message("SettingsUIBuilder: Rumble visibility updated (visible=%s)", (!is_uhid).to_string());
            }
        }

        // ==================== UI BUILDING METHODS ====================
        public void build_for_controller(Controller controller, Gtk.Window parent) {
            if (controller == null || settings_scrolled == null) return;
            this.parent_window = parent;
            this.controller.set_current_controller(controller);
        }

        private void build_ui(Controller controller) {
            if (settings_scrolled == null) return;
            message("SettingsUIBuilder: Building UI for %s", controller.to_string());

            building_ui = true;
            updating_from_controller = true;

            // Create a temporary container (not yet added to the tree)
            var temp_page = new Adw.PreferencesPage();
            temp_page.vexpand = true;
            // Do not add to settings_scrolled yet

            try {
                reset_widget_references();

                profile_group = create_profile_group();
                temp_page.add(profile_group);

                if (supports_led(controller)) {
                    led_group = create_led_group();
                    temp_page.add(led_group);
                }

                emulation_group = create_emulation_group();
                temp_page.add(emulation_group);

                rumble_group = create_rumble_group();
                temp_page.add(rumble_group);

                stick_group = create_stick_group();
                temp_page.add(stick_group);

                triggers_group = create_triggers_group();
                temp_page.add(triggers_group);

                buttons_group = create_buttons_group();
                temp_page.add(buttons_group);

                update_emulation_dependent_visibility(controller.emulate_active);
                update_rumble_visibility(controller.is_uhid);

                // Now replace the content of the ScrolledWindow
                var old_child = settings_scrolled.get_child();
                settings_scrolled.set_child(temp_page);
                if (old_child != null) {
                    old_child.destroy();
                }

                refresh_current_profile.begin();
            } finally {
                building_ui = false;
                updating_from_controller = false;
            }
        }

        private void reset_widget_references() {
            gain_row = null;
            deadzone_row = null;
            brightness_row = null;
            player_row = null;
            emulate_switch = null;
            debounce_switch = null;
            rumble_active_switch = null;
            emulation_mode_row = null;
            led_mode_row = null;
            effect_row = null;
            speed_row = null;
            color_preview = null;
            color_row = null;
            reapply_switch = null;
            rumble_group = null;
            led_group = null;
            emulation_group = null;
            stick_group = null;
            buttons_group = null;
            triggers_group = null;
            sens_left_row = null;
            sens_right_row = null;
            invert_ly_switch = null;
            invert_ry_switch = null;
            triggers_digital_switch = null;
            profile_group = null;
            current_profile_row = null;
        }

        private bool supports_led(Controller controller) {
            return (controller.controller_type == ControllerType.DS4 ||
                    controller.controller_type == ControllerType.DUALSENSE);
        }

        // ==================== CREATE CONFIGURATION GROUPS ====================
        private Adw.PreferencesGroup create_led_group() {
            if (current_controller == null) return new Adw.PreferencesGroup();
            var group = new Adw.PreferencesGroup();
            group.set_title(_("LED"));

            int led_mode_index = current_controller.led_static ? 0 : 1;
            string[] led_mode_items = { _("Static"), _("Dynamic") };
            var led_mode_list = new Gtk.StringList(led_mode_items);
            led_mode_row = new Adw.ComboRow();
            led_mode_row.set_title(_("LED Mode"));
            led_mode_row.set_model(led_mode_list);
            led_mode_row.set_selected(led_mode_index);
led_mode_row.notify["selected"].connect(() => {
    if (updating_from_controller || building_ui) return;
    bool is_static = (led_mode_row.get_selected() == 0);
    
    // Update visibility of widgets that do not depend on the effect
    update_led_options_visibility(is_static);
    
    if (!is_static) {
        // Get the current effect index
        uint current_effect_index = 0;
        if (current_controller != null && current_controller.current_effect >= 1 && current_controller.current_effect <= 8) {
            current_effect_index = current_controller.current_effect - 1;
        } else if (effect_row != null) {
            current_effect_index = effect_row.get_selected();
        }
        
        // Calculate final visibility based on the effect
        bool should_show_color = true, should_show_speed = true;
        switch (current_effect_index) {
            case 1:  // Rainbow
            case 4:  // Wave
                should_show_color = false;
                should_show_speed = true;
                break;
            case 5:  // Battery
                should_show_color = false;
                should_show_speed = false;
                break;
            case 6:  // Triggers
            case 7:  // Buttons
                should_show_color = true;
                should_show_speed = false;
                break;
            default: // Breathing, Pulse, Blink, and others
                should_show_color = true;
                should_show_speed = true;
                break;
        }
        
        // Apply visibilities all at once
        if (color_row != null) color_row.visible = should_show_color;
        if (speed_row != null) speed_row.visible = should_show_speed;
        
        // Synchronize effect_row if needed
        if (effect_row != null && effect_row.get_selected() != current_effect_index) {
            updating_from_controller = true;
            effect_row.set_selected(current_effect_index);
            updating_from_controller = false;
        }
        
        // Send commands to the daemon
        controller.set_led_static.begin(false);
        if (effect_row != null) {
            uint8 api_effect = (uint8)(current_effect_index + 1);
            uint8 speed = (speed_row != null && speed_row.visible) ? (uint8)speed_row.get_value() : 5;
            uint8 brightness = (brightness_row != null) ? (uint8)brightness_row.get_value() : 80;
            controller.set_effect.begin(api_effect, speed, brightness);
        }
    } else {
        // Static mode: color visible, speed invisible
        if (color_row != null) color_row.visible = true;
        if (speed_row != null) speed_row.visible = false;
        controller.set_led_static.begin(true);
    }
});
            group.add(led_mode_row);

            var effect_list = new Gtk.StringList(null);
            for (int i = 0; i < EFFECT_NAMES.length; i++) {
                effect_list.append(_(EFFECT_NAMES[i]));
            }
            effect_row = new Adw.ComboRow();
            effect_row.set_title(_("Effect"));
            effect_row.set_model(effect_list);
            uint effect_index = (current_controller.current_effect >= 1 && current_controller.current_effect <= 8)
                ? current_controller.current_effect - 1 : 0;
            effect_row.set_selected(effect_index);
            effect_row.notify["selected"].connect(() => {
                if (updating_from_controller || building_ui) return;
                uint selected = effect_row.get_selected();
                update_visibility_for_effect(selected);
                uint8 api_effect = (uint8)(selected + 1);
                uint8 speed = (speed_row != null) ? (uint8)speed_row.get_value() : 5;
                uint8 brightness = (brightness_row != null) ? (uint8)brightness_row.get_value() : 80;
                controller.set_effect.begin(api_effect, speed, brightness);
            });
            group.add(effect_row);

            current_color = Gdk.RGBA();
            current_color.red = current_controller.led_base_r / 255.0f;
            current_color.green = current_controller.led_base_g / 255.0f;
            current_color.blue = current_controller.led_base_b / 255.0f;
            current_color.alpha = 1.0f;
            current_base_rgb = current_color;

            color_preview = new Gtk.DrawingArea();
            color_preview.set_size_request(150, 5);
            color_preview.add_css_class("color-preview-rounded");
            color_preview.set_draw_func(draw_color_preview);

            color_row = new Adw.ActionRow() { visible = false };
            color_row.set_title(_("LED Color"));
            color_row.set_activatable(true);
            color_row.add_suffix(color_preview);
            color_row.activated.connect(() => {
                var ctrl = controller.current_controller;
                if (ctrl != null && parent_window != null) {
                    uint8 r = ctrl.led_base_r;
                    uint8 g = ctrl.led_base_g;
                    uint8 b = ctrl.led_base_b;
                    var dialog = new ColorPickerDialog(parent_window, r, g, b, current_saturation);
                    dialog.color_selected.connect((final_color) => {
                        current_color = final_color;
                        if (color_preview != null) color_preview.queue_draw();

                        uint8 new_r, new_g, new_b;
                        dialog.get_base_rgb(out new_r, out new_g, out new_b);
                        current_base_rgb = Gdk.RGBA();
                        current_base_rgb.red = new_r / 255.0f;
                        current_base_rgb.green = new_g / 255.0f;
                        current_base_rgb.blue = new_b / 255.0f;
                        current_base_rgb.alpha = 1.0f;
                        current_saturation = dialog.get_saturation();

                        uint8 final_r = (uint8)(final_color.red * 255);
                        uint8 final_g = (uint8)(final_color.green * 255);
                        uint8 final_b = (uint8)(final_color.blue * 255);

                        controller.set_led_color.begin(final_r, final_g, final_b);
                        if (ctrl != null && !ctrl.led_static && effect_row != null && speed_row != null && brightness_row != null) {
                            uint selected = effect_row.get_selected();
                            uint8 api_effect = (uint8)(selected + 1);
                            uint8 speed = (uint8)speed_row.get_value();
                            uint8 brightness = (uint8)brightness_row.get_value();
                            controller.set_effect.begin(api_effect, speed, brightness);
                        }
                        recent_colors = dialog.get_recent_colors();
                    });
                    dialog.present();
                }
            });

            var cursor = new Gdk.Cursor.from_name("pointer", null);
            if (cursor != null) color_row.set_cursor(cursor);
            group.add(color_row);

            var speed_adj = new Gtk.Adjustment(current_controller.effect_speed, 1, 10, 1, 1, 0);
            speed_row = new Adw.SpinRow(speed_adj, 1.0, 0) { visible = false };
            speed_row.set_title(_("Speed"));
            speed_row.notify["value"].connect(() => {
                if (updating_from_controller || building_ui) return;
                if (speed_timeout != 0) Source.remove(speed_timeout);
                speed_timeout = Timeout.add(200, () => {
                    uint8 speed = (uint8)speed_row.get_value();
                    uint8 effect = (effect_row != null) ? (uint8)(effect_row.get_selected() + 1) : 1;
                    uint8 brightness = (brightness_row != null) ? (uint8)brightness_row.get_value() : 80;
                    controller.set_effect.begin(effect, speed, brightness);
                    speed_timeout = 0;
                    return Source.REMOVE;
                });
            });
            group.add(speed_row);

            var brightness_adj = new Gtk.Adjustment(current_controller.global_brightness, 0, 100, 1, 10, 0);
            brightness_row = new Adw.SpinRow(brightness_adj, 1.0, 0);
            brightness_row.set_title(_("Brightness"));
            brightness_row.notify["value"].connect(() => {
                if (updating_from_controller || building_ui) return;
                if (brightness_timeout != 0) Source.remove(brightness_timeout);
                brightness_timeout = Timeout.add(200, () => {
                    controller.set_brightness.begin((uint8)brightness_row.get_value());
                    brightness_timeout = 0;
                    return Source.REMOVE;
                });
            });
            group.add(brightness_row);

            if (current_controller.controller_type == ControllerType.DUALSENSE) {
                var player_adj = new Gtk.Adjustment(current_controller.player_leds, 0, 4, 1, 1, 0);
                player_row = new Adw.SpinRow(player_adj, 1.0, 0);
                player_row.set_title(_("Player LEDs"));
                player_row.notify["value"].connect(() => {
                    if (updating_from_controller || building_ui) return;
                    if (player_timeout != 0) Source.remove(player_timeout);
                    player_timeout = Timeout.add(200, () => {
                        controller.set_player_leds.begin((uint8)player_row.get_value());
                        player_timeout = 0;
                        return Source.REMOVE;
                    });
                });
                group.add(player_row);
            }

            reapply_switch = new Adw.SwitchRow();
            reapply_switch.set_title(_("Reapply LED"));
            reapply_switch.set_active(current_controller.led_reapply);
            reapply_switch.notify["active"].connect(() => {
                if (updating_from_controller || building_ui) return;
                controller.set_led_reapply.begin(reapply_switch.get_active());
            });
            group.add(reapply_switch);

            if (current_controller != null) {
                current_controller.notify["led-base-r"].connect(() => {
                    if (updating_from_controller) return;
                    current_color.red = current_controller.led_base_r / 255.0f;
                    current_color.green = current_controller.led_base_g / 255.0f;
                    current_color.blue = current_controller.led_base_b / 255.0f;
                    if (color_preview != null) color_preview.queue_draw();
                });
                current_controller.notify["led-base-g"].connect(() => {
                    if (updating_from_controller) return;
                    current_color.red = current_controller.led_base_r / 255.0f;
                    current_color.green = current_controller.led_base_g / 255.0f;
                    current_color.blue = current_controller.led_base_b / 255.0f;
                    if (color_preview != null) color_preview.queue_draw();
                });
                current_controller.notify["led-base-b"].connect(() => {
                    if (updating_from_controller) return;
                    current_color.red = current_controller.led_base_r / 255.0f;
                    current_color.green = current_controller.led_base_g / 255.0f;
                    current_color.blue = current_controller.led_base_b / 255.0f;
                    if (color_preview != null) color_preview.queue_draw();
                });
            }

            // Apply final visibility
            update_led_options_visibility(current_controller.led_static);
            if (current_controller.led_static) {
                // Static mode: color visible, speed invisible
                if (color_row != null) color_row.visible = true;
                if (speed_row != null) speed_row.visible = false;
            } else if (effect_row != null) {
                // Dynamic mode: visibility based on effect
                update_visibility_for_effect(effect_row.get_selected());
            }
            return group;
        }

        private Adw.PreferencesGroup create_emulation_group() {
            if (current_controller == null) return new Adw.PreferencesGroup();
            var group = new Adw.PreferencesGroup();
            group.set_title(_("Emulation"));
            emulate_switch = new Adw.SwitchRow();
            emulate_switch.set_title(_("Enable Emulation"));
            emulate_switch.set_active(current_controller.emulate_active);
            emulate_switch.notify["active"].connect(() => {
                if (updating_from_controller || building_ui) return;
                bool active = emulate_switch.get_active();
                update_emulation_dependent_visibility(active);
                if (active && current_controller != null) update_rumble_visibility(current_controller.is_uhid);
                controller.set_emulate_active.begin(active);
            });
            group.add(emulate_switch);

            string[] emulation_items = { "UINPUT", "UHID" };
            var string_list = new Gtk.StringList(emulation_items);
            emulation_mode_row = new Adw.ComboRow();
            emulation_mode_row.set_title(_("Emulation Mode"));
            emulation_mode_row.set_model(string_list);
            emulation_mode_row.set_selected(current_controller.is_uhid ? 1 : 0);
            emulation_mode_row.notify["selected"].connect(() => {
                if (updating_from_controller || building_ui) return;
                bool use_uhid = (emulation_mode_row.get_selected() == 1);
                if (current_controller != null && current_controller.emulate_active) update_rumble_visibility(use_uhid);
                controller.set_emulation_mode.begin(use_uhid);
            });
            group.add(emulation_mode_row);
            return group;
        }

        private Adw.PreferencesGroup create_rumble_group() {
            if (current_controller == null) return new Adw.PreferencesGroup();
            var group = new Adw.PreferencesGroup();
            group.set_title(_("Rumble"));
            rumble_active_switch = new Adw.SwitchRow();
            rumble_active_switch.set_title(_("Enable Rumble"));
            rumble_active_switch.set_active(current_controller.rumble_active);
            rumble_active_switch.notify["active"].connect(() => {
                if (updating_from_controller || building_ui) return;
                bool active = rumble_active_switch.get_active();
                if (gain_row != null) gain_row.visible = active;
                controller.set_rumble_active.begin(active);
            });
            group.add(rumble_active_switch);

            var gain_adj = new Gtk.Adjustment(current_controller.rumble_gain, 0, 100, 1, 10, 0);
            gain_row = new Adw.SpinRow(gain_adj, 1.0, 0);
            gain_row.set_title(_("Gain"));
            gain_row.visible = current_controller.rumble_active;
            gain_row.notify["value"].connect(() => {
                if (updating_from_controller || building_ui) return;
                if (gain_timeout != 0) Source.remove(gain_timeout);
                gain_timeout = Timeout.add(200, () => {
                    controller.set_rumble_gain.begin((uint8)gain_row.get_value());
                    gain_timeout = 0;
                    return Source.REMOVE;
                });
            });
            group.add(gain_row);
            return group;
        }

        private Adw.PreferencesGroup create_stick_group() {
            if (current_controller == null) return new Adw.PreferencesGroup();
            var group = new Adw.PreferencesGroup();
            group.set_title(_("Analog Sticks"));
            var deadzone_adj = new Gtk.Adjustment(current_controller.deadzone, 0, 100, 1, 10, 0);
            deadzone_row = new Adw.SpinRow(deadzone_adj, 1.0, 0);
            deadzone_row.set_title(_("Deadzone"));
            deadzone_row.notify["value"].connect(() => {
                if (updating_from_controller || building_ui) return;
                if (deadzone_timeout != 0) Source.remove(deadzone_timeout);
                deadzone_timeout = Timeout.add(200, () => {
                    controller.set_deadzone.begin((uint8)deadzone_row.get_value());
                    deadzone_timeout = 0;
                    return Source.REMOVE;
                });
            });
            group.add(deadzone_row);

            var sens_left_model = new Gtk.StringList(null);
            for (int i = 0; i < SENSITIVITY_PRESET_NAMES.length; i++) {
                sens_left_model.append(_(SENSITIVITY_PRESET_NAMES[i]));
            }
            sens_left_row = new Adw.ComboRow();
            sens_left_row.set_title(_("Left Stick Sensitivity"));
            sens_left_row.set_model(sens_left_model);
            sens_left_row.set_selected(current_controller.sensitivity_left_preset);
            sens_left_row.notify["selected"].connect(() => {
                if (updating_from_controller || building_ui) return;
                controller.set_sensitivity_left.begin((uint8)sens_left_row.get_selected());
            });
            group.add(sens_left_row);

            var sens_right_model = new Gtk.StringList(null);
            for (int i = 0; i < SENSITIVITY_PRESET_NAMES.length; i++) {
                sens_right_model.append(_(SENSITIVITY_PRESET_NAMES[i]));
            }
            sens_right_row = new Adw.ComboRow();
            sens_right_row.set_title(_("Right Stick Sensitivity"));
            sens_right_row.set_model(sens_right_model);
            sens_right_row.set_selected(current_controller.sensitivity_right_preset);
            sens_right_row.notify["selected"].connect(() => {
                if (updating_from_controller || building_ui) return;
                controller.set_sensitivity_right.begin((uint8)sens_right_row.get_selected());
            });
            group.add(sens_right_row);

            invert_ly_switch = new Adw.SwitchRow();
            invert_ly_switch.set_title(_("Invert Y Axis (Left)"));
            invert_ly_switch.set_active(current_controller.invert_ly);
            invert_ly_switch.notify["active"].connect(() => {
                if (updating_from_controller || building_ui) return;
                controller.set_invert_ly.begin(invert_ly_switch.get_active());
            });
            group.add(invert_ly_switch);

            invert_ry_switch = new Adw.SwitchRow();
            invert_ry_switch.set_title(_("Invert Y Axis (Right)"));
            invert_ry_switch.set_active(current_controller.invert_ry);
            invert_ry_switch.notify["active"].connect(() => {
                if (updating_from_controller || building_ui) return;
                controller.set_invert_ry.begin(invert_ry_switch.get_active());
            });
            group.add(invert_ry_switch);
            return group;
        }

        private Adw.PreferencesGroup create_triggers_group() {
            if (current_controller == null) return new Adw.PreferencesGroup();
            var group = new Adw.PreferencesGroup();
            group.set_title(_("Triggers"));

            triggers_digital_switch = new Adw.SwitchRow();
            triggers_digital_switch.set_title(_("Digital Triggers"));
            triggers_digital_switch.set_active(current_controller.triggers_digital);
            
            triggers_digital_switch.notify["active"].connect(() => {
                if (updating_from_controller) return;
                bool new_value = triggers_digital_switch.get_active();
                controller.set_triggers_digital.begin(new_value);
            });
            
            group.add(triggers_digital_switch);
            return group;
        }

        private Adw.PreferencesGroup create_buttons_group() {
            if (current_controller == null) return new Adw.PreferencesGroup();
            var group = new Adw.PreferencesGroup();
            group.set_title(_("Buttons"));

            debounce_switch = new Adw.SwitchRow();
            debounce_switch.set_title(_("Debounce"));
            debounce_switch.set_active(current_controller.debounce_enabled);
            debounce_switch.notify["active"].connect(() => {
                if (updating_from_controller || building_ui) return;
                controller.set_debounce.begin(debounce_switch.get_active());
            });
            group.add(debounce_switch);

            return group;
        }

        private void draw_color_preview(Gtk.DrawingArea area, Cairo.Context cr, int width, int height) {
            int margin = 2;
            int rect_width = width - 2 * margin;
            int rect_height = height - 2 * margin;
            int x = margin;
            int y = margin;
            int radius = 10;

            cr.new_path();
            cr.move_to(x + radius, y);
            cr.line_to(x + rect_width - radius, y);
            cr.arc(x + rect_width - radius, y + radius, radius, -Math.PI/2, 0);
            cr.line_to(x + rect_width, y + rect_height - radius);
            cr.arc(x + rect_width - radius, y + rect_height - radius, radius, 0, Math.PI/2);
            cr.line_to(x + radius, y + rect_height);
            cr.arc(x + radius, y + rect_height - radius, radius, Math.PI/2, Math.PI);
            cr.line_to(x, y + radius);
            cr.arc(x + radius, y + radius, radius, Math.PI, 3*Math.PI/2);
            cr.close_path();

            cr.set_source_rgba(current_color.red, current_color.green, current_color.blue, 1.0);
            cr.fill();

            cr.set_source_rgba(0.5, 0.5, 0.5, 0.3);
            cr.set_line_width(1.0);
            cr.stroke();
        }

        public void clear() {
            if (settings_scrolled != null) {
                var old_child = settings_scrolled.get_child();
                if (old_child != null) {
                    settings_scrolled.set_child(null);
                    old_child.destroy();
                }
            }
            current_controller = null;
            current_saturation = 100.0;
            current_base_rgb = Gdk.RGBA() { red = 1.0f, green = 1.0f, blue = 1.0f, alpha = 1.0f };
            current_color = current_base_rgb;
            recent_colors = {};
            last_known_version = 0;
        }

        public void update_from_controller(Controller controller) {
            this.controller.update_from_controller(controller);
        }

        // ==================== PREFERENCES DIALOG ====================
        public async void show_preferences_dialog(Gtk.Window parent) {
            this.parent_window = parent;

            var dialog = new Adw.PreferencesDialog();
            dialog.set_title(_("DSTX Preferences"));
            dialog.set_content_width(700);
            dialog.set_content_height(600);

            var general_page = new Adw.PreferencesPage();
            general_page.set_title(_("General"));
            general_page.set_icon_name("gnome-tweak-tool-symbolic");

            var lang_group = new Adw.PreferencesGroup();
            lang_group.set_title(_("Language"));
            lang_group.set_description(_("User interface language"));

            var locale_mgr = LocaleManager.get_default();

            void show_toast_on_parent(Gtk.Window win, string message) {
                var main_window = win as Dstx.MainWindow;
                if (main_window != null) {
                    main_window.show_toast(message);
                } else {
                    warning("SettingsUIBuilder: Cannot show toast, parent is not MainWindow");
                }
            }

            var lang_row = new Adw.ComboRow();
            lang_row.set_title(_("Language"));
            var lang_names = locale_mgr.get_all_native_names();
            var lang_list = new Gtk.StringList(lang_names);
            lang_row.set_model(lang_list);
            lang_row.set_selected(locale_mgr.get_current_language_id());
            lang_row.notify["selected"].connect(() => {
                int new_lang_id = (int)lang_row.get_selected();
                if (new_lang_id != locale_mgr.get_current_language_id()) {
                    locale_mgr.set_language(new_lang_id);
                    show_toast_on_parent(parent, _("Language changed. Please restart the application for full effect."));
                }
            });
            lang_group.add(lang_row);
            general_page.add(lang_group);

            // ===== AUTO-SAVE GROUP =====
            var auto_group = new Adw.PreferencesGroup();
            auto_group.set_title(_("Automatic Profile Saving"));
            auto_group.set_description(_("Automatically save the active profile after changes."));

            var auto_save_switch = new Adw.SwitchRow();
            auto_save_switch.set_title(_("Enable Auto-save"));
            auto_save_switch.set_active(true);
            auto_save_switch.set_sensitive(false);

            bool real_enabled = true;
            int32 real_delay = 2000;
            try {
                bool enabled;
                int32 delay;
                yield controller.get_auto_save_status(out enabled, out delay);
                real_enabled = enabled;
                real_delay = delay;
            } catch (Error e) {
                warning("Failed to get auto-save status: %s", e.message);
            }

            auto_save_switch.set_active(real_enabled);
            auto_save_switch.set_sensitive(true);

            auto_save_switch.notify["active"].connect(() => {
                bool enable = auto_save_switch.get_active();
                save_auto_settings.begin(enable, real_delay);
            });

            auto_group.add(auto_save_switch);
            general_page.add(auto_group);

            // ===== APPEARANCE PAGE =====
            var appearance_page = new AppearancePage.with_state(
                controller.get_custom_theme_id(),
                controller.get_custom_theme_name(),
                controller.get_custom_accent_color(),
                controller.get_custom_accent_index()
            );
            appearance_page.set_settings_controller(controller);
            appearance_page.set_theme_changed_callback((theme_id, theme_name, accent_color, accent_index) => {
                controller.save_custom_theme(theme_id, theme_name, accent_color, accent_index);
            });
            appearance_page.set_theme_mode_changed_callback((mode) => {
                controller.set_theme_mode(mode);
            });

            // ===== SERVICE PAGE =====
            var service_page = new Adw.PreferencesPage();
            service_page.set_title(_("Service"));
            service_page.set_icon_name("computer-symbolic");
            var service_group = new Adw.PreferencesGroup();
            service_group.set_title(_("Systemd Service"));

            var auto_start_row = new Adw.SwitchRow();
            auto_start_row.set_title(_("Start automatically"));
            auto_start_row.set_subtitle(_("Starts DSTX service when the system boots"));
            auto_start_row.set_active(controller.get_auto_start());
            auto_start_row.notify["active"].connect(() => {
                controller.set_auto_start.begin(auto_start_row.get_active());
            });
            service_group.add(auto_start_row);

            var service_status_row = new Adw.ActionRow();
            service_status_row.set_title(_("Service Status"));
            var status_label = new Gtk.Label("");
            service_status_row.add_suffix(status_label);
            service_group.add(service_status_row);

            Adw.ActionRow stop_row = null;
            Adw.ActionRow start_row = null;

            var stop_button = new Gtk.Button.with_label(_("Stop Service"));
            stop_button.add_css_class("destructive-action");
            stop_button.add_css_class("compact-button");
            stop_button.clicked.connect(() => {
                controller.stop_service.begin((obj, res) => {
                    controller.stop_service.end(res);
                    Timeout.add(500, () => {
                        update_service_status.begin(status_label, stop_row, start_row);
                        show_toast_on_parent(parent, _("Service stopped"));
                        return Source.REMOVE;
                    });
                });
            });
            stop_row = new Adw.ActionRow();
            stop_row.set_title(_("Stop"));
            stop_row.add_suffix(stop_button);
            stop_row.set_activatable_widget(stop_button);
            stop_row.visible = true;
            service_group.add(stop_row);

            var start_button = new Gtk.Button.with_label(_("Start Service"));
            start_button.add_css_class("suggested-action");
            start_button.add_css_class("compact-button");
            start_button.clicked.connect(() => {
                controller.start_service.begin((obj, res) => {
                    controller.start_service.end(res);
                    Timeout.add(500, () => {
                        update_service_status.begin(status_label, stop_row, start_row);
                        show_toast_on_parent(parent, _("Service started"));
                        return Source.REMOVE;
                    });
                });
            });
            start_row = new Adw.ActionRow();
            start_row.set_title(_("Start"));
            start_row.add_suffix(start_button);
            start_row.set_activatable_widget(start_button);
            start_row.visible = true;
            service_group.add(start_row);

            var restart_button = new Gtk.Button.with_label(_("Restart Service"));
            restart_button.add_css_class("destructive-action");
            restart_button.add_css_class("compact-button");
            restart_button.clicked.connect(() => {
                controller.restart_service.begin((obj, res) => {
                    controller.restart_service.end(res);
                    Timeout.add(500, () => {
                        update_service_status.begin(status_label, stop_row, start_row);
                        show_toast_on_parent(parent, _("Service restarted"));
                        return Source.REMOVE;
                    });
                });
            });
            var restart_row = new Adw.ActionRow();
            restart_row.set_title(_("Restart"));
            restart_row.add_suffix(restart_button);
            restart_row.set_activatable_widget(restart_button);
            service_group.add(restart_row);

            update_service_status.begin(status_label, stop_row, start_row);
            service_page.add(service_group);

            if (Core.is_flatpak()) {
                flatpak_row = new Adw.ActionRow();
                flatpak_action_button = new Gtk.Button();
                flatpak_action_button.clicked.connect(on_flatpak_button_clicked);
                flatpak_action_button.add_css_class("compact-button");
                flatpak_row.add_suffix(flatpak_action_button);
                flatpak_row.set_activatable_widget(flatpak_action_button);

                var flatpak_group = new Adw.PreferencesGroup();
                flatpak_group.set_title(_("System Components (Flatpak)"));
                flatpak_group.add(flatpak_row);
                service_page.add(flatpak_group);

                update_flatpak_status.begin();
            }

            dialog.add(general_page);
            dialog.add(appearance_page);
            dialog.add(service_page);
            dialog.present(parent);
        }

        private async void update_service_status(Gtk.Label status_label, Adw.ActionRow stop_row, Adw.ActionRow start_row) {
            bool is_active = yield controller.is_service_active();
            bool is_enabled = yield controller.is_service_enabled();
            string status_text = is_active ? _("Active") : _("Inactive");
            string detail = is_active ? _("Service is running")
                         : (is_enabled ? _("Enabled to start with system") : _("Disabled"));
            status_label.set_label(status_text);
            var parent_row = status_label.get_parent() as Adw.ActionRow;
            if (parent_row != null) {
                parent_row.set_subtitle(detail);
            }
            if (stop_row != null) stop_row.visible = is_active;
            if (start_row != null) start_row.visible = !is_active;
        }

        private async void update_flatpak_status() {
            if (flatpak_row == null || flatpak_action_button == null) return;
            flatpak_components_installed = yield SystemServiceManager.are_system_components_installed();
            flatpak_action_button.remove_css_class("suggested-action");
            flatpak_action_button.remove_css_class("destructive-action");
            if (flatpak_components_installed) {
                flatpak_row.set_title(_("Installed"));
                flatpak_action_button.set_label(_("Uninstall..."));
                flatpak_action_button.add_css_class("destructive-action");
            } else {
                flatpak_row.set_title(_("Not installed"));
                flatpak_action_button.set_label(_("Install..."));
                flatpak_action_button.add_css_class("suggested-action");
            }
        }

        private void on_flatpak_button_clicked() {
            if (flatpak_components_installed) {
                uninstall_flatpak_components.begin();
            } else {
                var main_window = parent_window as Dstx.MainWindow;
                if (main_window != null) {
                    main_window.confirm_installation.begin((obj, res) => {
                        update_flatpak_status.begin();
                    });
                } else {
                    warning("SettingsUIBuilder: parent_window is not a valid MainWindow");
                }
            }
        }

        private async void uninstall_flatpak_components() {
            if (flatpak_action_button == null || parent_window == null) return;
            var confirm = new Adw.AlertDialog(
                _("Confirm Uninstall"),
                _("Removing the system components will stop DSTX from working. Are you sure?")
            );
            confirm.add_response("cancel", _("Cancel"));
            confirm.add_response("uninstall", _("Uninstall"));
            confirm.set_default_response("cancel");
            confirm.set_close_response("cancel");
            string response = yield confirm.choose(parent_window, null);
            if (response != "uninstall") return;

            flatpak_action_button.set_sensitive(false);
            bool success = yield SystemServiceManager.uninstall_system_components();
            if (success) {
                var info_dialog = new Adw.AlertDialog(
                    _("Uninstall Complete"),
                    _("The DSTX system components have been removed successfully.\n\nThe application will now close.")
                );
                info_dialog.add_response("close", _("Close"));
                info_dialog.set_default_response("close");
                info_dialog.set_close_response("close");
                info_dialog.response.connect(() => {
                    var app = GLib.Application.get_default() as Adw.Application;
                    if (app != null) app.quit();
                    else parent_window.close();
                });
                info_dialog.present(parent_window);
            } else {
                show_toast_on_parent(parent_window, _("Removal failed."));
                flatpak_action_button.set_sensitive(true);
                yield update_flatpak_status();
            }
        }

        private async void save_auto_settings(bool enable, int delay_ms) {
            try {
                string msg = yield profile_manager.set_auto_save(enable, delay_ms);
                var main_window = parent_window as Dstx.MainWindow;
                if (main_window != null) main_window.show_toast(msg);
                else message("Auto-save: %s", msg);
            } catch (Error e) {
                warning("Failed to set auto-save: %s", e.message);
                var main_window = parent_window as Dstx.MainWindow;
                if (main_window != null) main_window.show_toast(_("Error setting auto-save: %s").printf(e.message));
            }
        }

        private void show_toast_on_parent(Gtk.Window win, string message) {
            var main_window = win as Dstx.MainWindow;
            if (main_window != null) main_window.show_toast(message);
            else warning("SettingsUIBuilder: Cannot show toast, parent is not MainWindow");
        }

        ~SettingsUIBuilder() {
            if (gain_timeout != 0) Source.remove(gain_timeout);
            if (deadzone_timeout != 0) Source.remove(deadzone_timeout);
            if (brightness_timeout != 0) Source.remove(brightness_timeout);
            if (speed_timeout != 0) Source.remove(speed_timeout);
            if (player_timeout != 0) Source.remove(player_timeout);
            if (controller_manager != null) {
                if (config_changed_handler_id != 0)
                    controller_manager.disconnect(config_changed_handler_id);
                if (controller_updated_handler_id != 0)
                    controller_manager.disconnect(controller_updated_handler_id);
            }
        }
    }
}
