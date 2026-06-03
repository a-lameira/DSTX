/*
 * color-picker-widget.vala - Color picker widget for DSTX GUI
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
 * - Provide RGB and saturation sliders for color selection
 * - Display color preview, hex input, and color bar for hue selection
 * - Manage preset and recent colors
 * - Emit color_changed signal on user interaction
 */

// src/widgets/color-picker-widget.vala

using Gtk;
using Gdk;

namespace Dstx.Widgets {
    public class ColorPickerWidget : Gtk.Box {
        // Internal widgets
        private Gtk.DrawingArea color_preview;
        private Gtk.Entry hex_entry;
        private Gtk.Box quick_colors_box;
        private Gtk.Box recent_colors_box;
        private Gtk.Scale red_scale;
        private Gtk.Scale green_scale;
        private Gtk.Scale blue_scale;
        private Gtk.Scale saturation_scale;
        private Gtk.DrawingArea color_bar;
        
        // Value labels
        private Gtk.Label red_value_label;
        private Gtk.Label green_value_label;
        private Gtk.Label blue_value_label;
        private Gtk.Label saturation_value_label;
        
        // Visibility control widgets
        private Adw.PreferencesGroup recent_group;
        private Gtk.Button clear_recent_button;
        private Gtk.Widget? recent_header_box = null;
        private Gtk.Box? recent_container = null;
        
        private bool updating = false;
        private bool dragging = false;
        
        private Gdk.RGBA _base_rgb;
        private Gdk.RGBA _final_color;
        private double _saturation = 100.0;
        private double _hue = 0.0;
        
        private Gdk.RGBA[] recent_colors;
        private const int MAX_RECENT_COLORS = 10;
        
        // Signals
        public signal void color_changed();
        public signal void recent_colors_cleared();
        public signal void recent_color_added(Gdk.RGBA color);
        
        public Gdk.RGBA current_color {
            get { return _final_color; }
            set {
                if (updating) return;
                _final_color = value;
                update_preview_and_hex();
                color_changed();
            }
        }
        
        public Gdk.RGBA base_rgb {
            get { return _base_rgb; }
            set {
                if (updating) return;
                _base_rgb = value;
                update_hue_from_rgb();
                apply_saturation();
                update_all_displays();
                color_changed();
            }
        }
        
        public double saturation {
            get { return _saturation; }
            set {
                _saturation = value.clamp(0.0, 100.0);
                if (saturation_scale != null) {
                    saturation_scale.set_value(_saturation);
                }
                apply_saturation();
                update_all_displays();
                color_changed();
            }
        }
        
        private Gdk.RGBA[] preset_colors = {
            Gdk.RGBA() { red = 1.0f, green = 0.0f, blue = 0.0f, alpha = 1.0f },
            Gdk.RGBA() { red = 1.0f, green = 0.5f, blue = 0.0f, alpha = 1.0f },
            Gdk.RGBA() { red = 1.0f, green = 1.0f, blue = 0.0f, alpha = 1.0f },
            Gdk.RGBA() { red = 0.0f, green = 1.0f, blue = 0.0f, alpha = 1.0f },
            Gdk.RGBA() { red = 0.0f, green = 1.0f, blue = 1.0f, alpha = 1.0f },
            Gdk.RGBA() { red = 0.0f, green = 0.0f, blue = 1.0f, alpha = 1.0f },
            Gdk.RGBA() { red = 0.5f, green = 0.0f, blue = 1.0f, alpha = 1.0f },
            Gdk.RGBA() { red = 1.0f, green = 0.0f, blue = 1.0f, alpha = 1.0f },
            Gdk.RGBA() { red = 0.5f, green = 0.5f, blue = 0.5f, alpha = 1.0f },
            Gdk.RGBA() { red = 0.0f, green = 0.0f, blue = 0.0f, alpha = 1.0f },
            Gdk.RGBA() { red = 1.0f, green = 1.0f, blue = 1.0f, alpha = 1.0f }
        };
        
        public ColorPickerWidget() {
            Object(orientation: Gtk.Orientation.VERTICAL, spacing: 16);
            
            recent_colors = {};
            
            setup_widgets();
            setup_layout();
            setup_signals();
            setup_css();
            
            build_quick_colors();
            build_recent_colors();
            
            _base_rgb = Gdk.RGBA() { red = 1.0f, green = 1.0f, blue = 1.0f, alpha = 1.0f };
            _saturation = 100.0;
            update_hue_from_rgb();
            apply_saturation();
            update_all_displays();
        }
        
        private void setup_widgets() {
            color_preview = new Gtk.DrawingArea();
            color_preview.set_size_request(64, 64);
            color_preview.set_draw_func(draw_color_preview);
            
            hex_entry = new Gtk.Entry();
            hex_entry.set_width_chars(8);
            hex_entry.set_max_length(7);
            hex_entry.set_placeholder_text(Dstx._("#RRGGBB"));
            hex_entry.add_css_class("monospace");
            hex_entry.set_hexpand(true);
            
            red_scale = create_scale(0, 255, 255);
            green_scale = create_scale(0, 255, 255);
            blue_scale = create_scale(0, 255, 255);
            saturation_scale = create_scale(0, 100, 100);
            
            red_scale.hexpand = true;
            green_scale.hexpand = true;
            blue_scale.hexpand = true;
            saturation_scale.hexpand = true;
            
            red_scale.margin_start = 0;
            red_scale.margin_end = 0;
            green_scale.margin_start = 0;
            green_scale.margin_end = 0;
            blue_scale.margin_start = 0;
            blue_scale.margin_end = 0;
            saturation_scale.margin_start = 0;
            saturation_scale.margin_end = 0;
            
            color_bar = new Gtk.DrawingArea();
            color_bar.set_size_request(-1, 32);
            color_bar.set_draw_func(draw_color_bar);
            color_bar.hexpand = true;
            color_bar.vexpand = false;
            color_bar.halign = Gtk.Align.FILL;
            color_bar.valign = Gtk.Align.FILL;
            
            quick_colors_box = new Gtk.Box(Gtk.Orientation.HORIZONTAL, 4);
            quick_colors_box.margin_top = 4;
            quick_colors_box.margin_bottom = 4;
            quick_colors_box.halign = Gtk.Align.CENTER;
            
            recent_colors_box = new Gtk.Box(Gtk.Orientation.HORIZONTAL, 8);
            recent_colors_box.margin_top = 4;
            recent_colors_box.margin_bottom = 4;
            recent_colors_box.hexpand = true;
            
            clear_recent_button = new Gtk.Button();
            var trash_icon = new Gtk.Image.from_icon_name("user-trash-symbolic");
            trash_icon.set_pixel_size(16);
            clear_recent_button.set_child(trash_icon);
            clear_recent_button.add_css_class("destructive-action");
            clear_recent_button.add_css_class("flat");
            clear_recent_button.set_tooltip_text(Dstx._("Clear all recent colors"));
        }
        
        private Gtk.Scale create_scale(double min, double max, double value) {
            var adj = new Gtk.Adjustment(value, min, max, 1, 10, 0);
            var scale = new Gtk.Scale(Gtk.Orientation.HORIZONTAL, adj);
            scale.set_draw_value(false);
            scale.set_hexpand(true);
            return scale;
        }
        
        private Adw.PreferencesRow create_slider_row(string label, Gtk.Scale scale, out Gtk.Label value_label) {
            var row = new Adw.PreferencesRow();
            
            var container = new Gtk.Box(Gtk.Orientation.HORIZONTAL, 12);
            container.hexpand = true;
            container.margin_start = 16;
            container.margin_end = 16;
            container.margin_top = 8;
            container.margin_bottom = 8;
            
            var label_widget = new Gtk.Label(label);
            label_widget.set_width_chars(10);
            label_widget.set_xalign(0);
            label_widget.hexpand = false;
            
            scale.hexpand = true;
            scale.halign = Gtk.Align.FILL;
            
            var val_label = new Gtk.Label(((int)scale.get_value()).to_string());
            val_label.set_width_chars(4);
            val_label.set_xalign(1);
            value_label = val_label;
            
            scale.value_changed.connect(() => {
                val_label.set_text(((int)scale.get_value()).to_string());
            });
            
            container.append(label_widget);
            container.append(scale);
            container.append(val_label);
            
            row.set_child(container);
            
            return row;
        }
        
        private void setup_layout() {
            // Top row: preview + hex
            var top_row = new Gtk.Box(Gtk.Orientation.HORIZONTAL, 16);
            top_row.halign = Gtk.Align.CENTER;
            top_row.append(color_preview);
            top_row.append(hex_entry);
            this.append(top_row);
            
            // PRESET COLORS GROUP
            var presets_group = new Adw.PreferencesGroup();
            
            var preset_container = new Gtk.Box(Gtk.Orientation.VERTICAL, 6);
            preset_container.margin_start = 16;
            preset_container.margin_end = 16;
            preset_container.margin_top = 8;
            preset_container.margin_bottom = 8;
            
            quick_colors_box.spacing = 4;
            quick_colors_box.halign = Gtk.Align.CENTER;
            
            preset_container.append(quick_colors_box);
            
            var preset_row = new Adw.ActionRow();
            preset_row.set_child(preset_container);
            presets_group.add(preset_row);
            
            this.append(presets_group);
            
            // RECENT COLORS GROUP
            recent_group = new Adw.PreferencesGroup();
            
            recent_container = new Gtk.Box(Gtk.Orientation.VERTICAL, 6);
            recent_container.margin_start = 16;
            recent_container.margin_end = 16;
            recent_container.margin_top = 8;
            recent_container.margin_bottom = 8;
            recent_container.hexpand = true;
            
            // Header (title + button) using CenterBox
            var header_box = new Gtk.CenterBox();
            header_box.set_halign(Gtk.Align.FILL);
            header_box.set_hexpand(true);
            header_box.add_css_class("recent-header-box");
            
            var title_label = new Gtk.Label(null);
            title_label.set_markup("<span weight='normal'>%s</span>".printf(Dstx._("Recent Colors")));
            title_label.set_halign(Gtk.Align.START);
            
            header_box.set_start_widget(title_label);
            header_box.set_end_widget(clear_recent_button);
            header_box.visible = false; // initially invisible
            
            recent_container.append(header_box);
            recent_container.append(recent_colors_box);
            
            // Store reference for visibility control
            recent_header_box = header_box;
            
            var recent_row = new Adw.ActionRow();
            recent_row.set_child(recent_container);
            recent_group.add(recent_row);
            
            this.append(recent_group);
            
            // RGB GROUP
            var rgb_group = new Adw.PreferencesGroup();
            
            var red_row = create_slider_row(Dstx._("Red"), red_scale, out red_value_label);
            var green_row = create_slider_row(Dstx._("Green"), green_scale, out green_value_label);
            var blue_row = create_slider_row(Dstx._("Blue"), blue_scale, out blue_value_label);
            
            rgb_group.add(red_row);
            rgb_group.add(green_row);
            rgb_group.add(blue_row);
            
            this.append(rgb_group);
            
            // SATURATION GROUP
            var sat_group = new Adw.PreferencesGroup();
            
            var saturation_row = create_slider_row(Dstx._("Saturation"), saturation_scale, out saturation_value_label);
            sat_group.add(saturation_row);
            
            this.append(sat_group);
            
            // COLOR BAR GROUP
            var colorbar_group = new Adw.PreferencesGroup();
            
            var colorbar_row = new Adw.PreferencesRow();
            
            var colorbar_container = new Gtk.Box(Gtk.Orientation.HORIZONTAL, 0);
            colorbar_container.margin_start = 0;
            colorbar_container.margin_end = 0;
            colorbar_container.margin_top = 0;
            colorbar_container.margin_bottom = 0;
            colorbar_container.hexpand = true;
            colorbar_container.vexpand = false;
            colorbar_container.halign = Gtk.Align.FILL;
            colorbar_container.valign = Gtk.Align.CENTER;
            colorbar_container.height_request = 32;
            colorbar_container.append(color_bar);
            
            colorbar_row.set_child(colorbar_container);
            colorbar_group.add(colorbar_row);
            
            this.append(colorbar_group);
        }
        
        private void build_quick_colors() {
            while (true) {
                var child = quick_colors_box.get_first_child();
                if (child == null) break;
                quick_colors_box.remove(child);
            }
            
            foreach (var color in preset_colors) {
                var color_btn = create_color_button(color);
                quick_colors_box.append(color_btn);
            }
            
            quick_colors_box.visible = true;
        }
        
        private void build_recent_colors() {
            while (true) {
                var child = recent_colors_box.get_first_child();
                if (child == null) break;
                recent_colors_box.remove(child);
            }
            
            if (recent_colors.length == 0) {
                var center_box = new Gtk.Box(Gtk.Orientation.HORIZONTAL, 0);
                center_box.hexpand = true;
                center_box.halign = Gtk.Align.CENTER;
                center_box.valign = Gtk.Align.CENTER;
                
                var empty_label = new Gtk.Label(Dstx._("No recent colors"));
                empty_label.add_css_class("dim-label");
                empty_label.add_css_class("caption");
                empty_label.margin_top = 8;
                empty_label.margin_bottom = 8;
                empty_label.hexpand = true;
                empty_label.halign = Gtk.Align.CENTER;
                
                center_box.append(empty_label);
                recent_colors_box.append(center_box);
                recent_colors_box.halign = Gtk.Align.CENTER;
                if (recent_header_box != null) {
                    recent_header_box.visible = false;
                }
                return;
            }
            
            if (recent_header_box != null) {
                recent_header_box.visible = true;
            }
            recent_colors_box.halign = Gtk.Align.START;
            
            for (int i = recent_colors.length - 1; i >= 0; i--) {
                var color = recent_colors[i];
                var color_btn = create_color_button(color);
                recent_colors_box.append(color_btn);
            }
        }
        
        private Gtk.Button create_color_button(Gdk.RGBA color) {
            var button = new Gtk.Button();
            button.set_size_request(32, 32);
            button.add_css_class("flat");
            button.add_css_class("color-swatch-btn");
            
            string button_style_css = """
                button.color-swatch-btn {
                    background: transparent;
                    border: none;
                    padding: 0;
                    margin: 0;
                }
                button.color-swatch-btn:hover {
                    background-color: transparent;
                    box-shadow: none;
                }
            """;
            
            try {
                var style_provider = new Gtk.CssProvider();
                style_provider.load_from_string(button_style_css);
                button.get_style_context().add_provider(style_provider, Gtk.STYLE_PROVIDER_PRIORITY_USER);
            } catch (Error e) {
                warning("ColorPickerWidget: Error removing hover: %s", e.message);
            }
            
            var drawing = new Gtk.DrawingArea();
            drawing.set_size_request(36, 36);
            drawing.set_margin_start(2);
            drawing.set_margin_end(2);
            drawing.set_margin_top(2);
            drawing.set_margin_bottom(2);
            drawing.add_css_class("color-swatch");
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
            });
            
            button.clicked.connect(() => {
                base_rgb = btn_color;
                saturation = 100.0;
                drawing.queue_draw();
                
                Timeout.add(100, () => {
                    drawing.queue_draw();
                    return Source.REMOVE;
                });
            });
            
            button.set_halign(Gtk.Align.CENTER);
            
            return button;
        }
        
        private void add_to_recent_colors(Gdk.RGBA color) {
            int existing_index = -1;
            for (int i = 0; i < recent_colors.length; i++) {
                var c = recent_colors[i];
                if (c.red == color.red && c.green == color.green && c.blue == color.blue) {
                    existing_index = i;
                    break;
                }
            }
            
            if (existing_index >= 0) {
                Gdk.RGBA[] new_array = {};
                for (int i = 0; i < recent_colors.length; i++) {
                    if (i != existing_index) {
                        new_array += recent_colors[i];
                    }
                }
                recent_colors = new_array;
            }
            
            recent_colors += color;
            
            while (recent_colors.length > MAX_RECENT_COLORS) {
                Gdk.RGBA[] new_array = {};
                for (int i = 1; i < recent_colors.length; i++) {
                    new_array += recent_colors[i];
                }
                recent_colors = new_array;
            }
            
            build_recent_colors();
            recent_color_added(color);
        }
        
        private void setup_signals() {
            hex_entry.activate.connect(() => update_from_hex());
            
            red_scale.value_changed.connect(() => {
                if (!updating) update_base_from_sliders();
            });
            green_scale.value_changed.connect(() => {
                if (!updating) update_base_from_sliders();
            });
            blue_scale.value_changed.connect(() => {
                if (!updating) update_base_from_sliders();
            });
            saturation_scale.value_changed.connect(() => {
                if (!updating) saturation = saturation_scale.get_value();
            });
            
            var gesture_click = new Gtk.GestureClick();
            gesture_click.pressed.connect(on_colorbar_pressed);
            gesture_click.released.connect(on_colorbar_released);
            color_bar.add_controller(gesture_click);
            
            var gesture_motion = new Gtk.EventControllerMotion();
            gesture_motion.motion.connect(on_colorbar_motion);
            color_bar.add_controller(gesture_motion);
            
            clear_recent_button.clicked.connect(() => {
                clear_recent_colors();
            });
        }
        
        public void clear_recent_colors() {
            recent_colors = {};
            build_recent_colors();
            if (recent_header_box != null) {
                recent_header_box.visible = false;
            }
            recent_colors_cleared();
        }
        
        private void update_from_hex() {
            string hex = hex_entry.get_text();
            if (hex.has_prefix("#")) hex = hex.substring(1);
            
            if (hex.length == 6) {
                uint8 r = 0, g = 0, b = 0;
                bool valid = true;
                
                for (int i = 0; i < 6; i++) {
                    char c = hex[i];
                    uint8 val = 0;
                    if (c >= '0' && c <= '9') val = (uint8)(c - '0');
                    else if (c >= 'A' && c <= 'F') val = (uint8)(c - 'A' + 10);
                    else if (c >= 'a' && c <= 'f') val = (uint8)(c - 'a' + 10);
                    else { valid = false; break; }
                    
                    if (i < 2) r = (uint8)((r << 4) | val);
                    else if (i < 4) g = (uint8)((g << 4) | val);
                    else b = (uint8)((b << 4) | val);
                }
                
                if (valid) {
                    var new_color = Gdk.RGBA() {
                        red = r / 255.0f, green = g / 255.0f, blue = b / 255.0f, alpha = 1.0f
                    };
                    base_rgb = new_color;
                }
            }
        }
        
        private void update_base_from_sliders() {
            if (updating) return;
            
            _base_rgb = Gdk.RGBA() {
                red = (float)(red_scale.get_value() / 255.0),
                green = (float)(green_scale.get_value() / 255.0),
                blue = (float)(blue_scale.get_value() / 255.0),
                alpha = 1.0f
            };
            
            update_hue_from_rgb();
            apply_saturation();
            update_all_displays();
            color_changed();
        }
        
        private void update_hue_from_rgb() {
            double r = _base_rgb.red;
            double g = _base_rgb.green;
            double b = _base_rgb.blue;
            
            double max = double.max(r, double.max(g, b));
            double min = double.min(r, double.min(g, b));
            double delta = max - min;
            
            if (delta == 0) {
                _hue = 0;
                return;
            }
            
            if (max == r) {
                double hue = (g - b) / delta;
                if (hue < 0) hue += 6;
                _hue = 60 * hue;
            } else if (max == g) {
                _hue = 60 * ((b - r) / delta + 2);
            } else {
                _hue = 60 * ((r - g) / delta + 4);
            }
            
            if (_hue < 0) _hue += 360;
            if (_hue >= 360) _hue -= 360;
        }
        
        private void apply_saturation() {
            double sat = _saturation / 100.0;
            double r = _base_rgb.red;
            double g = _base_rgb.green;
            double b = _base_rgb.blue;
            
            double luminance = 0.299 * r + 0.587 * g + 0.114 * b;
            
            double new_r = luminance + (r - luminance) * sat;
            double new_g = luminance + (g - luminance) * sat;
            double new_b = luminance + (b - luminance) * sat;
            
            if (new_r < 0) new_r = 0; if (new_r > 1) new_r = 1;
            if (new_g < 0) new_g = 0; if (new_g > 1) new_g = 1;
            if (new_b < 0) new_b = 0; if (new_b > 1) new_b = 1;
            
            _final_color = Gdk.RGBA() {
                red = (float)new_r, green = (float)new_g, blue = (float)new_b, alpha = 1.0f
            };
        }
        
        private void update_all_displays() {
            updating = true;
            
            color_preview.queue_draw();
            
            string hex = "#%02X%02X%02X".printf(
                (uint8)(_final_color.red * 255),
                (uint8)(_final_color.green * 255),
                (uint8)(_final_color.blue * 255)
            );
            hex_entry.set_text(hex);
            
            red_scale.set_value(_base_rgb.red * 255);
            green_scale.set_value(_base_rgb.green * 255);
            blue_scale.set_value(_base_rgb.blue * 255);
            saturation_scale.set_value(_saturation);
            
            if (red_value_label != null) red_value_label.set_text(((int)(_base_rgb.red * 255)).to_string());
            if (green_value_label != null) green_value_label.set_text(((int)(_base_rgb.green * 255)).to_string());
            if (blue_value_label != null) blue_value_label.set_text(((int)(_base_rgb.blue * 255)).to_string());
            if (saturation_value_label != null) saturation_value_label.set_text(((int)_saturation).to_string());
            
            color_bar.queue_draw();
            
            updating = false;
        }
        
        private void update_preview_and_hex() {
            color_preview.queue_draw();
            string hex = "#%02X%02X%02X".printf(
                (uint8)(_final_color.red * 255),
                (uint8)(_final_color.green * 255),
                (uint8)(_final_color.blue * 255)
            );
            hex_entry.set_text(hex);
        }
        
        private void draw_color_bar(Gtk.DrawingArea area, Cairo.Context cr, int width, int height) {
            if (width <= 1 || height <= 1) return;
            
            double radius = height / 3.0;
            var pattern = new Cairo.Pattern.linear(0, 0, width, 0);
            
            for (int i = 0; i <= 360; i += 30) {
                double position = i / 360.0;
                double r, g, b;
                hsl_to_rgb(position, 1.0, 0.5, out r, out g, out b);
                pattern.add_color_stop_rgb(position, r, g, b);
            }
            
            cr.new_path();
            cr.move_to(radius, 0);
            cr.line_to(width - radius, 0);
            cr.arc(width - radius, radius, radius, -Math.PI / 2, 0);
            cr.line_to(width, height - radius);
            cr.arc(width - radius, height - radius, radius, 0, Math.PI / 2);
            cr.line_to(radius, height);
            cr.arc(radius, height - radius, radius, Math.PI / 2, Math.PI);
            cr.line_to(0, radius);
            cr.arc(radius, radius, radius, Math.PI, 3 * Math.PI / 2);
            cr.close_path();
            
            cr.set_source(pattern);
            cr.fill_preserve();
            
            cr.set_source_rgba(0.5, 0.5, 0.5, 0.3);
            cr.set_line_width(1.0);
            cr.stroke();
            
            int indicator_x = (int)(_hue / 360.0 * width);
            indicator_x = indicator_x.clamp(0, width - 1);
            
            int line_width = 3;
            int border_width = 1;
            int total_width = line_width + 2 * border_width;
            int start_x = indicator_x - total_width / 2;
            
            if (start_x < 0) start_x = 0;
            if (start_x + total_width > width) start_x = width - total_width;
            
            cr.set_source_rgb(0.0, 0.0, 0.0);
            cr.rectangle(start_x, 0, total_width, height);
            cr.fill();
            
            cr.set_source_rgb(1.0, 1.0, 1.0);
            cr.rectangle(start_x + border_width, 0, line_width, height);
            cr.fill();
        }
        
        private void hsl_to_rgb(double h, double s, double l, out double r, out double g, out double b) {
            if (s == 0) {
                r = l; g = l; b = l;
                return;
            }
            
            double hue2rgb(double p, double q, double t) {
                if (t < 0) t += 1;
                if (t > 1) t -= 1;
                if (t < 1.0/6.0) return p + (q - p) * 6 * t;
                if (t < 1.0/2.0) return q;
                if (t < 2.0/3.0) return p + (q - p) * (2.0/3.0 - t) * 6;
                return p;
            }
            
            double q = l < 0.5 ? l * (1 + s) : l + s - l * s;
            double p = 2 * l - q;
            
            r = hue2rgb(p, q, h + 1.0/3.0);
            g = hue2rgb(p, q, h);
            b = hue2rgb(p, q, h - 1.0/3.0);
        }
        
        private void update_color_from_bar_position(int x, int width) {
            if (width <= 0) return;
            
            double new_hue = (double)x / width * 360.0;
            new_hue = new_hue.clamp(0.0, 360.0);
            
            if (_hue != new_hue) {
                _hue = new_hue;
                double r, g, b;
                hsl_to_rgb(_hue / 360.0, 1.0, 0.5, out r, out g, out b);
                if (!updating) {
                    var new_color = Gdk.RGBA() { red = (float)r, green = (float)g, blue = (float)b, alpha = 1.0f };
                    base_rgb = new_color;
                }
            }
        }
        
        private void on_colorbar_pressed(Gtk.GestureClick gesture, int n_press, double x, double y) {
            int width = color_bar.get_width();
            if (width > 0) {
                dragging = true;
                update_color_from_bar_position((int)x, width);
            }
        }
        
        private void on_colorbar_released(Gtk.GestureClick gesture, int n_press, double x, double y) {
            dragging = false;
        }
        
        private void on_colorbar_motion(Gtk.EventControllerMotion motion, double x, double y) {
            if (dragging) {
                int width = color_bar.get_width();
                if (width > 0) {
                    update_color_from_bar_position((int)x, width);
                }
            }
        }
        
        private void setup_css() {
            string css = """
                .color-preview-circle {
                    background: none;
                    border: none;
                }
                .monospace {
                    font-family: monospace;
                }
                .recent-header-box {
                    min-height: 32px;
                }
                .recent-header-box label {
                    font-size: 0.85em;
                    font-weight: normal;
                }
                .recent-header-box button {
                    padding: 2px 6px;
                    min-height: 24px;
                    font-size: 0.8em;
                }
            """;
            
            var provider = new Gtk.CssProvider();
            try {
                provider.load_from_string(css);
                var display = Gdk.Display.get_default();
                if (display != null) {
                    Gtk.StyleContext.add_provider_for_display(display, provider, Gtk.STYLE_PROVIDER_PRIORITY_APPLICATION);
                }
            } catch (Error e) {
                warning("ColorPickerWidget: Error loading CSS: %s", e.message);
            }
            color_preview.add_css_class("color-preview-circle");
        }
        
        private void draw_color_preview(Gtk.DrawingArea area, Cairo.Context cr, int width, int height) {
            int size = int.min(width, height);
            int x = (width - size) / 2;
            int y = (height - size) / 2;
            
            cr.set_source_rgba(_final_color.red, _final_color.green, _final_color.blue, 1.0);
            cr.arc(x + size/2, y + size/2, size/2 - 3, 0, 2 * Math.PI);
            cr.fill();
            
            cr.set_source_rgba(0.5, 0.5, 0.5, 0.5);
            cr.set_line_width(2.0);
            cr.arc(x + size/2, y + size/2, size/2 - 3, 0, 2 * Math.PI);
            cr.stroke();
        }
        
        private void draw_color_swatch(Gtk.DrawingArea area, Cairo.Context cr, int width, int height, Gdk.RGBA color) {
            int size = int.min(width, height);
            int x = (width - size) / 2;
            int y = (height - size) / 2;
            
            cr.set_source_rgba(color.red, color.green, color.blue, 1.0);
            cr.arc(x + size/2, y + size/2, size/2 - 2, 0, 2 * Math.PI);
            cr.fill();
            
            cr.set_source_rgba(0.5, 0.5, 0.5, 0.5);
            cr.set_line_width(1.0);
            cr.arc(x + size/2, y + size/2, size/2 - 2, 0, 2 * Math.PI);
            cr.stroke();
        }
        
        private string get_color_name(Gdk.RGBA color) {
            if (color.red > 0.9 && color.green < 0.1 && color.blue < 0.1) return "Red";
            if (color.red > 0.9 && color.green > 0.4 && color.blue < 0.1) return "Orange";
            if (color.red > 0.9 && color.green > 0.9 && color.blue < 0.1) return "Yellow";
            if (color.red < 0.1 && color.green > 0.9 && color.blue < 0.1) return "Green";
            if (color.red < 0.1 && color.green > 0.9 && color.blue > 0.9) return "Cyan";
            if (color.red < 0.1 && color.green < 0.1 && color.blue > 0.9) return "Blue";
            if (color.red > 0.4 && color.red < 0.6 && color.green < 0.1 && color.blue > 0.9) return "Violet";
            if (color.red > 0.9 && color.green < 0.1 && color.blue > 0.9) return "Magenta";
            if (color.red > 0.4 && color.red < 0.6 && color.green > 0.4 && color.green < 0.6 && color.blue > 0.4 && color.blue < 0.6) return "Gray";
            if (color.red < 0.1 && color.green < 0.1 && color.blue < 0.1) return "Black";
            if (color.red > 0.9 && color.green > 0.9 && color.blue > 0.9) return "White";
            return "Custom";
        }
        
        public void set_rgb(uint8 r, uint8 g, uint8 b) {
            var new_color = Gdk.RGBA() { red = r / 255.0f, green = g / 255.0f, blue = b / 255.0f, alpha = 1.0f };
            base_rgb = new_color;
            saturation = 100.0;
        }
        
        public void set_rgb_with_saturation(uint8 r, uint8 g, uint8 b, double sat) {
            var new_color = Gdk.RGBA() { red = r / 255.0f, green = g / 255.0f, blue = b / 255.0f, alpha = 1.0f };
            base_rgb = new_color;
            saturation = sat;
        }
        
        public void set_base_rgb_and_saturation(Gdk.RGBA rgb_base, double sat) {
            if (updating) return;
            _base_rgb = rgb_base;
            _saturation = sat.clamp(0.0, 100.0);
            update_hue_from_rgb();
            apply_saturation();
            update_all_displays();
            color_changed();
        }
        
        public void get_rgb(out uint8 r, out uint8 g, out uint8 b) {
            r = (uint8)(_final_color.red * 255);
            g = (uint8)(_final_color.green * 255);
            b = (uint8)(_final_color.blue * 255);
        }
        
        public void get_base_rgb_values(out uint8 r, out uint8 g, out uint8 b) {
            r = (uint8)(_base_rgb.red * 255);
            g = (uint8)(_base_rgb.green * 255);
            b = (uint8)(_base_rgb.blue * 255);
        }
        
        public Gdk.RGBA[] get_recent_colors() {
            return recent_colors;
        }
        
        public void set_recent_colors(Gdk.RGBA[] colors) {
            recent_colors = {};
            foreach (var color in colors) {
                recent_colors += color;
            }
            build_recent_colors();
        }
        
        public void add_recent_color(Gdk.RGBA color) {
            add_to_recent_colors(color);
        }
        
        public bool is_preset_color(Gdk.RGBA color) {
            double tolerance = 0.02;
            
            foreach (var preset in preset_colors) {
                if (Math.fabs(preset.red - color.red) <= tolerance &&
                    Math.fabs(preset.green - color.green) <= tolerance &&
                    Math.fabs(preset.blue - color.blue) <= tolerance) {
                    return true;
                }
            }
            return false;
        }
    }
}
