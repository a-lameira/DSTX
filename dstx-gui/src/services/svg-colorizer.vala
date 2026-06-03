/*
 * svg-colorizer.vala - SVG colorization service for controller rendering
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
 * - Colorize SVG assets with theme colors (primary, secondary, accent, symbol)
 * - Generate CSS for SVG styling based on UI mode and theme
 * - Cache rendered textures for performance
 */

// src/services/svg-colorizer.vala

using Rsvg;
using Gdk;
using Gtk;
using Cairo;
using Dstx.Models;

namespace Dstx.Services {
    public class SvgColorizer : Object {
        private static SvgColorizer? instance = null;
        
        private SvgColorizer() {
            message("SvgColorizer: Initialized");
        }
        
        public static SvgColorizer get_default() {
            if (instance == null) {
                instance = new SvgColorizer();
            }
            return instance;
        }
        
        public string get_cache_key(string svg_resource_path, ControllerColors? colors, int ui_mode, bool is_system_dark) {
            string primary, secondary, accent, symbol;
            
            const string LIGHT_PRIMARY = "#999999";
            const string LIGHT_SECONDARY = "#666666";
            const string LIGHT_ACCENT = "#3584e4";
            const string LIGHT_SYMBOL = "#2e3436";
            
            const string DARK_PRIMARY = "#666666";
            const string DARK_SECONDARY = "#4d4d4d";
            const string DARK_ACCENT = "#3584e4";
            const string DARK_SYMBOL = "#e6e6e6";
            
            if (ui_mode == 3 && colors != null) {
                primary = colors.primary ?? DARK_PRIMARY;
                secondary = colors.secondary ?? DARK_SECONDARY;
                accent = colors.accent ?? DARK_ACCENT;
                symbol = colors.symbol ?? DARK_SYMBOL;
            } else if (ui_mode == 1 || (ui_mode == 0 && !is_system_dark)) {
                primary = LIGHT_PRIMARY;
                secondary = LIGHT_SECONDARY;
                accent = LIGHT_ACCENT;
                symbol = LIGHT_SYMBOL;
            } else {
                primary = DARK_PRIMARY;
                secondary = DARK_SECONDARY;
                accent = DARK_ACCENT;
                symbol = DARK_SYMBOL;
            }
            
            primary = swap_rb(primary);
            secondary = swap_rb(secondary);
            accent = swap_rb(accent);
            symbol = swap_rb(symbol);
            
            return @"$(svg_resource_path):$(primary):$(secondary):$(accent):$(symbol)";
        }
        
        public string generate_css(ControllerColors? colors, int ui_mode, bool is_system_dark) {
            string primary, secondary, accent, symbol;
            
            const string LIGHT_PRIMARY = "#c9c4c4";
            const string LIGHT_SECONDARY = "#a69d9d";
            const string LIGHT_ACCENT = "#3584e4";
            const string LIGHT_SYMBOL = "#2e3436";
            
            const string DARK_PRIMARY = "#666666";
            const string DARK_SECONDARY = "#4d4d4d";
            const string DARK_ACCENT = "#3584e4";
            const string DARK_SYMBOL = "#e6e6e6";
            
            if (ui_mode == 3 && colors != null) {
                primary = colors.primary != null ? colors.primary : DARK_PRIMARY;
                secondary = colors.secondary != null ? colors.secondary : DARK_SECONDARY;
                accent = colors.accent != null ? colors.accent : DARK_ACCENT;
                symbol = colors.symbol != null ? colors.symbol : DARK_SYMBOL;
            } else if (ui_mode == 1 || (ui_mode == 0 && !is_system_dark)) {
                primary = LIGHT_PRIMARY;
                secondary = LIGHT_SECONDARY;
                accent = LIGHT_ACCENT;
                symbol = LIGHT_SYMBOL;
            } else {
                primary = DARK_PRIMARY;
                secondary = DARK_SECONDARY;
                accent = DARK_ACCENT;
                symbol = DARK_SYMBOL;
            }
            
            primary = swap_rb(primary);
            secondary = swap_rb(secondary);
            accent = swap_rb(accent);
            symbol = swap_rb(symbol);
            
            return """
                .primary { fill: %s; stroke: none; }
                .secondary { fill: %s; stroke: none; }
                .accent { fill: %s; stroke: none; }
                .symbol { fill: %s; stroke: none; }
            """.printf(primary, secondary, accent, symbol);
        }
        
        private string swap_rb(string hex_color) {
            string hex = hex_color;
            if (hex.has_prefix("#")) {
                hex = hex.substring(1);
            }
            
            if (hex.length == 6) {
                string r = hex.substring(0, 2);
                string g = hex.substring(2, 2);
                string b = hex.substring(4, 2);
                return @"#$(b)$(g)$(r)";
            }
            
            return hex_color;
        }
        
public Gdk.Texture? colorize_svg_sync(string svg_resource_path, ControllerColors? colors, int ui_mode, bool is_system_dark, int target_width, int target_height) {
    string cache_key = get_cache_key(svg_resource_path, colors, ui_mode, is_system_dark);
    cache_key = @"$(cache_key):$(target_width)x$(target_height)";  // Include size in cache
    var cache_mgr = TextureCacheManager.get_default();
    
    var cached = cache_mgr.get(cache_key);
    if (cached != null) {
        return cached;
    }
    
    string css = generate_css(colors, ui_mode, is_system_dark);
    var texture = render_svg_to_texture(svg_resource_path, css, target_width, target_height);
    
    if (texture != null) {
        cache_mgr.put(cache_key, texture);
    }
    
    return texture;
}
        
private Gdk.Texture? render_svg_to_texture(string svg_resource_path, string css, int target_width, int target_height) {
    Cairo.ImageSurface? surface = null;
    Cairo.Context? ctx = null;
    Rsvg.Handle? svg_handle = null;
    Gdk.Texture? texture = null;
    
    try {
        var bytes = GLib.resources_lookup_data(svg_resource_path, GLib.ResourceLookupFlags.NONE);
        if (bytes == null) {
            warning("Unable to load %s", svg_resource_path);
            return null;
        }
        
        svg_handle = new Rsvg.Handle.from_data(bytes.get_data());
        
        if (css != null && css != "") {
            svg_handle.set_stylesheet(css.data);
        }
        
        // Get original SVG dimensions
        var dimensions = svg_handle.get_dimensions();
        double svg_width = dimensions.width;
        double svg_height = dimensions.height;
        
        message("Original SVG: %dx%d, target: %dx%d", (int)svg_width, (int)svg_height, target_width, target_height);
        
        // Create surface at TARGET size (for the controller)
        surface = new Cairo.ImageSurface(Cairo.Format.ARGB32, target_width, target_height);
        ctx = new Cairo.Context(surface);
        
        // Calculate scale to fill the surface while maintaining aspect ratio
        double scale_x = (double)target_width / svg_width;
        double scale_y = (double)target_height / svg_height;
        double scale = double.min(scale_x, scale_y);
        
        // Center the image
        double offset_x = (target_width - svg_width * scale) / 2;
        double offset_y = (target_height - svg_height * scale) / 2;
        
        ctx.translate(offset_x, offset_y);
        ctx.scale(scale, scale);
        
        message("Rendering with scale=%.3f, offset=(%.1f,%.1f)", scale, offset_x, offset_y);
        
        svg_handle.render_cairo(ctx);
        surface.flush();
        
        uint8* data_ptr = surface.get_data();
        int stride = surface.get_stride();
        size_t data_size = target_height * stride;
        
        uint8[] data = new uint8[data_size];
        GLib.Memory.copy(data, data_ptr, data_size);
        
        var bytes_obj = new GLib.Bytes.take(data);
        
        texture = new Gdk.MemoryTexture(target_width, target_height, 
                                        Gdk.MemoryFormat.R8G8B8A8_PREMULTIPLIED, 
                                        bytes_obj, stride);
        
        message("Texture created: %dx%d", target_width, target_height);
        
        return texture;
        
    } catch (GLib.Error e) {
        warning("Error: %s", e.message);
        return null;
    } finally {
        if (ctx != null) ctx = null;
        if (surface != null) surface = null;
        if (svg_handle != null) svg_handle = null;
    }
}
        
        ~SvgColorizer() {
            message("SvgColorizer: Destroyed");
        }
    }
}
