/*
 * appearance-page.vala - Theme appearance configuration page for DSTX GUI
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
 * - Provide UI for theme selection (standard, light, dark, user themes)
 * - Manage accent color palette and selection
 * - Handle theme mode switching (System, Light, Dark, Custom)
 * - Integrate with ThemeManager and SettingsController
 * - Provide sticky header with quick accent selection in custom mode
 * - Load theme thumbnails asynchronously
 */

// src/widgets/appearance-page.vala

using Gtk;
using Gdk;
using Dstx.Managers;
using Dstx.Models;

namespace Dstx.Widgets {

    public delegate void ThemeChangedCallback(string theme_id, string theme_name, Gdk.RGBA accent_color, int accent_index);
    public delegate void ThemeModeChangedCallback(int mode);

    public class AppearancePage : Adw.PreferencesPage {

        private ThemeManager theme_manager;
        private SettingsController? settings_controller = null;

        // Main widgets
        private Gtk.Box accent_colors_box;
        private Gtk.Box standard_gallery;
        private Gtk.Box light_gallery;
        private Gtk.Box dark_gallery;
        private Gtk.Box user_gallery;
        private List<Gtk.Widget> theme_items;

        // Current state
        private string selected_theme_id = "";
        private string selected_theme_name = "";
        private Gdk.RGBA selected_accent_color;
        private int selected_accent_index = 0;

        // Visual selection
        private Gtk.Widget? last_selected_theme_item = null;
        private Gtk.Button? last_selected_accent_button = null;

        // Callbacks
        private ThemeChangedCallback? on_theme_changed_callback;
        private ThemeModeChangedCallback? on_theme_mode_changed_callback;

        // Section widgets
        private Adw.PreferencesGroup? accent_group = null;
        private Adw.PreferencesGroup? standard_themes_group = null;
        private Adw.PreferencesGroup? light_themes_group = null;
        private Adw.PreferencesGroup? dark_themes_group = null;
        private Adw.PreferencesGroup? user_themes_group = null;

        // Sticky header
        private StickyHeader? sticky_header = null;
        private bool is_custom_mode = false;
        private bool is_active_page = false;
        private ulong page_changed_handler_id = 0;

        // Retry timeouts
        private uint retry_dialog_timeout = 0;
        private int retry_dialog_count = 0;
        private const uint MAX_RETRY_DIALOG = 5;
        private const uint RETRY_DIALOG_DELAY_MS = 500;

        // Cache of the actual system theme
        private bool _cached_system_is_dark = false;

        public AppearancePage.with_state(string? theme_id, string? theme_name, Gdk.RGBA? accent_color, int accent_index) {
            Object(
                title: Dstx._("Appearance"),
                icon_name: "brush-monitor-symbolic"
            );

            this.theme_manager = ThemeManager.get_default();
            this.theme_items = new List<Gtk.Widget>();

            this.selected_theme_id = theme_id ?? "light";
            this.selected_theme_name = theme_name ?? Dstx._("Light");
            this.selected_accent_index = accent_index;
            this.selected_accent_color = accent_color ?? Gdk.RGBA() { red = 0.2f, green = 0.5f, blue = 0.8f, alpha = 1.0f };

            // Get the real system theme
            update_system_theme_cache();

            setup_ui();
            setup_signals();
            load_current_settings();
            load_accent_colors_for_theme(this.selected_theme_id);
            build_theme_galleries.begin();

            this.realize.connect(on_realized);
            this.unrealize.connect(on_unrealized);
        }

        ~AppearancePage() {
            if (retry_dialog_timeout != 0) {
                Source.remove(retry_dialog_timeout);
                retry_dialog_timeout = 0;
            }
        }

        // Updates the cache of the real system theme
        private void update_system_theme_cache() {
            var settings = Gtk.Settings.get_default();
            if (settings != null) {
                _cached_system_is_dark = settings.gtk_application_prefer_dark_theme;
                message("AppearancePage: Real system theme: %s", _cached_system_is_dark ? "dark" : "light");
            } else {
                _cached_system_is_dark = false;
                warning("AppearancePage: Could not obtain Gtk.Settings");
            }
        }

        public void set_settings_controller(SettingsController controller) {
            this.settings_controller = controller;
            load_current_settings();
        }

        public void set_theme_mode_changed_callback(owned ThemeModeChangedCallback callback) {
            this.on_theme_mode_changed_callback = (owned)callback;
        }

        public void set_theme_changed_callback(owned ThemeChangedCallback callback) {
            this.on_theme_changed_callback = (owned)callback;
        }

        public void refresh() {
            load_current_settings();
            build_theme_galleries.begin();
        }

        public void force_sticky_reevaluate() {
            if (sticky_header != null) {
                sticky_header.force_reevaluate();
            }
        }

        private bool is_system_dark() {
            var settings = Gtk.Settings.get_default();
            return (settings != null) ? settings.gtk_application_prefer_dark_theme : false;
        }

        private void setup_ui() {
            // ===== SECTION 1: THEME MODE =====
            var theme_mode_section = new Adw.PreferencesGroup();
            theme_mode_section.set_title(Dstx._("Theme Mode"));
            theme_mode_section.set_description(Dstx._("Defines how the application theme is determined"));

            var theme_mode_row = new Adw.ComboRow();
            theme_mode_row.set_title(Dstx._("Mode"));
            string[] modes = { Dstx._("System"), Dstx._("Light (System)"), Dstx._("Dark (System)"), Dstx._("Custom (DSTX)") };
            var mode_model = new Gtk.StringList(modes);
            theme_mode_row.set_model(mode_model);

            int saved_mode = 0;
            if (settings_controller != null) {
                saved_mode = settings_controller.get_theme_mode();
            } else {
                saved_mode = theme_manager.ui_mode;
            }
            theme_mode_row.set_selected(saved_mode);
            is_custom_mode = (saved_mode == 3);

            set_theme_galleries_visible(is_custom_mode);
            update_accent_group_visibility();

            theme_mode_section.add(theme_mode_row);
            this.add(theme_mode_section);

            // ===== SECTION 2: ACCENT COLOR (ONLY IN CUSTOM MODE) =====
            accent_group = new Adw.PreferencesGroup();
            accent_group.set_title(Dstx._("Accent Color"));
            accent_group.set_description(Dstx._("Choose the color to be used on accent elements"));
            accent_group.visible = false;

            accent_colors_box = new Gtk.Box(Gtk.Orientation.HORIZONTAL, 4);
            accent_colors_box.halign = Gtk.Align.CENTER;
            accent_colors_box.margin_top = 12;
            accent_colors_box.margin_bottom = 12;
            accent_colors_box.hexpand = true;

            var center_container = new Gtk.Box(Gtk.Orientation.HORIZONTAL, 0);
            center_container.hexpand = true;
            center_container.halign = Gtk.Align.CENTER;
            center_container.append(accent_colors_box);

            var accent_row = new Adw.ActionRow();
            accent_row.set_child(center_container);
            accent_group.add(accent_row);
            this.add(accent_group);

            // ===== SECTION 3: DSTX BASE THEMES =====
            standard_themes_group = new Adw.PreferencesGroup();
            standard_themes_group.set_title(Dstx._("DSTX Base Themes"));
            standard_themes_group.set_description(Dstx._("Light and dark DSTX themes (independent of the system)"));

            standard_gallery = new Gtk.Box(Gtk.Orientation.HORIZONTAL, 32);
            standard_gallery.halign = Gtk.Align.CENTER;
            standard_gallery.margin_top = 12;
            standard_gallery.margin_bottom = 12;
            standard_gallery.hexpand = true;

            var standard_container = new Gtk.Box(Gtk.Orientation.HORIZONTAL, 0);
            standard_container.hexpand = true;
            standard_container.halign = Gtk.Align.CENTER;
            standard_container.append(standard_gallery);

            var standard_row = new Adw.ActionRow();
            standard_row.set_child(standard_container);
            standard_themes_group.add(standard_row);
            this.add(standard_themes_group);

            // ===== SECTION 4: LIGHT THEMES =====
            light_themes_group = new Adw.PreferencesGroup();
            light_themes_group.set_title(Dstx._("Light Themes"));
            light_themes_group.set_description(Dstx._("Themes with light background for well-lit environments"));

            light_gallery = new Gtk.Box(Gtk.Orientation.VERTICAL, 16);
            light_gallery.halign = Gtk.Align.CENTER;
            light_gallery.margin_top = 12;
            light_gallery.margin_bottom = 12;
            light_gallery.hexpand = true;

            var light_container = new Gtk.Box(Gtk.Orientation.HORIZONTAL, 0);
            light_container.hexpand = true;
            light_container.halign = Gtk.Align.CENTER;
            light_container.append(light_gallery);

            var light_row = new Adw.ActionRow();
            light_row.set_child(light_container);
            light_themes_group.add(light_row);
            this.add(light_themes_group);

            // ===== SECTION 5: DARK THEMES =====
            dark_themes_group = new Adw.PreferencesGroup();
            dark_themes_group.set_title(Dstx._("Dark Themes"));
            dark_themes_group.set_description(Dstx._("Themes with dark background for low-light environments"));

            dark_gallery = new Gtk.Box(Gtk.Orientation.VERTICAL, 16);
            dark_gallery.halign = Gtk.Align.CENTER;
            dark_gallery.margin_top = 12;
            dark_gallery.margin_bottom = 12;
            dark_gallery.hexpand = true;

            var dark_container = new Gtk.Box(Gtk.Orientation.HORIZONTAL, 0);
            dark_container.hexpand = true;
            dark_container.halign = Gtk.Align.CENTER;
            dark_container.append(dark_gallery);

            var dark_row = new Adw.ActionRow();
            dark_row.set_child(dark_container);
            dark_themes_group.add(dark_row);
            this.add(dark_themes_group);

            // ===== SECTION 6: USER THEMES =====
            user_themes_group = new Adw.PreferencesGroup();
            user_themes_group.set_title(Dstx._("Community Themes"));
            user_themes_group.set_description(Dstx._("Custom themes submitted by users"));
            user_themes_group.visible = false;  // Initially hidden, shown only if there are user themes

            user_gallery = new Gtk.Box(Gtk.Orientation.VERTICAL, 16);
            user_gallery.halign = Gtk.Align.CENTER;
            user_gallery.margin_top = 12;
            user_gallery.margin_bottom = 12;
            user_gallery.hexpand = true;

            var user_container = new Gtk.Box(Gtk.Orientation.HORIZONTAL, 0);
            user_container.hexpand = true;
            user_container.halign = Gtk.Align.CENTER;
            user_container.append(user_gallery);

            var user_row = new Adw.ActionRow();
            user_row.set_child(user_container);
            user_themes_group.add(user_row);
            this.add(user_themes_group);

            // Connect theme_mode_row signal
            theme_mode_row.notify["selected"].connect(() => {
                uint selected = theme_mode_row.get_selected();
                bool is_custom_now = (selected == 3);
                message("AppearancePage: Theme mode changed to %u (custom=%s)", selected, is_custom_now.to_string());
                is_custom_mode = is_custom_now;

                set_theme_galleries_visible(is_custom_now);
                update_accent_group_visibility();

                var style_manager = Adw.StyleManager.get_default();

                if (!is_custom_now) {
                    if (style_manager != null) {
                        switch (selected) {
                            case 0:
                                style_manager.color_scheme = Adw.ColorScheme.DEFAULT;
                                break;
                            case 1:
                                style_manager.color_scheme = Adw.ColorScheme.FORCE_LIGHT;
                                break;
                            case 2:
                                style_manager.color_scheme = Adw.ColorScheme.FORCE_DARK;
                                break;
                        }
                    }
                    theme_manager.set_ui_mode((int)selected);
                    if (sticky_header != null) {
                        sticky_header.set_custom_mode(false);
                        disable_scroll_monitoring();
                    }
                } else {
                    // --- FIXED CUSTOM MODE ---
                    // 1. Get saved values
                    string saved_theme = settings_controller != null
                        ? settings_controller.get_custom_theme_id()
                        : "light";
                    string saved_theme_name = settings_controller != null
                        ? settings_controller.get_custom_theme_name()
                        : _("Light");
                    int saved_accent_index = settings_controller != null
                        ? settings_controller.get_custom_accent_index()
                        : 0;
                    Gdk.RGBA saved_accent_color = settings_controller != null
                        ? settings_controller.get_custom_accent_color()
                        : Gdk.RGBA() { red = 0.2f, green = 0.5f, blue = 0.8f, alpha = 1.0f };

                    // 2. Detect the real system theme (using libadwaita)
                    style_manager = Adw.StyleManager.get_default();
                    bool system_is_dark = (style_manager != null) ? style_manager.dark : false;
                    message("Custom mode: system is dark? %s", system_is_dark.to_string());

                    // 3. Adjust base theme according to the system
                    string theme_to_apply = saved_theme;
                    string theme_name_to_apply = saved_theme_name;
                    if (saved_theme == "light" && system_is_dark) {
                        theme_to_apply = "dark";
                        theme_name_to_apply = _("Dark");
                        message("Replacing light -> dark");
                    } else if (saved_theme == "dark" && !system_is_dark) {
                        theme_to_apply = "light";
                        theme_name_to_apply = _("Light");
                        message("Replacing dark -> light");
                    }

                    // 4. Update internal page state
                    selected_theme_id = theme_to_apply;
                    selected_theme_name = theme_name_to_apply;
                    selected_accent_index = saved_accent_index;
                    selected_accent_color = saved_accent_color;

                    // 5. Apply custom mode FIRST
                    theme_manager.set_ui_mode(3);

                    // 6. Synchronize index and apply theme
                    theme_manager.selected_accent_index = saved_accent_index;
                    theme_manager.apply_theme(theme_to_apply, saved_accent_color);

                    // 7. Reapply accent color (guarantee)
                    theme_manager.apply_accent_color(saved_accent_color, saved_accent_index);

                    // 8. Update gallery visually
                    update_selected_theme_visual(theme_to_apply);
                    restore_accent_selection();

                    // 9. Save if replacement occurred
                    if (settings_controller != null && (saved_theme != theme_to_apply)) {
                        settings_controller.save_custom_theme(theme_to_apply, theme_name_to_apply,
                                                              saved_accent_color, saved_accent_index);
                    }

                    // 10. Force window update
                    var parent_window = this.get_root() as Gtk.Window;
                    if (parent_window != null) {
                        parent_window.queue_draw();
                    }

                    if (sticky_header != null) {
                        sticky_header.set_custom_mode(true);
                        enable_scroll_monitoring();
                    }
                }

                if (on_theme_mode_changed_callback != null) {
                    on_theme_mode_changed_callback((int)selected);
                }
            });
        }

        private void set_theme_galleries_visible(bool visible) {
            if (standard_themes_group != null) standard_themes_group.visible = visible;
            if (light_themes_group != null) light_themes_group.visible = visible;
            if (dark_themes_group != null) dark_themes_group.visible = visible;
            if (user_themes_group != null) user_themes_group.visible = visible && has_user_themes();
        }

        private bool has_user_themes() {
            var all_themes = theme_manager.get_all_themes();
            foreach (var theme in all_themes) {
                if (theme.theme_type == "user") {
                    return true;
                }
            }
            return false;
        }

        private void update_accent_group_visibility() {
            if (accent_group == null) return;
            bool should_show = is_custom_mode && (sticky_header == null || !sticky_header.get_visible());
            if (accent_group.visible != should_show) {
                accent_group.visible = should_show;
                message("AppearancePage: accent_group visibility = %s", should_show.to_string());
            }
        }

        public void load_current_settings() {
            if (settings_controller != null) {
                selected_theme_id = settings_controller.get_custom_theme_id();
                selected_theme_name = settings_controller.get_custom_theme_name();
                selected_accent_index = settings_controller.get_custom_accent_index();
                selected_accent_color = settings_controller.get_custom_accent_color();
                load_accent_colors_for_theme(selected_theme_id);
            }
        }

        // ==================== THEME GALLERIES ====================

        private async void build_theme_galleries() {
            message("AppearancePage: Building theme galleries");
            foreach (var item in theme_items) {
                if (item != null && item.get_parent() != null) {
                    item.destroy();
                }
            }
            theme_items = new List<Gtk.Widget>();

            clear_gallery(standard_gallery);
            clear_gallery(light_gallery);
            clear_gallery(dark_gallery);
            clear_gallery(user_gallery);

            // 1. Standard themes (Light and Dark)
            var standard_themes = theme_manager.get_standard_themes();
            foreach (var theme in standard_themes) {
                var item = yield create_theme_item(theme);
                standard_gallery.append(item);
                theme_items.append(item);
            }

            // 2. Get exclusive themes (excluding light/dark)
            var exclusive_themes = theme_manager.get_exclusive_themes();

            var light_exclusive = new Gee.ArrayList<ThemeData>();
            var dark_exclusive = new Gee.ArrayList<ThemeData>();
            var user_exclusive = new Gee.ArrayList<ThemeData>();

            foreach (var theme in exclusive_themes) {
                if (theme.theme_type == "light") {
                    light_exclusive.add(theme);
                } else if (theme.theme_type == "dark") {
                    dark_exclusive.add(theme);
                } else if (theme.theme_type == "user") {
                    user_exclusive.add(theme);
                }
            }

            // 3. Build grid for LIGHT themes
            if (light_exclusive.size > 0) {
                yield build_theme_grid(light_gallery, light_exclusive);
            }

            // 4. Build grid for DARK themes
            if (dark_exclusive.size > 0) {
                yield build_theme_grid(dark_gallery, dark_exclusive);
            }

            // 5. Build grid for USER themes
            if (user_exclusive.size > 0) {
                yield build_theme_grid(user_gallery, user_exclusive);
            }

            // 6. Show/hide user themes group based on existence
            if (user_themes_group != null) {
                user_themes_group.visible = user_exclusive.size > 0 && is_custom_mode;
            }

            set_theme_galleries_visible(is_custom_mode);
            restore_accent_selection();
            message("AppearancePage: Galleries built with %u themes (user themes: %d)", 
                    theme_items.length(), user_exclusive.size);
        }

        private async void build_theme_grid(Gtk.Box gallery, Gee.ArrayList<ThemeData> themes) {
            if (themes.size == 0) return;
            
            int items_per_row = 3;
            int row = 0;
            int index = 0;
            Gtk.Box? current_row = null;
            
            foreach (var theme in themes) {
                if (index % items_per_row == 0) {
                    current_row = new Gtk.Box(Gtk.Orientation.HORIZONTAL, 24);
                    current_row.halign = Gtk.Align.CENTER;
                    current_row.margin_top = row > 0 ? 8 : 0;
                    current_row.margin_bottom = row < 2 ? 8 : 0;
                    gallery.append(current_row);
                    row++;
                }

                var item = yield create_theme_item(theme);
                if (current_row != null) {
                    current_row.append(item);
                    theme_items.append(item);
                }
                index++;
            }
        }

        private void clear_gallery(Gtk.Box gallery) {
            Gtk.Widget? child = gallery.get_first_child();
            while (child != null) {
                var next = child.get_next_sibling();
                gallery.remove(child);
                child.destroy();
                child = next;
            }
        }

        private async Gtk.Widget create_theme_item(ThemeData theme) {
            var container = new Gtk.Box(Gtk.Orientation.VERTICAL, 8);
            container.halign = Gtk.Align.CENTER;
            container.add_css_class("theme-item-container");
            container.set_data("theme-id", theme.id);   // Store ID for later retrieval

            var image_container = new Gtk.Box(Gtk.Orientation.VERTICAL, 0);
            image_container.add_css_class("theme-image-container");
            image_container.set_size_request(160, 100);

            var fixed_css = new Gtk.CssProvider();
            fixed_css.load_from_string(".theme-image-container { border-radius: 8px; border: none; outline: none; }");
            var display = Gdk.Display.get_default();
            if (display != null) {
                Gtk.StyleContext.add_provider_for_display(display, fixed_css, Gtk.STYLE_PROVIDER_PRIORITY_APPLICATION);
            }

            var gesture = new Gtk.GestureClick();
            gesture.pressed.connect((n_press, x, y) => {
                on_theme_clicked(container, image_container, theme.id, theme.name);
            });
            image_container.add_controller(gesture);

            Gtk.Picture? picture = null;
            Adw.Spinner? spinner = null;

            var texture = theme_manager.get_thumbnail(theme.id);

            if (texture != null) {
                picture = new Gtk.Picture();
                picture.set_size_request(160, 100);
                picture.content_fit = Gtk.ContentFit.CONTAIN;
                picture.add_css_class("theme-preview-image");
                picture.set_paintable(texture);
                image_container.append(picture);
            } else {
                spinner = new Adw.Spinner();
                spinner.halign = Gtk.Align.CENTER;
                spinner.valign = Gtk.Align.CENTER;
                spinner.width_request = 48;
                spinner.height_request = 48;
                image_container.append(spinner);
                load_thumbnail_async.begin(theme, picture, spinner);
            }

            var label = new Gtk.Label(theme.name);
            label.add_css_class("theme-label");

            container.append(image_container);
            container.append(label);

            // SELECT CURRENT THEME
            if (selected_theme_id == theme.id) {
                container.add_css_class("selected-theme");
                last_selected_theme_item = container;
                apply_theme_border(image_container, selected_accent_color);
            }

            return container;
        }

        private async void load_thumbnail_async(ThemeData theme,
                                                 Gtk.Picture? picture,
                                                 Adw.Spinner spinner) {
            var texture = theme_manager.get_thumbnail(theme.id);

            Idle.add(() => {
                if (texture != null) {
                    if (picture == null) {
                        var new_picture = new Gtk.Picture();
                        new_picture.set_size_request(160, 100);
                        new_picture.content_fit = Gtk.ContentFit.CONTAIN;
                        new_picture.add_css_class("theme-preview-image");
                        new_picture.set_paintable(texture);

                        var parent = spinner.get_parent() as Gtk.Box;
                        if (parent != null) {
                            parent.remove(spinner);
                            parent.append(new_picture);
                        }
                    } else {
                        picture.set_paintable(texture);
                        picture.visible = true;
                        spinner.visible = false;
                    }
                } else {
                    spinner.visible = false;
                }
                return Source.REMOVE;
            });
        }

        private void on_theme_clicked(Gtk.Widget container, Gtk.Widget image_container,
                                      string theme_id, string theme_name) {
            if (selected_theme_id == theme_id) return;

            // Remove border and class from previous theme
            if (last_selected_theme_item != null) {
                last_selected_theme_item.remove_css_class("selected-theme");
                var old_image_container = last_selected_theme_item.get_first_child() as Gtk.Widget;
                if (old_image_container != null) {
                    var old_provider = old_image_container.get_data<Gtk.CssProvider>("border-provider");
                    if (old_provider != null) {
                        old_image_container.get_style_context().remove_provider(old_provider);
                    }
                }
            }

            // Apply new visual selection
            container.add_css_class("selected-theme");
            last_selected_theme_item = container;
            selected_theme_id = theme_id;
            selected_theme_name = theme_name;

            // Load the palette of the new theme and update selected_accent_color and selected_accent_index
            load_accent_colors_for_theme(theme_id);

            // Synchronize the manager index with the page index
            theme_manager.selected_accent_index = selected_accent_index;

            // Apply the theme (this may reset the manager index to 0)
            theme_manager.apply_theme(selected_theme_id, selected_accent_color);

            // If the manager index was reset, restore and reapply accent color
            if (theme_manager.selected_accent_index != selected_accent_index) {
                theme_manager.selected_accent_index = selected_accent_index;
                theme_manager.apply_accent_color(selected_accent_color, selected_accent_index);
            }

            // Update the theme border with the current color
            apply_theme_border(image_container, selected_accent_color);

            // Restore the correct accent button highlight
            restore_accent_selection();

            // Notify external callback
            if (on_theme_changed_callback != null) {
                on_theme_changed_callback(selected_theme_id, selected_theme_name,
                                          selected_accent_color, selected_accent_index);
            }

            if (sticky_header != null) sticky_header.update_buttons();
        }

        // Helper method to update the appearance of the selected theme in the gallery
        private void update_selected_theme_visual(string theme_id) {
            foreach (var item in theme_items) {
                var container = item as Gtk.Box;
                if (container == null) continue;
                string? item_id = container.get_data<string>("theme-id");
                if (item_id == theme_id) {
                    // Remove previous selection
                    if (last_selected_theme_item != null && last_selected_theme_item != container) {
                        last_selected_theme_item.remove_css_class("selected-theme");
                        var old_image_container = last_selected_theme_item.get_first_child() as Gtk.Widget;
                        if (old_image_container != null) {
                            var old_provider = old_image_container.get_data<Gtk.CssProvider>("border-provider");
                            if (old_provider != null) {
                                old_image_container.get_style_context().remove_provider(old_provider);
                            }
                        }
                    }
                    container.add_css_class("selected-theme");
                    last_selected_theme_item = container;
                    var image_container = container.get_first_child() as Gtk.Widget;
                    if (image_container != null) {
                        apply_theme_border(image_container, selected_accent_color);
                    }
                    break;
                }
            }
        }

        // ==================== ACCENT COLORS ====================

        private void load_accent_colors_for_theme(string theme_id) {
            var palette_colors = theme_manager.get_theme_palette(theme_id);
            Gdk.RGBA[] rgba_colors;

            if (palette_colors.length == 10) {
                rgba_colors = new Gdk.RGBA[10];
                for (int i = 0; i < 10; i++) {
                    rgba_colors[i] = parse_hex_color(palette_colors[i]);
                }
            } else {
                rgba_colors = get_default_accent_colors();
            }

            update_accent_colors_palette(rgba_colors);

            if (selected_accent_index < rgba_colors.length) {
                selected_accent_color = rgba_colors[selected_accent_index];
            } else {
                selected_accent_index = 0;
                selected_accent_color = rgba_colors[0];
            }
        }

        private void update_accent_colors_palette(Gdk.RGBA[] colors) {
            while (true) {
                var child = accent_colors_box.get_first_child();
                if (child == null) break;
                accent_colors_box.remove(child);
            }

            for (int i = 0; i < colors.length && i < 10; i++) {
                var color_button = create_accent_button(colors[i], i);
                accent_colors_box.append(color_button);
            }

            restore_accent_selection();
            accent_colors_box.queue_draw();
            if (sticky_header != null) sticky_header.update_buttons();
        }

        private Gtk.Button create_accent_button(Gdk.RGBA color, int index) {
            var button = new Gtk.Button();
            button.set_size_request(38, 38);
            button.add_css_class("flat");
            button.add_css_class("accent-button");

            string no_hover_css = """
                button.accent-button {
                    background: transparent;
                    border: none;
                    padding: 0;
                    margin: 0;
                }
                button.accent-button:hover {
                    background-color: transparent;
                    box-shadow: none;
                }
            """;

            try {
                var hover_provider = new Gtk.CssProvider();
                hover_provider.load_from_string(no_hover_css);
                var display = Gdk.Display.get_default();
                if (display != null) {
                    Gtk.StyleContext.add_provider_for_display(display, hover_provider, Gtk.STYLE_PROVIDER_PRIORITY_USER);
                }
            } catch (Error e) {
                warning(Dstx._("Error removing hover: %s"), e.message);
            }

            var drawing = new Gtk.DrawingArea();
            drawing.set_size_request(34, 34);
            drawing.set_margin_start(2);
            drawing.set_margin_end(2);
            drawing.set_margin_top(2);
            drawing.set_margin_bottom(2);
            drawing.add_css_class("accent-swatch");
            drawing.set_halign(Gtk.Align.CENTER);
            drawing.set_valign(Gtk.Align.CENTER);

            button.set_child(drawing);

            Gdk.RGBA btn_color = color;
            drawing.set_draw_func((area, cr, w, h) => {
                int size = int.min(w, h);
                int x = (w - size) / 2;
                int y = (h - size) / 2;

                int circle_radius = 12;
                int center_x = x + size/2;
                int center_y = y + size/2;

                cr.set_source_rgba(btn_color.red, btn_color.green, btn_color.blue, 1.0);
                cr.arc(center_x, center_y, circle_radius, 0, 2 * Math.PI);
                cr.fill();

                cr.set_source_rgba(0.5, 0.5, 0.5, 0.3);
                cr.set_line_width(1.0);
                cr.arc(center_x, center_y, circle_radius, 0, 2 * Math.PI);
                cr.stroke();

                if (button.has_css_class("selected-card")) {
                    int selection_radius = circle_radius + 3;
                    cr.set_source_rgba(selected_accent_color.red, selected_accent_color.green,
                                      selected_accent_color.blue, 1.0);
                    cr.set_line_width(3.0);
                    cr.arc(center_x, center_y, selection_radius, 0, 2 * Math.PI);
                    cr.stroke();
                }
            });

            button.clicked.connect(() => {
                message("AppearancePage: Accent color %d selected", index);
                if (last_selected_accent_button != null) {
                    last_selected_accent_button.remove_css_class("selected-card");
                    var old_drawing = last_selected_accent_button.get_child() as Gtk.DrawingArea;
                    if (old_drawing != null) {
                        old_drawing.queue_draw();
                    }
                }

                button.add_css_class("selected-card");
                last_selected_accent_button = button;
                selected_accent_index = index;
                selected_accent_color = color;
                drawing.queue_draw();

                theme_manager.selected_accent_index = index;
                theme_manager.apply_accent_color(selected_accent_color, index);

                if (last_selected_theme_item != null) {
                    var image_container = last_selected_theme_item.get_first_child() as Gtk.Widget;
                    if (image_container != null) {
                        apply_theme_border(image_container, selected_accent_color);
                    }
                }

                if (on_theme_changed_callback != null) {
                    on_theme_changed_callback(selected_theme_id, selected_theme_name,
                                             selected_accent_color, selected_accent_index);
                }

                if (sticky_header != null) sticky_header.update_buttons();
            });

            bool is_selected = (index == selected_accent_index);
            if (is_selected) {
                button.add_css_class("selected-card");
                last_selected_accent_button = button;
                drawing.queue_draw();
            }

            button.set_halign(Gtk.Align.CENTER);
            return button;
        }

        private void restore_accent_selection() {
            var child = accent_colors_box.get_first_child();
            int i = 0;
            bool found = false;

            while (child != null) {
                if (child is Gtk.Button) {
                    if (!found && selected_accent_index == i) {
                        var btn = child as Gtk.Button;
                        if (btn != null) {
                            btn.add_css_class("selected-card");
                            last_selected_accent_button = btn;
                            found = true;
                            child.queue_draw();
                        }
                    }
                }
                child = child.get_next_sibling();
                i++;
            }

            if (!found && accent_colors_box.get_first_child() != null) {
                var first_child = accent_colors_box.get_first_child() as Gtk.Button;
                if (first_child != null) {
                    first_child.add_css_class("selected-card");
                    last_selected_accent_button = first_child;
                    selected_accent_index = 0;
                    first_child.queue_draw();
                }
            }
        }

        private void apply_theme_border(Gtk.Widget image_container, Gdk.RGBA color) {
            var old_provider = image_container.get_data<Gtk.CssProvider>("border-provider");
            if (old_provider != null) {
                image_container.get_style_context().remove_provider(old_provider);
            }

            string border_css = """
                .theme-image-container {
                    border-radius: 8px;
                    box-shadow: 0 0 0 3px rgb(%d, %d, %d);
                }
            """.printf(
                (int)(color.red * 255),
                (int)(color.green * 255),
                (int)(color.blue * 255)
            );

            try {
                var provider = new Gtk.CssProvider();
                provider.load_from_string(border_css);
                image_container.get_style_context().add_provider(provider, Gtk.STYLE_PROVIDER_PRIORITY_USER);
                image_container.set_data("border-provider", provider);
                image_container.queue_draw();
            } catch (Error e) {
                warning(Dstx._("Error applying theme border: %s"), e.message);
            }
        }

        private void setup_signals() {
            theme_manager.accent_color_changed.connect((color) => {
                if (last_selected_theme_item != null) {
                    var image_container = last_selected_theme_item.get_first_child() as Gtk.Widget;
                    if (image_container != null) {
                        apply_theme_border(image_container, color);
                    }
                }
                restore_accent_selection();
                if (sticky_header != null) sticky_header.update_buttons();
            });
        }

        // ==================== STICKY HEADER HELPER METHODS ====================

        private void enable_scroll_monitoring() {
            if (sticky_header != null) {
                sticky_header.enable_scroll_monitoring();
                message("AppearancePage: Scroll monitoring enabled");
            }
        }

        private void disable_scroll_monitoring() {
            if (sticky_header != null) {
                sticky_header.disable_scroll_monitoring();
                message("AppearancePage: Scroll monitoring disabled");
            }
        }

        // ==================== LIFECYCLE ====================

        private void on_realized() {
            message("AppearancePage: Realized");
            if (sticky_header != null) {
                message("AppearancePage: StickyHeader already exists, reusing");
                return;
            }

            var dialog = find_preferences_dialog();
            if (dialog == null) {
                schedule_retry_find_dialog();
                return;
            }

            create_sticky_header(dialog);
        }

        private void create_sticky_header(Adw.PreferencesDialog dialog) {
            message("AppearancePage: Creating StickyHeader");
            sticky_header = new StickyHeader(dialog,
                () => { return get_current_accent_colors(); },
                () => { return selected_accent_index; },
                () => { return selected_accent_color; },
                (index, color) => {
                    message("AppearancePage: StickyHeader accent %d selected", index);
                    if (last_selected_accent_button != null) {
                        last_selected_accent_button.remove_css_class("selected-card");
                    }
                    var original_btn = find_original_accent_button(index);
                    if (original_btn != null) {
                        original_btn.add_css_class("selected-card");
                        last_selected_accent_button = original_btn;
                        var drawing = original_btn.get_child() as Gtk.DrawingArea;
                        if (drawing != null) drawing.queue_draw();
                    }
                    selected_accent_index = index;
                    selected_accent_color = color;
                    theme_manager.selected_accent_index = index;
                    theme_manager.apply_accent_color(color, index);
                    if (last_selected_theme_item != null) {
                        var image_container = last_selected_theme_item.get_first_child() as Gtk.Widget;
                        if (image_container != null) apply_theme_border(image_container, color);
                    }
                    if (on_theme_changed_callback != null) {
                        on_theme_changed_callback(selected_theme_id, selected_theme_name, color, index);
                    }
                });

            sticky_header.set_page_active(true);
            if (is_custom_mode) {
                sticky_header.set_custom_mode(true);
                enable_scroll_monitoring();
            }

            page_changed_handler_id = dialog.notify["visible-page"].connect(() => {
                var visible_page = dialog.get_visible_page();
                bool is_visible = (visible_page == this);
                message("AppearancePage: visible-page changed, is_visible=%s", is_visible.to_string());
                if (sticky_header != null) {
                    sticky_header.set_page_active(is_visible);
                }
                update_accent_group_visibility();
            });

            Timeout.add(100, () => {
                if (sticky_header != null) {
                    update_accent_group_visibility();
                }
                return true;
            });

            preload_thumbnails_async.begin();
            message("AppearancePage: StickyHeader created and configured");
        }

        private async void preload_thumbnails_async() {
            yield theme_manager.preload_thumbnails();
        }

        private void schedule_retry_find_dialog() {
            if (retry_dialog_timeout != 0) return;
            if (retry_dialog_count >= MAX_RETRY_DIALOG) {
                warning("AppearancePage: Max retries reached, giving up on finding PreferencesDialog");
                retry_dialog_count = 0;
                return;
            }
            retry_dialog_count++;
            message("AppearancePage: Retry finding dialog, attempt %d/%u", retry_dialog_count, MAX_RETRY_DIALOG);
            retry_dialog_timeout = Timeout.add(RETRY_DIALOG_DELAY_MS, () => {
                var dialog = find_preferences_dialog();
                if (dialog != null) {
                    create_sticky_header(dialog);
                    retry_dialog_timeout = 0;
                    retry_dialog_count = 0;
                } else {
                    schedule_retry_find_dialog();
                }
                return Source.REMOVE;
            });
        }

        private void on_unrealized() {
            message("AppearancePage: Unrealized");
            if (page_changed_handler_id != 0) {
                var dialog = find_preferences_dialog();
                if (dialog != null) {
                    dialog.disconnect(page_changed_handler_id);
                }
                page_changed_handler_id = 0;
            }
            if (sticky_header != null) {
                sticky_header = null;
            }
            if (retry_dialog_timeout != 0) {
                Source.remove(retry_dialog_timeout);
                retry_dialog_timeout = 0;
            }
        }

        private Adw.PreferencesDialog? find_preferences_dialog() {
            var parent = this.get_parent();
            while (parent != null) {
                if (parent is Adw.PreferencesDialog) return parent as Adw.PreferencesDialog;
                parent = parent.get_parent();
            }
            return null;
        }

        // ==================== HELPER METHODS ====================

        private Gdk.RGBA parse_hex_color(string hex_str) {
            var color = Gdk.RGBA() { alpha = 1.0f };
            string hex = hex_str;
            if (hex.has_prefix("#")) hex = hex.substring(1);
            if (hex.length == 6) {
                uint32 rgb = 0;
                for (int i = 0; i < 6; i++) {
                    char c = hex[i];
                    uint32 val = 0;
                    if (c >= '0' && c <= '9') val = (uint32)(c - '0');
                    else if (c >= 'A' && c <= 'F') val = (uint32)(c - 'A' + 10);
                    else if (c >= 'a' && c <= 'f') val = (uint32)(c - 'a' + 10);
                    rgb = (rgb << 4) | val;
                }
                color.red = (float)((rgb >> 16) & 0xFF) / 255.0f;
                color.green = (float)((rgb >> 8) & 0xFF) / 255.0f;
                color.blue = (float)(rgb & 0xFF) / 255.0f;
            }
            return color;
        }

        private Gdk.RGBA[] get_current_accent_colors() {
            var colors = new Gdk.RGBA[10];
            var palette = theme_manager.get_theme_palette(selected_theme_id);
            if (palette.length == 10) {
                for (int i = 0; i < 10; i++) colors[i] = parse_hex_color(palette[i]);
            } else {
                colors = get_default_accent_colors();
            }
            return colors;
        }

        private Gdk.RGBA[] get_default_accent_colors() {
            var colors = new Gdk.RGBA[10];
            colors[0] = Gdk.RGBA() { red = 0.20f, green = 0.50f, blue = 0.80f, alpha = 1.0f };
            colors[1] = Gdk.RGBA() { red = 0.90f, green = 0.30f, blue = 0.30f, alpha = 1.0f };
            colors[2] = Gdk.RGBA() { red = 0.90f, green = 0.60f, blue = 0.20f, alpha = 1.0f };
            colors[3] = Gdk.RGBA() { red = 0.80f, green = 0.70f, blue = 0.20f, alpha = 1.0f };
            colors[4] = Gdk.RGBA() { red = 0.30f, green = 0.70f, blue = 0.30f, alpha = 1.0f };
            colors[5] = Gdk.RGBA() { red = 0.30f, green = 0.70f, blue = 0.70f, alpha = 1.0f };
            colors[6] = Gdk.RGBA() { red = 0.60f, green = 0.40f, blue = 0.80f, alpha = 1.0f };
            colors[7] = Gdk.RGBA() { red = 0.80f, green = 0.40f, blue = 0.70f, alpha = 1.0f };
            colors[8] = Gdk.RGBA() { red = 0.50f, green = 0.50f, blue = 0.50f, alpha = 1.0f };
            colors[9] = Gdk.RGBA() { red = 0.90f, green = 0.90f, blue = 0.90f, alpha = 1.0f };
            return colors;
        }

        private Gtk.Button? find_original_accent_button(int index) {
            var child = accent_colors_box.get_first_child();
            int i = 0;
            while (child != null) {
                if (child is Gtk.Button && i == index) return child as Gtk.Button;
                child = child.get_next_sibling();
                i++;
            }
            return null;
        }
    }
}
