/*
 * theme-manager.vala - Theme and appearance management for DSTX
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
 * - Load and manage themes from JSON resource
 * - Apply themes and accent colors to the interface
 * - Manage controller visual appearance based on theme
 * - Handle system theme synchronization and custom theme mode
 * - Cache thumbnails, textures, and CSS
 * - Throttle UI updates to avoid performance issues
 */

// src/managers/theme-manager.vala

using Gtk;
using Gdk;
using Json;
using Dstx.Models;
using Dstx.Services;

namespace Dstx.Managers {
    public class ThemeManager : GLib.Object {
        private static ThemeManager? instance = null;
        private Adw.StyleManager style_manager;
        
        // ==================== CACHES ====================
        private GLib.HashTable<string, Gdk.Texture?> texture_cache;
        private Gee.List<string> texture_cache_order;
        private GLib.HashTable<string, string> theme_css_cache;
        private const int MAX_TEXTURE_CACHE_SIZE = 10;
        
        // ==================== THEME DATA ====================
        private Gee.HashMap<string, ThemeData> themes;
        private ThumbnailRenderer thumbnail_renderer;
        
        // ==================== CENTRALIZED STATES ====================
        private string _current_theme_id = "light";
        private ThemeData? _current_theme = null;
        private Gtk.CssProvider? current_theme_provider = null;
        private Gtk.CssProvider? accent_only_provider = null;
        
        private int _selected_accent_index = 0;
        private Gdk.RGBA _accent_color;
        
        private int _ui_mode = 0;
        private ControllerColors _current_controller_colors;
        private bool _is_dark = false;
        
        // ==================== STATE CACHE ====================
        private string _cached_controller_colors_hash = "";
        private Gdk.RGBA _cached_system_accent;
        
        // ==================== THROTTLING ====================
        private uint controller_update_timeout = 0;
        private uint interface_update_timeout = 0;
        private const uint UPDATE_DELAY_MS = 50;
        
        // ==================== DEFAULT COLORS ====================
        private const string LIGHT_PRIMARY = "#999999";
        private const string LIGHT_SECONDARY = "#666666";
        private const string LIGHT_ACCENT = "#3584e4";
        private const string LIGHT_SYMBOL = "#2e3436";
        
        private const string DARK_PRIMARY = "#666666";
        private const string DARK_SECONDARY = "#4d4d4d";
        private const string DARK_ACCENT = "#3584e4";
        private const string DARK_SYMBOL = "#e6e6e6";
        
        // ==================== SIGNALS ====================
        public signal void controller_colors_changed(ControllerColors colors);
        public signal void theme_changed(bool is_dark);
        public signal void accent_color_changed(Gdk.RGBA color);
        public signal void ui_mode_changed(int mode);
        
        // ==================== PROPERTIES ====================
        public bool is_dark { get { return _is_dark; } }
        public Gdk.RGBA accent_color { get { return _accent_color; } }
        public ThemeData? current_theme { get { return _current_theme; } }
        public string current_theme_id { get { return _current_theme_id; } }
        public int ui_mode { get { return _ui_mode; } }
        
        public ControllerColors current_controller_colors {
            get { return _current_controller_colors; }
        }
        
        public int selected_accent_index {
            get { return _selected_accent_index; }
            set { _selected_accent_index = value; }
        }
        
        // ==================== CONSTRUCTOR ====================
        private ThemeManager() {
            style_manager = Adw.StyleManager.get_default();
            
            texture_cache = new GLib.HashTable<string, Gdk.Texture?>(str_hash, str_equal);
            texture_cache_order = new Gee.ArrayList<string>();
            theme_css_cache = new GLib.HashTable<string, string>(str_hash, str_equal);
            themes = new Gee.HashMap<string, ThemeData>();
            accent_only_provider = null;
            
            thumbnail_renderer = new ThumbnailRenderer();
            message("ThemeManager: ThumbnailRenderer initialized");
            
            _current_controller_colors = new ControllerColors();
            _accent_color = Gdk.RGBA() { red = 0.2f, green = 0.5f, blue = 0.8f, alpha = 1.0f };
            
            load_themes_from_json();
            
            if (style_manager != null) {
                _is_dark = style_manager.dark;
                update_accent_color_from_system();
                get_current_system_accent(out _cached_system_accent);
                
                style_manager.notify["dark"].connect(() => {
                    update_theme_state();
                    clear_texture_cache();
                    update_from_system_theme();
                    check_system_accent_change();
                });
            }
            
            update_controller_colors_by_mode();
        }
        
        public static ThemeManager get_default() {
            if (instance == null) {
                instance = new ThemeManager();
            }
            return instance;
        }
        
        // ==================== THEME LOADING ====================
        
        private void load_themes_from_json() {
            try {
                var bytes = GLib.resources_lookup_data("/org/dstx/gui/themes.json", 
                    GLib.ResourceLookupFlags.NONE);
                string json_content = (string)bytes.get_data();
                
                var parser = new Json.Parser();
                parser.load_from_data(json_content);
                var root = parser.get_root().get_object();
                var themes_obj = root.get_object_member("themes");
                
                foreach (var theme_id in themes_obj.get_members()) {
                    var theme_obj = themes_obj.get_object_member(theme_id);
                    var theme = parse_theme_data(theme_id, theme_obj);
                    themes.set(theme_id, theme);
                }
                
                message("ThemeManager: Loaded %d themes from JSON", themes.size);
                
            } catch (GLib.Error e) {
                error("ThemeManager: Error loading themes: %s", e.message);
            }
        }
        
        private ThemeData parse_theme_data(string id, Json.Object obj) {
            var theme = new ThemeData();
            theme.id = id;
            theme.name = obj.get_string_member("name");
            theme.theme_type = obj.get_string_member("type");
            
            var thumbnail = obj.get_object_member("thumbnail");
            if (thumbnail != null) {
                theme.thumbnail.bg = thumbnail.get_string_member("bg");
                theme.thumbnail.accent = thumbnail.get_string_member("accent");
                theme.thumbnail.text = thumbnail.get_string_member("text");
            }
            
            var palette_arr = obj.get_array_member("palette");
            for (int i = 0; i < 10 && i < palette_arr.get_length(); i++) {
                theme.palette[i] = palette_arr.get_string_element(i);
            }
            
            var window_obj = obj.get_object_member("window");
            if (window_obj != null) {
                foreach (var key in window_obj.get_members()) {
                    theme.window.set(key, window_obj.get_string_member(key));
                }
            }
            
            var controller_obj = obj.get_object_member("controller");
            if (controller_obj != null) {
                if (controller_obj.has_member("primary"))
                    theme.controller.primary = controller_obj.get_string_member("primary");
                if (controller_obj.has_member("secondary"))
                    theme.controller.secondary = controller_obj.get_string_member("secondary");
                if (controller_obj.has_member("accent"))
                    theme.controller.accent = controller_obj.get_string_member("accent");
                if (controller_obj.has_member("symbol"))
                    theme.controller.symbol = controller_obj.get_string_member("symbol");
            }
            
            return theme;
        }
        
        // ==================== THEME ACCESS METHODS ====================
        
        public Gee.Collection<ThemeData> get_all_themes() {
            return themes.values;
        }
        
        public Gee.Collection<ThemeData> get_standard_themes() {
            var standard = new Gee.ArrayList<ThemeData>();
            
            var light = themes.get("light");
            var dark = themes.get("dark");
            
            if (light != null) standard.add(light);
            if (dark != null) standard.add(dark);
            
            return standard;
        }
        
        public Gee.Collection<ThemeData> get_exclusive_themes() {
            var exclusive = new Gee.ArrayList<ThemeData>();
            
            foreach (var theme in themes.values) {
                if (theme.id != "light" && theme.id != "dark") {
                    exclusive.add(theme);
                }
            }
            
            return exclusive;
        }
        
        public ThemeData? get_theme(string theme_id) {
            return themes.get(theme_id);
        }
        
        public string[] get_theme_palette(string theme_id) {
            var theme = themes.get(theme_id);
            if (theme != null) {
                return theme.palette;
            }
            return new string[0];
        }
        
        // ==================== THUMBNAIL METHODS ====================
        
        public Gdk.Texture? get_thumbnail(string theme_id) {
            var theme = themes.get(theme_id);
            if (theme == null) {
                warning("ThemeManager: Theme not found: %s", theme_id);
                return null;
            }
            
            return thumbnail_renderer.get_thumbnail(theme, 160, 100);
        }
        
        public async void preload_thumbnails() {
            var all_themes = get_all_themes();
            foreach (var theme in all_themes) {
                get_thumbnail(theme.id);
                
                var source = new TimeoutSource(1);
                source.set_callback(() => {
                    preload_thumbnails.callback();
                    return Source.REMOVE;
                });
                source.attach(null);
                yield;
            }
            message("ThemeManager: Thumbnails preloaded");
        }
        
        // ==================== THEME APPLICATION METHODS ====================
        
        public void apply_theme(string theme_id, Gdk.RGBA accent_color) {
            if (_ui_mode != 3) {
                warning("ThemeManager: apply_theme called outside custom mode (ui_mode=%d)", _ui_mode);
                return;
            }
            
            var theme = themes.get(theme_id);
            if (theme == null) {
                warning("ThemeManager: Theme %s not found", theme_id);
                return;
            }
            
            _current_theme_id = theme_id;
            _current_theme = theme;
            _accent_color = accent_color;
            _selected_accent_index = 0;
            
            apply_interface_theme(theme, accent_color);
            
            var new_colors = new ControllerColors();
            new_colors.primary = theme.controller.primary ?? (theme.theme_type == "dark" ? DARK_PRIMARY : LIGHT_PRIMARY);
            new_colors.secondary = theme.controller.secondary ?? (theme.theme_type == "dark" ? DARK_SECONDARY : LIGHT_SECONDARY);
            new_colors.accent = theme.controller.accent ?? theme.thumbnail.accent;
            new_colors.symbol = theme.controller.symbol ?? theme.thumbnail.text;
            
            schedule_controller_update(new_colors);
            
            message("ThemeManager: Theme %s applied", theme.name);
        }
        
        public void apply_accent_color(Gdk.RGBA color, int index) {
            if (_ui_mode != 3) {
                warning("ThemeManager: apply_accent_color called outside custom mode (ui_mode=%d)", _ui_mode);
                return;
            }
            
            _accent_color = color;
            _selected_accent_index = index;
            
            if (_current_theme != null) {
                string hex = color_to_hex(color);
                _current_theme.window.set("--accent-bg", hex);
                _current_theme.window.set("--accent-color", hex);
                
                if (_selected_accent_index < _current_theme.palette.length) {
                    _current_theme.palette[_selected_accent_index] = hex;
                }
            }
            
            schedule_interface_accent_update(color);
        }
        
        public void set_ui_mode(int mode) {
            if (_ui_mode == mode) return;
            
            int old_mode = _ui_mode;
            _ui_mode = mode;
            
            if (mode == 3) {
                message("ThemeManager: Entering custom mode");
                
                remove_accent_provider();
                
                string saved_theme = "light";
                var saved_accent = Gdk.RGBA() { red = 0.2f, green = 0.5f, blue = 0.8f, alpha = 1.0f };
                apply_theme(saved_theme, saved_accent);
                
            } else {
                message("ThemeManager: Exiting custom mode, mode=%d", mode);
                
                if (current_theme_provider != null) {
                    var display = Gdk.Display.get_default();
                    if (display != null) {
                        Gtk.StyleContext.remove_provider_for_display(display, current_theme_provider);
                    }
                    current_theme_provider = null;
                }
                
                remove_accent_provider();
                
                if (style_manager != null) {
                    switch (mode) {
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
                
                _is_dark = (mode == 2) || (mode == 0 && (style_manager != null && style_manager.dark));
                
                theme_changed(_is_dark);
                update_accent_color_from_system();
                update_controller_colors_by_mode();
            }
            
            ui_mode_changed(mode);
            message("ThemeManager: UI mode changed from %d to %d", old_mode, mode);
        }
        
        public void reset_to_system_theme() {
            set_ui_mode(0);
        }
        
        // ==================== PRIVATE METHODS ====================
        
        private void apply_interface_theme(ThemeData theme, Gdk.RGBA accent_color) {
            if (_ui_mode != 3) {
                warning("ThemeManager: apply_interface_theme called outside custom mode");
                return;
            }
            
            remove_accent_provider();
            
            string hex = color_to_hex(accent_color);
            theme.window.set("--accent-bg", hex);
            
            if (theme.theme_type == "dark") {
                style_manager.color_scheme = Adw.ColorScheme.FORCE_DARK;
                _is_dark = true;
            } else {
                style_manager.color_scheme = Adw.ColorScheme.FORCE_LIGHT;
                _is_dark = false;
            }
            
            apply_full_css(theme);
            
            theme_changed(_is_dark);
            accent_color_changed(accent_color);
        }
        
        private void apply_interface_accent(Gdk.RGBA color) {
            if (_ui_mode != 3) {
                warning("ThemeManager: apply_interface_accent called outside custom mode");
                return;
            }
            
            if (accent_only_provider != null) {
                var display = Gdk.Display.get_default();
                if (display != null) {
                    Gtk.StyleContext.remove_provider_for_display(display, accent_only_provider);
                }
                accent_only_provider = null;
            }
            
            accent_only_provider = new Gtk.CssProvider();
            
            string accent_css = generate_accent_css(color);
            
            try {
                accent_only_provider.load_from_string(accent_css);
                
                var display = Gdk.Display.get_default();
                if (display != null) {
                    Gtk.StyleContext.add_provider_for_display(
                        display,
                        accent_only_provider,
                        Gtk.STYLE_PROVIDER_PRIORITY_APPLICATION + 10
                    );
                }
                
                message("ThemeManager: Accent color applied to interface");
                accent_color_changed(color);
                
            } catch (GLib.Error e) {
                warning("ThemeManager: Error applying accent color: %s", e.message);
                accent_only_provider = null;
            }
        }
        
        private void remove_accent_provider() {
            if (accent_only_provider != null) {
                var display = Gdk.Display.get_default();
                if (display != null) {
                    Gtk.StyleContext.remove_provider_for_display(display, accent_only_provider);
                }
                accent_only_provider = null;
                message("ThemeManager: Accent color provider removed");
            }
        }
        
        private void apply_full_css(ThemeData theme) {
            if (theme == null) return;
            
            if (current_theme_provider != null) {
                var display = Gdk.Display.get_default();
                if (display != null) {
                    Gtk.StyleContext.remove_provider_for_display(display, current_theme_provider);
                }
                current_theme_provider = null;
            }
            
            string theme_css = generate_theme_vars_css(theme);
            
            current_theme_provider = new Gtk.CssProvider();
            try {
                current_theme_provider.load_from_string(theme_css);
                
                var display = Gdk.Display.get_default();
                if (display != null) {
                    Gtk.StyleContext.add_provider_for_display(
                        display,
                        current_theme_provider,
                        Gtk.STYLE_PROVIDER_PRIORITY_APPLICATION
                    );
                }
            } catch (GLib.Error e) {
                warning("ThemeManager: Error applying theme CSS: %s", e.message);
                current_theme_provider = null;
            }
        }
        
        private string generate_theme_vars_css(ThemeData theme) {
            if (theme_css_cache.contains(theme.id)) {
                return theme_css_cache.get(theme.id);
            }
            
            var css = new StringBuilder();
            
            string accent = theme.window.get("--accent-bg", "#3584e4");
            string accent_fg = theme.window.get("--accent-fg", "#ffffff");
            string window_bg = theme.window.get("--window-bg", theme.theme_type == "dark" ? "#1e1e1e" : "#f6f5f4");
            string window_fg = theme.window.get("--window-fg", theme.theme_type == "dark" ? "#e6e6e6" : "#2e3436");
            string headerbar_bg = theme.window.get("--headerbar-bg", window_bg);
            string headerbar_fg = theme.window.get("--headerbar-fg", window_fg);
            string popover_bg = theme.window.get("--popover-bg", window_bg);
            string popover_fg = theme.window.get("--popover-fg", window_fg);
            string card_bg = theme.window.get("--card-bg", window_bg);
            string card_fg = theme.window.get("--card-fg", window_fg);
            string sidebar_bg = theme.window.get("--sidebar-bg", window_bg);
            string sidebar_fg = theme.window.get("--sidebar-fg", window_fg);
            string sidebar_border = theme.window.get("--sidebar-border", "#cdc7c2");
            string border = theme.window.get("--border", "#cdc7c2");
            string button_bg = theme.window.get("--button-bg", window_bg);
            string button_fg = theme.window.get("--button-fg", window_fg);
            string button_hover = theme.window.get("--button-hover", "#e5e3e0");
            string button_active = theme.window.get("--button-active", "#d9d7d4");
            string accent_hover = theme.window.get("--accent-hover", "#5e9bff");
            string accent_active = theme.window.get("--accent-active", "#1c71d8");
            string view_bg = theme.window.get("--view-bg", window_bg);
            string view_fg = theme.window.get("--view-fg", window_fg);
            string dialog_bg = theme.window.get("--dialog-bg", window_bg);
            string dialog_fg = theme.window.get("--dialog-fg", window_fg);
            
            string secondary_sidebar_bg = theme.window.get("--secondary-sidebar-bg", sidebar_bg);
            string secondary_sidebar_fg = theme.window.get("--secondary-sidebar-fg", sidebar_fg);
            string secondary_sidebar_border = theme.window.get("--secondary-sidebar-border", sidebar_border);
            
            string window_backdrop_bg = theme.window.get("--window-backdrop-bg", window_bg);
            string headerbar_backdrop_bg = theme.window.get("--headerbar-backdrop-bg", headerbar_bg);
            string sidebar_backdrop_bg = theme.window.get("--sidebar-backdrop-bg", sidebar_bg);
            string secondary_sidebar_backdrop_bg = theme.window.get("--secondary-sidebar-backdrop-bg", secondary_sidebar_bg);
            
            css.append("@define-color accent_bg_color ");
            css.append(accent);
            css.append(";\n");
            
            css.append("@define-color accent_fg_color ");
            css.append(accent_fg);
            css.append(";\n");
            
            css.append("@define-color window_bg_color ");
            css.append(window_bg);
            css.append(";\n");
            
            css.append("@define-color window_fg_color ");
            css.append(window_fg);
            css.append(";\n");
            
            css.append("@define-color headerbar_bg_color ");
            css.append(headerbar_bg);
            css.append(";\n");
            
            css.append("@define-color headerbar_fg_color ");
            css.append(headerbar_fg);
            css.append(";\n");
            
            css.append("@define-color popover_bg_color ");
            css.append(popover_bg);
            css.append(";\n");
            
            css.append("@define-color popover_fg_color ");
            css.append(popover_fg);
            css.append(";\n");
            
            css.append("@define-color card_bg_color ");
            css.append(card_bg);
            css.append(";\n");
            
            css.append("@define-color card_fg_color ");
            css.append(card_fg);
            css.append(";\n");
            
            css.append("@define-color sidebar_bg_color ");
            css.append(sidebar_bg);
            css.append(";\n");
            
            css.append("@define-color sidebar_fg_color ");
            css.append(sidebar_fg);
            css.append(";\n");
            
            css.append("@define-color sidebar_border_color ");
            css.append(sidebar_border);
            css.append(";\n");
            
            css.append("@define-color secondary_sidebar_bg_color ");
            css.append(secondary_sidebar_bg);
            css.append(";\n");
            
            css.append("@define-color secondary_sidebar_fg_color ");
            css.append(secondary_sidebar_fg);
            css.append(";\n");
            
            css.append("@define-color secondary_sidebar_border_color ");
            css.append(secondary_sidebar_border);
            css.append(";\n");
            
            css.append("@define-color border_color ");
            css.append(border);
            css.append(";\n");
            
            css.append("@define-color button_bg_color ");
            css.append(button_bg);
            css.append(";\n");
            
            css.append("@define-color button_fg_color ");
            css.append(button_fg);
            css.append(";\n");
            
            css.append("@define-color button_hover_bg_color ");
            css.append(button_hover);
            css.append(";\n");
            
            css.append("@define-color button_active_bg_color ");
            css.append(button_active);
            css.append(";\n");
            
            css.append("@define-color accent_hover_bg_color ");
            css.append(accent_hover);
            css.append(";\n");
            
            css.append("@define-color accent_active_bg_color ");
            css.append(accent_active);
            css.append(";\n");
            
            css.append("@define-color view_bg_color ");
            css.append(view_bg);
            css.append(";\n");
            
            css.append("@define-color view_fg_color ");
            css.append(view_fg);
            css.append(";\n");
            
            css.append("@define-color dialog_bg_color ");
            css.append(dialog_bg);
            css.append(";\n");
            
            css.append("@define-color dialog_fg_color ");
            css.append(dialog_fg);
            css.append(";\n");
            
            css.append("@define-color window_backdrop_bg_color ");
            css.append(window_backdrop_bg);
            css.append(";\n");
            
            css.append("@define-color headerbar_backdrop_bg_color ");
            css.append(headerbar_backdrop_bg);
            css.append(";\n");
            
            css.append("@define-color sidebar_backdrop_bg_color ");
            css.append(sidebar_backdrop_bg);
            css.append(";\n");
            
            css.append("@define-color secondary_sidebar_backdrop_bg_color ");
            css.append(secondary_sidebar_backdrop_bg);
            css.append(";\n");
            
            css.append("""
                
                overlay-split-view:backdrop > widget.sidebar-pane {
                    background-color: @sidebar_backdrop_bg_color;
                    border-right-color: alpha(@sidebar_border_color, 0.5);
                }
                
                overlay-split-view:backdrop > widget.sidebar-pane:last-child {
                    background-color: @secondary_sidebar_backdrop_bg_color;
                    border-left-color: alpha(@secondary_sidebar_border_color, 0.5);
                }
                
                .right-split-view > widget.sidebar-pane {
                    background-color: @secondary_sidebar_bg_color;
                    border-left: 1px solid @secondary_sidebar_border_color;
                }
                
                .right-split-view .sidebar-toolbar {
                    background-color: @secondary_sidebar_bg_color;
                }
            """);
            
            string result = css.str;
            theme_css_cache.set(theme.id, result);
            return result;
        }
        
        private string generate_accent_css(Gdk.RGBA accent_color) {
            int r = (int)(accent_color.red * 255);
            int g = (int)(accent_color.green * 255);
            int b = (int)(accent_color.blue * 255);
            
            return """
                :root {
                    --accent-bg: #%02X%02X%02X;
                    --accent-color: #%02X%02X%02X;
                }
                
                button.suggested-action {
                    background-color: #%02X%02X%02X;
                }
                
                button.suggested-action:hover {
                    background-color: #%02X%02X%02X;
                }
                
                button.suggested-action:active {
                    background-color: #%02X%02X%02X;
                }
                
                scale highlight {
                    background-color: #%02X%02X%02X;
                }
                
                scale slider {
                    background-color: #%02X%02X%02X;
                }
                
                switch:checked {
                    background-color: #%02X%02X%02X;
                }
                
                .accent {
                    color: #%02X%02X%02X;
                }
                
                .theme-image-container.selected-theme {
                    box-shadow: 0 0 0 3px #%02X%02X%02X;
                }
                
                spinner {
                    color: #%02X%02X%02X;
                }
            """.printf(
                r, g, b, r, g, b,
                r, g, b,
                (int)(r * 0.85), (int)(g * 0.85), (int)(b * 0.85),
                (int)(r * 0.7), (int)(g * 0.7), (int)(b * 0.7),
                r, g, b,
                r, g, b,
                r, g, b,
                r, g, b,
                r, g, b,
                r, g, b
            );
        }
        
        private string color_to_hex(Gdk.RGBA color) {
            int r = (int)(color.red * 255);
            int g = (int)(color.green * 255);
            int b = (int)(color.blue * 255);
            return @"#$(r.to_string("%02X"))$(g.to_string("%02X"))$(b.to_string("%02X"))";
        }
        
        private bool get_current_system_accent(out Gdk.RGBA color) {
            color = Gdk.RGBA();
            var dummy_widget = new Gtk.Label("");
            var style_context = dummy_widget.get_style_context();
            return style_context.lookup_color("accent_color", out color);
        }
        
        private void update_accent_color_from_system() {
            Gdk.RGBA color;
            if (get_current_system_accent(out color)) {
                _accent_color = color;
                _cached_system_accent = color;
                accent_color_changed(color);
                
                message("ThemeManager: System accent color = RGB(%.0f,%.0f,%.0f) [mode %d]",
                        color.red * 255, color.green * 255, color.blue * 255, _ui_mode);
            }
        }
        
        private void check_system_accent_change() {
            if (_ui_mode == 3) return;
            
            Gdk.RGBA current_accent;
            if (get_current_system_accent(out current_accent)) {
                if (!colors_equal(current_accent, _cached_system_accent)) {
                    _cached_system_accent = current_accent;
                    _accent_color = current_accent;
                    accent_color_changed(current_accent);
                    
                    message("ThemeManager: System accent color changed to RGB(%.0f,%.0f,%.0f)",
                            current_accent.red * 255, current_accent.green * 255, current_accent.blue * 255);
                }
            }
        }
        
        private bool colors_equal(Gdk.RGBA a, Gdk.RGBA b) {
            return Math.fabs(a.red - b.red) < 0.01 &&
                   Math.fabs(a.green - b.green) < 0.01 &&
                   Math.fabs(a.blue - b.blue) < 0.01 &&
                   Math.fabs(a.alpha - b.alpha) < 0.01;
        }
        
        private ControllerColors get_controller_colors_for_mode(int mode, bool is_system_dark) {
            var colors = new ControllerColors();
            
            if (mode == 1) {
                colors.primary = LIGHT_PRIMARY;
                colors.secondary = LIGHT_SECONDARY;
                colors.accent = LIGHT_ACCENT;
                colors.symbol = LIGHT_SYMBOL;
            } else if (mode == 2) {
                colors.primary = DARK_PRIMARY;
                colors.secondary = DARK_SECONDARY;
                colors.accent = DARK_ACCENT;
                colors.symbol = DARK_SYMBOL;
            } else {
                if (is_system_dark) {
                    colors.primary = DARK_PRIMARY;
                    colors.secondary = DARK_SECONDARY;
                    colors.accent = DARK_ACCENT;
                    colors.symbol = DARK_SYMBOL;
                } else {
                    colors.primary = LIGHT_PRIMARY;
                    colors.secondary = LIGHT_SECONDARY;
                    colors.accent = LIGHT_ACCENT;
                    colors.symbol = LIGHT_SYMBOL;
                }
            }
            
            return colors;
        }
        
        private void update_controller_colors_by_mode() {
            bool is_system_dark = (_ui_mode == 0) ? (style_manager != null && style_manager.dark) : (_ui_mode == 2);
            var new_colors = get_controller_colors_for_mode(_ui_mode, is_system_dark);
            schedule_controller_update(new_colors);
        }
        
        public void update_from_system_theme() {
            if (_ui_mode == 0) {
                bool is_dark = style_manager != null ? style_manager.dark : false;
                var new_colors = get_controller_colors_for_mode(0, is_dark);
                schedule_controller_update(new_colors);
                update_accent_color_from_system();
            }
        }
        
        private void schedule_controller_update(ControllerColors colors) {
            string new_hash = @"$(colors.primary):$(colors.secondary):$(colors.accent):$(colors.symbol)";
            if (_cached_controller_colors_hash == new_hash) {
                return;
            }
            _cached_controller_colors_hash = new_hash;
            
            if (controller_update_timeout != 0) {
                Source.remove(controller_update_timeout);
            }
            
            controller_update_timeout = Timeout.add(UPDATE_DELAY_MS, () => {
                _current_controller_colors = colors.copy();
                controller_colors_changed(_current_controller_colors);
                controller_update_timeout = 0;
                return Source.REMOVE;
            });
        }
        
        private void schedule_interface_accent_update(Gdk.RGBA color) {
            if (_ui_mode != 3) {
                return;
            }
            
            if (interface_update_timeout != 0) {
                Source.remove(interface_update_timeout);
            }
            
            interface_update_timeout = Timeout.add(UPDATE_DELAY_MS, () => {
                apply_interface_accent(color);
                interface_update_timeout = 0;
                return Source.REMOVE;
            });
        }
        
        private void update_theme_state() {
            bool new_is_dark = style_manager.dark;
            if (_is_dark != new_is_dark) {
                _is_dark = new_is_dark;
                theme_changed(_is_dark);
            }
        }
        
        // ==================== TEXTURE CACHE ====================
        
        private void add_to_texture_cache(string key, Gdk.Texture texture) {
            while (texture_cache_order.size >= MAX_TEXTURE_CACHE_SIZE) {
                string oldest = texture_cache_order[0];
                texture_cache_order.remove_at(0);
                texture_cache.remove(oldest);
                message("ThemeManager: Texture cache evicted: %s", oldest);
            }
            
            texture_cache.set(key, texture);
            texture_cache_order.add(key);
        }
        
        private void clear_texture_cache() {
            foreach (var key in texture_cache.get_keys()) {
                var texture = texture_cache.get(key);
                if (texture != null) {
                    texture = null;
                }
            }
            texture_cache.remove_all();
            texture_cache_order.clear();
            message("ThemeManager: Texture cache cleared");
        }
        
        // ==================== CACHE CLEARING ====================
        
        public void clear_cache() {
            clear_texture_cache();
            theme_css_cache.remove_all();
            thumbnail_renderer.clear_cache();
            message("ThemeManager: Caches cleared");
        }
        
        // ==================== DESTRUCTOR ====================
        
        ~ThemeManager() {
            if (controller_update_timeout != 0) {
                Source.remove(controller_update_timeout);
            }
            if (interface_update_timeout != 0) {
                Source.remove(interface_update_timeout);
            }
            var display = Gdk.Display.get_default();
            if (display != null) {
                if (current_theme_provider != null) {
                    Gtk.StyleContext.remove_provider_for_display(display, current_theme_provider);
                }
                if (accent_only_provider != null) {
                    Gtk.StyleContext.remove_provider_for_display(display, accent_only_provider);
                }
            }
            clear_cache();
            message("ThemeManager: Destroyed");
        }
    }
}
