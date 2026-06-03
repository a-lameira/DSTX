/*
 * update-dialog.vala - System component update dialog for DSTX GUI
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
 * - Display dialog for updating DSTX system components
 * - Show current and available versions
 * - Handle update process with user feedback
 * - Notify completion via signal
 */

// src/widgets/update-dialog.vala

using Gtk;
using Dstx.Core;

namespace Dstx.Widgets {
    public class UpdateDialog : Adw.Window {
        private Adw.HeaderBar header;
        private Gtk.Label status_label;
        private Gtk.Spinner spinner;
        private Gtk.Button action_button;
        private bool updating = false;
        private string current_version;
        private string expected_version;
        
        public signal void update_completed(bool success);
        
        public UpdateDialog(Gtk.Window parent, string current, string expected) {
            Object(
                title: _("  "),
                transient_for: parent,
                modal: true,
                resizable: false,
                default_width: 450,
                default_height: 200
            );
            
            this.current_version = current;
            this.expected_version = expected;
            
            setup_ui();
        }
        
        private void setup_ui() {
            var toolbar_view = new Adw.ToolbarView();
            
            header = new Adw.HeaderBar();
            header.set_show_start_title_buttons(false);
            header.set_show_end_title_buttons(false);
            
            var close_button = new Gtk.Button.with_label(_("Cancel"));
            close_button.add_css_class("flat");
            close_button.clicked.connect(() => close());
            header.pack_start(close_button);
            
            action_button = new Gtk.Button.with_label(_("Update Now"));
            action_button.add_css_class("suggested-action");
            action_button.clicked.connect(() => start_update());
            header.pack_end(action_button);
            
            toolbar_view.add_top_bar(header);
            
            var content = new Gtk.Box(Gtk.Orientation.VERTICAL, 24);
            content.margin_top = 32;
            content.margin_bottom = 32;
            content.margin_start = 24;
            content.margin_end = 24;
            
            string info_text = _("A new version of DSTX system components is available.\n\n") +
                               _("Current version: %s\n").printf(current_version) +
                               _("New version: %s\n\n").printf(expected_version) +
                               _("This operation requires administrative privileges.");
            
            var info_label = new Gtk.Label(info_text);
            info_label.set_wrap(true);
            info_label.set_wrap_mode(Pango.WrapMode.WORD);
            info_label.set_max_width_chars(50);
            info_label.set_justify(Gtk.Justification.CENTER);
            
            var center_box = new Gtk.Box(Gtk.Orientation.VERTICAL, 16);
            center_box.set_halign(Gtk.Align.CENTER);
            center_box.set_valign(Gtk.Align.CENTER);
            center_box.set_hexpand(true);
            center_box.set_vexpand(true);
            
            spinner = new Gtk.Spinner();
            spinner.set_size_request(48, 48);
            spinner.visible = false;
            
            status_label = new Gtk.Label("");
            status_label.visible = false;
            status_label.add_css_class("dim-label");
            
            center_box.append(spinner);
            center_box.append(status_label);
            
            content.append(info_label);
            content.append(center_box);
            
            toolbar_view.set_content(content);
            this.set_content(toolbar_view);
        }
        
        private async void start_update() {
            if (updating) return;
            updating = true;
            
            action_button.set_sensitive(false);
            spinner.visible = true;
            spinner.start();
            status_label.visible = true;
            status_label.set_text(_("Removing old components..."));
            
            bool success = yield SystemServiceManager.update_system_components();
            
            spinner.stop();
            spinner.visible = false;
            
            if (success) {
                status_label.set_text(_("Update completed successfully!\nPlease restart the application."));
                status_label.remove_css_class("dim-label");
                status_label.add_css_class("accent");
                
                var restart_button = new Gtk.Button.with_label(_("Close"));
                restart_button.add_css_class("suggested-action");
                restart_button.clicked.connect(() => {
                    var app = GLib.Application.get_default();
                    if (app != null) app.quit();
                });
                header.pack_end(restart_button);
            } else {
                status_label.set_text(_("Update failed. Please check terminal for details."));
                status_label.add_css_class("error");
                var close_btn = new Gtk.Button.with_label(_("Close"));
                close_btn.add_css_class("flat");
                close_btn.clicked.connect(() => close());
                header.pack_end(close_btn);
            }
            
            action_button.visible = false;
            update_completed(success);
        }
    }
}
