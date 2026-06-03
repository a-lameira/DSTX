/*
 * profiles-dialog.vala - Profile management dialog for DSTX GUI
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
 * - Provide UI for managing controller profiles (create, load, save, delete)
 * - Load profile list via ProfileManager
 * - Handle confirmation dialogs for destructive actions
 */

// src/widgets/profiles-dialog.vala

using Gtk;
using Adw;
using Dstx.Managers;

namespace Dstx.Widgets {
    public class ProfilesDialog : Adw.Window {
        private ProfileManager profile_manager;
        private unowned Gtk.Window parent;

        private Gtk.ListBox profile_list;
        private Adw.PreferencesGroup new_profile_group;
        private Adw.EntryRow new_profile_entry;
        private Gtk.Button save_new_button;
        private Gtk.Button close_button;
        private Gtk.Button add_button;

        private Gee.ArrayList<string> profiles;
        private bool operation_in_progress = false;

        public ProfilesDialog(Gtk.Window parent, ProfileManager profile_manager) {
            Object(
                title: _("Profile Manager"),
                transient_for: parent,
                modal: true,
                resizable: true,
                default_width: 550,
                default_height: 450
            );
            this.parent = parent;
            this.profile_manager = profile_manager;
            this.profiles = new Gee.ArrayList<string>();

            build_ui();
            load_profile_list.begin();
        }

        private void build_ui() {
            var toolbar_view = new Adw.ToolbarView();

            var header = new Adw.HeaderBar();
            header.set_show_start_title_buttons(false);
            header.set_show_end_title_buttons(false);

            add_button = new Gtk.Button();
            add_button.set_icon_name("list-add-symbolic");
            add_button.add_css_class("flat");
            add_button.set_tooltip_text(_("Create new profile"));
            add_button.clicked.connect(on_add_button_clicked);
            header.pack_start(add_button);

            close_button = new Gtk.Button.with_label(_("Close"));
            close_button.add_css_class("flat");
            close_button.clicked.connect(() => close());
            header.pack_end(close_button);

            toolbar_view.add_top_bar(header);

            var content = new Gtk.Box(Gtk.Orientation.VERTICAL, 24);
            content.margin_top = 24;
            content.margin_bottom = 24;
            content.margin_start = 24;
            content.margin_end = 24;
            content.set_vexpand(true);

            // Group for profile creation (initially hidden)
            new_profile_group = new Adw.PreferencesGroup();
            new_profile_group.set_title(_("New Profile"));
            new_profile_group.set_visible(false);
            content.append(new_profile_group);

            new_profile_entry = new Adw.EntryRow();
            new_profile_entry.set_title(_("Profile Name"));
            // Connect entry_activated signal (emitted when pressing Enter)
            new_profile_entry.entry_activated.connect(() => {
                if (!operation_in_progress) save_new_profile();
            });
            // Allow Entry to activate the window's default widget
            new_profile_entry.set_activates_default(true);
            new_profile_group.add(new_profile_entry);

            save_new_button = new Gtk.Button.with_label(_("Save"));
            save_new_button.add_css_class("suggested-action");
            save_new_button.set_halign(Gtk.Align.START);
            save_new_button.set_margin_top(12);
            save_new_button.clicked.connect(() => {
                if (!operation_in_progress) save_new_profile();
            });
            new_profile_group.add(save_new_button);

            // Set the "Save" button as the window's default widget
            this.set_default_widget(save_new_button);

            // List of saved profiles
            var list_group = new Adw.PreferencesGroup();
            list_group.set_title(_("Saved Profiles"));
            list_group.set_vexpand(true);

            var scrolled = new Gtk.ScrolledWindow();
            scrolled.set_policy(Gtk.PolicyType.NEVER, Gtk.PolicyType.AUTOMATIC);
            scrolled.set_vexpand(true);
            scrolled.set_hexpand(true);

            profile_list = new Gtk.ListBox();
            profile_list.set_selection_mode(Gtk.SelectionMode.NONE);
            profile_list.set_hexpand(true);
            profile_list.add_css_class("boxed-list");
            scrolled.set_child(profile_list);

            list_group.add(scrolled);
            content.append(list_group);

            toolbar_view.set_content(content);
            this.set_content(toolbar_view);
        }

        private void on_add_button_clicked() {
            if (operation_in_progress) return;
            bool visible = !new_profile_group.get_visible();
            new_profile_group.set_visible(visible);
            if (visible) {
                new_profile_entry.grab_focus();
            } else {
                new_profile_entry.set_text("");
            }
        }

        private async void save_new_profile() {
            if (operation_in_progress) return;
            operation_in_progress = true;

            string name = new_profile_entry.get_text().strip();
            if (name == "") {
                show_toast(_("Please enter a profile name"));
                operation_in_progress = false;
                return;
            }
            try {
                yield profile_manager.save_profile(name);
                show_toast(_("Profile '%s' created successfully").printf(name));
                new_profile_entry.set_text("");
                new_profile_group.set_visible(false);
                Idle.add(() => {
                    load_profile_list.begin();
                    return Source.REMOVE;
                });
            } catch (Error e) {
                show_toast(_("Failed to create profile: %s").printf(e.message));
            } finally {
                operation_in_progress = false;
            }
        }

        private async void load_profile_list() {
            if (operation_in_progress) {
                Idle.add(() => {
                    load_profile_list.begin();
                    return Source.REMOVE;
                });
                return;
            }
            operation_in_progress = true;

            while (true) {
                var row = profile_list.get_row_at_index(0);
                if (row == null) break;
                profile_list.remove(row);
                row.destroy();
            }
            profiles.clear();

            try {
                string[] list = yield profile_manager.get_profile_list();
                foreach (string name in list) {
                    profiles.add(name);
                    var row = new Adw.ActionRow();
                    row.set_title(name);
                    row.set_margin_bottom(6);
                    row.set_activatable(false);

                    var load_btn = new Gtk.Button.with_label(_("Load"));
                    load_btn.add_css_class("compact-button");
                    load_btn.clicked.connect(() => {
                        if (!operation_in_progress) load_profile(name);
                    });

                    var save_btn = new Gtk.Button();
                    save_btn.set_icon_name("document-save-symbolic");
                    save_btn.add_css_class("compact-button");
                    save_btn.add_css_class("flat");
                    save_btn.set_tooltip_text(_("Overwrite this profile with current settings"));
                    save_btn.clicked.connect(() => {
                        if (!operation_in_progress) save_profile(name);
                    });

                    var delete_btn = new Gtk.Button();
                    delete_btn.set_icon_name("user-trash-symbolic");
                    delete_btn.add_css_class("destructive-action");
                    delete_btn.add_css_class("compact-button");
                    delete_btn.add_css_class("flat");
                    delete_btn.set_tooltip_text(_("Delete this profile"));
                    delete_btn.clicked.connect(() => {
                        if (!operation_in_progress) delete_profile(name);
                    });

                    var box = new Gtk.Box(Gtk.Orientation.HORIZONTAL, 6);
                    box.set_halign(Gtk.Align.END);
                    box.append(load_btn);
                    box.append(save_btn);
                    box.append(delete_btn);
                    row.add_suffix(box);

                    profile_list.append(row);
                }
                profile_list.queue_resize();
            } catch (Error e) {
                show_toast(_("Failed to load profiles: %s").printf(e.message));
            } finally {
                operation_in_progress = false;
            }
        }

        private async void load_profile(string name) {
            if (operation_in_progress) return;
            operation_in_progress = true;
            try {
                yield profile_manager.load_profile(name);
                show_toast(_("Profile '%s' loaded successfully").printf(name));
                close();
            } catch (Error e) {
                show_toast(_("Failed to load profile: %s").printf(e.message));
            } finally {
                operation_in_progress = false;
            }
        }

        private async void save_profile(string name) {
            if (operation_in_progress) return;
            operation_in_progress = true;
            try {
                yield profile_manager.save_profile(name);
                show_toast(_("Profile '%s' saved (overwritten)").printf(name));
                Idle.add(() => {
                    load_profile_list.begin();
                    return Source.REMOVE;
                });
            } catch (Error e) {
                show_toast(_("Failed to save profile: %s").printf(e.message));
            } finally {
                operation_in_progress = false;
            }
        }

        private async void delete_profile(string name) {
            if (operation_in_progress) return;
            operation_in_progress = true;

            var confirm = new Adw.AlertDialog(
                _("Confirm Deletion"),
                _("Are you sure you want to delete the profile '%s'?").printf(name)
            );
            confirm.add_response("cancel", _("Cancel"));
            confirm.add_response("delete", _("Delete"));
            confirm.set_default_response("cancel");
            confirm.set_close_response("cancel");

            string response = yield confirm.choose(this, null);
            if (response != "delete") {
                operation_in_progress = false;
                return;
            }

            try {
                yield profile_manager.delete_profile(name);
                show_toast(_("Profile '%s' deleted").printf(name));
                Idle.add(() => {
                    load_profile_list.begin();
                    return Source.REMOVE;
                });
            } catch (Error e) {
                show_toast(_("Failed to delete profile: %s").printf(e.message));
            } finally {
                operation_in_progress = false;
            }
        }

        private void show_toast(string message) {
            var main_window = parent as Dstx.MainWindow;
            if (main_window != null) {
                main_window.show_toast(message);
            } else {
                var alert = new Adw.AlertDialog(_("Info"), message);
                alert.add_response("ok", _("OK"));
                alert.present(this);
            }
        }
    }
}
