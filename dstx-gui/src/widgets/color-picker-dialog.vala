/*
 * color-picker-dialog.vala - Color selection dialog for DSTX GUI
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
 * - Provide a color selection dialog window
 * - Integrate with ColorPickerWidget
 * - Load and save recent colors via SettingsManager
 * - Emit color_selected and cancelled signals
 */

// src/widgets/color-picker-dialog.vala

using Gtk;
using Gdk;
using Dstx.Core;

namespace Dstx.Widgets {
    /**
     * ColorPickerDialog - Window for color selection
     */
    public class ColorPickerDialog : Adw.Window {
        private ColorPickerWidget color_picker;
        private Gtk.Button cancel_button;
        private Gtk.Button select_button;
        
        private Gdk.RGBA selected_color;
        private Gdk.RGBA selected_base_rgb;
        private double selected_saturation = 100.0;
        
        public signal void color_selected(Gdk.RGBA color);
        public signal void cancelled();
        
        public ColorPickerDialog(Gtk.Window parent, uint8 r, uint8 g, uint8 b, double saturation = 100.0) {
            Object(
                title: Dstx._("Select Color"),
                transient_for: parent,
                modal: true,
                resizable: false,
                default_width: 500,
                default_height: 620
            );
            
            setup_ui(r, g, b, saturation);
            setup_signals();
            
            // Load recent colors from settings
            var settings = SettingsManager.get_default();
            var loaded_colors = settings.get_recent_colors();
            if (loaded_colors.length > 0) {
                color_picker.set_recent_colors(loaded_colors);
            }
        }
        
        private void setup_ui(uint8 r, uint8 g, uint8 b, double saturation) {
            var toolbar_view = new Adw.ToolbarView();
            
            var header = new Adw.HeaderBar();
            header.set_show_start_title_buttons(false);
            header.set_show_end_title_buttons(false);
            
            var title_stack = new Gtk.Stack();
            var title_label = new Adw.WindowTitle(Dstx._("Select Color"), "");
            title_stack.add_named(title_label, "title");
            title_stack.set_visible_child_name("title");
            header.set_title_widget(title_stack);
            
            cancel_button = new Gtk.Button.with_label(Dstx._("Cancel"));
            cancel_button.add_css_class("flat");
            header.pack_start(cancel_button);
            
            select_button = new Gtk.Button.with_label(Dstx._("Apply"));
            select_button.add_css_class("suggested-action");
            header.pack_end(select_button);
            
            toolbar_view.add_top_bar(header);
            
            var content = new Gtk.Box(Gtk.Orientation.VERTICAL, 0);
            content.margin_top = 24;
            content.margin_bottom = 24;
            content.margin_start = 24;
            content.margin_end = 24;
            
            color_picker = new ColorPickerWidget();
            color_picker.set_base_rgb_and_saturation(
                Gdk.RGBA() { red = r/255.0f, green = g/255.0f, blue = b/255.0f, alpha = 1.0f },
                saturation
            );
            
            content.append(color_picker);
            
            var spacer = new Gtk.Box(Gtk.Orientation.VERTICAL, 0);
            spacer.vexpand = true;
            content.append(spacer);
            
            toolbar_view.set_content(content);
            this.set_content(toolbar_view);
        }
        
        private void setup_signals() {
            cancel_button.clicked.connect(() => {
                cancelled();
                this.close();
            });
            
            select_button.clicked.connect(() => {
                uint8 r, g, b;
                uint8 br, bg, bb;
                
                color_picker.get_rgb(out r, out g, out b);
                selected_color = Gdk.RGBA() { 
                    red = r/255.0f, 
                    green = g/255.0f, 
                    blue = b/255.0f, 
                    alpha = 1.0f 
                };
                
                color_picker.get_base_rgb_values(out br, out bg, out bb);
                selected_base_rgb = Gdk.RGBA() { 
                    red = br/255.0f, 
                    green = bg/255.0f, 
                    blue = bb/255.0f, 
                    alpha = 1.0f 
                };
                
                selected_saturation = color_picker.saturation;
                
                if (!color_picker.is_preset_color(selected_color)) {
                    color_picker.add_recent_color(selected_color);
                }
                
                color_selected(selected_color);
                this.close();
            });
            
            var key_controller = new Gtk.EventControllerKey();
            key_controller.key_pressed.connect((keyval, keycode, state) => {
                if (keyval == Gdk.Key.Escape) {
                    cancelled();
                    this.close();
                    return true;
                }
                return false;
            });
            ((Gtk.Widget)this).add_controller(key_controller);
            
            // Connect color_picker signals to persist recent colors
            color_picker.recent_color_added.connect(on_recent_colors_changed);
            color_picker.recent_colors_cleared.connect(on_recent_colors_changed);
        }
        
        private void on_recent_colors_changed() {
            var settings = SettingsManager.get_default();
            settings.set_recent_colors(color_picker.get_recent_colors());
        }
        
        public void get_selected_color(out uint8 r, out uint8 g, out uint8 b) {
            r = (uint8)(selected_color.red * 255);
            g = (uint8)(selected_color.green * 255);
            b = (uint8)(selected_color.blue * 255);
        }
        
        public Gdk.RGBA get_selected_color_rgba() {
            return selected_color;
        }
        
        public void get_base_rgb(out uint8 r, out uint8 g, out uint8 b) {
            r = (uint8)(selected_base_rgb.red * 255);
            g = (uint8)(selected_base_rgb.green * 255);
            b = (uint8)(selected_base_rgb.blue * 255);
        }
        
        public double get_saturation() {
            return selected_saturation;
        }
        
        public Gdk.RGBA get_base_rgb_rgba() {
            return selected_base_rgb;
        }
        
        public Gdk.RGBA[] get_recent_colors() {
            if (color_picker != null) {
                return color_picker.get_recent_colors();
            }
            return {};
        }
        
        public void set_select_button_sensitive(bool sensitive) {
            if (select_button != null) {
                select_button.set_sensitive(sensitive);
            }
        }
        
        public ColorPickerWidget get_color_picker() {
            return color_picker;
        }
        
        public void set_current_color(uint8 r, uint8 g, uint8 b) {
            color_picker.current_color = Gdk.RGBA() {
                red = r / 255.0f,
                green = g / 255.0f,
                blue = b / 255.0f,
                alpha = 1.0f
            };
        }
        
        public uint8[] get_base_rgb_array() {
            uint8 r, g, b;
            get_base_rgb(out r, out g, out b);
            return { r, g, b };
        }
        
        public uint8[] get_current_color_array() {
            uint8 r, g, b;
            color_picker.get_rgb(out r, out g, out b);
            return { r, g, b };
        }
    }
}
