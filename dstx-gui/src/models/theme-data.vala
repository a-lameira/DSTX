/*
 * theme-data.vala - Theme data models for DSTX GUI
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
 * - Define thumbnail colors, controller colors, and window colors structures
 * - Provide ThemeData container for complete theme information
 * - Load theme data from JSON and provide access methods
 */

// src/models/theme-data.vala

using Gee;

namespace Dstx.Models {
    /**
     * ThumbnailColors - Specific colors for the theme thumbnail
     * These colors are used to render the theme preview
     */
    public class ThumbnailColors : Object {
        public string bg { get; set; }      // Thumbnail background color
        public string accent { get; set; }  // Highlight color (top bar, UI elements)
        public string text { get; set; }    // Text color
        
        public ThumbnailColors() {
            bg = "#f6f5f4";
            accent = "#3584e4";
            text = "#2e3436";
        }
        
        public ThumbnailColors copy() {
            var copy = new ThumbnailColors();
            copy.bg = this.bg;
            copy.accent = this.accent;
            copy.text = this.text;
            return copy;
        }
        
        public string to_hash() {
            return @"$(bg):$(accent):$(text)";
        }
    }
    
    /**
     * ControllerColors - Colors for controller SVG coloring
     * These colors are used by SvgColorizer to paint the base controller
     */
    public class ControllerColors : Object {
        // 4 main colors for SVG coloring
        public string primary { get; set; }    // Primary color
        public string secondary { get; set; }  // Secondary color
        public string accent { get; set; }
        public string symbol { get; set; }
        
        public ControllerColors() {
            // Default values (dark mode)
            primary = "#666666";
            secondary = "#4d4d4d";
            accent = "#3584e4";
            symbol = "#e6e6e6";
        }
        
        public ControllerColors copy() {
            var copy = new ControllerColors();
            copy.primary = this.primary;
            copy.secondary = this.secondary;
            copy.accent = this.accent;
            copy.symbol = this.symbol;
            return copy;
        }
        
        /**
         * Compares two ControllerColors instances for equality
         * @param other Another instance to compare
         * @return true if all colors are equal
         */
        public bool equals(ControllerColors other) {
            if (other == null) return false;
            return this.primary == other.primary &&
                   this.secondary == other.secondary &&
                   this.accent == other.accent &&
                   this.symbol == other.symbol;
        }
        
        /**
         * Returns a string representation for cache/hash
         */
        public string to_hash() {
            return @"$(primary):$(secondary):$(accent):$(symbol)";
        }
        
        public string to_string() {
            return @"ControllerColors(primary:$(primary), secondary:$(secondary), accent:$(accent), symbol:$(symbol))";
        }
    }
    
    /**
     * WindowColors - Colors for the window and user interface
     * These colors are used to generate dynamic CSS via ThemeManager
     */
public class WindowColors : Object {
    public HashMap<string, string> vars { get; set; }
    
    public WindowColors() {
        vars = new HashMap<string, string>();
    }
    
    public WindowColors copy() {
        var copy = new WindowColors();
        foreach (var key in vars.keys) {
            copy.vars.set(key, vars.get(key));
        }
        return copy;
    }
    
    /**
     * Gets a color variable with fallback
     * @param key Variable name (e.g., "sidebar-bg")
     * @param default_value Default value if variable does not exist
     * @return Variable value or default_value
     */
    public string get(string key, string default_value) {
        if (vars.has_key(key)) {
            return vars.get(key);
        }
        return default_value;
    }
    
    /**
     * Sets a color variable
     * @param key Variable name (e.g., "sidebar-bg")
     * @param value Hexadecimal color value (e.g., "#f0f0ef")
     */
    public void set(string key, string value) {
        vars.set(key, value);
    }
}
    
    /**
     * ThemeData - Complete theme data
     * 
     * This class centralizes all theme information:
     * - Thumbnail colors (for preview)
     * - Controller colors (for SVG coloring)
     * - Window colors (for interface CSS)
     * - Accent color palette
     * 
     * Data is loaded from the themes.json file and is the single
     * source of truth for theme configuration.
     */
    public class ThemeData : Object {
        public string id { get; set; }           // Unique identifier (e.g., "light", "algae")
        public string name { get; set; }         // Display name in UI (e.g., "Light", "Algae")
        public string theme_type { get; set; }   // "light" or "dark" (affects libadwaita mode)
        
        public ThumbnailColors thumbnail { get; set; }  // Colors for thumbnail
        public string[] palette { get; set; }           // Palette of 10 accent colors
        public WindowColors window { get; set; }        // Colors for interface CSS
        public ControllerColors controller { get; set; } // Colors for controller SVG
        
        public ThemeData() {
            id = "";
            name = "";
            theme_type = "light";
            
            thumbnail = new ThumbnailColors();
            palette = new string[10];
            window = new WindowColors();
            controller = new ControllerColors();
        }
        
        /**
         * Creates a deep copy of the theme
         * @return New instance with the same data
         */
        public ThemeData copy() {
            var copy = new ThemeData();
            copy.id = this.id;
            copy.name = this.name;
            copy.theme_type = this.theme_type;
            
            copy.thumbnail = this.thumbnail.copy();
            
            copy.palette = new string[10];
            for (int i = 0; i < 10; i++) {
                copy.palette[i] = this.palette[i];
            }
            
            copy.window = this.window.copy();
            copy.controller = this.controller.copy();
            
            return copy;
        }
        
        /**
         * Checks if the theme is dark
         * @return true if theme_type is "dark"
         */
        public bool is_dark() {
            return theme_type == "dark";
        }
        
        /**
         * Checks if the theme is light
         * @return true if theme_type is "light"
         */
        public bool is_light() {
            return theme_type == "light";
        }
        
        /**
         * Gets the accent color from a specific palette index
         * @param index Color index (0-9)
         * @return Hexadecimal color or fallback if index is invalid
         */
        public string get_accent_color(int index) {
            if (index >= 0 && index < palette.length && palette[index] != null) {
                return palette[index];
            }
            return thumbnail.accent; // Fallback to thumbnail accent color
        }
        
        /**
         * Returns a string representation for debugging
         */
        public string to_string() {
            return @"ThemeData(id:$(id), name:$(name), type:$(theme_type))";
        }
        
        /**
         * Generates a unique hash for rendering cache
         * @param accent_index Current accent color index
         * @return Unique hash string for this theme with the specific accent color
         */
        public string get_cache_key(int accent_index) {
            string accent = get_accent_color(accent_index);
            return @"$(id):$(thumbnail.bg):$(thumbnail.accent):$(thumbnail.text):$(accent)";
        }
        
        /**
         * Validates if the theme has all required properties
         * @return true if the theme is valid
         */
        public bool is_valid() {
            if (id == null || id == "") return false;
            if (name == null || name == "") return false;
            if (theme_type == null || theme_type == "") return false;
            if (thumbnail.bg == null || thumbnail.bg == "") return false;
            if (thumbnail.accent == null || thumbnail.accent == "") return false;
            if (thumbnail.text == null || thumbnail.text == "") return false;
            
            // Controller colors can be null (use fallback)
            if (controller.primary == null) controller.primary = theme_type == "dark" ? "#666666" : "#999999";
            if (controller.secondary == null) controller.secondary = theme_type == "dark" ? "#4d4d4d" : "#666666";
            if (controller.accent == null) controller.accent = thumbnail.accent;
            if (controller.symbol == null) controller.symbol = thumbnail.text;
            
            return true;
        }
    }
}
