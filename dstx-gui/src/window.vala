/*
 * window.vala - Main application window for DSTX GUI
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
 * - Main window UI setup and state management
 * - Controller selection and widget rendering
 * - Integration with DBus client, profile manager, keybinds manager
 * - Handling daemon, service installation, and version updates
 * - Window size and sidebar persistence
 */

// src/window.vala

using Dstx.Core;
using Dstx.Models;
using Dstx.Widgets;
using Dstx.Renderers;
using Dstx.Managers;
using Dstx.ViewModels;
using Gtk;

namespace Dstx {
    [GtkTemplate (ui = "/org/dstx/gui/window.ui")]
    public class MainWindow : Adw.Window {
        [GtkChild] private unowned Gtk.Stack main_stack;
        [GtkChild] private unowned Adw.StatusPage no_daemon_page;
        [GtkChild] private unowned Adw.StatusPage no_controllers_page;
        [GtkChild] private unowned Adw.OverlaySplitView left_split_view;
        [GtkChild] private unowned Adw.OverlaySplitView right_split_view;
        [GtkChild] private unowned Gtk.Box cards_container;
        [GtkChild] private unowned Adw.PreferencesPage settings_page;
        [GtkChild] private unowned Gtk.CenterBox controller_center_container;
        [GtkChild] private unowned Gtk.Button hide_sidebar_button;
        [GtkChild] private unowned Gtk.Button show_sidebar_button;
        [GtkChild] private unowned Gtk.Button hide_right_sidebar_button;
        [GtkChild] private unowned Adw.HeaderBar left_sidebar_header;
        [GtkChild] private unowned Adw.HeaderBar center_header;
        [GtkChild] private unowned Gtk.Label splash_status_label;
        [GtkChild] private unowned Gtk.Button info_button;
        [GtkChild] private unowned Gtk.Button start_service_button;

        [GtkChild] private unowned Gtk.Label splash_title_label;
        [GtkChild] private unowned Adw.WindowTitle left_sidebar_title;
        [GtkChild] private unowned Adw.WindowTitle window_title;
        [GtkChild] private unowned Gtk.MenuButton main_menu_button;
        [GtkChild] private unowned Gtk.MenuButton splash_menu_button;
        [GtkChild] private unowned Gtk.MenuButton no_daemon_menu_button;
        [GtkChild] private unowned Gtk.MenuButton no_controllers_menu_button;
        [GtkChild] private unowned Adw.StatusPage no_service_page;
        [GtkChild] private unowned Gtk.Button install_service_button;
        [GtkChild] private unowned Gtk.MenuButton no_service_menu_button;

        // Manager fields
        private ProfileManager profile_manager;
        private KeybindsManager keybinds_manager;

        private DBusClient dbus_client;
        private AppStateManager state_manager;
        private ControllerManager controller_manager;
        private SettingsController settings_controller;
        private SettingsUIBuilder settings_ui_builder;

        private Widget? current_controller_widget = null;
        private ControllerViewModel? current_view_model = null; // Reference to current widget's ViewModel
        private uint64 current_widget_version = 0;
        private bool updating_from_selection = false;
        private uint update_timeout = 0;
        private Adw.ToastOverlay? toast_overlay = null;
        private uint check_updates_timeout = 0;
        private bool update_dialog_shown = false;

        // Download URL for core package (non-Flatpak)
        private const string CORE_DOWNLOAD_URL = "https://dstxapp.org/#download";

        public MainWindow(DBusClient dbus_client) {
            Object();
            this.dbus_client = dbus_client;
            this.profile_manager = new ProfileManager(dbus_client);
            this.keybinds_manager = new KeybindsManager(dbus_client);
            this.set_size_request(700, 500);

            // Load and restore window size
            var settings = SettingsManager.get_default();
            int win_width = settings.get_window_width();
            int win_height = settings.get_window_height();
            if (win_width > 0 && win_height > 0) {
                this.set_default_size(win_width, win_height);
            }
            if (settings.get_window_maximized()) {
                this.maximize();
            }

            var settings_scrolled = find_settings_scrolled();

            this.state_manager = new AppStateManager(main_stack, splash_status_label, dbus_client);
            this.controller_manager = new ControllerManager(dbus_client, keybinds_manager, cards_container, null);
            this.settings_controller = new SettingsController(dbus_client);
            this.settings_ui_builder = new SettingsUIBuilder(dbus_client, profile_manager, controller_manager, settings_scrolled);

            setup_ui();
            setup_signals();
            setup_actions();
            setup_destroy();
            setup_no_daemon_buttons();
            setup_no_service_buttons();
            setup_toast_overlay();
            setup_localized_strings();

            // *** Configure buttons on the center toolbar ***
            setup_center_header_buttons();

            update_info_button_state(false);

            bool sidebar_visible = settings.get_sidebar_left_visible();
            if (left_split_view != null) {
                left_split_view.show_sidebar = sidebar_visible;
            }
            update_sidebar_buttons();

            state_manager.initialize.begin();

            // Wait for full initialization and automatically check for updates
            schedule_version_check();

            // Connect signal for maximized state persistence
            this.notify["maximized"].connect(on_window_maximized_changed);
        }

        private void setup_center_header_buttons() {
            if (center_header == null) {
                warning("MainWindow: center_header not found");
                return;
            }

            var button_box = new Gtk.Box(Gtk.Orientation.HORIZONTAL, 6);
            button_box.set_halign(Gtk.Align.CENTER);

            // Profiles button
            var profiles_btn = new Gtk.Button();
            var profiles_box = new Gtk.Box(Gtk.Orientation.HORIZONTAL, 6);
            var profiles_icon = new Gtk.Image.from_icon_name("accessories-dictionary-symbolic");
            profiles_icon.set_pixel_size(16);
            var profiles_label = new Gtk.Label(_("Profiles"));
            profiles_box.append(profiles_icon);
            profiles_box.append(profiles_label);
            profiles_btn.set_child(profiles_box);
            profiles_btn.set_tooltip_text(_("Manage profiles"));
            profiles_btn.clicked.connect(() => {
                var dialog = new ProfilesDialog(this, profile_manager);
                dialog.close_request.connect(() => {
                    settings_ui_builder.refresh_current_profile.begin();
                    return false;
                });
                dialog.present();
            });

            // Keybinds button
            var keybinds_btn = new Gtk.Button();
            var keybinds_box = new Gtk.Box(Gtk.Orientation.HORIZONTAL, 6);
            var keybinds_icon = new Gtk.Image.from_icon_name("year-symbolic");
            keybinds_icon.set_pixel_size(16);
            var keybinds_label = new Gtk.Label(_("Keybinds"));
            keybinds_box.append(keybinds_icon);
            keybinds_box.append(keybinds_label);
            keybinds_btn.set_child(keybinds_box);
            keybinds_btn.set_tooltip_text(_("Configure button mappings"));
            
            // Single clicked connection
            keybinds_btn.clicked.connect(() => {
                if (controller_manager.selected_controller == null) {
                    show_toast(_("No controller selected"));
                    return;
                }
                var dialog = new KeybindsDialog(this, keybinds_manager, controller_manager.selected_controller);
                dialog.layout_changed.connect(() => {
                    // Force keymap refresh in the next cycle to avoid conflicts
                    Idle.add(() => {
                        if (current_view_model != null) {
                            current_view_model.refresh_keymap();
                        }
                        return Source.REMOVE;
                    });
                });
                dialog.present();
            });

            button_box.append(profiles_btn);
            button_box.append(keybinds_btn);
            center_header.set_title_widget(button_box);

            profiles_btn.set_sensitive(false);
            keybinds_btn.set_sensitive(false);

            controller_manager.controller_selected.connect((controller) => {
                bool enabled = (controller != null);
                profiles_btn.set_sensitive(enabled);
                keybinds_btn.set_sensitive(enabled);
            });

            message("MainWindow: Profiles and Keybinds buttons configured with icons on center toolbar");
        }

        // ==================== EXISTING METHODS ====================
        private Gtk.ScrolledWindow? find_settings_scrolled() {
            if (settings_page == null) return null;
            var parent = settings_page.get_parent();
            while (parent != null) {
                if (parent is Gtk.ScrolledWindow) return (Gtk.ScrolledWindow)parent;
                parent = parent.get_parent();
            }
            return null;
        }

        private void setup_destroy() {
            this.close_request.connect(() => {
                if (update_timeout != 0) {
                    Source.remove(update_timeout);
                    update_timeout = 0;
                }
                if (check_updates_timeout != 0) {
                    Source.remove(check_updates_timeout);
                    check_updates_timeout = 0;
                }
                clear_controller_widget();
                return false;
            });
        }

        private void setup_ui() {
            if (left_split_view != null) {
                left_split_view.notify["show-sidebar"].connect(update_sidebar_buttons);
            }
            if (right_split_view != null) {
                right_split_view.notify["show-sidebar"].connect(update_right_sidebar);
                right_split_view.notify["collapsed"].connect(update_right_sidebar);
            }
            if (hide_right_sidebar_button != null) {
                hide_right_sidebar_button.clicked.connect(on_hide_right_sidebar_clicked);
            }
            update_sidebar_buttons();
            update_right_sidebar();
        }

        private void setup_toast_overlay() {
            var original_content = this.get_content();
            if (original_content != null) {
                this.set_content(null);
                toast_overlay = new Adw.ToastOverlay();
                toast_overlay.set_child(original_content);
                this.set_content(toast_overlay);
                message("MainWindow: ToastOverlay configured successfully");
            } else {
                warning("MainWindow: Could not configure ToastOverlay - no content found");
            }
        }

        public void show_toast(string message) {
            if (toast_overlay != null) {
                var toast = new Adw.Toast(message);
                toast.set_timeout(2);
                toast_overlay.add_toast(toast);
            } else {
                warning("MainWindow: ToastOverlay not available to display: %s", message);
            }
        }

        private void setup_signals() {
            state_manager.transition_complete.connect(on_state_transition);
            state_manager.controllers_ready.connect(on_controllers_ready);
            controller_manager.controller_selected.connect(on_controller_selected);
            controller_manager.controllers_list_changed.connect(on_list_changed);
            controller_manager.controller_updated.connect(on_controller_updated);
            controller_manager.controller_added.connect(on_controller_added);
            controller_manager.controller_removed.connect(on_controller_removed);

            // Connect signal for when daemon goes offline – clear all controllers
            state_manager.daemon_offline.connect(() => {
                message("MainWindow: Daemon offline, clearing all controllers");
                controller_manager.clear_all();
                if (current_controller_widget != null) {
                    clear_controller_widget();
                    settings_ui_builder.clear();
                    current_widget_version = 0;
                    current_view_model = null;
                    update_info_button_state(false);
                }
            });
        }

        private void setup_actions() {
            var group = new GLib.SimpleActionGroup();

            var preferences = new GLib.SimpleAction("preferences", null);
            preferences.activate.connect(show_preferences_dialog);
            group.add_action(preferences);

            var tips = new GLib.SimpleAction("tips", null);
            tips.activate.connect(() => {
                var dialog = new TipsDialog();
                dialog.present(this);
            });
            group.add_action(tips);

            var donate = new GLib.SimpleAction("donate", null);
            donate.activate.connect(() => {
                var dialog = new DonationsDialog(this);
                dialog.present(this);
            });
            group.add_action(donate);

            var about = new GLib.SimpleAction("about", null);
            about.activate.connect(() => {
                var dialog = Dstx.Widgets.AboutDialog.create();
                dialog.present(this);
            });
            group.add_action(about);

            var quit = new GLib.SimpleAction("quit", null);
            quit.activate.connect(() => destroy());
            group.add_action(quit);

            this.insert_action_group("win", group);

            var menu = new GLib.Menu();
            var section = new GLib.Menu();
            section.append(_("Preferences"), "win.preferences");
            section.append(_("Tips"), "win.tips");
            section.append(_("Donate ❤️"), "win.donate");
            menu.append_section(null, section);

            section = new GLib.Menu();
            section.append(_("About DSTX"), "win.about");
            section.append(_("Quit"), "win.quit");
            menu.append_section(null, section);

            if (splash_menu_button != null) splash_menu_button.set_menu_model(menu);
            if (no_daemon_menu_button != null) no_daemon_menu_button.set_menu_model(menu);
            if (no_controllers_menu_button != null) no_controllers_menu_button.set_menu_model(menu);
            if (no_service_menu_button != null) no_service_menu_button.set_menu_model(menu);
            if (main_menu_button != null) main_menu_button.set_menu_model(menu);
        }

        private void setup_no_daemon_buttons() {
            if (start_service_button != null) {
                start_service_button.clicked.connect(() => {
                    start_service_async.begin();
                });
            }
        }

        private async void start_service_async() {
            message("MainWindow: Requesting service start");
            show_toast(_("Starting service..."));
            try {
                int exit_status = yield dbus_client.start_core_service();
                if (exit_status == 0) {
                    show_toast(_("Service started, reconnecting..."));
                    yield sleep(1500);
                    state_manager.retry_connection();
                } else {
                    show_toast(_("Failed to start service. Exit code: %d").printf(exit_status));
                }
            } catch (Error e) {
                warning("MainWindow: Error starting service: %s", e.message);
                show_toast(_("Error starting service: %s").printf(e.message));
            }
        }

		private void setup_no_service_buttons() {
    			if (Core.is_flatpak()) {
    			    // Flatpak: uses the install button from UI
    			    if (install_service_button != null) {
    			        install_service_button.clicked.connect(() => {
    			            confirm_installation.begin();
    			        });
    			    }
    			} else {
    			    // Non-Flatpak: core missing – show download link
    			    if (no_service_page != null) {
    			        no_service_page.set_title(_("DSTX Core Package Required"));
    			        no_service_page.set_description(
    			            _("The DSTX core service is not installed on your system.\n\n" +
    			              "Please download and install the core package from the official website.")
    			        );
    		        
    			        // Remove existing child
    			        var old_child = no_service_page.get_child();
    			        if (old_child != null) {
    			            no_service_page.set_child(null);
    			            old_child.destroy();
    			        }
    	        
    			        // Centered container for the button
    			        var center_box = new Gtk.Box(Gtk.Orientation.HORIZONTAL, 0);
    			        center_box.set_halign(Gtk.Align.CENTER);
    			        center_box.set_valign(Gtk.Align.CENTER);
    			        center_box.set_margin_top(12);
    			        center_box.set_margin_bottom(12);
            
    			        // Button with icon
    			        var download_button = new Gtk.Button();
    			        var button_box = new Gtk.Box(Gtk.Orientation.HORIZONTAL, 8);
    			        var icon = new Gtk.Image.from_icon_name("symbolic-link-symbolic");
    			        icon.set_pixel_size(14);
    			        var label = new Gtk.Label(_("Go to Downloads Page"));
    			        button_box.append(label);
    			        button_box.append(icon);
    			        download_button.set_child(button_box);
    			        download_button.add_css_class("suggested-action");
    			        download_button.add_css_class("pill");
    		        
    			        download_button.clicked.connect(() => {
    			            try {
    			                var launcher = new Gtk.UriLauncher(CORE_DOWNLOAD_URL);
    			                launcher.launch.begin(this, null, (obj, res) => {
    			                    try {
    			                        launcher.launch.end(res);
    			                    } catch (Error e) {
    			                        warning("Failed to open URL: %s", e.message);
    			                        show_toast(_("Could not open browser. Please visit %s").printf(CORE_DOWNLOAD_URL));
    			                    }
    			                });
    			            } catch (Error e) {
    			                warning("Error creating launcher: %s", e.message);
    			                show_toast(_("Could not open browser. Please visit %s").printf(CORE_DOWNLOAD_URL));
    			            }
    			        });
    		        
    			        center_box.append(download_button);
    			        no_service_page.set_child(center_box);
    			    }
    			}
		}

        public async void confirm_installation() {
            if (!Core.is_flatpak()) return;
            
            var dialog = new Adw.AlertDialog(
                _("DSTX System Service Required"),
                _("Click 'Install' to set up the DSTX system service (dstx-daemon).\n\n" +
                  "This operation requires administrative privileges.\n\n" +
                  "If you cancel, you can install later using the button on this screen.")
            );
            dialog.add_response("cancel", _("Cancel"));
            dialog.add_response("install", _("Install"));
            dialog.set_default_response("install");
            dialog.set_close_response("cancel");

            string response = yield dialog.choose(this, null);
            if (response == "install") {
                yield install_flatpak_components();
            }
        }

        private async void install_flatpak_components() {
            if (!Core.is_flatpak()) return;

            var progress_dialog = new Adw.AlertDialog(
                _("Installing DSTX Service"),
                _("Please wait while the DSTX service is being installed...\n\nThis may take a few seconds.")
            );
            progress_dialog.set_response_enabled("install", false);
            progress_dialog.set_response_enabled("cancel", false);

            var spinner = new Gtk.Spinner();
            spinner.set_size_request(48, 48);
            spinner.start();
            var spinner_box = new Gtk.Box(Gtk.Orientation.VERTICAL, 12);
            spinner_box.set_halign(Gtk.Align.CENTER);
            spinner_box.set_valign(Gtk.Align.CENTER);
            spinner_box.append(spinner);
            progress_dialog.set_extra_child(spinner_box);

            progress_dialog.present(this);
            bool success = yield SystemServiceManager.install_system_components();
            progress_dialog.close();

            if (success) {
                var result_dialog = new Adw.AlertDialog(
                    _("Installation Complete"),
                    _("The DSTX system service has been installed successfully.\n\n" +
                      "If this is your first installation, you will need to restart your user session in order to connect to the service.\n\n" +
                      "You can now try to connect your controller.")
                );
                result_dialog.add_response("close", _("Close"));
                yield result_dialog.choose(this, null);
                show_toast(_("✓ Service installed successfully"));
                state_manager.restart_check.begin();
            } else {
                show_toast(_("Installation failed. Check terminal for details."));
            }
        }

        private void setup_localized_strings() {
            this.set_title(_("DSTX"));
            splash_title_label.set_label(_("Initializing DSTX..."));
            splash_status_label.set_label(_("Checking service..."));
            no_daemon_page.set_title(_("Daemon is not running"));
            no_daemon_page.set_description(_("Start the DSTX service to continue"));
            start_service_button.set_label(_("Start Service"));
            no_controllers_page.set_title(_("No Controller Found"));
            no_controllers_page.set_description(_("Connect a controller to start"));
            
            // For non-Flatpak, the title/description will be overwritten in setup_no_service_buttons()
            // but we set defaults here for Flatpak case
            no_service_page.set_title(_("DSTX Service Not Installed"));
            no_service_page.set_description(_("Install the DSTX system service to use controllers."));
            install_service_button.set_label(_("Install Service"));
            
            if (left_sidebar_title != null) left_sidebar_title.set_title(_("Controllers"));
            hide_sidebar_button.set_tooltip_text(_("Hide controllers list"));
            show_sidebar_button.set_tooltip_text(_("Show controllers list"));
            hide_right_sidebar_button.set_tooltip_text(_("Close settings"));
            info_button.set_tooltip_text(_("Controller information"));
            if (splash_menu_button != null) splash_menu_button.set_tooltip_text(_("Menu"));
            if (no_daemon_menu_button != null) no_daemon_menu_button.set_tooltip_text(_("Menu"));
            if (no_controllers_menu_button != null) no_controllers_menu_button.set_tooltip_text(_("Menu"));
            if (no_service_menu_button != null) no_service_menu_button.set_tooltip_text(_("Menu"));
            if (main_menu_button != null) main_menu_button.set_tooltip_text(_("Menu"));
            if (window_title != null) window_title.set_title(_("DSTX"));
        }

        private void on_state_transition(AppState state) {
            if (state == AppState.MAIN && controller_manager.get_controller_count() > 0) {
                controller_manager.select_first();
            } else if (state == AppState.NO_CONTROLLERS) {
                clear_controller_widget();
                settings_ui_builder.clear();
                update_info_button_state(false);
            }
        }

        private void on_controllers_ready() {
            controller_manager.load_initial_controllers.begin();
        }

        private void on_controller_selected(Controller controller) {
            message("Window: Controller selected - %s", controller.to_string());
            updating_from_selection = true;
            clear_controller_widget();
            update_controller_widget(controller);
            settings_controller.set_current_controller(controller);
            settings_ui_builder.build_for_controller(controller, this);
            current_widget_version = controller.version;
            update_info_button_state(true);
            updating_from_selection = false;
        }

        private void on_list_changed(int count) {
            if (count == 0 && state_manager.current_state == AppState.MAIN) {
                state_manager.transition_to_state(AppState.NO_CONTROLLERS);
            } else if (count > 0 && state_manager.current_state == AppState.NO_CONTROLLERS) {
                state_manager.force_main();
            }
        }

        private void on_controller_updated(Controller controller) {
            if (updating_from_selection) return;
            if (controller_manager.selected_controller == null ||
                controller_manager.selected_controller.slot != controller.slot) return;
            if (controller.version <= current_widget_version) return;
            message("Window: Updating settings for version %llu", controller.version);
            
            // Update settings (LED, rumble, etc.) with debounce
            if (update_timeout != 0) Source.remove(update_timeout);
            update_timeout = Timeout.add(50, () => {
                settings_controller.update_from_controller(controller);
                current_widget_version = controller.version;
                update_timeout = 0;
                return Source.REMOVE;
            });
            
            // Update keymap immediately (may have changed due to layout)
            if (current_view_model != null) {
                current_view_model.refresh_keymap();
            }
        }

        private void on_controller_added(Controller controller) {
            if (controller_manager.get_controller_count() == 1) {
                controller_manager.select_controller(controller);
            }
        }

        private void on_controller_removed(uint8 slot) {
            message("MainWindow: Controller removed - slot %d", slot);
            if (controller_manager.selected_controller != null &&
                controller_manager.selected_controller.slot == slot) {
                message("MainWindow: Selected controller was removed, clearing widget");
                if (current_controller_widget != null) reset_sticks_position();
                clear_controller_widget();
                settings_ui_builder.clear();
                current_widget_version = 0;
                current_view_model = null;
                update_info_button_state(false);
            }
        }

        private void reset_sticks_position() {
            if (current_controller_widget != null && current_controller_widget is ControllerRenderer) {
                ((ControllerRenderer)current_controller_widget).reset_sticks();
            }
        }

        private void clear_controller_widget() {
            if (current_controller_widget != null) {
                message("=== Clearing controller widget ===");
                var old = controller_center_container.get_center_widget();
                if (old != null) {
                    controller_center_container.set_center_widget(null);
                    old.destroy();
                }
                current_controller_widget = null;
                current_view_model = null;
                message("=== Widget cleared ===");
            }
        }

        private Gtk.Widget create_info_box(ControllerViewModel view_model, string display_name) {
            var box = new Gtk.Box(Gtk.Orientation.VERTICAL, 6);
            box.set_halign(Gtk.Align.CENTER);
            box.set_margin_top(12);

            var name_label = new Gtk.Label(null);
            name_label.set_markup("<span font='16' weight='bold'>%s</span>".printf(display_name));
            name_label.set_halign(Gtk.Align.CENTER);
            box.append(name_label);

            var info_row = new Gtk.Box(Gtk.Orientation.HORIZONTAL, 12);
            info_row.set_halign(Gtk.Align.CENTER);

            var battery_icon = new Gtk.Image.from_icon_name("battery-full-symbolic");
            var battery_label = new Gtk.Label("%d%%".printf(view_model.battery));
            battery_label.add_css_class("caption");

            var connection_icon = new Gtk.Image();
            connection_icon.set_from_icon_name(view_model.is_bluetooth ? "bluetooth-symbolic" : "drive-removable-media-usb-symbolic");
            var connection_label = new Gtk.Label(view_model.is_bluetooth ? _("Bluetooth") : _("USB"));
            connection_label.add_css_class("caption");

            info_row.append(battery_icon);
            info_row.append(battery_label);
            info_row.append(connection_icon);
            info_row.append(connection_label);
            box.append(info_row);

            view_model.battery_changed.connect((percent) => {
                battery_label.set_text("%d%%".printf(percent));
            });
            view_model.connection_changed.connect((is_bluetooth) => {
                connection_icon.set_from_icon_name(is_bluetooth ? "bluetooth-symbolic" : "usb-symbolic");
                connection_label.set_text(is_bluetooth ? _("Bluetooth") : _("USB"));
            });

            return box;
        }

        private void update_controller_widget(Controller controller) {
            message("Window: update_controller_widget called for slot %d", controller.slot);
            if (controller_center_container == null || controller == null) return;

            var old_child = controller_center_container.get_center_widget();
            if (old_child != null) {
                controller_center_container.set_center_widget(null);
                old_child.destroy();
            }

            var view_model = new ControllerViewModel();
            view_model.bind(controller);
            current_view_model = view_model;  // Store reference for future updates

            ControllerRenderer? controller_widget = null;
            switch (controller.controller_type) {
                case ControllerType.DUALSENSE:
                    controller_widget = new DualsenseWidget(view_model);
                    break;
                case ControllerType.DS4:
                    controller_widget = new Ds4Widget(view_model);
                    break;
                case ControllerType.NSW_PRO:
                    controller_widget = new NswWidget(view_model);
                    break;
                default:
                    warning("Window: Unknown controller type: %d", controller.controller_type);
                    return;
            }

            // Set minimum widget size (expands to maximum)
            const int MIN_SIZE = 300;
            const int MAX_WIDTH = 650;
            controller_widget.set_size_request(MIN_SIZE, MIN_SIZE);

            // Allow expansion
            controller_widget.set_hexpand(true);
            controller_widget.set_vexpand(true);
            controller_widget.set_halign(Gtk.Align.FILL);
            controller_widget.set_valign(Gtk.Align.FILL);

            // Wrap in Adw.Clamp to control maximum width
            var clamp = new Adw.Clamp();
            clamp.maximum_size = MAX_WIDTH;
            clamp.set_child(controller_widget);
            clamp.set_hexpand(true);
            clamp.set_vexpand(true);
            clamp.set_halign(Gtk.Align.CENTER);
            clamp.set_valign(Gtk.Align.CENTER);

            var container_box = new Gtk.Box(Gtk.Orientation.VERTICAL, 0);
            container_box.set_halign(Gtk.Align.CENTER);
            container_box.set_valign(Gtk.Align.CENTER);
            container_box.set_hexpand(true);
            container_box.set_vexpand(true);
            container_box.append(clamp);

            var info_box = create_info_box(view_model, controller_widget.controller_display_name);
            container_box.append(info_box);

            controller_center_container.set_center_widget(container_box);
            current_controller_widget = controller_widget;
            current_widget_version = controller.version;
            update_info_button_state(true);
            controller_center_container.queue_resize();
        }

        private void update_sidebar_buttons() {
            if (left_split_view == null) return;
            bool visible = left_split_view.show_sidebar;
            if (hide_sidebar_button != null) hide_sidebar_button.visible = visible;
            if (show_sidebar_button != null) show_sidebar_button.visible = !visible;
        }

        private void update_right_sidebar() {
            if (right_split_view == null) return;
            bool collapsed = right_split_view.collapsed;
            bool show = right_split_view.show_sidebar;
            if (hide_right_sidebar_button != null) {
                hide_right_sidebar_button.visible = collapsed && show;
            }
        }

        [GtkCallback] private void on_hide_sidebar_clicked() {
            if (left_split_view != null) {
                left_split_view.show_sidebar = false;
                SettingsManager.get_default().set_sidebar_left_visible(false);
            }
        }

        [GtkCallback] private void on_show_sidebar_clicked() {
            if (left_split_view != null) {
                left_split_view.show_sidebar = true;
                SettingsManager.get_default().set_sidebar_left_visible(true);
            }
        }

        [GtkCallback] private void on_hide_right_sidebar_clicked() {
            if (right_split_view != null) right_split_view.show_sidebar = false;
        }

        [GtkCallback] private void on_info_button_clicked() {
            message("Window: Info button clicked");
            if (controller_manager.selected_controller != null) {
                show_controller_info_dialog(controller_manager.selected_controller);
            }
        }

        private void update_info_button_state(bool enabled) {
            if (info_button != null) info_button.sensitive = enabled;
        }

        private void show_controller_info_dialog(Controller controller) {
            if (controller == null) return;
            message("Window: Showing info dialog for slot %d", controller.slot);
            var dialog = new Adw.PreferencesDialog();
            dialog.set_title(_("Controller Information %d").printf(controller.slot + 1));
            var page = new Adw.PreferencesPage();
            page.set_title(_("Technical Details"));
            fetch_and_build_info_page.begin(controller, page, dialog);
        }

        private async void fetch_and_build_info_page(Controller controller,
                                                      Adw.PreferencesPage page,
                                                      Adw.PreferencesDialog dialog) {
            try {
                message("Window: Fetching detailed information from D-Bus...");
                var detailed = yield dbus_client.get_detailed_controller_info((uint8)controller.slot);
                message("Window: Detailed information received");

                var device_group = new Adw.PreferencesGroup();
                device_group.set_title(_("Device Information"));

                var type_row = new Adw.ActionRow();
                type_row.set_title(_("Type"));
                type_row.set_subtitle(controller.controller_type.to_string());
                type_row.set_activatable(false);
                type_row.set_selectable(false);
                device_group.add(type_row);

                string driver = (detailed != null && detailed.driver != "") ? detailed.driver : _("Not available");
                var driver_row = new Adw.ActionRow();
                driver_row.set_title(_("Driver"));
                driver_row.set_subtitle(driver);
                driver_row.set_activatable(false);
                driver_row.set_selectable(false);
                device_group.add(driver_row);

                string serial = (detailed != null && detailed.serial != "") ? detailed.serial : _("Not available");
                var serial_row = new Adw.ActionRow();
                serial_row.set_title(_("Address"));
                serial_row.set_subtitle(serial);
                serial_row.set_activatable(false);
                serial_row.set_selectable(false);
                device_group.add(serial_row);

                var connection_row = new Adw.ActionRow();
                connection_row.set_title(_("Connection"));
                connection_row.set_subtitle(controller.is_bluetooth ? _("Bluetooth") : _("USB"));
                connection_row.set_activatable(false);
                connection_row.set_selectable(false);
                device_group.add(connection_row);

                var slot_row = new Adw.ActionRow();
                slot_row.set_title(_("Slot"));
                slot_row.set_subtitle(controller.slot.to_string());
                slot_row.set_activatable(false);
                slot_row.set_selectable(false);
                device_group.add(slot_row);
                page.add(device_group);

                if (detailed != null && detailed.get_input_nodes().length() > 0) {
                    var nodes_group = new Adw.PreferencesGroup();
                    nodes_group.set_title(_("Input Nodes"));
                    int i = 1;
                    foreach (var node in detailed.get_input_nodes()) {
                        var node_row = new Adw.ActionRow();
                        node_row.set_title(_("Node %d").printf(i));
                        node_row.set_subtitle(node.name);
                        var path_label = new Gtk.Label(node.path);
                        path_label.add_css_class("caption");
                        path_label.add_css_class("dim-label");
                        path_label.halign = Gtk.Align.END;
                        path_label.set_selectable(false);
                        node_row.add_suffix(path_label);
                        node_row.set_activatable(false);
                        node_row.set_selectable(false);
                        nodes_group.add(node_row);
                        i++;
                    }
                    page.add(nodes_group);
                }
                dialog.add(page);
                dialog.present(this);
                message("Window: Information dialog built successfully");
            } catch (Error e) {
                warning("Window: Error fetching detailed information: %s", e.message);
                show_error_dialog(_("Error loading information"), e.message);
            }
        }

        private void show_preferences_dialog() {
            message("Window: Showing preferences dialog");
            settings_ui_builder.show_preferences_dialog(this);
        }

        private void show_error_dialog(string title, string message) {
            var dialog = new Adw.AlertDialog(title, message);
            dialog.add_response("ok", _("OK"));
            dialog.set_default_response("ok");
            dialog.set_close_response("ok");
            dialog.present(this);
        }

        // ==================== VERSIONING ====================

        private void schedule_version_check() {
            if (check_updates_timeout != 0) Source.remove(check_updates_timeout);
            check_updates_timeout = Timeout.add_seconds(5, () => {
                check_for_updates_async();
                check_updates_timeout = 0;
                return Source.REMOVE;
            });
        }

        // Helper to check if core is installed (non-Flatpak)
        private async bool check_core_installed() {
            // First try to find the dstx binary in PATH
            string? dstx_path = Environment.find_program_in_path("dstx");
            if (dstx_path != null) {
                return true;
            }
            // Fallback: try to connect to D-Bus and get version (daemon might be running)
            try {
                var connection = yield Bus.get(BusType.SYSTEM);
                var proxy = yield connection.get_proxy<DstxDBus>(
                    "org.dstx.Bridge",
                    "/org/dstx/Bridge",
                    DBusProxyFlags.NONE,
                    null
                );
                string version = yield proxy.get_core_version();
                return true;
            } catch (Error e) {
                return false;
            }
        }

        private async void check_for_updates_async() {
            if (update_dialog_shown) return;

            // For non-Flatpak, skip update check if core is not installed
            if (!Core.is_flatpak()) {
                bool core_installed = yield check_core_installed();
                if (!core_installed) {
                    message("MainWindow: Core package not installed, skipping update check.");
                    return;
                }
            }

            // For Flatpak, check if system components are installed
            if (Core.is_flatpak()) {
                bool installed = yield SystemServiceManager.are_system_components_installed();
                if (!installed) {
                    message("MainWindow: System components not installed, skipping update check.");
                    return;
                }
            }

            try {
                bool has_update = yield settings_controller.check_for_updates();
                if (has_update) {
                    update_dialog_shown = true;
                    string current = yield settings_controller.get_current_core_version();
                    string expected = settings_controller.get_expected_core_version();
                    var dialog = new UpdateDialog(this, current, expected);
                    dialog.update_completed.connect((success) => {
                        update_dialog_shown = false;
                        if (success) { }
                    });
                    dialog.present();
                }
            } catch (Error e) {
                warning("MainWindow: Error checking for updates: %s", e.message);
            }
        }

        // ==================== WINDOW SIZE PERSISTENCE (GTK4) ====================

        protected override void size_allocate(int width, int height, int baseline) {
            base.size_allocate(width, height, baseline);

            // Save only if window is not maximized
            if (!this.is_maximized()) {
                var settings = SettingsManager.get_default();
                int current_width = settings.get_window_width();
                int current_height = settings.get_window_height();
                if (current_width != width || current_height != height) {
                    settings.set_window_width(width);
                    settings.set_window_height(height);
                }
            }
        }

        private void on_window_maximized_changed() {
            bool maximized = this.is_maximized();
            var settings = SettingsManager.get_default();
            settings.set_window_maximized(maximized);
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

        ~MainWindow() {
            debug("Window destroyed");
        }
    }
}
