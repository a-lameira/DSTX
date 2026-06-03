/*
 * controller-card.vala - Widget for displaying controller information in a card format
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
 * - Display controller information (type, connection, emulation status, battery)
 * - Update UI reactively when controller properties change
 * - Throttle updates to avoid excessive redraws
 */

// src/widgets/controller-card.vala

using Dstx.Models;

namespace Dstx.Widgets {
    public class ControllerCard : Adw.ActionRow {
        private Gtk.Image type_icon;
        private Gtk.Label name_label;
        private Gtk.Label connection_label;
        private Gtk.Label emulation_label;
        private Gtk.Label battery_label;
        private Gtk.DrawingArea battery_drawing_area;
        
        private Controller _controller;
        private uint64 _controller_version = 0;
        
        private List<ulong> signal_handlers;
        private uint update_timeout_id = 0;
        private const uint UPDATE_RATE_MS = 50;
        
        private bool battery_dirty = false;
        private bool connection_dirty = false;
        private bool emulation_dirty = false;
        private bool type_dirty = false;
        
        private int cached_battery = -1;
        private bool cached_is_bluetooth = false;
        private bool cached_emulate_active = false;
        private ControllerType cached_type;
        
        public Controller controller {
            get { return _controller; }
            set {
                if (_controller != null) disconnect_signals();
                _controller = value;
                _controller_version = value.version;
                cached_battery = value.battery;
                cached_is_bluetooth = value.is_bluetooth;
                cached_emulate_active = value.emulate_active;
                cached_type = value.controller_type;
                connect_signals();
                update_all();
            }
        }
        
        public ControllerCard(Controller controller) {
            Object();
            signal_handlers = new List<ulong>();
            add_css_class("controller-card");
            build_ui();
            this.controller = controller;
        }
        
        private void build_ui() {
            var main_box = new Gtk.Box(Gtk.Orientation.HORIZONTAL, 12);
            main_box.set_margin_top(12);
            main_box.set_margin_bottom(12);
            main_box.set_margin_start(16);
            main_box.set_margin_end(16);
            
            type_icon = new Gtk.Image();
            type_icon.set_pixel_size(32);
            type_icon.valign = Gtk.Align.START;
            type_icon.add_css_class("controller-icon");
            main_box.append(type_icon);
            
            var info_box = new Gtk.Box(Gtk.Orientation.VERTICAL, 4);
            info_box.hexpand = true;
            
            name_label = new Gtk.Label("");
            name_label.halign = Gtk.Align.START;
            name_label.ellipsize = Pango.EllipsizeMode.END;
            name_label.max_width_chars = 20;
            name_label.add_css_class("controller-name");
            info_box.append(name_label);
            
            connection_label = new Gtk.Label("");
            connection_label.halign = Gtk.Align.START;
            connection_label.add_css_class("connection-status");
            connection_label.add_css_class("caption");
            info_box.append(connection_label);
            
            emulation_label = new Gtk.Label("");
            emulation_label.halign = Gtk.Align.START;
            emulation_label.add_css_class("emulation-status");
            emulation_label.add_css_class("caption");
            info_box.append(emulation_label);
            
            var battery_container = new Gtk.Box(Gtk.Orientation.HORIZONTAL, 8);
            battery_container.halign = Gtk.Align.START;
            
            battery_drawing_area = new Gtk.DrawingArea();
            battery_drawing_area.set_size_request(80, 8);
            battery_drawing_area.set_draw_func(draw_battery_level);
            battery_drawing_area.add_css_class("battery-level-custom");
            battery_container.append(battery_drawing_area);
            
            battery_label = new Gtk.Label("");
            battery_label.add_css_class("battery-percentage");
            battery_label.add_css_class("caption");
            battery_label.add_css_class("dim-label");
            battery_container.append(battery_label);
            
            info_box.append(battery_container);
            main_box.append(info_box);
            set_child(main_box);
        }
        
        private void draw_rounded_rectangle(Cairo.Context cr, double x, double y, double w, double h, double r) {
            if (r <= 0) {
                cr.rectangle(x, y, w, h);
                return;
            }
            cr.move_to(x + r, y);
            cr.line_to(x + w - r, y);
            cr.arc(x + w - r, y + r, r, -Math.PI/2, 0);
            cr.line_to(x + w, y + h - r);
            cr.arc(x + w - r, y + h - r, r, 0, Math.PI/2);
            cr.line_to(x + r, y + h);
            cr.arc(x + r, y + h - r, r, Math.PI/2, Math.PI);
            cr.line_to(x, y + r);
            cr.arc(x + r, y + r, r, Math.PI, 3*Math.PI/2);
            cr.close_path();
        }
        
        private void draw_battery_level(Gtk.DrawingArea area, Cairo.Context cr, int width, int height) {
            if (_controller == null) return;
            
            double radius = 10.0;
            
            // Background
            cr.set_source_rgba(0.5, 0.5, 0.5, 0.3);
            draw_rounded_rectangle(cr, 0, 0, width, height, radius);
            cr.fill();
            
            int battery = _controller.battery;
            double fraction = battery / 100.0;
            int fill_width = (int)(width * fraction);
            if (fill_width <= 0) return;
            
            Gdk.RGBA color;
            if (battery < 30) {
                color = Gdk.RGBA() { red = 0.956f, green = 0.262f, blue = 0.212f, alpha = 1.0f }; // Red: low battery
            } else if (battery < 80) {
                color = Gdk.RGBA() { red = 1.0f, green = 0.922f, blue = 0.231f, alpha = 1.0f }; // Yellow: medium battery
            } else {
                color = Gdk.RGBA() { red = 0.180f, green = 0.760f, blue = 0.494f, alpha = 1.0f }; // Green: full battery
            }
            cr.set_source_rgba(color.red, color.green, color.blue, 1.0);
            draw_rounded_rectangle(cr, 0, 0, fill_width, height, radius);
            cr.fill();
        }
        
        private void connect_signals() {
            if (_controller == null) return;
            signal_handlers.append(_controller.notify["battery"].connect((obj, spec) => {
                if (_controller.battery != cached_battery) {
                    cached_battery = _controller.battery;
                    battery_dirty = true;
                    schedule_update();
                }
            }));
            signal_handlers.append(_controller.notify["is-bluetooth"].connect((obj, spec) => {
                if (_controller.is_bluetooth != cached_is_bluetooth) {
                    cached_is_bluetooth = _controller.is_bluetooth;
                    connection_dirty = true;
                    schedule_update();
                }
            }));
            signal_handlers.append(_controller.notify["emulate-active"].connect((obj, spec) => {
                if (_controller.emulate_active != cached_emulate_active) {
                    cached_emulate_active = _controller.emulate_active;
                    emulation_dirty = true;
                    schedule_update();
                }
            }));
            signal_handlers.append(_controller.notify["controller-type"].connect((obj, spec) => {
                if (_controller.controller_type != cached_type) {
                    cached_type = _controller.controller_type;
                    type_dirty = true;
                    schedule_update();
                }
            }));
        }
        
        private void disconnect_signals() {
            foreach (var handler_id in signal_handlers) _controller.disconnect(handler_id);
            signal_handlers = new List<ulong>();
        }
        
        private void schedule_update() {
            if (update_timeout_id != 0) return;
            update_timeout_id = Timeout.add(UPDATE_RATE_MS, () => {
                perform_update();
                update_timeout_id = 0;
                return Source.REMOVE;
            });
        }
        
        private void perform_update() {
            bool needs_redraw = false;
            if (type_dirty) { update_type_icon(); type_dirty = false; needs_redraw = true; }
            if (connection_dirty) { update_connection_label(); connection_dirty = false; needs_redraw = true; }
            if (emulation_dirty) { update_emulation_label(); emulation_dirty = false; needs_redraw = true; }
            if (battery_dirty) { update_battery(); battery_dirty = false; needs_redraw = true; }
            if (needs_redraw) queue_draw();
        }
        
        private void update_all() {
            update_type_icon();
            update_connection_label();
            update_emulation_label();
            update_battery();
            type_dirty = connection_dirty = emulation_dirty = battery_dirty = false;
        }
        
        private void update_type_icon() {
            if (_controller == null) return;
            string icon_name;
            switch (_controller.controller_type) {
                case ControllerType.DS4: icon_name = "ds4-symbolic"; break;
                case ControllerType.DUALSENSE: icon_name = "dualsense-symbolic"; break;
                case ControllerType.NSW_PRO: icon_name = "nsw-pro-symbolic"; break;
                default: icon_name = "gamepad-symbolic"; break;
            }
            type_icon.set_from_icon_name(icon_name);
            name_label.label = _controller.controller_type.to_string();
        }
        
        private void update_connection_label() {
            if (_controller == null) return;
            if (_controller.is_bluetooth) {
                connection_label.set_text(_("Connection: Bluetooth"));
                connection_label.add_css_class("bluetooth");
                connection_label.remove_css_class("usb");
            } else {
                connection_label.set_text(_("Connection: USB"));
                connection_label.add_css_class("usb");
                connection_label.remove_css_class("bluetooth");
            }
        }
        
        private void update_emulation_label() {
            if (_controller == null) return;
            if (_controller.emulate_active) {
                emulation_label.set_text(_("Emulation Active"));
                emulation_label.add_css_class("active");
                emulation_label.remove_css_class("inactive");
            } else {
                emulation_label.set_text(_("Emulation Inactive"));
                emulation_label.add_css_class("inactive");
                emulation_label.remove_css_class("active");
            }
        }
        
        private void update_battery() {
            if (_controller == null) return;
            battery_label.set_text("%d%%".printf(_controller.battery));
            battery_drawing_area.queue_draw();
        }
        
        public void update_from_controller(Controller new_controller) {
            if (new_controller == null || new_controller.version <= _controller_version) return;
            if (new_controller.battery != cached_battery) battery_dirty = true;
            if (new_controller.is_bluetooth != cached_is_bluetooth) connection_dirty = true;
            if (new_controller.emulate_active != cached_emulate_active) emulation_dirty = true;
            if (new_controller.controller_type != cached_type) type_dirty = true;
            _controller = new_controller;
            _controller_version = new_controller.version;
            schedule_update();
        }
        
        ~ControllerCard() {
            if (update_timeout_id != 0) Source.remove(update_timeout_id);
            disconnect_signals();
        }
    }
}
