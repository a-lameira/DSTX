/*
 * controller-renderer.vala - Base class for controller SVG rendering with overlays
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
 * - Render controller SVG with colorization
 * - Display stick radars with cursor and deadzone overlay
 * - Show trigger press overlays (L2/R2)
 * - Handle theme changes and view model updates
 */

using Gtk;
using Gdk;
using Cairo;
using Graphene;
using Gsk;
using Dstx.Models;
using Dstx.Services;
using Dstx.Managers;
using Dstx.ViewModels;
using Dstx.Widgets;

namespace Dstx.Renderers {
    public abstract class ControllerRenderer : Gtk.Box {
        protected ControllerViewModel view_model;
        protected ThemeManager theme_manager;
        protected SvgColorizer svg_colorizer;
        
        private Gtk.Picture base_picture;
        private Gtk.Overlay main_overlay;
        private Gtk.DrawingArea button_overlay_area;
        private Gtk.DrawingArea triggers_overlay_area;
        
        private Gsk.RenderNode? left_radar_background_node = null;
        private Gsk.RenderNode? right_radar_background_node = null;
        private Gsk.RenderNode? left_deadzone_node = null;
        private Gsk.RenderNode? right_deadzone_node = null;
        
        private double left_cursor_x = 0.0;
        private double left_cursor_y = 0.0;
        private double right_cursor_x = 0.0;
        private double right_cursor_y = 0.0;
        
        private int current_radar_size = 80;
        private int current_trigger_size = 60;
        
        private uint reload_timeout = 0;
        private const uint RELOAD_DELAY_MS = 50;
        
        protected abstract int CANVAS_WIDTH { get; }
        protected abstract int CANVAS_HEIGHT { get; }
        protected abstract int LEFT_STICK_CANVAS_X { get; }
        protected abstract int RIGHT_STICK_CANVAS_X { get; }
        protected abstract int STICK_CANVAS_Y { get; }
        protected abstract int LEFT_TRIGGER_CANVAS_X { get; }
        protected abstract int RIGHT_TRIGGER_CANVAS_X { get; }
        protected abstract int TRIGGER_CANVAS_Y { get; }
        
        public abstract string controller_display_name { get; }
        
        protected virtual int RADAR_CANVAS_SIZE { get { return 220; } }
        protected virtual int TRIGGER_CANVAS_SIZE { get { return 60; } }
        protected virtual int MIN_RADAR_SIZE { get { return 40; } }
        protected virtual int MAX_RADAR_SIZE { get { return 220; } }
        protected virtual int MIN_TRIGGER_SIZE { get { return 20; } }
        protected virtual int MAX_TRIGGER_SIZE { get { return 60; } }
        
        private Gdk.RGBA current_accent_color;
        
        protected ControllerRenderer(ControllerViewModel view_model) {
            Object(orientation: Gtk.Orientation.VERTICAL, spacing: 0);
            this.set_size_request(300, 300);
            this.view_model = view_model;
            this.theme_manager = ThemeManager.get_default();
            this.svg_colorizer = SvgColorizer.get_default();
            this.current_accent_color = theme_manager.accent_color;
            
            setup_ui();
            connect_viewmodel_signals();
            connect_theme_signals();
            load_base_image();
            
            this.notify["width"].connect(on_size_changed);
            this.notify["height"].connect(on_size_changed);
        }
        
        private void setup_ui() {
            this.hexpand = true;
            this.vexpand = true;
            this.halign = Gtk.Align.CENTER;
            this.valign = Gtk.Align.CENTER;
            
            main_overlay = new Gtk.Overlay();
            main_overlay.vexpand = true;
            main_overlay.hexpand = true;
            
            base_picture = new Gtk.Picture();
            base_picture.content_fit = Gtk.ContentFit.CONTAIN;
            base_picture.set_hexpand(true);
            base_picture.set_vexpand(true);
            base_picture.set_halign(Gtk.Align.FILL);
            base_picture.set_valign(Gtk.Align.FILL);
            base_picture.set_size_request(1, 1);
            main_overlay.set_child(base_picture);
            
            button_overlay_area = new Gtk.DrawingArea();
            button_overlay_area.set_hexpand(true);
            button_overlay_area.set_vexpand(true);
            button_overlay_area.set_halign(Gtk.Align.FILL);
            button_overlay_area.set_valign(Gtk.Align.FILL);
            button_overlay_area.set_draw_func(on_draw_button_overlay);
            main_overlay.add_overlay(button_overlay_area);
            
            triggers_overlay_area = new Gtk.DrawingArea();
            triggers_overlay_area.set_hexpand(true);
            triggers_overlay_area.set_vexpand(true);
            triggers_overlay_area.set_halign(Gtk.Align.FILL);
            triggers_overlay_area.set_valign(Gtk.Align.FILL);
            triggers_overlay_area.set_draw_func(on_draw_triggers_overlay);
            main_overlay.add_overlay(triggers_overlay_area);
            
            this.append(main_overlay);
        }
        
        private void connect_viewmodel_signals() {
            view_model.sticks_changed.connect(on_sticks_changed);
            view_model.triggers_changed.connect(on_triggers_changed);
            view_model.deadzone_changed.connect(on_deadzone_changed);
            view_model.emulation_mode_changed.connect(on_emulation_mode_changed);
            // layout_changed removed
            view_model.any_update.connect(() => {
                button_overlay_area.queue_draw();
                triggers_overlay_area.queue_draw();
                queue_draw(); // update stick values
            });
        }
        
        private void on_sticks_changed(int16 lx, int16 ly, int16 rx, int16 ry) {
            update_left_stick(lx, ly);
            update_right_stick(rx, ry);
            queue_draw();
        }
        
        private void on_triggers_changed(int16 lt, int16 rt) {
            triggers_overlay_area.queue_draw();
        }
        
        private void on_deadzone_changed(uint8 deadzone) {
            left_deadzone_node = null;
            right_deadzone_node = null;
            queue_draw();
        }
        
        private void on_emulation_mode_changed(bool enabled) {
            button_overlay_area.queue_draw();
        }
        
        private void connect_theme_signals() {
            theme_manager.controller_colors_changed.connect(on_controller_colors_changed);
            theme_manager.accent_color_changed.connect(on_accent_color_changed);
        }
        
        private void on_controller_colors_changed(ControllerColors colors) {
            schedule_reload();
        }
        
        private void on_accent_color_changed(Gdk.RGBA color) {
            current_accent_color = color;
            left_deadzone_node = null;
            right_deadzone_node = null;
            queue_draw();
        }
        
        private void schedule_reload() {
            if (reload_timeout != 0) return;
            reload_timeout = Timeout.add(RELOAD_DELAY_MS, () => {
                load_base_image();
                reload_timeout = 0;
                return Source.REMOVE;
            });
        }
        
        private void load_base_image() {
            int ui_mode = theme_manager.ui_mode;
            var style_manager = Adw.StyleManager.get_default();
            bool is_system_dark = style_manager != null ? style_manager.dark : false;
            ControllerColors? colors = (ui_mode == 3) ? theme_manager.current_controller_colors : null;
            
            var texture = svg_colorizer.colorize_svg_sync(
                get_base_svg_path(), colors, ui_mode, is_system_dark,
                CANVAS_WIDTH, CANVAS_HEIGHT
            );
            if (texture != null) {
                base_picture.set_paintable(texture);
                update_radar_and_trigger_sizes();
                button_overlay_area.queue_draw();
                triggers_overlay_area.queue_draw();
            }
        }
        
        protected abstract string get_base_svg_path();
        
        private void update_left_stick(int16 x, int16 y) {
            double new_x = x / 32767.0;
            double new_y = y / 32767.0;
            double distance = Math.sqrt(new_x * new_x + new_y * new_y);
            if (distance > 1.0) {
                new_x /= distance;
                new_y /= distance;
            }
            left_cursor_x = new_x;
            left_cursor_y = new_y;
        }
        
        private void update_right_stick(int16 x, int16 y) {
            double new_x = x / 32767.0;
            double new_y = y / 32767.0;
            double distance = Math.sqrt(new_x * new_x + new_y * new_y);
            if (distance > 1.0) {
                new_x /= distance;
                new_y /= distance;
            }
            right_cursor_x = new_x;
            right_cursor_y = new_y;
        }
        
        private void update_radar_and_trigger_sizes() {
            var paintable = base_picture.get_paintable();
            if (paintable == null) return;
            int img_width = paintable.get_intrinsic_width();
            int img_height = paintable.get_intrinsic_height();
            if (img_width <= 0 || img_height <= 0) return;
            
            double scale_x = (double)img_width / CANVAS_WIDTH;
            double scale_y = (double)img_height / CANVAS_HEIGHT;
            double canvas_scale = double.min(scale_x, scale_y);
            
            int new_radar_size = (int)(RADAR_CANVAS_SIZE * canvas_scale);
            new_radar_size = new_radar_size.clamp(MIN_RADAR_SIZE, MAX_RADAR_SIZE);
            if (new_radar_size != current_radar_size) {
                current_radar_size = new_radar_size;
                left_radar_background_node = null;
                right_radar_background_node = null;
                left_deadzone_node = null;
                right_deadzone_node = null;
            }
            
            int new_trigger_size = (int)(TRIGGER_CANVAS_SIZE * canvas_scale);
            new_trigger_size = new_trigger_size.clamp(MIN_TRIGGER_SIZE, MAX_TRIGGER_SIZE);
            if (new_trigger_size != current_trigger_size) {
                current_trigger_size = new_trigger_size;
                triggers_overlay_area.queue_draw();
            }
        }
        
        private void on_size_changed() {
            update_radar_and_trigger_sizes();
            queue_draw();
        }
        
        // ==================== BUTTON OVERLAY ====================
        private void on_draw_button_overlay(Gtk.DrawingArea area, Cairo.Context cr, int width, int height) {
            if (width <= 0 || height <= 0) return;
            cr.set_operator(Cairo.Operator.CLEAR);
            cr.paint();
            cr.set_operator(Cairo.Operator.OVER);
            
            var paintable = base_picture.get_paintable();
            if (paintable == null) return;
            int img_width = paintable.get_intrinsic_width();
            int img_height = paintable.get_intrinsic_height();
            if (img_width <= 0 || img_height <= 0) return;
            
            double scale_x = (double)width / img_width;
            double scale_y = (double)height / img_height;
            double scale = double.min(scale_x, scale_y);
            int offset_x = (width - (int)(img_width * scale)) / 2;
            int offset_y = (height - (int)(img_height * scale)) / 2;
            
            cr.translate(offset_x, offset_y);
            // DO NOT apply cr.scale – subclasses already multiply coordinates by the scale parameter
            
            draw_button_overlay(cr, img_width, img_height, scale);
        }
        
        protected abstract void draw_button_overlay(Cairo.Context cr, int canvas_width, int canvas_height, double scale);
        
        // ==================== TRIGGER OVERLAY ====================
        private void on_draw_triggers_overlay(Gtk.DrawingArea area, Cairo.Context cr, int width, int height) {
            if (width <= 0 || height <= 0) return;
            cr.set_operator(Cairo.Operator.CLEAR);
            cr.paint();
            cr.set_operator(Cairo.Operator.OVER);
            
            var paintable = base_picture.get_paintable();
            if (paintable == null) return;
            int img_width = paintable.get_intrinsic_width();
            int img_height = paintable.get_intrinsic_height();
            if (img_width <= 0 || img_height <= 0) return;
            
            double scale_x = (double)width / img_width;
            double scale_y = (double)height / img_height;
            double scale = double.min(scale_x, scale_y);
            int offset_x = (width - (int)(img_width * scale)) / 2;
            int offset_y = (height - (int)(img_height * scale)) / 2;
            
            cr.translate(offset_x, offset_y);
            cr.scale(scale, scale);
            
            int trigger_size = current_trigger_size;
            if (trigger_size > 0) {
                int left_x = LEFT_TRIGGER_CANVAS_X;
                int left_y = TRIGGER_CANVAS_Y;
                int right_x = RIGHT_TRIGGER_CANVAS_X - trigger_size;
                int right_y = TRIGGER_CANVAS_Y;
                
                // Determine if each trigger is pressed (analog OR digital)
                bool left_pressed = view_model.l2;
                bool right_pressed = view_model.r2;
                
                cr.save();
                cr.translate(left_x, left_y);
                draw_trigger(cr, trigger_size, true, left_pressed);
                cr.restore();
                
                cr.save();
                cr.translate(right_x, right_y);
                draw_trigger(cr, trigger_size, false, right_pressed);
                cr.restore();
            }
        }
        
        private void draw_trigger(Cairo.Context cr, int size, bool is_left, bool pressed) {
            if (!pressed) return;
            cr.set_source_rgba(1.0, 0.33, 0.33, 0.9);
            cr.rectangle(2, 2, size - 4, size - 4);
            cr.fill();
            cr.set_source_rgba(1,1,1,0.9);
            cr.select_font_face("Sans", FontSlant.NORMAL, FontWeight.BOLD);
            cr.set_font_size(size * 0.3);
            string label = is_left ? "L2" : "R2";
            Cairo.TextExtents extents;
            cr.text_extents(label, out extents);
            cr.move_to((size - extents.width)/2, (size + extents.height)/2);
            cr.show_text(label);
        }
        
        // ==================== SNAPSHOT (RADARS + STICK VALUES) ====================
        public override void snapshot(Gtk.Snapshot snapshot) {
            base.snapshot(snapshot);
            
            var paintable = base_picture.get_paintable();
            if (paintable == null) return;
            int tex_width = paintable.get_intrinsic_width();
            int tex_height = paintable.get_intrinsic_height();
            if (tex_width <= 0 || tex_height <= 0) return;
            
            int widget_width = get_width();
            int widget_height = get_height();
            if (widget_width <= 0 || widget_height <= 0) return;
            
            double scale_x = (double)widget_width / tex_width;
            double scale_y = (double)widget_height / tex_height;
            double scale = double.min(scale_x, scale_y);
            int draw_width = (int)(tex_width * scale);
            int draw_height = (int)(tex_height * scale);
            int offset_x = (widget_width - draw_width) / 2;
            int offset_y = (widget_height - draw_height) / 2;
            
            snapshot.save();
            snapshot.translate(Graphene.Point() { x = (float)offset_x, y = (float)offset_y });
            snapshot.scale((float)scale, (float)scale);
            
            draw_radars(snapshot, tex_width, tex_height);
            
            snapshot.restore();
            
            // Draw stick values on screen (absolute window coordinates)
            draw_stick_values_screen(snapshot, tex_width, tex_height, scale, offset_x, offset_y);
        }
        
        private void draw_radars(Gtk.Snapshot snapshot, int tex_width, int tex_height) {
            double scale_x = (double)tex_width / CANVAS_WIDTH;
            double scale_y = (double)tex_height / CANVAS_HEIGHT;
            double canvas_scale = double.min(scale_x, scale_y);
            
            int scaled_width = (int)(CANVAS_WIDTH * canvas_scale);
            int scaled_height = (int)(CANVAS_HEIGHT * canvas_scale);
            int offset_x = (tex_width - scaled_width) / 2;
            int offset_y = (tex_height - scaled_height) / 2;
            
            draw_radar(snapshot, true, LEFT_STICK_CANVAS_X, STICK_CANVAS_Y,
                       canvas_scale, offset_x, offset_y, left_cursor_x, left_cursor_y);
            draw_radar(snapshot, false, RIGHT_STICK_CANVAS_X, STICK_CANVAS_Y,
                       canvas_scale, offset_x, offset_y, right_cursor_x, right_cursor_y);
        }
        
        private void draw_radar(Gtk.Snapshot snapshot, bool is_left, int canvas_x, int canvas_y,
                                double canvas_scale, int offset_x, int offset_y,
                                double cursor_x, double cursor_y) {
            int radar_size = current_radar_size;
            int pos_x = (int)(canvas_x * canvas_scale) - radar_size / 2 + offset_x;
            int pos_y = (int)(canvas_y * canvas_scale) - radar_size / 2 + offset_y;
            
            pos_x = pos_x.clamp(0, (int)(CANVAS_WIDTH * canvas_scale) - radar_size);
            pos_y = pos_y.clamp(0, (int)(CANVAS_HEIGHT * canvas_scale) - radar_size);
            
            snapshot.save();
            snapshot.translate(Graphene.Point() { x = (float)pos_x, y = (float)pos_y });
            
            Gsk.RenderNode? background_node = is_left ? left_radar_background_node : right_radar_background_node;
            if (background_node == null) {
                background_node = create_radar_background_node(radar_size);
                if (is_left) left_radar_background_node = background_node;
                else right_radar_background_node = background_node;
            }
            if (background_node != null) snapshot.append_node(background_node);
            
            if (view_model.deadzone > 0) {
                Gsk.RenderNode? deadzone_node = is_left ? left_deadzone_node : right_deadzone_node;
                if (deadzone_node == null) {
                    deadzone_node = create_deadzone_node(radar_size, view_model.deadzone);
                    if (is_left) left_deadzone_node = deadzone_node;
                    else right_deadzone_node = deadzone_node;
                }
                if (deadzone_node != null) snapshot.append_node(deadzone_node);
            }
            
            Graphene.Rect bounds = Graphene.Rect() { origin = {0,0}, size = { (float)radar_size, (float)radar_size } };
            var cr = snapshot.append_cairo(bounds);
            draw_cursor(cr, radar_size, cursor_x, cursor_y);
            cr = null;
            
            snapshot.restore();
        }
        
        private Gsk.RenderNode? create_radar_background_node(int size) {
            var snapshot = new Gtk.Snapshot();
            Graphene.Rect bounds = Graphene.Rect() { origin = {0,0}, size = { (float)size, (float)size } };
            var cr = snapshot.append_cairo(bounds);
            
            int center = size / 2;
            int radius = (int)(size * 0.45);
            if (radius < 5) return null;
            
            cr.set_source_rgba(0.5, 0.5, 0.5, 0.8);
            cr.set_line_width(1.5);
            cr.arc(center, center, radius, 0, 2 * Math.PI);
            cr.stroke();
            
            cr.set_source_rgba(0.5, 0.5, 0.5, 0.5);
            cr.set_line_width(1.0);
            cr.arc(center, center, radius/2, 0, 2 * Math.PI);
            cr.stroke();
            
            cr.set_source_rgba(0.5, 0.5, 0.5, 0.3);
            cr.set_line_width(1.0);
            cr.move_to(center - radius, center);
            cr.line_to(center + radius, center);
            cr.stroke();
            cr.move_to(center, center - radius);
            cr.line_to(center, center + radius);
            cr.stroke();
            
            cr.set_source_rgba(0.5, 0.5, 0.5, 0.3);
            cr.arc(center, center, radius * 0.03, 0, 2 * Math.PI);
            cr.fill();
            
            cr = null;
            return snapshot.free_to_node();
        }
        
        private Gsk.RenderNode? create_deadzone_node(int size, uint8 deadzone) {
            if (deadzone == 0) return null;
            var snapshot = new Gtk.Snapshot();
            Graphene.Rect bounds = Graphene.Rect() { origin = {0,0}, size = { (float)size, (float)size } };
            var cr = snapshot.append_cairo(bounds);
            
            int center = size / 2;
            int radius = (int)(size * 0.45);
            int deadzone_radius = (int)(radius * deadzone / 100.0);
            if (deadzone_radius > 0) {
                cr.set_source_rgba(1.0, 0.2, 0.2, 0.15);
                cr.arc(center, center, deadzone_radius, 0, 2 * Math.PI);
                cr.fill();
                cr.set_source_rgba(1.0, 0.2, 0.2, 0.8);
                cr.set_line_width(1.5);
                double[] dashes = {4.0, 4.0};
                cr.set_dash(dashes, 0);
                cr.arc(center, center, deadzone_radius, 0, 2 * Math.PI);
                cr.stroke();
                cr.set_dash(null, 0);
            }
            cr = null;
            return snapshot.free_to_node();
        }
        
        private void draw_cursor(Cairo.Context cr, int size, double x, double y) {
            int center = size / 2;
            int radius = (int)(size * 0.45);
            int point_x = center + (int)(x * radius);
            int point_y = center + (int)(y * radius);
            double distance = Math.sqrt(x*x + y*y);
            if (distance > 1.0) {
                point_x = center + (int)((x/distance) * radius);
                point_y = center + (int)((y/distance) * radius);
            }
            double dot_radius = radius * 0.12;
            if (dot_radius < 2) dot_radius = 2;
            double brightness = 0.7 + distance * 0.3;
            
            cr.set_source_rgba(current_accent_color.red * brightness,
                               current_accent_color.green * brightness,
                               current_accent_color.blue * brightness, 0.9);
            cr.arc(point_x, point_y, dot_radius, 0, 2 * Math.PI);
            cr.fill();
            cr.set_source_rgba(1,1,1,0.9);
            cr.set_line_width(2.0);
            cr.arc(point_x, point_y, dot_radius, 0, 2 * Math.PI);
            cr.stroke();
        }
        
        // ==================== METHOD TO REDRAW BUTTON OVERLAY ====================
        protected void queue_button_overlay_draw() {
            if (button_overlay_area != null) {
                button_overlay_area.queue_draw();
            }
        }
        
        // ==================== DISPLAY STICK VALUES (SCREEN COORDINATES) ====================
        private void draw_stick_values_screen(Gtk.Snapshot snapshot, int tex_width, int tex_height, double scale, int offset_x, int offset_y) {
            int widget_width = get_width();
            int widget_height = get_height();
            if (widget_width <= 0 || widget_height <= 0) return;
            
            // Fixed coordinates on canvas for the text (below the radar)
            const int GAP_CANVAS = 5;   // fixed spacing on canvas (in canvas pixels)
            int text_canvas_y = STICK_CANVAS_Y + RADAR_CANVAS_SIZE / 2 + GAP_CANVAS;
            
            // Screen position after scaling and offset
            int left_center_x = (int)(LEFT_STICK_CANVAS_X * scale) + offset_x;
            int right_center_x = (int)(RIGHT_STICK_CANVAS_X * scale) + offset_x;
            int text_y = (int)(text_canvas_y * scale) + offset_y;
            
            // Create Cairo context for the entire widget area
            Graphene.Rect full_bounds = Graphene.Rect() {
                origin = { 0, 0 },
                size = { (float)widget_width, (float)widget_height }
            };
            var cr = snapshot.append_cairo(full_bounds);
            
            cr.select_font_face("Sans", Cairo.FontSlant.NORMAL, Cairo.FontWeight.NORMAL);
            cr.set_font_size(9);
            
            // Left stick text
            int16 lx = view_model.lx;
            int16 ly = view_model.ly;
            string left_text = @"X: $(lx)  Y: $(ly)";
            Cairo.TextExtents extents;
            cr.text_extents(left_text, out extents);
            int left_text_x = left_center_x - (int)(extents.width / 2);
            int left_text_y = text_y + (int)extents.height;
            cr.move_to(left_text_x, left_text_y);
            cr.set_source_rgba(0.5, 0.5, 0.5, 1.0);
            cr.show_text(left_text);
            
            // Right stick text
            int16 rx = view_model.rx;
            int16 ry = view_model.ry;
            string right_text = @"X: $(rx)  Y: $(ry)";
            cr.text_extents(right_text, out extents);
            int right_text_x = right_center_x - (int)(extents.width / 2);
            int right_text_y = text_y + (int)extents.height;
            cr.move_to(right_text_x, right_text_y);
            cr.show_text(right_text);
            
            cr = null;
        }
        
        public void reset_sticks() {
            left_cursor_x = 0.0;
            left_cursor_y = 0.0;
            right_cursor_x = 0.0;
            right_cursor_y = 0.0;
            queue_draw();
        }
        
        public void reload_base_image() { schedule_reload(); }
        
        ~ControllerRenderer() {
            if (reload_timeout != 0) Source.remove(reload_timeout);
            left_radar_background_node = null;
            right_radar_background_node = null;
            left_deadzone_node = null;
            right_deadzone_node = null;
        }
    }
}
