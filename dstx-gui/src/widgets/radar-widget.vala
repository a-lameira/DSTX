/*
 * radar-widget.vala - Analog stick visualization widget for DSTX GUI
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
 * - Render analog stick position as a circular radar widget
 * - Three-layer rendering: background (cached), deadzone (cached), cursor (real-time)
 * - Handle deadzone visualization with dashed circle
 * - Provide methods to update stick values and colors
 */

// src/widgets/radar-widget.vala

using Dstx.Models;
using Dstx.Widgets;
using Gtk;
using Gdk;
using Cairo;
using Graphene;
using Gsk;

namespace Dstx.Widgets {
    /**
     * RadarWidget - Widget for analog stick visualization
     * 
     * Three-layer rendering:
     * - Layer 1: Background (concentric circles, axes) - cached as Gsk.RenderNode
     * - Layer 2: Deadzone (dashed circle) - cached, invalidated when value changes
     * - Layer 3: Cursor (colored dot) - drawn in real-time via Cairo
     */
    public class RadarWidget : Gtk.Widget {
        
        // ==================== STICK DATA ====================
        private int16 _raw_x = 0;
        private int16 _raw_y = 0;
        private double _cursor_x = 0.0;
        private double _cursor_y = 0.0;
        private uint8 _deadzone = 0;
        
        // ==================== COLORS ====================
        private Gdk.RGBA _accent_color;
        private Gdk.RGBA _gray_color;
        private Gdk.RGBA _deadzone_color;
        private Gdk.RGBA _deadzone_border_color;
        
        // ==================== RENDERING CACHE ====================
        private Gsk.RenderNode? _background_node = null;
        private Gsk.RenderNode? _deadzone_node = null;
        
        // ==================== PROPERTIES ====================
        public string label { get; set; default = "LS"; }
        
        public int16 raw_x {
            get { return _raw_x; }
            set {
                _raw_x = value;
                update_cursor_position();
            }
        }
        
        public int16 raw_y {
            get { return _raw_y; }
            set {
                _raw_y = value;
                update_cursor_position();
            }
        }
        
        public RadarWidget() {
            Object();
            
            _accent_color = Gdk.RGBA() {
                red = 0.2f, green = 0.6f, blue = 1.0f, alpha = 0.9f
            };
            
            _gray_color = Gdk.RGBA() {
                red = 0.5f, green = 0.5f, blue = 0.5f, alpha = 0.5f
            };
            
            _deadzone_color = Gdk.RGBA() {
                red = 1.0f, green = 0.2f, blue = 0.2f, alpha = 0.15f
            };
            
            _deadzone_border_color = Gdk.RGBA() {
                red = 1.0f, green = 0.2f, blue = 0.2f, alpha = 0.8f
            };
            
            this.set_size_request(80, 80);
            this.set_halign(Gtk.Align.CENTER);
            this.set_valign(Gtk.Align.CENTER);
            
            this.destroy.connect(() => {
                _background_node = null;
                _deadzone_node = null;
            });
        }
        
        // ==================== SNAPSHOT (MAIN RENDERING) ====================
        
        public override void snapshot(Gtk.Snapshot snapshot) {
            int size = this.get_width();
            int height = this.get_height();
            
            if (size <= 1 || height <= 1) {
                return;
            }
            
            // Use the smaller side to keep the radar square
            int radar_size = int.min(size, height);
            int offset_x = (size - radar_size) / 2;
            int offset_y = (height - radar_size) / 2;
            
            snapshot.save();
            
            // Translate using Point allocated on the stack
            Graphene.Point translate_point = Graphene.Point() { x = (float)offset_x, y = (float)offset_y };
            snapshot.translate(translate_point);
            
            // Layer 1: Radar background (cached)
            if (_background_node == null) {
                _background_node = create_background_node(radar_size);
            }
            if (_background_node != null) {
                snapshot.append_node(_background_node);
            }
            
            // Layer 2: Deadzone (cached, invalidated when value changes)
            if (_deadzone > 0) {
                if (_deadzone_node == null) {
                    _deadzone_node = create_deadzone_node(radar_size, _deadzone);
                }
                if (_deadzone_node != null) {
                    snapshot.append_node(_deadzone_node);
                }
            }
            
            // Layer 3: Cursor (drawn in real-time via Cairo)
            Graphene.Rect cursor_bounds = Graphene.Rect();
            cursor_bounds.init(0.0f, 0.0f, (float)radar_size, (float)radar_size);
            var cr = snapshot.append_cairo(cursor_bounds);
            draw_cursor(cr, radar_size, _cursor_x, _cursor_y);
            cr = null;
            
            snapshot.restore();
        }
        
        // ==================== RENDER NODE CREATION ====================
        
        private Gsk.RenderNode? create_background_node(int size) {
            var snapshot = new Gtk.Snapshot();
            
            Graphene.Rect bounds = Graphene.Rect();
            bounds.init(0.0f, 0.0f, (float)size, (float)size);
            var cr = snapshot.append_cairo(bounds);
            
            int center_x = size / 2;
            int center_y = size / 2;
            int radius = (int)(size * 0.45);
            
            if (radius < 5) {
                cr = null;
                return null;
            }
            
            // Outer circle
            cr.set_source_rgba(_gray_color.red, _gray_color.green, _gray_color.blue, 0.8);
            cr.set_line_width(1.5);
            cr.arc(center_x, center_y, radius, 0, 2 * Math.PI);
            cr.stroke();
            
            // Inner circle (50% of radius)
            cr.set_source_rgba(_gray_color.red, _gray_color.green, _gray_color.blue, 0.5);
            cr.set_line_width(1.0);
            cr.arc(center_x, center_y, radius / 2, 0, 2 * Math.PI);
            cr.stroke();
            
            // X and Y axis lines
            cr.set_source_rgba(_gray_color.red, _gray_color.green, _gray_color.blue, 0.3);
            cr.set_line_width(1.0);
            cr.move_to(center_x - radius, center_y);
            cr.line_to(center_x + radius, center_y);
            cr.stroke();
            cr.move_to(center_x, center_y - radius);
            cr.line_to(center_x, center_y + radius);
            cr.stroke();
            
            // Center point
            cr.set_source_rgba(_gray_color.red, _gray_color.green, _gray_color.blue, 0.3);
            cr.arc(center_x, center_y, radius * 0.03, 0, 2 * Math.PI);
            cr.fill();
            
            cr = null;
            return snapshot.free_to_node();
        }
        
        private Gsk.RenderNode? create_deadzone_node(int size, uint8 deadzone) {
            if (deadzone == 0) return null;
            
            var snapshot = new Gtk.Snapshot();
            
            Graphene.Rect bounds = Graphene.Rect();
            bounds.init(0.0f, 0.0f, (float)size, (float)size);
            var cr = snapshot.append_cairo(bounds);
            
            int center_x = size / 2;
            int center_y = size / 2;
            int radius = (int)(size * 0.45);
            int deadzone_radius = (int)(radius * deadzone / 100.0);
            
            if (deadzone_radius > 0) {
                // Deadzone area (semi-transparent fill)
                cr.set_source_rgba(_deadzone_color.red, _deadzone_color.green,
                                  _deadzone_color.blue, _deadzone_color.alpha);
                cr.arc(center_x, center_y, deadzone_radius, 0, 2 * Math.PI);
                cr.fill();
                
                // Dashed deadzone border
                cr.set_source_rgba(_deadzone_border_color.red, _deadzone_border_color.green,
                                  _deadzone_border_color.blue, _deadzone_border_color.alpha);
                cr.set_line_width(1.5);
                
                double[] dashes = { 4.0, 4.0 };
                cr.set_dash(dashes, 0);
                cr.arc(center_x, center_y, deadzone_radius, 0, 2 * Math.PI);
                cr.stroke();
                cr.set_dash(null, 0);
            }
            
            cr = null;
            return snapshot.free_to_node();
        }
        
        // ==================== CURSOR DRAWING (REAL-TIME) ====================
        
        private void draw_cursor(Cairo.Context cr, int size, double x, double y) {
            int center_x = size / 2;
            int center_y = size / 2;
            int radius = (int)(size * 0.45);
            
            int point_x = center_x + (int)(x * radius);
            int point_y = center_y + (int)(y * radius);
            
            double distance = Math.sqrt(x * x + y * y);
            if (distance > 1.0) {
                double norm_x = x / distance;
                double norm_y = y / distance;
                point_x = center_x + (int)(norm_x * radius);
                point_y = center_y + (int)(norm_y * radius);
            }
            
            double dot_radius = radius * 0.12;
            if (dot_radius < 2) dot_radius = 2;
            
            double brightness = 0.7 + distance * 0.3;
            
            // Main cursor circle
            cr.set_source_rgba(
                _accent_color.red * brightness,
                _accent_color.green * brightness,
                _accent_color.blue * brightness,
                0.9
            );
            cr.arc(point_x, point_y, dot_radius, 0, 2 * Math.PI);
            cr.fill();
            
            // White border around cursor
            cr.set_source_rgba(1.0, 1.0, 1.0, 0.9);
            cr.set_line_width(2.0);
            cr.arc(point_x, point_y, dot_radius, 0, 2 * Math.PI);
            cr.stroke();
            
            // Cursor trail
            if (distance > 0.1) {
                double trail_length = 0.15;
                int trail_x = point_x - (int)(x * radius * trail_length);
                int trail_y = point_y - (int)(y * radius * trail_length);
                
                cr.set_source_rgba(_accent_color.red, _accent_color.green,
                                  _accent_color.blue, 0.3);
                cr.set_line_width(2.0);
                cr.move_to(point_x, point_y);
                cr.line_to(trail_x, trail_y);
                cr.stroke();
            }
        }
        
        // ==================== CURSOR POSITION UPDATE ====================
        
        private void update_cursor_position() {
            double new_x = _raw_x / 32767.0;
            double new_y = _raw_y / 32767.0;
            
            // Limit to unit circle
            double distance = Math.sqrt(new_x * new_x + new_y * new_y);
            if (distance > 1.0) {
                new_x = new_x / distance;
                new_y = new_y / distance;
            }
            
            _cursor_x = new_x;
            _cursor_y = new_y;
            
            // Selective redraw - only cursor area
            this.queue_draw();
        }
        
        // ==================== PUBLIC METHODS ====================
        
        public void update_values(int16 x, int16 y) {
            _raw_x = x;
            _raw_y = y;
            update_cursor_position();
        }
        
        public void set_deadzone(uint8 deadzone) {
            if (_deadzone == deadzone) return;
            
            _deadzone = deadzone.clamp(0, 100);
            
            // Invalidate deadzone node for recreation
            _deadzone_node = null;
            
            this.queue_draw();
        }
        
        public void set_accent_color(Gdk.RGBA color) {
            float eps = 0.0001f;
            if (Math.fabs(_accent_color.red - color.red) < eps &&
                Math.fabs(_accent_color.green - color.green) < eps &&
                Math.fabs(_accent_color.blue - color.blue) < eps &&
                Math.fabs(_accent_color.alpha - color.alpha) < eps) {
                return;
            }
            
            _accent_color = color;
            
            // Invalidate nodes that depend on accent color
            _deadzone_node = null;
            
            this.queue_draw();
        }
        
        public void reset_position() {
            _raw_x = 0;
            _raw_y = 0;
            _cursor_x = 0.0;
            _cursor_y = 0.0;
            this.queue_draw();
        }
        
        public void invalidate_cache() {
            _background_node = null;
            _deadzone_node = null;
            this.queue_draw();
        }
        
        // ==================== DESTRUCTOR ====================
        
        ~RadarWidget() {
            _background_node = null;
            _deadzone_node = null;
        }
    }
}
