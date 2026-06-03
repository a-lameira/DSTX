/*
 * keybinds-dialog.vala - Keybinds configuration dialog for DSTX GUI
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
 * - Provide UI for configuring button keybinds per controller slot
 * - Load and apply keymaps via KeybindsManager
 * - Support Xbox and Switch layout toggles (for Nintendo Switch Pro controller)
 * - Reset to default keybinds
 * - Notify MainWindow when layout changes
 */

// src/widgets/keybinds-dialog.vala

using Gtk;
using Adw;
using Dstx.Core;
using Dstx.Managers;
using Dstx.Models;

namespace Dstx.Widgets {
    public class KeybindsDialog : Adw.Window {
        private unowned Gtk.Window parent;
        private KeybindsManager keybinds_manager;
        private uint8 slot;
        private Controller controller;
        private uint8[] current_keymap;
        private bool loading = false;
        
        private HashTable<int, Adw.ComboRow> rows_by_physical;
        
        private const int MIN_ROW_WIDTH = 280;
        private static string[] logical_names;
        private string[] physical_names;
        
        private const int[] DPAD_INDICES = { 14, 15, 16, 17 };
        private const int[] FACE_INDICES = { 0, 1, 2, 3 };
        private const int[] SYSTEM_INDICES = { 9, 8 };
        private const int[] HOME_TOUCH_INDICES = { 12, 13 };
        private const int[] L1_R1_INDICES = { 4, 5 };
        private const int[] L2_R2_INDICES = { 6, 7 };
        private const int[] L3_R3_INDICES = { 10, 11 };

        // Toggle group fields
        private Adw.ToggleGroup? toggle_group;
        private Adw.Toggle? xbox_toggle;
        private Adw.Toggle? switch_toggle;
        private bool layout_updating = false;
        private ulong toggle_group_handler_id = 0;

        public signal void layout_changed();  // Signal to notify MainWindow

        private enum LayoutType {
            XBOX,
            SWITCH
        }

        static construct {
            logical_names = {
                _("None"),
                "A", "B", "X", "Y",
                "L1", "R1", "L2", "R2",
                _("Select"), _("Start"), "L3", "R3", _("Home"), _("Touchpad"),
                _("D-Pad Up"), _("D-Pad Down"), _("D-Pad Left"), _("D-Pad Right")
            };
        }
        
        public KeybindsDialog(Gtk.Window parent, KeybindsManager manager, Controller controller) {
            Object(
                title: _("Keybinds Configuration"),
                transient_for: parent,
                modal: true,
                resizable: true,
                default_width: 800,
                default_height: 560
            );
            this.parent = parent;
            this.keybinds_manager = manager;
            this.slot = (uint8)controller.slot;
            this.controller = controller;
            this.rows_by_physical = new HashTable<int, Adw.ComboRow>(direct_hash, direct_equal);
            
            init_physical_names();
            build_ui();
            load_keymap.begin();
            
            var key_controller = new Gtk.EventControllerKey();
            key_controller.key_pressed.connect((keyval, keycode, state) => {
                if (keyval == Gdk.Key.Escape) {
                    close();
                    return true;
                }
                return false;
            });
            ((Gtk.Widget)this).add_controller(key_controller);
        }
        
        private void init_physical_names() {
            physical_names = new string[18];
            switch (controller.controller_type) {
                case ControllerType.DS4:
                case ControllerType.DUALSENSE:
                    set_playstation_names();
                    break;
                case ControllerType.NSW_PRO:
                    set_nsw_names();
                    break;
                default:
                    set_playstation_names();
                    break;
            }
        }
        
        private void set_playstation_names() {
            physical_names[0] = "Cross";
            physical_names[1] = "Circle";
            physical_names[2] = "Square";
            physical_names[3] = "Triangle";
            physical_names[4] = "L1";
            physical_names[5] = "R1";
            physical_names[6] = "L2";
            physical_names[7] = "R2";
            physical_names[8] = controller.controller_type == ControllerType.DUALSENSE ? "Create" : "Share";
            physical_names[9] = "Options";
            physical_names[10] = "L3";
            physical_names[11] = "R3";
            physical_names[12] = "PS";
            physical_names[13] = "Touchpad";
            physical_names[14] = _("D-Pad Up");
            physical_names[15] = _("D-Pad Down");
            physical_names[16] = _("D-Pad Left");
            physical_names[17] = _("D-Pad Right");
        }
        
        private void set_nsw_names() {
            physical_names[0] = "B";
            physical_names[1] = "A";
            physical_names[2] = "Y";
            physical_names[3] = "X";
            physical_names[4] = "L";
            physical_names[5] = "R";
            physical_names[6] = "ZL";
            physical_names[7] = "ZR";
            physical_names[8] = "Minus";
            physical_names[9] = "Plus";
            physical_names[10] = "L3";
            physical_names[11] = "R3";
            physical_names[12] = "Home";
            physical_names[13] = "Capture";
            physical_names[14] = _("D-Pad Up");
            physical_names[15] = _("D-Pad Down");
            physical_names[16] = _("D-Pad Left");
            physical_names[17] = _("D-Pad Right");
        }
        
        private void build_ui() {
            // ==================== Main ToolbarView ====================
            var toolbar_view = new Adw.ToolbarView();
            
            // --- Main top bar (default header) ---
            var main_header = new Adw.HeaderBar();
            main_header.set_show_start_title_buttons(false);
            main_header.set_show_end_title_buttons(false);
            
            // Reset button (left)
            var reset_button = new Gtk.Button.with_label(_("Reset to Default"));
            reset_button.add_css_class("destructive-action");
            reset_button.add_css_class("flat");
            reset_button.clicked.connect(on_reset_clicked);
            main_header.pack_start(reset_button);
            
            // Close button (right)
            var close_button = new Gtk.Button.with_label(_("Close"));
            close_button.add_css_class("flat");
            close_button.clicked.connect(() => close());
            main_header.pack_end(close_button);
            
            toolbar_view.add_top_bar(main_header);
            
            // --- Second top bar (flat, only for NSW_PRO) ---
            if (controller.controller_type == ControllerType.NSW_PRO) {
                var secondary_header = new Adw.HeaderBar();
                secondary_header.set_show_start_title_buttons(false);
                secondary_header.set_show_end_title_buttons(false);
                secondary_header.add_css_class("flat");
                
                // Container to center the ToggleGroup
                var center_box = new Gtk.Box(Gtk.Orientation.HORIZONTAL, 12);
                center_box.set_halign(Gtk.Align.CENTER);
                
                // Create the toggle group
                toggle_group = new Adw.ToggleGroup();
                
                // Xbox Layout button
                xbox_toggle = new Adw.Toggle();
                xbox_toggle.set_label(_("Xbox Layout"));
                xbox_toggle.tooltip = _("Restore Xbox button layout (A/B/X/Y identity)");
                xbox_toggle.set_name("xbox-layout");
                
                // Switch Layout button
                switch_toggle = new Adw.Toggle();
                switch_toggle.set_label(_("Switch Layout"));
                switch_toggle.tooltip = _("Enable Nintendo Switch button layout (swap A/B, X/Y)");
                switch_toggle.set_name("switch-layout");
                
                // Add to group
                toggle_group.add(xbox_toggle);
                toggle_group.add(switch_toggle);
                
                // Connect group change signal
                toggle_group_handler_id = toggle_group.notify["active-name"].connect(() => {
                    if (layout_updating || loading) return;
                    string? active_name = toggle_group.get_active_name();
                    if (active_name == "xbox-layout") {
                        on_layout_triggered.begin(LayoutType.XBOX);
                    } else if (active_name == "switch-layout") {
                        on_layout_triggered.begin(LayoutType.SWITCH);
                    }
                });
                
                center_box.append(toggle_group);
                secondary_header.set_title_widget(center_box);
                toolbar_view.add_top_bar(secondary_header);
            }
            
            // ==================== Main content ====================
            var scrolled = new Gtk.ScrolledWindow();
            scrolled.set_policy(PolicyType.NEVER, PolicyType.AUTOMATIC);
            scrolled.set_vexpand(true);
            
            var content_box = new Gtk.Box(Orientation.VERTICAL, 0);
            content_box.set_margin_top(24);
            content_box.set_margin_bottom(24);
            content_box.set_margin_start(24);
            content_box.set_margin_end(24);
            content_box.set_halign(Align.FILL);
            content_box.set_hexpand(true);
            
            apply_window_background(content_box);
            
            var clamp = new Adw.Clamp();
            clamp.set_maximum_size(1200);
            clamp.set_tightening_threshold(800);
            clamp.set_child(content_box);
            
            // Grid with 3 homogeneous columns
            var grid = new Gtk.Grid();
            grid.set_column_homogeneous(true);
            grid.set_row_spacing(0);
            grid.set_column_spacing(32);
            grid.set_halign(Align.CENTER);
            grid.set_vexpand(false);
            content_box.append(grid);
            
            // COLUMN 0: D-Pad + Start/Select
            var col0_box = new Gtk.Box(Orientation.VERTICAL, 16);
            col0_box.set_halign(Align.FILL);
            col0_box.set_hexpand(true);
            
            var dpad_group = create_group_for_buttons(_("D-Pad"), DPAD_INDICES);
            col0_box.append(dpad_group);
            
            var start_select_group = create_group_for_buttons(_("Start / Select"), SYSTEM_INDICES);
            col0_box.append(start_select_group);
            
            grid.attach(col0_box, 0, 0, 1, 1);
            
            // COLUMN 1: Face Buttons + Home/Touchpad
            var col1_box = new Gtk.Box(Orientation.VERTICAL, 16);
            col1_box.set_halign(Align.FILL);
            col1_box.set_hexpand(true);
            
            var face_group = create_group_for_buttons(_("Face Buttons"), FACE_INDICES);
            col1_box.append(face_group);
            
            var home_touch_group = create_group_for_buttons(_("System"), HOME_TOUCH_INDICES);
            col1_box.append(home_touch_group);
            
            grid.attach(col1_box, 1, 0, 1, 1);
            
            // COLUMN 2: L/R, L2/R2, L3/R3
            var col2_box = new Gtk.Box(Orientation.VERTICAL, 28);
            col2_box.set_halign(Align.FILL);
            col2_box.set_hexpand(true);
            
            var l1r1_group = create_group_for_buttons(_("L / R"), L1_R1_INDICES);
            col2_box.append(l1r1_group);
            
            var l2r2_group = create_group_for_buttons("", L2_R2_INDICES);
            col2_box.append(l2r2_group);
            
            var l3r3_group = create_group_for_buttons("", L3_R3_INDICES);
            col2_box.append(l3r3_group);
            
            grid.attach(col2_box, 2, 0, 1, 1);
            
            scrolled.set_child(clamp);
            toolbar_view.set_content(scrolled);
            this.set_content(toolbar_view);
        }
        
        private Adw.PreferencesGroup create_group_for_buttons(string title, int[] indices) {
            var group = new Adw.PreferencesGroup();
            if (title != null && title != "")
                group.set_title(title);
            
            foreach (int idx in indices) {
                var row = new Adw.ComboRow();
                row.set_title(physical_names[idx]);
                row.set_size_request(MIN_ROW_WIDTH, -1);
                
                var model = new Gtk.StringList(logical_names);
                row.set_model(model);
                row.set_data("phy-index", idx);
                
                row.notify["selected"].connect(() => {
                    if (loading) return;
                    int phy = row.get_data<int>("phy-index");
                    uint selected = row.get_selected();
                    if (selected != current_keymap[phy])
                        apply_keybind.begin(phy, (uint8)selected);
                });
                
                rows_by_physical.set(idx, row);
                group.add(row);
            }
            return group;
        }
        
        private void apply_window_background(Gtk.Widget widget) {
            widget.add_css_class("keybinds-window-bg");
            var provider = new Gtk.CssProvider();
            try {
                provider.load_from_string("""
                    .keybinds-window-bg {
                        background-color: var(--window-bg) !important;
                    }
                """);
                var display = Gdk.Display.get_default();
                if (display != null)
                    Gtk.StyleContext.add_provider_for_display(display, provider, Gtk.STYLE_PROVIDER_PRIORITY_APPLICATION);
            } catch (Error e) {
                warning("Failed to load CSS: %s", e.message);
            }
        }
        
        // ==================== LAYOUT METHODS ====================
        
        private async void reload_keymap_with_delay() {
            // Wait 300ms for the daemon to process the layout switch
            yield sleep(300);
            yield load_keymap();
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
        
        /// Synchronizes the toggle group with the current controller.layout_mode value
        private void update_layout_toggle_from_controller() {
            if (toggle_group == null) return;
            
            // Disconnect the signal temporarily to avoid loops
            if (toggle_group_handler_id != 0) {
                toggle_group.disconnect(toggle_group_handler_id);
                toggle_group_handler_id = 0;
            }
            
            bool is_switch = (controller.layout_mode == 1);
            string active_name = is_switch ? "switch-layout" : "xbox-layout";
            toggle_group.set_active_name(active_name);
            
            // Reconnect the signal
            toggle_group_handler_id = toggle_group.notify["active-name"].connect(() => {
                if (layout_updating || loading) return;
                string? active = toggle_group.get_active_name();
                if (active == "xbox-layout") {
                    on_layout_triggered.begin(LayoutType.XBOX);
                } else if (active == "switch-layout") {
                    on_layout_triggered.begin(LayoutType.SWITCH);
                }
            });
        }
        
        /// Sets layout_mode based on the current keymap (only for initialization or reset)
        private void set_layout_mode_from_keymap() {
            if (current_keymap == null || current_keymap.length < 4) return;
            uint8 b = current_keymap[0];
            uint8 a = current_keymap[1];
            uint8 y = current_keymap[2];
            uint8 x = current_keymap[3];
            // Switch layout: B->A, A->B, Y->X, X->Y
            bool is_switch = (b == 1 && a == 2 && y == 3 && x == 4);
            controller.layout_mode = is_switch ? 1 : 0;
        }
        
        private async void on_layout_triggered(LayoutType layout) {
            if (layout_updating) return;
            
            layout_updating = true;
            
            // Disable the group during the operation
            if (toggle_group != null) toggle_group.set_sensitive(false);
            
            try {
                if (layout == LayoutType.XBOX) {
                    yield keybinds_manager.apply_xbox_layout(slot);
                } else {
                    yield keybinds_manager.apply_switch_layout(slot);
                }
                yield reload_keymap_with_delay();
                
                // Explicitly set layout_mode on the controller
                controller.layout_mode = (layout == LayoutType.SWITCH) ? 1 : 0;
                // Synchronize the toggle group
                update_layout_toggle_from_controller();
                
                layout_changed();
            } catch (Error e) {
                show_error(_("Failed to apply layout: %s").printf(e.message));
                // Revert the toggle based on the current layout_mode
                update_layout_toggle_from_controller();
            } finally {
                layout_updating = false;
                if (toggle_group != null) toggle_group.set_sensitive(true);
            }
        }
        
        private async void load_keymap() {
            if (loading) return;
            loading = true;
            try {
                current_keymap = yield keybinds_manager.get_keymap(slot);
                foreach (int phy in rows_by_physical.get_keys()) {
                    var row = rows_by_physical.get(phy);
                    if (row != null) {
                        uint8 logical = (phy < current_keymap.length) ? current_keymap[phy] : 0;
                        if (logical >= logical_names.length) logical = 0;
                        row.set_selected(logical);
                    }
                }
                
                // Update the shared Controller object with MainWindow
                if (current_keymap != null && current_keymap.length == 18) {
                    for (int i = 0; i < 18; i++) {
                        controller.keymap[i] = current_keymap[i];
                    }
                }
                
                // Synchronize the toggle group with the existing layout_mode on the controller
                // (layout_mode was set by ControllerManager during initialization)
                update_layout_toggle_from_controller();
            } catch (Error e) {
                show_error(_("Failed to load keymap: %s").printf(e.message));
            } finally {
                loading = false;
            }
        }
        
        private async void apply_keybind(int physical, uint8 logical) {
            try {
                yield keybinds_manager.set_keybind(slot, (uint8)physical, logical);
                current_keymap[physical] = logical;
                show_toast(_("Keybind applied"));
                // After changing a keybind, do NOT update layout_mode.
                // Only keep the toggle group synchronized with the current layout_mode.
                // layout_mode only changes by explicit user action on the toggle.
                // (no call to update_layout_toggle_from_controller is needed here)
            } catch (Error e) {
                show_error(_("Failed to set keybind: %s").printf(e.message));
                load_keymap.begin();
            }
        }
        
        private async void on_reset_clicked() {
            var confirm = new Adw.AlertDialog(
                _("Reset Keybinds"),
                _("Are you sure you want to reset all keybinds to default?")
            );
            confirm.add_response("cancel", _("Cancel"));
            confirm.add_response("reset", _("Reset"));
            confirm.set_default_response("cancel");
            confirm.set_close_response("cancel");
            string response = yield confirm.choose(this, null);
            if (response != "reset") return;
            try {
                yield keybinds_manager.reset_keybinds(slot);
                show_toast(_("Keybinds reset to default"));
                yield load_keymap();   // wait for full load
                
                // Set layout_mode to Xbox (0) because reset restores identity mapping
                controller.layout_mode = 0;
                update_layout_toggle_from_controller();
                layout_changed();
            } catch (Error e) {
                show_error(_("Failed to reset keybinds: %s").printf(e.message));
            }
        }
        
        private void show_toast(string message) {
            var main_window = parent as Dstx.MainWindow;
            if (main_window != null)
                main_window.show_toast(message);
            else {
                var alert = new Adw.AlertDialog(_("Info"), message);
                alert.add_response("ok", _("OK"));
                alert.present(this);
            }
        }
        
        private void show_error(string message) {
            var alert = new Adw.AlertDialog(_("Error"), message);
            alert.add_response("ok", _("OK"));
            alert.present(this);
        }
    }
}
