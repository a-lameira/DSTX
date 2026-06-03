/*
 * controller-manager.vala - Controller management for DSTX GUI
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
 * - Manage controller list and selection
 * - Handle D-Bus signals for telemetry, buttons, axes, connection events
 * - Update controller configurations with debouncing
 * - Maintain controller cards UI and selection state
 */

// src/managers/controller-manager.vala

using Dstx.Core;
using Dstx.Models;
using Dstx.Widgets;

namespace Dstx.Managers {
    public class ControllerManager : Object {
        private unowned DBusClient dbus_client;
        private unowned KeybindsManager keybinds_manager;
        private unowned Gtk.Box cards_container;
        
        private GLib.HashTable<string, Controller> controller_map;
        private GLib.List<Controller> connected_controllers;
        private GLib.HashTable<string, ControllerCard> card_map;
        
        private GLib.HashTable<uint8, uint> config_timeout_ids;
        private GLib.HashTable<uint8, uint> connection_timeout_ids;
        
        private const uint CONFIG_UPDATE_DELAY_MS = 150;
        private const uint CONNECTION_DELAY_MS = 100;
        
        public Controller? selected_controller { get; private set; default = null; }
        
        private bool processing_telemetry = false;
        private bool processing_config = false;
        private bool is_removing = false;
        
        public signal void controller_selected(Controller controller);
        public signal void controllers_list_changed(int count);
        public signal void controller_telemetry(Controller controller);
        public signal void controller_config_changed(Controller controller);
        public signal void controller_added(Controller controller);
        public signal void controller_removed(uint8 slot);
        public signal void controller_updated(Controller controller);
        
        public ControllerManager(DBusClient dbus_client, KeybindsManager keybinds_manager,
                                 Gtk.Box cards_container, Gtk.Widget? unused = null) {
            this.dbus_client = dbus_client;
            this.keybinds_manager = keybinds_manager;
            this.cards_container = cards_container;
            
            this.controller_map = new GLib.HashTable<string, Controller>(str_hash, str_equal);
            this.connected_controllers = new GLib.List<Controller>();
            this.card_map = new GLib.HashTable<string, ControllerCard>(str_hash, str_equal);
            this.config_timeout_ids = new GLib.HashTable<uint8, uint>(direct_hash, direct_equal);
            this.connection_timeout_ids = new GLib.HashTable<uint8, uint>(direct_hash, direct_equal);
            
            connect_dbus_signals();
        }
        
        private void connect_dbus_signals() {
            dbus_client.telemetry_update.connect(on_telemetry_update);
            dbus_client.button_update.connect(on_button_update);
            dbus_client.axis_update.connect(on_axis_update);
            
            dbus_client.controller_connected.connect(on_controller_connected);
            dbus_client.controller_disconnected.connect(on_controller_disconnected);
            dbus_client.controller_updated.connect(on_config_updated);
        }
        
        private string get_key(Controller c) {
            return "%d-%d".printf(c.slot, (int)c.controller_type);
        }
        
        private string get_key_from_slot(uint8 slot, ControllerType type) {
            return "%d-%d".printf(slot, (int)type);
        }
        
        private async void fetch_keymap_for_controller(Controller controller) {
            if (controller == null) return;
            try {
                uint8[] keymap = yield keybinds_manager.get_keymap((uint8)controller.slot);
                bool changed = false;
                for (int i = 0; i < keymap.length; i++) {
                    if (controller.keymap[i] != keymap[i]) {
                        changed = true;
                        break;
                    }
                }
                if (changed) {
                    controller.keymap = keymap;
                    controller_config_changed(controller);
                }
            } catch (Error e) {
                warning("Failed to get keymap for slot %d: %s", controller.slot, e.message);
            }
        }
        
        private void detect_and_set_layout_mode(Controller controller) {
            if (controller.keymap == null || controller.keymap.length < 4) return;
            uint8 a = controller.keymap[0]; // physical Cross/B (south)
            uint8 b = controller.keymap[1]; // physical Circle/A (east)
            uint8 x = controller.keymap[2]; // physical Square/Y (north)
            uint8 y = controller.keymap[3]; // physical Triangle/X (west)
            // Switch layout: B (physical 0) -> logical A (1); A (physical 1) -> logical B (2);
            // Y (physical 2) -> logical X (3); X (physical 3) -> logical Y (4)
            bool is_switch = (b == 1 && a == 2 && y == 3 && x == 4);
            controller.layout_mode = is_switch ? 1 : 0;
        }
        
        private void on_telemetry_update(uint8 slot, int16 lx, int16 ly, int16 rx, int16 ry,
                                         int16 lt, int16 rt, int16 hatx, int16 haty, uint16 buttons) {
            if (processing_telemetry) return;
            var controller = find_controller_by_slot(slot);
            if (controller == null) return;
            processing_telemetry = true;
            controller.update_from_telemetry(lx, ly, rx, ry, lt, rt, hatx, haty, buttons);
            controller_telemetry(controller);
            controller_updated(controller);
            processing_telemetry = false;
        }
        
        private void on_button_update(uint8 slot, uint16 buttons) {
            if (processing_telemetry) return;
            var controller = find_controller_by_slot(slot);
            if (controller == null) return;
            processing_telemetry = true;
            controller.update_buttons_from_bitmap(buttons);
            controller_telemetry(controller);
            controller_updated(controller);
            processing_telemetry = false;
        }
        
        private void on_axis_update(uint8 slot, int16 lx, int16 ly, int16 rx, int16 ry,
                                    int16 lt, int16 rt, int16 hatx, int16 haty) {
            if (processing_telemetry) return;
            var controller = find_controller_by_slot(slot);
            if (controller == null) return;
            processing_telemetry = true;
            controller.update_axes(lx, ly, rx, ry, lt, rt, hatx, haty);
            controller_telemetry(controller);
            controller_updated(controller);
            processing_telemetry = false;
        }
        
        private void on_config_updated(uint8 slot) {
            if (processing_config) return;
            if (config_timeout_ids.contains(slot)) {
                Source.remove(config_timeout_ids.get(slot));
                config_timeout_ids.remove(slot);
            }
            uint timeout_id = Timeout.add(CONFIG_UPDATE_DELAY_MS, () => {
                fetch_config_update.begin(slot);
                config_timeout_ids.remove(slot);
                return Source.REMOVE;
            });
            config_timeout_ids.set(slot, timeout_id);
        }
        
        private async void fetch_config_update(uint8 slot) {
            if (processing_config) return;
            try {
                var updated = yield dbus_client.get_controller_info(slot);
                if (updated != null && updated.connected) {
                    message("ControllerManager: triggers_digital for slot %d = %s", slot, updated.triggers_digital.to_string());
                    processing_config = true;
                    merge_controller_config(updated);
                    processing_config = false;
                }
            } catch (Error e) {
                processing_config = false;
                warning("ControllerManager: Error updating config for slot %d: %s", slot, e.message);
                if (e.message.contains("not connected") || e.message.contains("Daemon not connected")) {
                    Idle.add(() => {
                        remove_controller(slot);
                        return Source.REMOVE;
                    });
                }
            }
        }
        
        private void merge_controller_config(Controller updated) {
            string key = get_key(updated);
            var existing = controller_map.get(key);
            var card = card_map.get(key);
            
            if (existing == null) {
                add_controller(updated);
                return;
            }
            
            bool changed = false;
            
            // LED and colors
            if (existing.led_base_r != updated.led_base_r) {
                existing.led_base_r = updated.led_base_r;
                changed = true;
            }
            if (existing.led_base_g != updated.led_base_g) {
                existing.led_base_g = updated.led_base_g;
                changed = true;
            }
            if (existing.led_base_b != updated.led_base_b) {
                existing.led_base_b = updated.led_base_b;
                changed = true;
            }
            if (existing.led_r != updated.led_r) {
                existing.led_r = updated.led_r;
                changed = true;
            }
            if (existing.led_g != updated.led_g) {
                existing.led_g = updated.led_g;
                changed = true;
            }
            if (existing.led_b != updated.led_b) {
                existing.led_b = updated.led_b;
                changed = true;
            }
            if (existing.led_static != updated.led_static) {
                existing.led_static = updated.led_static;
                changed = true;
            }
            if (existing.led_reapply != updated.led_reapply) {
                existing.led_reapply = updated.led_reapply;
                changed = true;
            }
            if (existing.player_leds != updated.player_leds) {
                existing.player_leds = updated.player_leds;
                changed = true;
            }
            if (existing.global_brightness != updated.global_brightness) {
                existing.global_brightness = updated.global_brightness;
                changed = true;
            }
            if (existing.current_effect != updated.current_effect) {
                existing.current_effect = updated.current_effect;
                changed = true;
            }
            if (existing.effect_speed != updated.effect_speed) {
                existing.effect_speed = updated.effect_speed;
                changed = true;
            }
            if (existing.effect_brightness != updated.effect_brightness) {
                existing.effect_brightness = updated.effect_brightness;
                changed = true;
            }
            
            // Rumble
            if (existing.rumble_gain != updated.rumble_gain) {
                existing.rumble_gain = updated.rumble_gain;
                changed = true;
            }
            if (existing.rumble_active != updated.rumble_active) {
                existing.rumble_active = updated.rumble_active;
                changed = true;
            }
            if (existing.deadzone != updated.deadzone) {
                existing.deadzone = updated.deadzone;
                changed = true;
            }
            
            // Sensitivity and inversion
            if (existing.sensitivity_left_preset != updated.sensitivity_left_preset) {
                existing.sensitivity_left_preset = updated.sensitivity_left_preset;
                changed = true;
            }
            if (existing.sensitivity_right_preset != updated.sensitivity_right_preset) {
                existing.sensitivity_right_preset = updated.sensitivity_right_preset;
                changed = true;
            }
            if (existing.invert_ly != updated.invert_ly) {
                existing.invert_ly = updated.invert_ly;
                changed = true;
            }
            if (existing.invert_ry != updated.invert_ry) {
                existing.invert_ry = updated.invert_ry;
                changed = true;
            }
            
            // Digital triggers
            if (existing.triggers_digital != updated.triggers_digital) {
                existing.triggers_digital = updated.triggers_digital;
                changed = true;
            }
            
            // Emulation
            if (existing.emulate_active != updated.emulate_active) {
                existing.emulate_active = updated.emulate_active;
                changed = true;
            }
            if (existing.is_uhid != updated.is_uhid) {
                existing.is_uhid = updated.is_uhid;
                changed = true;
            }
            if (existing.debounce_enabled != updated.debounce_enabled) {
                existing.debounce_enabled = updated.debounce_enabled;
                changed = true;
            }
            
            // Battery and connectivity
            if (existing.battery != updated.battery) {
                existing.battery = updated.battery;
                changed = true;
            }
            if (existing.is_bluetooth != updated.is_bluetooth) {
                existing.is_bluetooth = updated.is_bluetooth;
                changed = true;
            }
            
            // Keymap
            bool keymap_changed = false;
            for (int i = 0; i < updated.keymap.length; i++) {
                if (existing.keymap[i] != updated.keymap[i]) {
                    existing.keymap[i] = updated.keymap[i];
                    keymap_changed = true;
                }
            }
            if (keymap_changed) {
                existing.bump_version("keymap");
                changed = true;
            }
            
            if (changed) {
                existing.increment_version();
                if (card != null) {
                    card.update_from_controller(existing);
                }
                controller_config_changed(existing);
            }
        }
        
        private void on_controller_connected(uint8 slot) {
            message("ControllerManager: Connection signal received for slot %d", slot);
            if (connection_timeout_ids.contains(slot)) {
                Source.remove(connection_timeout_ids.get(slot));
                connection_timeout_ids.remove(slot);
            }
            uint timeout_id = Timeout.add(CONNECTION_DELAY_MS, () => {
                fetch_new_controller.begin(slot);
                connection_timeout_ids.remove(slot);
                return Source.REMOVE;
            });
            connection_timeout_ids.set(slot, timeout_id);
        }
        
        private async void fetch_new_controller(uint8 slot) {
            try {
                var controller = yield dbus_client.get_controller_info(slot);
                if (controller != null && controller.connected) {
                    yield fetch_keymap_for_controller(controller);
                    detect_and_set_layout_mode(controller);
                    Idle.add(() => {
                        add_controller(controller);
                        return Source.REMOVE;
                    });
                }
            } catch (Error e) {
                warning("ControllerManager: Error fetching new controller %d: %s", slot, e.message);
            }
        }
        
        private void on_controller_disconnected(uint8 slot) {
            message("ControllerManager: Disconnection signal received for slot %d", slot);
            if (connection_timeout_ids.contains(slot)) {
                Source.remove(connection_timeout_ids.get(slot));
                connection_timeout_ids.remove(slot);
            }
            uint timeout_id = Timeout.add(CONNECTION_DELAY_MS, () => {
                Idle.add(() => {
                    remove_controller(slot);
                    return Source.REMOVE;
                });
                connection_timeout_ids.remove(slot);
                return Source.REMOVE;
            });
            connection_timeout_ids.set(slot, timeout_id);
        }
        
        public async void load_initial_controllers() {
            try {
                var slots = yield dbus_client.get_controllers();
                message("ControllerManager: Loading %d initial controllers", slots.length);
                foreach (uint8 slot in slots) {
                    var controller = yield dbus_client.get_controller_info(slot);
                    if (controller.connected) {
                        yield fetch_keymap_for_controller(controller);
                        detect_and_set_layout_mode(controller);
                        add_controller(controller);
                    }
                }
            } catch (Error e) {
                warning("ControllerManager: Error loading initial controllers: %s", e.message);
            }
        }
        
        private Controller? find_controller_by_slot(uint8 slot) {
            foreach (var c in connected_controllers) {
                if (c.slot == slot) return c;
            }
            return null;
        }
        
        private void add_controller(Controller controller) {
            string key = get_key(controller);
            if (controller_map.contains(key)) {
                merge_controller_config(controller);
                return;
            }
            message("ControllerManager: Adding controller slot %d type %s", 
                    controller.slot, controller.controller_type.to_string());
            controller_map.set(key, controller);
            connected_controllers.append(controller);
            var card = new ControllerCard(controller);
            card.add_css_class("controller-card");
            var gesture = new Gtk.GestureClick();
            gesture.pressed.connect(() => {
                if (!is_removing) select_controller(controller);
            });
            card.add_controller(gesture);
            card_map.set(key, card);
            rebuild_cards();
            controller_added(controller);
            controllers_list_changed((int)connected_controllers.length());
            if (connected_controllers.length() == 1) select_controller(controller);
        }
        
        private void remove_controller(uint8 slot) {
            if (is_removing) return;
            is_removing = true;
            string key_to_remove = null;
            Controller? ctrl_to_remove = null;
            foreach (var c in connected_controllers) {
                if (c.slot == slot) {
                    key_to_remove = get_key(c);
                    ctrl_to_remove = c;
                    break;
                }
            }
            if (key_to_remove == null) {
                is_removing = false;
                return;
            }
            bool was_selected = (selected_controller != null && selected_controller.slot == slot);
            if (was_selected) selected_controller = null;
            controller_removed(slot);
            connected_controllers.remove(ctrl_to_remove);
            controller_map.remove(key_to_remove);
            var card = card_map.get(key_to_remove);
            if (card != null) {
                if (card.get_parent() != null) cards_container.remove(card);
                card.destroy();
                card_map.remove(key_to_remove);
            }
            if (config_timeout_ids.contains(slot)) {
                Source.remove(config_timeout_ids.get(slot));
                config_timeout_ids.remove(slot);
            }
            if (connection_timeout_ids.contains(slot)) {
                Source.remove(connection_timeout_ids.get(slot));
                connection_timeout_ids.remove(slot);
            }
            if (connected_controllers.length() > 0) {
                rebuild_cards();
            } else {
                Gtk.Widget? child = cards_container.get_first_child();
                while (child != null) {
                    var next = child.get_next_sibling();
                    cards_container.remove(child);
                    child.destroy();
                    child = next;
                }
            }
            controllers_list_changed((int)connected_controllers.length());
            if (was_selected && connected_controllers.length() > 0) {
                Idle.add(() => {
                    select_first();
                    return Source.REMOVE;
                });
            }
            is_removing = false;
        }
        
        private void rebuild_cards() {
            Gtk.Widget? child = cards_container.get_first_child();
            while (child != null) {
                var next = child.get_next_sibling();
                cards_container.remove(child);
                child.destroy();
                child = next;
            }
            if (connected_controllers.length() == 0) return;
            int num = 1;
            foreach (var c in connected_controllers) {
                string key = get_key(c);
                var card = card_map.get(key);
                if (card != null) {
                    var title = new Gtk.Label(null);
                    title.set_markup("<b>%s</b>".printf(_("CONTROLLER %d").printf(num)));
                    title.halign = Gtk.Align.START;
                    title.add_css_class("card-title");
                    title.margin_start = 12;
                    title.margin_top = 8;
                    title.margin_bottom = 4;
                    cards_container.append(title);
                    cards_container.append(card);
                    if (selected_controller != null && selected_controller.slot == c.slot) {
                        card.add_css_class("selected-card");
                    }
                    num++;
                }
            }
        }
        
        public void select_controller(Controller controller) {
            if (controller == null || selected_controller == controller) return;
            if (is_removing) return;
            message("ControllerManager: Selecting slot %d", controller.slot);
            selected_controller = controller;
            foreach (var c in connected_controllers) {
                string key = get_key(c);
                var card = card_map.get(key);
                if (card != null) {
                    if (c.slot == controller.slot)
                        card.add_css_class("selected-card");
                    else
                        card.remove_css_class("selected-card");
                }
            }
            controller_selected(controller);
        }
        
        public bool select_first() {
            if (connected_controllers.length() > 0) {
                var first = connected_controllers.nth_data(0);
                if (first != null) {
                    select_controller(first);
                    return true;
                }
            }
            return false;
        }
        
        public int get_controller_count() {
            return (int)connected_controllers.length();
        }
        
        public unowned GLib.List<Controller> get_all_controllers() {
            return connected_controllers;
        }
        
        public Controller? get_controller_by_slot(uint8 slot) {
            return find_controller_by_slot(slot);
        }
        
        public void clear_all() {
            is_removing = true;
            foreach (var slot in config_timeout_ids.get_keys()) {
                if (config_timeout_ids.contains(slot))
                    Source.remove(config_timeout_ids.get(slot));
            }
            config_timeout_ids.remove_all();
            foreach (var slot in connection_timeout_ids.get_keys()) {
                if (connection_timeout_ids.contains(slot))
                    Source.remove(connection_timeout_ids.get(slot));
            }
            connection_timeout_ids.remove_all();
            Gtk.Widget? child = cards_container.get_first_child();
            while (child != null) {
                var next = child.get_next_sibling();
                cards_container.remove(child);
                child = next;
            }
            controller_map.remove_all();
            connected_controllers = new GLib.List<Controller>();
            card_map.remove_all();
            selected_controller = null;
            is_removing = false;
        }
        
        public void validate_selection() {
            if (selected_controller == null) return;
            bool found = false;
            foreach (var c in connected_controllers) {
                if (c.slot == selected_controller.slot) {
                    found = true;
                    break;
                }
            }
            if (!found) {
                message("ControllerManager: Invalid selection, clearing");
                selected_controller = null;
            }
        }
        
        ~ControllerManager() {
            foreach (var slot in config_timeout_ids.get_keys()) {
                if (config_timeout_ids.contains(slot))
                    Source.remove(config_timeout_ids.get(slot));
            }
            foreach (var slot in connection_timeout_ids.get_keys()) {
                if (connection_timeout_ids.contains(slot))
                    Source.remove(connection_timeout_ids.get(slot));
            }
        }
    }
}
