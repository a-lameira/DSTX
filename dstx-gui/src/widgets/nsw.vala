/*
 * nsw.vala - Nintendo Switch Pro controller rendering widget for DSTX GUI
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
 * - Render Nintendo Switch Pro controller SVG with button overlays
 * - Draw face buttons with correct labels (B, A, Y, X) and colors
 * - Support Xbox layout mapping when emulation is active
 * - Handle Switch layout swapping when layout_mode is set
 * - Draw L3/R3, L1/R1, Share, Options, Touch button, D-pad, PS button
 */

// src/widgets/nsw.vala

using Cairo;
using Dstx.ViewModels;
using Dstx.Renderers;

namespace Dstx.Widgets {
    public class NswWidget : ControllerRenderer {
        // ==================== DIMENSIONS ====================
        protected override int CANVAS_WIDTH { get { return 900; } }
        protected override int CANVAS_HEIGHT { get { return 690; } }
        protected override int LEFT_STICK_CANVAS_X { get { return 320; } }
        protected override int RIGHT_STICK_CANVAS_X { get { return 580; } }
        protected override int STICK_CANVAS_Y { get { return 560; } }
        protected override int LEFT_TRIGGER_CANVAS_X { get { return 0; } }
        protected override int RIGHT_TRIGGER_CANVAS_X { get { return 900; } }
        protected override int TRIGGER_CANVAS_Y { get { return 0; } }
        public override string controller_display_name { get { return "Nintendo Switch Pro"; } }

        // ==================== PHYSICAL COORDINATES ====================
        private const int A_X = 689;
        private const int A_Y = 251;
        private const int B_X = 760;
        private const int B_Y = 190;
        private const int X_X = 619;
        private const int X_Y = 190;
        private const int Y_X = 690;
        private const int Y_Y = 128;

        private const int L3_X = 202;
        private const int L3_Y = 190;
        private const int R3_X = 570;
        private const int R3_Y = 315;
        private const int PS_X = 515;
        private const int PS_Y = 190;
        private const int SHARE_X = 339;
        private const int SHARE_Y = 122;
        private const int OPTIONS_X = 562;
        private const int OPTIONS_Y = 122;

        private const int FACE_RADIUS_OUTER = 32;
        private const int L3_RADIUS_OUTER = 54;
        private const int L3_RADIUS_INNER = 38;
        private const int PS_RADIUS = 20;
        private const int SHARE_OPTIONS_RADIUS = 20;

        // Default colors (non-emulated)
        private const double PS_COLOR_R = 1.0;
        private const double PS_COLOR_G = 0.33;
        private const double PS_COLOR_B = 0.33;

        // Xbox colors (emulated)
        private const double XBOX_A_R = 0.33;
        private const double XBOX_A_G = 1.0;
        private const double XBOX_A_B = 0.33;
        private const double XBOX_B_R = 1.0;
        private const double XBOX_B_G = 0.33;
        private const double XBOX_B_B = 0.33;
        private const double XBOX_X_R = 0.22;
        private const double XBOX_X_G = 0.44;
        private const double XBOX_X_B = 0.78;
        private const double XBOX_Y_R = 0.78;
        private const double XBOX_Y_G = 0.67;
        private const double XBOX_Y_B = 0.22;

        public NswWidget(ControllerViewModel view_model) {
            base(view_model);
            // Redraw when the switch_layout flag changes
            view_model.layout_mode_changed.connect(() => {
                queue_draw();
                queue_button_overlay_draw();
            });
            // Also redraw if keymap changes
            view_model.keymap_changed.connect(() => {
                queue_draw();
                queue_button_overlay_draw();
            });
        }

        protected override string get_base_svg_path() {
            return "/org/dstx/gui/icons/nsw/base.svg";
        }

        protected override void draw_button_overlay(Cairo.Context cr, int canvas_width, int canvas_height, double scale) {
            if (canvas_width <= 0 || canvas_height <= 0) return;

            draw_face_button(cr, ControllerViewModel.BTN_CROSS, scale);
            draw_face_button(cr, ControllerViewModel.BTN_CIRCLE, scale);
            draw_face_button(cr, ControllerViewModel.BTN_SQUARE, scale);
            draw_face_button(cr, ControllerViewModel.BTN_TRIANGLE, scale);

            draw_l3_r3_button(cr, ControllerViewModel.BTN_L3, L3_X, L3_Y, scale);
            draw_l3_r3_button(cr, ControllerViewModel.BTN_R3, R3_X, R3_Y, scale);
            draw_path_button(cr, ControllerViewModel.BTN_L1, scale);
            draw_path_button(cr, ControllerViewModel.BTN_R1, scale);
            draw_path_button(cr, ControllerViewModel.BTN_SHARE, scale);
            draw_path_button(cr, ControllerViewModel.BTN_OPTIONS, scale);
            draw_path_button(cr, ControllerViewModel.BTN_PS, scale);
            draw_path_button(cr, ControllerViewModel.BTN_TOUCH, scale);
            draw_path_button(cr, ControllerViewModel.BTN_DPAD_UP, scale);
            draw_path_button(cr, ControllerViewModel.BTN_DPAD_DOWN, scale);
            draw_path_button(cr, ControllerViewModel.BTN_DPAD_LEFT, scale);
            draw_path_button(cr, ControllerViewModel.BTN_DPAD_RIGHT, scale);
            draw_dpad_arrows(cr, scale);
        }

        // ==================== FACE BUTTON LOGIC ====================

        private void get_face_coords(int btn, out int x, out int y) {
            bool emulation = view_model.emulate_active;
            bool switch_layout = view_model.layout_mode == 1;  // calculated flag

            if (!emulation) {
                // Non-emulated mode: physical labels (B, A, Y, X) at original positions
                switch (btn) {
                    case ControllerViewModel.BTN_CROSS:   x = A_X; y = A_Y; break;
                    case ControllerViewModel.BTN_CIRCLE:  x = B_X; y = B_Y; break;
                    case ControllerViewModel.BTN_SQUARE:  x = X_X; y = X_Y; break;
                    case ControllerViewModel.BTN_TRIANGLE: x = Y_X; y = Y_Y; break;
                    default: x = 0; y = 0; break;
                }
            } else {
                // Emulated mode (Xbox)
                if (switch_layout) {
                    // Switch layout: swaps physical positions
                    switch (btn) {
                        case ControllerViewModel.BTN_CROSS:   x = B_X; y = B_Y; break;  // south → east
                        case ControllerViewModel.BTN_CIRCLE:  x = A_X; y = A_Y; break;  // east → south
                        case ControllerViewModel.BTN_SQUARE:  x = Y_X; y = Y_Y; break;  // west → north
                        case ControllerViewModel.BTN_TRIANGLE: x = X_X; y = X_Y; break; // north → west
                        default: x = 0; y = 0; break;
                    }
                } else {
                    // Default Xbox layout
                    switch (btn) {
                        case ControllerViewModel.BTN_CROSS:   x = A_X; y = A_Y; break;
                        case ControllerViewModel.BTN_CIRCLE:  x = B_X; y = B_Y; break;
                        case ControllerViewModel.BTN_SQUARE:  x = X_X; y = X_Y; break;
                        case ControllerViewModel.BTN_TRIANGLE: x = Y_X; y = Y_Y; break;
                        default: x = 0; y = 0; break;
                    }
                }
            }
        }

        private string get_face_text(int btn) {
            bool emulation = view_model.emulate_active;
            bool switch_layout = view_model.layout_mode == 1;

            if (!emulation) {
                // Non-emulated mode: physical Switch labels (B, A, Y, X)
                switch (btn) {
                    case ControllerViewModel.BTN_CROSS:   return "B";
                    case ControllerViewModel.BTN_CIRCLE:  return "A";
                    case ControllerViewModel.BTN_SQUARE:  return "Y";
                    case ControllerViewModel.BTN_TRIANGLE: return "X";
                    default: return "";
                }
            } else {
                // Emulated mode (Xbox)
                if (switch_layout) {
                    // Switch layout: labels follow swapped positions
                    // Since coordinates have already been swapped, the label should be the standard Xbox
                    // for the position where the button was drawn.
                    switch (btn) {
                        case ControllerViewModel.BTN_CROSS:   return "A";  // drawn at east position → label A
                        case ControllerViewModel.BTN_CIRCLE:  return "B";  // drawn at south position → label B
                        case ControllerViewModel.BTN_SQUARE:  return "X";  // drawn at north position → label X
                        case ControllerViewModel.BTN_TRIANGLE: return "Y"; // drawn at west position → label Y
                        default: return "";
                    }
                } else {
                    // Default Xbox layout
                    switch (btn) {
                        case ControllerViewModel.BTN_CROSS:   return "A";
                        case ControllerViewModel.BTN_CIRCLE:  return "B";
                        case ControllerViewModel.BTN_SQUARE:  return "X";
                        case ControllerViewModel.BTN_TRIANGLE: return "Y";
                        default: return "";
                    }
                }
            }
        }

        private void set_face_color(Cairo.Context cr, int btn) {
            if (!view_model.emulate_active) {
                cr.set_source_rgba(PS_COLOR_R, PS_COLOR_G, PS_COLOR_B, 0.9);
            } else {
                // Color follows the label (logic identical to get_face_text)
                bool switch_layout = view_model.layout_mode == 1;
                if (switch_layout) {
                    switch (btn) {
                        case ControllerViewModel.BTN_CROSS:
                            cr.set_source_rgba(XBOX_A_R, XBOX_A_G, XBOX_A_B, 0.9);
                            break;
                        case ControllerViewModel.BTN_CIRCLE:
                            cr.set_source_rgba(XBOX_B_R, XBOX_B_G, XBOX_B_B, 0.9);
                            break;
                        case ControllerViewModel.BTN_SQUARE:
                            cr.set_source_rgba(XBOX_X_R, XBOX_X_G, XBOX_X_B, 0.9);
                            break;
                        case ControllerViewModel.BTN_TRIANGLE:
                            cr.set_source_rgba(XBOX_Y_R, XBOX_Y_G, XBOX_Y_B, 0.9);
                            break;
                        default:
                            cr.set_source_rgba(PS_COLOR_R, PS_COLOR_G, PS_COLOR_B, 0.9);
                            break;
                    }
                } else {
                    switch (btn) {
                        case ControllerViewModel.BTN_CROSS:
                            cr.set_source_rgba(XBOX_A_R, XBOX_A_G, XBOX_A_B, 0.9);
                            break;
                        case ControllerViewModel.BTN_CIRCLE:
                            cr.set_source_rgba(XBOX_B_R, XBOX_B_G, XBOX_B_B, 0.9);
                            break;
                        case ControllerViewModel.BTN_SQUARE:
                            cr.set_source_rgba(XBOX_X_R, XBOX_X_G, XBOX_X_B, 0.9);
                            break;
                        case ControllerViewModel.BTN_TRIANGLE:
                            cr.set_source_rgba(XBOX_Y_R, XBOX_Y_G, XBOX_Y_B, 0.9);
                            break;
                        default:
                            cr.set_source_rgba(PS_COLOR_R, PS_COLOR_G, PS_COLOR_B, 0.9);
                            break;
                    }
                }
            }
        }

        private void draw_face_button(Cairo.Context cr, int btn, double scale) {
            if (!view_model.get_button_state(btn)) return;

            int bx, by;
            get_face_coords(btn, out bx, out by);
            if (bx == 0 && by == 0) return;

            double r_outer = FACE_RADIUS_OUTER * scale;
            cr.save();

            set_face_color(cr, btn);
            cr.arc(bx * scale, by * scale, r_outer, 0, 2 * Math.PI);
            cr.fill();

            string text = get_face_text(btn);
            cr.select_font_face("Sans", FontSlant.NORMAL, FontWeight.BOLD);
            cr.set_font_size(r_outer * 0.7);
            Cairo.TextExtents extents;
            cr.text_extents(text, out extents);
            cr.set_source_rgba(0, 0, 0, 0.9);
            cr.move_to(bx * scale - extents.width / 2, by * scale + extents.height / 2);
            cr.show_text(text);
            cr.restore();
        }

        private string get_physical_label(int physical_btn) {
            switch (physical_btn) {
                case ControllerViewModel.BTN_CROSS:   return "B";
                case ControllerViewModel.BTN_CIRCLE:  return "A";
                case ControllerViewModel.BTN_SQUARE:  return "Y";
                case ControllerViewModel.BTN_TRIANGLE: return "X";
                default: return "";
            }
        }

        private void draw_text(Cairo.Context cr, string text, int x, int y, double scale, double r_outer) {
            if (text == "") return;
            cr.select_font_face("Sans", FontSlant.NORMAL, FontWeight.BOLD);
            cr.set_font_size(r_outer * 0.7);
            Cairo.TextExtents extents;
            cr.text_extents(text, out extents);
            cr.set_source_rgba(0, 0, 0, 0.9);
            cr.move_to(x * scale - extents.width / 2, y * scale + extents.height / 2);
            cr.show_text(text);
        }

        // ==================== DRAWING METHODS ====================
        private void draw_l3_r3_button(Cairo.Context cr, int btn, int x, int y, double scale) {
            if (!view_model.get_button_state(btn)) return;

            double r_outer = L3_RADIUS_OUTER * scale;
            double r_inner = L3_RADIUS_INNER * scale;
            cr.save();

            cr.set_source_rgba(0.5, 0, 0, 0.8);
            cr.arc(x * scale, y * scale, r_outer, 0, 2 * Math.PI);
            cr.fill();

            cr.set_source_rgba(PS_COLOR_R, PS_COLOR_G, PS_COLOR_B, 0.9);
            cr.arc(x * scale, y * scale, r_inner, 0, 2 * Math.PI);
            cr.fill();

            cr.set_source_rgba(0, 0, 0, 0.6);
            cr.set_line_width(1.5);
            cr.arc(x * scale, y * scale, r_outer, 0, 2 * Math.PI);
            cr.stroke();
            cr.restore();
        }

        private void draw_share_options(Cairo.Context cr, int btn, double scale) {
            if (!view_model.get_button_state(btn)) return;
            double x = (btn == ControllerViewModel.BTN_SHARE) ? SHARE_X : OPTIONS_X;
            double y = (btn == ControllerViewModel.BTN_SHARE) ? SHARE_Y : OPTIONS_Y;
            double r = SHARE_OPTIONS_RADIUS * scale;
            cr.save();
            cr.set_source_rgba(PS_COLOR_R, PS_COLOR_G, PS_COLOR_B, 0.9);
            cr.arc(x * scale, y * scale, r, 0, 2 * Math.PI);
            cr.fill();
            cr.set_source_rgba(0, 0, 0, 0.6);
            cr.set_line_width(1.5);
            cr.arc(x * scale, y * scale, r, 0, 2 * Math.PI);
            cr.stroke();
            if (btn == ControllerViewModel.BTN_OPTIONS) {
                cr.set_source_rgba(0, 0, 0, 0.9);
                cr.set_line_width(3.0);
                cr.move_to((x - 10) * scale, y * scale);
                cr.line_to((x + 10) * scale, y * scale);
                cr.stroke();
                cr.move_to(x * scale, (y - 10) * scale);
                cr.line_to(x * scale, (y + 10) * scale);
                cr.stroke();
            } else {
                cr.set_source_rgba(0, 0, 0, 0.9);
                cr.set_line_width(3.0);
                cr.move_to((x - 10) * scale, y * scale);
                cr.line_to((x + 10) * scale, y * scale);
                cr.stroke();
            }
            cr.restore();
        }

        private void draw_ps_button(Cairo.Context cr, double scale) {
            if (!view_model.get_button_state(ControllerViewModel.BTN_PS)) return;
            double cx = 514.8 * scale;
            double cy = 189.8 * scale;
            double r = 19.5 * scale;
            cr.save();
            cr.set_source_rgba(PS_COLOR_R, PS_COLOR_G, PS_COLOR_B, 0.9);
            cr.arc(cx, cy, r, 0, 2 * Math.PI);
            cr.fill();
            cr.set_source_rgba(0, 0, 0, 0.6);
            cr.set_line_width(1.5);
            cr.arc(cx, cy, r, 0, 2 * Math.PI);
            cr.stroke();

            double ps_scale = 0.85;
            double px = 99;
            double py = 35;
            cr.set_source_rgba(0.1, 0.1, 0.1, 0.9);
            cr.move_to((506.4 + px) * ps_scale * scale, (198.3 + py) * ps_scale * scale);
            cr.line_to((516.6 + px) * ps_scale * scale, (198.3 + py) * ps_scale * scale);
            cr.line_to((516.6 + px) * ps_scale * scale, (185.5 + py) * ps_scale * scale);
            cr.line_to((520.7 + px) * ps_scale * scale, (185.5 + py) * ps_scale * scale);
            cr.line_to((506.4 + px) * ps_scale * scale, (173.3 + py) * ps_scale * scale);
            cr.line_to((492.0 + px) * ps_scale * scale, (185.5 + py) * ps_scale * scale);
            cr.line_to((496.3 + px) * ps_scale * scale, (185.5 + py) * ps_scale * scale);
            cr.line_to((496.3 + px) * ps_scale * scale, (198.3 + py) * ps_scale * scale);
            cr.close_path();
            cr.fill();

            cr.set_source_rgba(PS_COLOR_R, PS_COLOR_G, PS_COLOR_B, 0.9);
            cr.rectangle(511.7 * scale, 187.8 * scale, 6.5 * scale, 6.0 * scale);
            cr.fill();
            cr.restore();
        }

        private void draw_path_button(Cairo.Context cr, int btn, double scale) {
            if (!view_model.get_button_state(btn)) return;
            cr.save();
            switch (btn) {
                case ControllerViewModel.BTN_L1:
                    cr.set_source_rgba(PS_COLOR_R, PS_COLOR_G, PS_COLOR_B, 0.9);
                    draw_l1_path(cr, scale);
                    cr.fill();
                    break;
                case ControllerViewModel.BTN_R1:
                    cr.set_source_rgba(PS_COLOR_R, PS_COLOR_G, PS_COLOR_B, 0.9);
                    draw_r1_path(cr, scale);
                    cr.fill();
                    break;
                case ControllerViewModel.BTN_SHARE:
                    draw_share_options(cr, ControllerViewModel.BTN_SHARE, scale);
                    break;
                case ControllerViewModel.BTN_OPTIONS:
                    draw_share_options(cr, ControllerViewModel.BTN_OPTIONS, scale);
                    break;
                case ControllerViewModel.BTN_PS:
                    draw_ps_button(cr, scale);
                    break;
                case ControllerViewModel.BTN_TOUCH:
                    draw_touch_button(cr, scale);
                    break;
                case ControllerViewModel.BTN_DPAD_UP:
                    cr.set_source_rgba(PS_COLOR_R, PS_COLOR_G, PS_COLOR_B, 0.9);
                    draw_dpad_up_path(cr, scale);
                    cr.fill();
                    break;
                case ControllerViewModel.BTN_DPAD_DOWN:
                    cr.set_source_rgba(PS_COLOR_R, PS_COLOR_G, PS_COLOR_B, 0.9);
                    draw_dpad_down_path(cr, scale);
                    cr.fill();
                    break;
                case ControllerViewModel.BTN_DPAD_LEFT:
                    cr.set_source_rgba(PS_COLOR_R, PS_COLOR_G, PS_COLOR_B, 0.9);
                    draw_dpad_left_path(cr, scale);
                    cr.fill();
                    break;
                case ControllerViewModel.BTN_DPAD_RIGHT:
                    cr.set_source_rgba(PS_COLOR_R, PS_COLOR_G, PS_COLOR_B, 0.9);
                    draw_dpad_right_path(cr, scale);
                    cr.fill();
                    break;
            }
            cr.restore();
        }
        
        private void draw_touch_button(Cairo.Context cr, double scale) {
            // Coordinates already converted from original viewBox (1060x812) to base canvas (900x690)
            double rect_x = 368.7;
            double rect_y = 172.0;
            double rect_w = 35.3;
            double rect_h = 35.3;
            double rect_rx = 5.94;
            double circle_cx = 386.6;
            double circle_cy = 189.5;
            double circle_r = 11.7;

            // Colors
            double rect_r = 0x80 / 255.0;
            double rect_g = 0.0;
            double rect_b = 0.0;
            double circle_r_r = 1.0;
            double circle_g = 0x55 / 255.0;
            double circle_b = 0x55 / 255.0;
            double stroke_r = 0x2c / 255.0;
            double stroke_g = 0x2c / 255.0;
            double stroke_b = 0x2c / 255.0;

            cr.save();

            // Main rounded rectangle
            cr.set_source_rgba(rect_r, rect_g, rect_b, 0.9);
            draw_rounded_rectangle(cr, rect_x * scale, rect_y * scale, rect_w * scale, rect_h * scale, rect_rx * scale);
            cr.fill();

            // Rectangle border
            cr.set_source_rgba(stroke_r, stroke_g, stroke_b, 0.9);
            cr.set_line_width(2.16051 * scale);
            draw_rounded_rectangle(cr, rect_x * scale, rect_y * scale, rect_w * scale, rect_h * scale, rect_rx * scale);
            cr.stroke();

            // Inner circle
            cr.set_source_rgba(circle_r_r, circle_g, circle_b, 0.9);
            cr.arc(circle_cx * scale, circle_cy * scale, circle_r * scale, 0, 2 * Math.PI);
            cr.fill();

            // Circle border
            cr.set_source_rgba(stroke_r, stroke_g, stroke_b, 0.9);
            cr.set_line_width(0.64662 * scale);
            cr.arc(circle_cx * scale, circle_cy * scale, circle_r * scale, 0, 2 * Math.PI);
            cr.stroke();

            cr.restore();
        }

        private void draw_dpad_arrows(Cairo.Context cr, double scale) {
            if (view_model.get_button_state(ControllerViewModel.BTN_DPAD_UP)) {
                cr.save();
                cr.set_source_rgba(1, 1, 1, 0.9);
                double cx = 311.68 * scale;
                double cy = 265.17 * scale;
                cr.move_to(cx - 4.90 * scale, cy + 8.57 * scale);
                cr.line_to(cx, cy);
                cr.line_to(cx + 4.90 * scale, cy + 8.57 * scale);
                cr.close_path();
                cr.fill();
                cr.restore();
            }
            if (view_model.get_button_state(ControllerViewModel.BTN_DPAD_DOWN)) {
                cr.save();
                cr.set_source_rgba(1, 1, 1, 0.9);
                double cx = 311.68 * scale;
                double cy = 360.83 * scale;
                cr.move_to(cx - 4.90 * scale, cy - 8.57 * scale);
                cr.line_to(cx, cy);
                cr.line_to(cx + 4.90 * scale, cy - 8.57 * scale);
                cr.close_path();
                cr.fill();
                cr.restore();
            }
            if (view_model.get_button_state(ControllerViewModel.BTN_DPAD_LEFT)) {
                cr.save();
                cr.set_source_rgba(1, 1, 1, 0.9);
                double cx = 264.03 * scale;
                double cy = 313.17 * scale;
                cr.move_to(cx + 8.57 * scale, cy - 4.90 * scale);
                cr.line_to(cx, cy);
                cr.line_to(cx + 8.57 * scale, cy + 4.90 * scale);
                cr.close_path();
                cr.fill();
                cr.restore();
            }
            if (view_model.get_button_state(ControllerViewModel.BTN_DPAD_RIGHT)) {
                cr.save();
                cr.set_source_rgba(1, 1, 1, 0.9);
                double cx = 359.34 * scale;
                double cy = 313.17 * scale;
                cr.move_to(cx - 8.57 * scale, cy - 4.90 * scale);
                cr.line_to(cx, cy);
                cr.line_to(cx - 8.57 * scale, cy + 4.90 * scale);
                cr.close_path();
                cr.fill();
                cr.restore();
            }
        }

        // ==================== PATHS ====================
        private void draw_l1_path(Cairo.Context cr, double scale) {
            cr.move_to(99.25 * scale, 75.17 * scale);
            cr.line_to(99.10 * scale, 73.08 * scale);
            cr.line_to(107.79 * scale, 59.00 * scale);
            cr.line_to(113.44 * scale, 50.31 * scale);
            cr.line_to(116.48 * scale, 46.75 * scale);
            cr.line_to(119.51 * scale, 43.92 * scale);
            cr.line_to(129.62 * scale, 36.01 * scale);
            cr.line_to(140.61 * scale, 28.79 * scale);
            cr.line_to(152.12 * scale, 21.88 * scale);
            cr.line_to(160.61 * scale, 18.16 * scale);
            cr.line_to(168.83 * scale, 15.13 * scale);
            cr.line_to(177.15 * scale, 12.83 * scale);
            cr.line_to(188.09 * scale, 10.57 * scale);
            cr.line_to(206.31 * scale, 6.96 * scale);
            cr.line_to(216.99 * scale, 5.24 * scale);
            cr.line_to(226.83 * scale, 4.08 * scale);
            cr.line_to(242.33 * scale, 4.08 * scale);
            cr.line_to(253.69 * scale, 3.21 * scale);
            cr.line_to(262.90 * scale, 2.27 * scale);
            cr.line_to(269.34 * scale, 2.37 * scale);
            cr.line_to(275.36 * scale, 3.42 * scale);
            cr.line_to(280.07 * scale, 5.19 * scale);
            cr.line_to(304.07 * scale, 14.81 * scale);
            cr.line_to(314.44 * scale, 19.62 * scale);
            cr.line_to(314.42 * scale, 23.06 * scale);
            cr.line_to(275.63 * scale, 24.52 * scale);
            cr.line_to(254.27 * scale, 25.59 * scale);
            cr.line_to(238.54 * scale, 27.17 * scale);
            cr.line_to(223.58 * scale, 28.84 * scale);
            cr.line_to(198.53 * scale, 32.49 * scale);
            cr.line_to(190.20 * scale, 34.20 * scale);
            cr.line_to(177.20 * scale, 37.89 * scale);
            cr.line_to(164.43 * scale, 42.17 * scale);
            cr.line_to(153.88 * scale, 46.27 * scale);
            cr.line_to(132.34 * scale, 57.05 * scale);
            cr.close_path();
        }

        private void draw_r1_path(Cairo.Context cr, double scale) {
            cr.move_to(587.63 * scale, 21.87 * scale);
            cr.line_to(587.77 * scale, 18.35 * scale);
            cr.line_to(596.79 * scale, 14.19 * scale);
            cr.line_to(619.39 * scale, 4.63 * scale);
            cr.line_to(625.38 * scale, 2.41 * scale);
            cr.line_to(627.47 * scale, 1.86 * scale);
            cr.line_to(631.30 * scale, 1.15 * scale);
            cr.line_to(634.91 * scale, 0.92 * scale);
            cr.line_to(641.58 * scale, 1.10 * scale);
            cr.line_to(651.63 * scale, 1.67 * scale);
            cr.line_to(665.13 * scale, 2.72 * scale);
            cr.line_to(678.59 * scale, 4.34 * scale);
            cr.line_to(690.22 * scale, 5.73 * scale);
            cr.line_to(700.55 * scale, 7.62 * scale);
            cr.line_to(716.60 * scale, 10.78 * scale);
            cr.line_to(726.00 * scale, 12.96 * scale);
            cr.line_to(731.97 * scale, 14.80 * scale);
            cr.line_to(737.89 * scale, 17.02 * scale);
            cr.line_to(744.87 * scale, 19.98 * scale);
            cr.line_to(751.44 * scale, 23.49 * scale);
            cr.line_to(764.16 * scale, 30.76 * scale);
            cr.line_to(770.75 * scale, 35.73 * scale);
            cr.line_to(778.66 * scale, 41.41 * scale);
            cr.line_to(784.76 * scale, 46.94 * scale);
            cr.line_to(788.66 * scale, 51.49 * scale);
            cr.line_to(794.13 * scale, 59.19 * scale);
            cr.line_to(802.54 * scale, 72.43 * scale);
            cr.line_to(802.58 * scale, 75.10 * scale);
            cr.line_to(779.14 * scale, 61.37 * scale);
            cr.line_to(770.41 * scale, 56.30 * scale);
            cr.line_to(756.56 * scale, 48.89 * scale);
            cr.line_to(739.31 * scale, 41.71 * scale);
            cr.line_to(722.98 * scale, 36.24 * scale);
            cr.line_to(703.11 * scale, 31.46 * scale);
            cr.line_to(685.56 * scale, 28.42 * scale);
            cr.line_to(670.31 * scale, 26.65 * scale);
            cr.line_to(652.09 * scale, 26.65 * scale);
            cr.line_to(636.62 * scale, 25.61 * scale);
            cr.line_to(615.53 * scale, 25.53 * scale);
            cr.close_path();
        }

        private void draw_dpad_up_path(Cairo.Context cr, double scale) {
            cr.move_to(328.74 * scale, 296.12 * scale);
            cr.line_to(311.68 * scale, 313.17 * scale);
            cr.line_to(294.64 * scale, 296.12 * scale);
            cr.line_to(294.64 * scale, 248.41 * scale);
            cr.line_to(328.74 * scale, 248.41 * scale);
            cr.close_path();
        }

        private void draw_dpad_down_path(Cairo.Context cr, double scale) {
            cr.move_to(294.64 * scale, 330.23 * scale);
            cr.line_to(311.68 * scale, 313.17 * scale);
            cr.line_to(328.74 * scale, 330.23 * scale);
            cr.line_to(328.74 * scale, 377.94 * scale);
            cr.line_to(294.64 * scale, 377.94 * scale);
            cr.close_path();
        }

        private void draw_dpad_left_path(Cairo.Context cr, double scale) {
            cr.move_to(294.64 * scale, 296.11 * scale);
            cr.line_to(311.68 * scale, 313.17 * scale);
            cr.line_to(294.64 * scale, 330.23 * scale);
            cr.line_to(246.93 * scale, 330.23 * scale);
            cr.line_to(246.93 * scale, 296.11 * scale);
            cr.close_path();
        }

        private void draw_dpad_right_path(Cairo.Context cr, double scale) {
            cr.move_to(328.74 * scale, 330.23 * scale);
            cr.line_to(311.68 * scale, 313.17 * scale);
            cr.line_to(328.74 * scale, 296.11 * scale);
            cr.line_to(376.45 * scale, 296.11 * scale);
            cr.line_to(376.45 * scale, 330.23 * scale);
            cr.close_path();
        }
        
        private void draw_rounded_rectangle(Cairo.Context cr, double x, double y, double w, double h, double r) {
            cr.move_to(x + r, y);
            cr.line_to(x + w - r, y);
            cr.curve_to(x + w, y, x + w, y, x + w, y + r);
            cr.line_to(x + w, y + h - r);
            cr.curve_to(x + w, y + h, x + w, y + h, x + w - r, y + h);
            cr.line_to(x + r, y + h);
            cr.curve_to(x, y + h, x, y + h, x, y + h - r);
            cr.line_to(x, y + r);
            cr.curve_to(x, y, x, y, x + r, y);
            cr.close_path();
        }
    }
}
