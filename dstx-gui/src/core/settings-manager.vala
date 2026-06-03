/*
 * settings-manager.vala - Agnostic settings manager for DSTX GUI
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
 * - Manage application settings using JSON persistence
 * - Provide getters/setters for theme, language, notifications, window state
 * - Handle recent colors list
 * - Throttled saving with debounce
 */

// src/core/settings-manager.vala

using Json;

namespace Dstx.Core {
    /**
     * SettingsManager - Agnostic configuration manager
     */
    public class SettingsManager : GLib.Object {
        private static SettingsManager? instance = null;
        
        private string config_dir;
        private string config_file;
        private Json.Object? settings = null;
        
        private bool loaded = false;
        private uint save_timeout = 0;
        private const uint SAVE_DELAY_MS = 100;
        
        // Signals to notify changes
        public signal void theme_changed(int theme_mode);
        public signal void language_changed(int language_id);
        public signal void accent_color_changed(Gdk.RGBA color);
        
        // Default values
        private const int DEFAULT_THEME = 0;
        private const int DEFAULT_LANGUAGE = 0;
        private const bool DEFAULT_AUTO_START = true;
        private const bool DEFAULT_NOTIFY_CONNECT = true;
        private const bool DEFAULT_NOTIFY_BATTERY = true;
        private const bool DEFAULT_NOTIFY_UPDATE = true;
        private const bool DEFAULT_SIDEBAR_LEFT_VISIBLE = true;
        private const string DEFAULT_CUSTOM_THEME = "light";
        private const string DEFAULT_CUSTOM_THEME_NAME = "Light";
        private const int DEFAULT_CUSTOM_ACCENT_INDEX = 0;
        private const double DEFAULT_ACCENT_R = 0.2;
        private const double DEFAULT_ACCENT_G = 0.5;
        private const double DEFAULT_ACCENT_B = 0.8;
        
        // Default window size values
        private const int DEFAULT_WINDOW_WIDTH = 1200;
        private const int DEFAULT_WINDOW_HEIGHT = 800;
        private const bool DEFAULT_WINDOW_MAXIMIZED = false;
        
        private SettingsManager() {
            init_paths();
            load();
        }
        
        public static SettingsManager get_default() {
            if (instance == null) {
                instance = new SettingsManager();
            }
            return instance;
        }
        
        /**
         * Initialize paths using XDG Base Directory Specification
         */
        private void init_paths() {
            string config_home = Environment.get_user_config_dir();
            // Use GLib.Path explicitly to avoid ambiguity with Json.Path
            config_dir = GLib.Path.build_path(GLib.Path.DIR_SEPARATOR_S, config_home, "dstx");
            config_file = GLib.Path.build_path(GLib.Path.DIR_SEPARATOR_S, config_dir, "settings.json");
            
            message("SettingsManager: Configuration directory: %s", config_dir);
        }
        
        /**
         * Ensure the configuration directory exists
         */
        private void ensure_config_dir() {
            if (!GLib.FileUtils.test(config_dir, GLib.FileTest.IS_DIR)) {
                try {
                    GLib.DirUtils.create_with_parents(config_dir, 0755);
                    message("SettingsManager: Directory created: %s", config_dir);
                } catch (GLib.Error e) {
                    warning("SettingsManager: Error creating directory: %s", e.message);
                }
            }
        }
        
        /**
         * Load settings from JSON file
         */
        public void load() {
            if (loaded) return;
            
            ensure_config_dir();
            
            if (!GLib.FileUtils.test(config_file, GLib.FileTest.EXISTS)) {
                message("SettingsManager: Configuration file does not exist, creating with default values");
                create_default_settings();
                return;
            }
            
            try {
                var parser = new Json.Parser();
                parser.load_from_file(config_file);
                var root = parser.get_root();
                
                if (root.get_node_type() == Json.NodeType.OBJECT) {
                    settings = root.get_object();
                    message("SettingsManager: Settings loaded from %s", config_file);
                } else {
                    warning("SettingsManager: Invalid configuration file, using defaults");
                    create_default_settings();
                }
            } catch (GLib.Error e) {
                warning("SettingsManager: Error loading settings: %s", e.message);
                create_default_settings();
            }
            
            loaded = true;
        }
        
        /**
         * Create default settings
         */
        private void create_default_settings() {
            settings = new Json.Object();
            
            set_int("theme", DEFAULT_THEME);
            set_int("language", DEFAULT_LANGUAGE);
            set_bool("auto_start", DEFAULT_AUTO_START);
            set_bool("notify_connect", DEFAULT_NOTIFY_CONNECT);
            set_bool("notify_battery", DEFAULT_NOTIFY_BATTERY);
            set_bool("notify_update", DEFAULT_NOTIFY_UPDATE);
            set_bool("sidebar_left_visible", DEFAULT_SIDEBAR_LEFT_VISIBLE);
            set_string("custom_theme", DEFAULT_CUSTOM_THEME);
            set_string("custom_theme_name", DEFAULT_CUSTOM_THEME_NAME);
            set_int("custom_accent_index", DEFAULT_CUSTOM_ACCENT_INDEX);
            set_double("custom_accent_r", DEFAULT_ACCENT_R);
            set_double("custom_accent_g", DEFAULT_ACCENT_G);
            set_double("custom_accent_b", DEFAULT_ACCENT_B);
            
            // Window settings
            set_int("window_width", DEFAULT_WINDOW_WIDTH);
            set_int("window_height", DEFAULT_WINDOW_HEIGHT);
            set_bool("window_maximized", DEFAULT_WINDOW_MAXIMIZED);
            
            save();
        }
        
        /**
         * Save settings (with throttle)
         */
        public void save() {
            if (save_timeout != 0) {
                GLib.Source.remove(save_timeout);
            }
            
            save_timeout = GLib.Timeout.add(SAVE_DELAY_MS, () => {
                perform_save();
                save_timeout = 0;
                return GLib.Source.REMOVE;
            });
        }
        
        /**
         * Perform immediate save
         */
        private void perform_save() {
            if (settings == null) return;
            
            ensure_config_dir();
            
            try {
                var generator = new Json.Generator();
                var root = new Json.Node(Json.NodeType.OBJECT);
                root.set_object(settings);
                generator.set_root(root);
                generator.set_pretty(true);
                generator.to_file(config_file);
                message("SettingsManager: Settings saved to %s", config_file);
            } catch (GLib.Error e) {
                warning("SettingsManager: Error saving settings: %s", e.message);
            }
        }
        
        /**
         * Save and sync immediately
         */
        public void sync() {
            if (save_timeout != 0) {
                GLib.Source.remove(save_timeout);
                save_timeout = 0;
            }
            perform_save();
        }
        
        // ==================== ACCESS METHODS ====================
        
        public int get_theme() {
            return get_int("theme", DEFAULT_THEME);
        }
        
        public void set_theme(int value) {
            if (get_theme() == value) return;
            set_int("theme", value);
            theme_changed(value);
        }
        
        public int get_language() {
            return get_int("language", DEFAULT_LANGUAGE);
        }
        
        public void set_language(int value) {
            if (get_language() == value) return;
            set_int("language", value);
            language_changed(value);
        }
        
        public bool get_auto_start() {
            return get_bool("auto_start", DEFAULT_AUTO_START);
        }
        
        public void set_auto_start(bool value) {
            if (get_auto_start() == value) return;
            set_bool("auto_start", value);
        }
        
        public bool get_notify_connect() {
            return get_bool("notify_connect", DEFAULT_NOTIFY_CONNECT);
        }
        
        public void set_notify_connect(bool value) {
            if (get_notify_connect() == value) return;
            set_bool("notify_connect", value);
        }
        
        public bool get_notify_battery() {
            return get_bool("notify_battery", DEFAULT_NOTIFY_BATTERY);
        }
        
        public void set_notify_battery(bool value) {
            if (get_notify_battery() == value) return;
            set_bool("notify_battery", value);
        }
        
        public bool get_notify_update() {
            return get_bool("notify_update", DEFAULT_NOTIFY_UPDATE);
        }
        
        public void set_notify_update(bool value) {
            if (get_notify_update() == value) return;
            set_bool("notify_update", value);
        }
        
        public bool get_sidebar_left_visible() {
            return get_bool("sidebar_left_visible", DEFAULT_SIDEBAR_LEFT_VISIBLE);
        }
        
        public void set_sidebar_left_visible(bool value) {
            if (get_sidebar_left_visible() == value) return;
            set_bool("sidebar_left_visible", value);
        }
        
        public string get_custom_theme() {
            return get_string("custom_theme", DEFAULT_CUSTOM_THEME);
        }
        
        public void set_custom_theme(string value) {
            if (get_custom_theme() == value) return;
            set_string("custom_theme", value);
        }
        
        public string get_custom_theme_name() {
            return get_string("custom_theme_name", DEFAULT_CUSTOM_THEME_NAME);
        }
        
        public void set_custom_theme_name(string value) {
            if (get_custom_theme_name() == value) return;
            set_string("custom_theme_name", value);
        }
        
        public int get_custom_accent_index() {
            return get_int("custom_accent_index", DEFAULT_CUSTOM_ACCENT_INDEX);
        }
        
        public void set_custom_accent_index(int value) {
            if (get_custom_accent_index() == value) return;
            set_int("custom_accent_index", value);
        }
        
        public Gdk.RGBA get_custom_accent_color() {
            double r = get_double("custom_accent_r", DEFAULT_ACCENT_R);
            double g = get_double("custom_accent_g", DEFAULT_ACCENT_G);
            double b = get_double("custom_accent_b", DEFAULT_ACCENT_B);
            
            return Gdk.RGBA() {
                red = (float)r,
                green = (float)g,
                blue = (float)b,
                alpha = 1.0f
            };
        }
        
        public void set_custom_accent_color(Gdk.RGBA color) {
            var current = get_custom_accent_color();
            if (Math.fabs(current.red - color.red) < 0.01 &&
                Math.fabs(current.green - color.green) < 0.01 &&
                Math.fabs(current.blue - color.blue) < 0.01) {
                return;
            }
            
            set_double("custom_accent_r", color.red);
            set_double("custom_accent_g", color.green);
            set_double("custom_accent_b", color.blue);
            accent_color_changed(color);
        }
        
        // ==================== WINDOW ACCESS METHODS ====================
        
        public int get_window_width() {
            return get_int("window_width", DEFAULT_WINDOW_WIDTH);
        }
        
        public void set_window_width(int value) {
            if (get_window_width() == value) return;
            set_int("window_width", value);
        }
        
        public int get_window_height() {
            return get_int("window_height", DEFAULT_WINDOW_HEIGHT);
        }
        
        public void set_window_height(int value) {
            if (get_window_height() == value) return;
            set_int("window_height", value);
        }
        
        public bool get_window_maximized() {
            return get_bool("window_maximized", DEFAULT_WINDOW_MAXIMIZED);
        }
        
        public void set_window_maximized(bool value) {
            if (get_window_maximized() == value) return;
            set_bool("window_maximized", value);
        }
        
        // ==================== PRIVATE METHODS ====================
        
        private int get_int(string key, int default_value) {
            if (settings == null) return default_value;
            var node = settings.get_member(key);
            if (node != null && node.get_node_type() == Json.NodeType.VALUE) {
                return (int)node.get_int();
            }
            return default_value;
        }
        
        private void set_int(string key, int value) {
            if (settings == null) return;
            settings.set_int_member(key, value);
            save();
        }
        
        private bool get_bool(string key, bool default_value) {
            if (settings == null) return default_value;
            var node = settings.get_member(key);
            if (node != null && node.get_node_type() == Json.NodeType.VALUE) {
                return node.get_boolean();
            }
            return default_value;
        }
        
        private void set_bool(string key, bool value) {
            if (settings == null) return;
            settings.set_boolean_member(key, value);
            save();
        }
        
        private string get_string(string key, string default_value) {
            if (settings == null) return default_value;
            var node = settings.get_member(key);
            if (node != null && node.get_node_type() == Json.NodeType.VALUE) {
                return node.get_string();
            }
            return default_value;
        }
        
        private void set_string(string key, string value) {
            if (settings == null) return;
            settings.set_string_member(key, value);
            save();
        }
        
        private double get_double(string key, double default_value) {
            if (settings == null) return default_value;
            var node = settings.get_member(key);
            if (node != null && node.get_node_type() == Json.NodeType.VALUE) {
                return node.get_double();
            }
            return default_value;
        }
        
        private void set_double(string key, double value) {
            if (settings == null) return;
            settings.set_double_member(key, value);
            save();
        }
        
        // ==================== METHODS FOR RECENT COLORS ====================

private string color_to_hex(Gdk.RGBA color) {
    return "#%02X%02X%02X".printf(
        (uint8)(color.red * 255),
        (uint8)(color.green * 255),
        (uint8)(color.blue * 255)
    );
}

private Gdk.RGBA? parse_hex_color(string hex) {
    string h = hex;
    if (h.has_prefix("#")) h = h.substring(1);
    if (h.length != 6) return null;
    
    uint32 rgb = 0;
    for (int i = 0; i < 6; i++) {
        char c = h[i];
        uint32 val = 0;
        if (c >= '0' && c <= '9') val = (uint32)(c - '0');
        else if (c >= 'A' && c <= 'F') val = (uint32)(c - 'A' + 10);
        else if (c >= 'a' && c <= 'f') val = (uint32)(c - 'a' + 10);
        else return null;
        rgb = (rgb << 4) | val;
    }
    
    Gdk.RGBA color = Gdk.RGBA() {
        red = (float)((rgb >> 16) & 0xFF) / 255.0f,
        green = (float)((rgb >> 8) & 0xFF) / 255.0f,
        blue = (float)(rgb & 0xFF) / 255.0f,
        alpha = 1.0f
    };
    return color;
}

private string[] get_string_list(string key) {
    if (settings == null) return {};
    var node = settings.get_member(key);
    if (node == null || node.get_node_type() != Json.NodeType.ARRAY) {
        return {};
    }
    var array = node.get_array();
    string[] result = {};
    for (int i = 0; i < array.get_length(); i++) {
        var elem = array.get_element(i);
        if (elem != null && elem.get_node_type() == Json.NodeType.VALUE) {
            result += elem.get_string();
        }
    }
    return result;
}

private void set_string_list(string key, string[] values) {
    if (settings == null) return;
    var array = new Json.Array();
    foreach (string v in values) {
        array.add_string_element(v);
    }
    var node = new Json.Node(Json.NodeType.ARRAY);
    node.set_array(array);
    settings.set_member(key, node);
    save();
}

public Gdk.RGBA[] get_recent_colors() {
    string[] hex_list = get_string_list("recent_colors");
    Gdk.RGBA[] colors = {};
    foreach (string hex in hex_list) {
        var color = parse_hex_color(hex);
        if (color != null) {
            colors += color;
        }
    }
    return colors;
}

public void set_recent_colors(Gdk.RGBA[] colors) {
    string[] hex_list = {};
    foreach (var color in colors) {
        hex_list += color_to_hex(color);
    }
    set_string_list("recent_colors", hex_list);
}

public void clear_recent_colors() {
    set_string_list("recent_colors", {});
}

        ~SettingsManager() {
            if (save_timeout != 0) {
                GLib.Source.remove(save_timeout);
            }
            sync();
        }
    }
}
