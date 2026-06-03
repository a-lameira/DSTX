/*
 * dualsense.vala - DualSense controller rendering widget for DSTX GUI
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
 * - Render DualSense controller SVG with button overlays
 * - Draw face buttons, L3/R3, L1/R1, Share, Options, Touchpad, D-pad, PS button
 * - Handle button highlighting based on controller state
 * - Support Xbox layout mapping when emulation is active
 */

// src/widgets/dualsense.vala

using Cairo;
using Dstx.ViewModels;
using Dstx.Renderers;

namespace Dstx.Widgets {
    public class DualsenseWidget : ControllerRenderer {
        // ==================== DIMENSIONS ====================
        protected override int CANVAS_WIDTH { get { return 900; } }
        protected override int CANVAS_HEIGHT { get { return 640; } }
        protected override int LEFT_STICK_CANVAS_X { get { return 305; } }
        protected override int RIGHT_STICK_CANVAS_X { get { return 593; } }
        protected override int STICK_CANVAS_Y { get { return 510; } }
        protected override int LEFT_TRIGGER_CANVAS_X { get { return 0; } }
        protected override int RIGHT_TRIGGER_CANVAS_X { get { return 900; } }
        protected override int TRIGGER_CANVAS_Y { get { return 0; } }
        public override string controller_display_name { get { return "DualSense"; } }

        // ==================== BUTTON COORDINATES ====================
        private const int PS_CIRCLE_X = 797;
        private const int PS_CIRCLE_Y = 172;
        private const int PS_CROSS_X = 731;
        private const int PS_CROSS_Y = 239;
        private const int PS_SQUARE_X = 665;
        private const int PS_SQUARE_Y = 172;
        private const int PS_TRIANGLE_X = 731;
        private const int PS_TRIANGLE_Y = 106;

        private const int XBOX_A_X = 731;
        private const int XBOX_A_Y = 238;
        private const int XBOX_B_X = 797;
        private const int XBOX_B_Y = 172;
        private const int XBOX_X_X = 665;
        private const int XBOX_X_Y = 172;
        private const int XBOX_Y_X = 731;
        private const int XBOX_Y_Y = 106;

        private const int L3_X = 306;
        private const int L3_Y = 297;
        private const int R3_X = 593;
        private const int R3_Y = 296;
        private const int PS_X = 451;
        private const int PS_Y = 290;
        private const int SHARE_X = 250;
        private const int SHARE_Y = 79;
        private const int OPTIONS_X = 650;
        private const int OPTIONS_Y = 79;

        private const int FACE_RADIUS_OUTER = 29;
        private const int FACE_RADIUS_MID = 25;
        private const int L3_RADIUS_OUTER = 52;
        private const int L3_RADIUS_INNER = 33;
        private const int PS_RADIUS = 20;
        private const int SHARE_OPTIONS_RADIUS = 20;

        // Colors
        private const double PS_COLOR_R = 1.0;
        private const double PS_COLOR_G = 0.33;
        private const double PS_COLOR_B = 0.33;

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

        public DualsenseWidget(ControllerViewModel view_model) {
            base(view_model);
        }

        protected override string get_base_svg_path() {
            return "/org/dstx/gui/icons/dualsense/base.svg";
        }

        protected override void draw_button_overlay(Cairo.Context cr, int canvas_width, int canvas_height, double scale) {
            if (canvas_width <= 0 || canvas_height <= 0) return;

            if (!view_model.emulate_active) {
                draw_face_button(cr, ControllerViewModel.BTN_CIRCLE, PS_CIRCLE_X, PS_CIRCLE_Y, scale);
                draw_face_button(cr, ControllerViewModel.BTN_CROSS, PS_CROSS_X, PS_CROSS_Y, scale);
                draw_face_button(cr, ControllerViewModel.BTN_SQUARE, PS_SQUARE_X, PS_SQUARE_Y, scale);
                draw_face_button(cr, ControllerViewModel.BTN_TRIANGLE, PS_TRIANGLE_X, PS_TRIANGLE_Y, scale);
            } else {
                draw_face_button(cr, ControllerViewModel.BTN_CIRCLE, XBOX_B_X, XBOX_B_Y, scale);
                draw_face_button(cr, ControllerViewModel.BTN_CROSS, XBOX_A_X, XBOX_A_Y, scale);
                draw_face_button(cr, ControllerViewModel.BTN_SQUARE, XBOX_X_X, XBOX_X_Y, scale);
                draw_face_button(cr, ControllerViewModel.BTN_TRIANGLE, XBOX_Y_X, XBOX_Y_Y, scale);
            }

            draw_l3_r3_button(cr, ControllerViewModel.BTN_L3, L3_X, L3_Y, scale);
            draw_l3_r3_button(cr, ControllerViewModel.BTN_R3, R3_X, R3_Y, scale);
            draw_ps_button(cr, scale);

            draw_path_button(cr, ControllerViewModel.BTN_L1, scale);
            draw_path_button(cr, ControllerViewModel.BTN_R1, scale);
            draw_path_button(cr, ControllerViewModel.BTN_SHARE, scale);
            draw_path_button(cr, ControllerViewModel.BTN_OPTIONS, scale);
            draw_path_button(cr, ControllerViewModel.BTN_TOUCH, scale);
            draw_path_button(cr, ControllerViewModel.BTN_DPAD_UP, scale);
            draw_path_button(cr, ControllerViewModel.BTN_DPAD_DOWN, scale);
            draw_path_button(cr, ControllerViewModel.BTN_DPAD_LEFT, scale);
            draw_path_button(cr, ControllerViewModel.BTN_DPAD_RIGHT, scale);
            draw_dpad_arrows(cr, scale);
        }

        // ==================== DRAWING METHODS ====================
        private void draw_face_button(Cairo.Context cr, int btn, int x, int y, double scale) {
            if (!view_model.get_button_state(btn)) return;

            double r_outer = FACE_RADIUS_OUTER * scale;
            double r_mid = FACE_RADIUS_MID * scale;
            double r_inner = 17 * scale;
            cr.save();

            set_face_color(cr, btn);
            cr.arc(x * scale, y * scale, r_outer, 0, 2 * Math.PI);
            cr.fill();

            cr.set_source_rgba(0, 0, 0, 0.8);
            cr.set_line_width(1.5);
            cr.arc(x * scale, y * scale, r_mid, 0, 2 * Math.PI);
            cr.stroke();

            if (!view_model.emulate_active) {
                cr.set_source_rgba(0, 0, 0, 0.9);
                cr.set_line_width(2.5);
                switch (btn) {
                    case ControllerViewModel.BTN_CIRCLE:
                        cr.arc(x * scale, y * scale, r_inner, 0, 2 * Math.PI);
                        cr.stroke();
                        break;
                    case ControllerViewModel.BTN_CROSS:
                        double offset = r_inner * 0.85;
                        cr.move_to(x * scale - offset, y * scale - offset);
                        cr.line_to(x * scale + offset, y * scale + offset);
                        cr.stroke();
                        cr.move_to(x * scale + offset, y * scale - offset);
                        cr.line_to(x * scale - offset, y * scale + offset);
                        cr.stroke();
                        break;
                    case ControllerViewModel.BTN_SQUARE:
                        double size = r_inner * 1.7;
                        cr.rectangle(x * scale - size/2, y * scale - size/2, size, size);
                        cr.stroke();
                        break;
                    case ControllerViewModel.BTN_TRIANGLE:
                        double offset_x = 0;
                        double offset_y = -4;
                        double side = r_inner * 2.0;
                        double height = side * Math.sqrt(3) / 2;
                        cr.move_to((x + offset_x) * scale, (y + offset_y) * scale - height/2);
                        cr.line_to((x + offset_x) * scale - side/2, (y + offset_y) * scale + height/2);
                        cr.line_to((x + offset_x) * scale + side/2, (y + offset_y) * scale + height/2);
                        cr.close_path();
                        cr.stroke();
                        break;
                }
            } else {
                string text = get_face_text(btn);
                cr.select_font_face("Sans", FontSlant.NORMAL, FontWeight.BOLD);
                cr.set_font_size(r_outer * 0.7);
                Cairo.TextExtents extents;
                cr.text_extents(text, out extents);
                cr.set_source_rgba(0, 0, 0, 0.9);
                cr.move_to(x * scale - extents.width / 2, y * scale + extents.height / 2);
                cr.show_text(text);
            }
            cr.restore();
        }

        private void set_face_color(Cairo.Context cr, int btn) {
            if (!view_model.emulate_active) {
                cr.set_source_rgba(PS_COLOR_R, PS_COLOR_G, PS_COLOR_B, 1.0);
            } else {
                switch (btn) {
                    case ControllerViewModel.BTN_CROSS:
                        cr.set_source_rgba(XBOX_A_R, XBOX_A_G, XBOX_A_B, 1.0);
                        break;
                    case ControllerViewModel.BTN_CIRCLE:
                        cr.set_source_rgba(XBOX_B_R, XBOX_B_G, XBOX_B_B, 1.0);
                        break;
                    case ControllerViewModel.BTN_SQUARE:
                        cr.set_source_rgba(XBOX_X_R, XBOX_X_G, XBOX_X_B, 1.0);
                        break;
                    case ControllerViewModel.BTN_TRIANGLE:
                        cr.set_source_rgba(XBOX_Y_R, XBOX_Y_G, XBOX_Y_B, 1.0);
                        break;
                    default:
                        cr.set_source_rgba(PS_COLOR_R, PS_COLOR_G, PS_COLOR_B, 1.0);
                        break;
                }
            }
        }

        private string get_face_text(int btn) {
            if (!view_model.emulate_active) {
                switch (btn) {
                    case ControllerViewModel.BTN_CROSS: return "✕";
                    case ControllerViewModel.BTN_CIRCLE: return "◯";
                    case ControllerViewModel.BTN_SQUARE: return "□";
                    case ControllerViewModel.BTN_TRIANGLE: return "△";
                    default: return "";
                }
            } else {
                switch (btn) {
                    case ControllerViewModel.BTN_CROSS: return "A";
                    case ControllerViewModel.BTN_CIRCLE: return "B";
                    case ControllerViewModel.BTN_SQUARE: return "X";
                    case ControllerViewModel.BTN_TRIANGLE: return "Y";
                    default: return "";
                }
            }
        }

        private void draw_l3_r3_button(Cairo.Context cr, int btn, int x, int y, double scale) {
            if (!view_model.get_button_state(btn)) return;

            double r_outer = L3_RADIUS_OUTER * scale;
            double r_inner = L3_RADIUS_INNER * scale;
            cr.save();

            cr.set_source_rgba(0, 0, 0, 0.3);
            cr.arc(x * scale + 1, y * scale + 1, r_outer, 0, 2 * Math.PI);
            cr.fill();

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

        private void draw_ps_button(Cairo.Context cr, double scale) {
            if (!view_model.get_button_state(ControllerViewModel.BTN_PS)) return;
            double r = PS_RADIUS * scale;
            cr.save();
            cr.set_source_rgba(0, 0, 0, 0.3);
            cr.arc(PS_X * scale + 1, PS_Y * scale + 1, r, 0, 2 * Math.PI);
            cr.fill();
            cr.set_source_rgba(PS_COLOR_R, PS_COLOR_G, PS_COLOR_B, 0.9);
            cr.arc(PS_X * scale, PS_Y * scale, r, 0, 2 * Math.PI);
            cr.fill();
            cr.set_source_rgba(0, 0, 0, 0.6);
            cr.set_line_width(1.5);
            cr.arc(PS_X * scale, PS_Y * scale, r, 0, 2 * Math.PI);
            cr.stroke();
            cr.restore();
        }

        private void draw_path_button(Cairo.Context cr, int btn, double scale) {
            if (!view_model.get_button_state(btn)) return;
            cr.save();
            switch (btn) {
                case ControllerViewModel.BTN_L1:
                    cr.set_source_rgba(0.5, 0, 0, 0.8);
                    draw_l1_side(cr, scale);
                    cr.fill();
                    cr.set_source_rgba(PS_COLOR_R, PS_COLOR_G, PS_COLOR_B, 0.9);
                    draw_l1_top(cr, scale);
                    cr.fill();
                    break;
                case ControllerViewModel.BTN_R1:
                    cr.set_source_rgba(0.5, 0, 0, 0.8);
                    draw_r1_side(cr, scale);
                    cr.fill();
                    cr.set_source_rgba(PS_COLOR_R, PS_COLOR_G, PS_COLOR_B, 0.9);
                    draw_r1_top(cr, scale);
                    cr.fill();
                    break;
                case ControllerViewModel.BTN_SHARE:
                    cr.set_source_rgba(PS_COLOR_R, PS_COLOR_G, PS_COLOR_B, 0.9);
                    draw_share_path(cr, scale);
                    cr.fill();
                    break;
                case ControllerViewModel.BTN_OPTIONS:
                    cr.set_source_rgba(PS_COLOR_R, PS_COLOR_G, PS_COLOR_B, 0.9);
                    draw_options_path(cr, scale);
                    cr.fill();
                    break;
                case ControllerViewModel.BTN_TOUCH:
                    cr.set_source_rgba(PS_COLOR_R, PS_COLOR_G, PS_COLOR_B, 0.9);
                    draw_touchpad_path(cr, scale);
                    cr.fill();
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

        private void draw_dpad_arrows(Cairo.Context cr, double scale) {
            if (view_model.get_button_state(ControllerViewModel.BTN_DPAD_UP)) {
                cr.save();
                cr.set_source_rgba(1, 1, 1, 0.9);
                double cx = 169.3 * scale;
                double cy = 114.7 * scale;
                cr.move_to(cx - 7.2 * scale, cy + 6.9 * scale);
                cr.line_to(cx, cy);
                cr.line_to(cx + 7.2 * scale, cy + 6.9 * scale);
                cr.close_path();
                cr.fill();
                cr.restore();
            }
            if (view_model.get_button_state(ControllerViewModel.BTN_DPAD_DOWN)) {
                cr.save();
                cr.set_source_rgba(1, 1, 1, 0.9);
                double cx = 169.7 * scale;
                double cy = 230.3 * scale;
                cr.move_to(cx - 6.9 * scale, cy - 7.2 * scale);
                cr.line_to(cx, cy);
                cr.line_to(cx + 6.9 * scale, cy - 7.2 * scale);
                cr.close_path();
                cr.fill();
                cr.restore();
            }
            if (view_model.get_button_state(ControllerViewModel.BTN_DPAD_LEFT)) {
                cr.save();
                cr.set_source_rgba(1, 1, 1, 0.9);
                double cx = 112.0 * scale;
                double cy = 171.3 * scale;
                cr.move_to(cx + 7.2 * scale, cy - 6.9 * scale);
                cr.line_to(cx, cy);
                cr.line_to(cx + 7.2 * scale, cy + 6.9 * scale);
                cr.close_path();
                cr.fill();
                cr.restore();
            }
            if (view_model.get_button_state(ControllerViewModel.BTN_DPAD_RIGHT)) {
                cr.save();
                cr.set_source_rgba(1, 1, 1, 0.9);
                double cx = 227.1 * scale;
                double cy = 171.3 * scale;
                cr.move_to(cx - 7.2 * scale, cy - 6.9 * scale);
                cr.line_to(cx, cy);
                cr.line_to(cx - 7.2 * scale, cy + 6.9 * scale);
                cr.close_path();
                cr.fill();
                cr.restore();
            }
        }

        // ==================== PATHS ====================
        private void draw_l1_side(Cairo.Context cr, double scale) {
            cr.move_to(108.8 * scale, 43.0 * scale);
            cr.line_to(110.8 * scale, 28.3 * scale);
            cr.line_to(127.2 * scale, 24.9 * scale);
            cr.line_to(147.1 * scale, 20.6 * scale);
            cr.line_to(167.8 * scale, 16.6 * scale);
            cr.line_to(197.2 * scale, 11.5 * scale);
            cr.line_to(218.0 * scale, 8.6 * scale);
            cr.line_to(228.3 * scale, 7.1 * scale);
            cr.line_to(230.5 * scale, 21.7 * scale);
            cr.line_to(226.1 * scale, 21.5 * scale);
            cr.line_to(222.7 * scale, 21.6 * scale);
            cr.line_to(166.9 * scale, 30.4 * scale);
            cr.line_to(131.7 * scale, 37.2 * scale);
            cr.line_to(124.0 * scale, 38.9 * scale);
            cr.line_to(115.6 * scale, 41.0 * scale);
            cr.close_path();
        }

        private void draw_l1_top(Cairo.Context cr, double scale) {
            cr.move_to(110.8 * scale, 28.3 * scale);
            cr.line_to(127.2 * scale, 24.9 * scale);
            cr.line_to(147.1 * scale, 20.6 * scale);
            cr.line_to(167.8 * scale, 16.6 * scale);
            cr.line_to(197.2 * scale, 11.5 * scale);
            cr.line_to(218.0 * scale, 8.6 * scale);
            cr.line_to(228.3 * scale, 7.1 * scale);
            cr.line_to(228.08 * scale, 5.5 * scale);
            cr.line_to(227.5 * scale, 4.6 * scale);
            cr.line_to(226.3 * scale, 3.7 * scale);
            cr.line_to(224.6 * scale, 3.2 * scale);
            cr.line_to(212.15 * scale, 1.32 * scale);
            cr.line_to(204.6 * scale, 0.6 * scale);
            cr.line_to(195.0 * scale, 0.0 * scale);
            cr.line_to(187.4 * scale, 0.0 * scale);
            cr.line_to(181.6 * scale, 0.6 * scale);
            cr.line_to(173.5 * scale, 1.7 * scale);
            cr.line_to(164.3 * scale, 3.4 * scale);
            cr.line_to(154.4 * scale, 6.0 * scale);
            cr.line_to(141.0 * scale, 10.3 * scale);
            cr.line_to(132.5 * scale, 14.2 * scale);
            cr.line_to(121.6 * scale, 19.7 * scale);
            cr.line_to(115.8 * scale, 23.2 * scale);
            cr.line_to(112.5 * scale, 25.4 * scale);
            cr.line_to(111.3 * scale, 26.6 * scale);
            cr.close_path();
        }

        private void draw_r1_side(Cairo.Context cr, double scale) {
            cr.move_to(669.6 * scale, 21.2 * scale);
            cr.line_to(671.7 * scale, 6.5 * scale);
            cr.line_to(679.5 * scale, 7.3 * scale);
            cr.line_to(699.1 * scale, 10.0 * scale);
            cr.line_to(724.7 * scale, 14.4 * scale);
            cr.line_to(754.2 * scale, 19.9 * scale);
            cr.line_to(775.2 * scale, 24.5 * scale);
            cr.line_to(790.1 * scale, 28.2 * scale);
            cr.line_to(791.2 * scale, 42.8 * scale);
            cr.line_to(775.9 * scale, 38.7 * scale);
            cr.line_to(758.3 * scale, 34.6 * scale);
            cr.line_to(695.2 * scale, 23.6 * scale);
            cr.line_to(677.7 * scale, 21.6 * scale);
            cr.close_path();
        }

        private void draw_r1_top(Cairo.Context cr, double scale) {
            cr.move_to(671.7 * scale, 6.5 * scale);
            cr.line_to(679.5 * scale, 7.3 * scale);
            cr.line_to(699.1 * scale, 10.0 * scale);
            cr.line_to(724.7 * scale, 14.4 * scale);
            cr.line_to(754.2 * scale, 19.9 * scale);
            cr.line_to(775.2 * scale, 24.5 * scale);
            cr.line_to(790.1 * scale, 28.2 * scale);
            cr.line_to(788.9 * scale, 26.3 * scale);
            cr.line_to(786.9 * scale, 24.6 * scale);
            cr.line_to(780.0 * scale, 20.7 * scale);
            cr.line_to(771.1 * scale, 15.8 * scale);
            cr.line_to(761.7 * scale, 11.8 * scale);
            cr.line_to(753.0 * scale, 8.3 * scale);
            cr.line_to(745.3 * scale, 5.8 * scale);
            cr.line_to(736.1 * scale, 3.3 * scale);
            cr.line_to(727.8 * scale, 1.7 * scale);
            cr.line_to(719.1 * scale, 0.7 * scale);
            cr.line_to(707.9 * scale, 0.2 * scale);
            cr.line_to(698.7 * scale, 0.5 * scale);
            cr.line_to(688.0 * scale, 1.5 * scale);
            cr.line_to(679.1 * scale, 2.7 * scale);
            cr.line_to(675.1 * scale, 3.3 * scale);
            cr.line_to(673.5 * scale, 4.2 * scale);
            cr.line_to(671.7 * scale, 6.5 * scale);
            cr.close_path();
        }

        private void draw_share_path(Cairo.Context cr, double scale) {
            cr.move_to(250.5 * scale, 79.0 * scale);
            cr.line_to(246.8 * scale, 61.1 * scale);
            cr.line_to(245.9 * scale, 58.5 * scale);
            cr.line_to(244.7 * scale, 56.9 * scale);
            cr.line_to(243.5 * scale, 55.7 * scale);
            cr.line_to(242.5 * scale, 54.9 * scale);
            cr.line_to(241.0 * scale, 54.3 * scale);
            cr.line_to(239.7 * scale, 53.8 * scale);
            cr.line_to(237.5 * scale, 53.7 * scale);
            cr.line_to(236.4 * scale, 53.7 * scale);
            cr.line_to(234.6 * scale, 54.1 * scale);
            cr.line_to(233.0 * scale, 54.7 * scale);
            cr.line_to(231.3 * scale, 55.8 * scale);
            cr.line_to(229.9 * scale, 57.1 * scale);
            cr.line_to(229.0 * scale, 58.4 * scale);
            cr.line_to(228.1 * scale, 59.7 * scale);
            cr.line_to(227.6 * scale, 61.8 * scale);
            cr.line_to(227.8 * scale, 64.6 * scale);
            cr.line_to(229.2 * scale, 71.1 * scale);
            cr.line_to(231.5 * scale, 81.8 * scale);
            cr.line_to(232.7 * scale, 86.9 * scale);
            cr.line_to(233.7 * scale, 89.1 * scale);
            cr.line_to(235.4 * scale, 90.8 * scale);
            cr.line_to(237.5 * scale, 92.0 * scale);
            cr.line_to(240.5 * scale, 92.8 * scale);
            cr.line_to(243.3 * scale, 92.8 * scale);
            cr.line_to(245.4 * scale, 92.2 * scale);
            cr.line_to(247.3 * scale, 91.1 * scale);
            cr.line_to(249.4 * scale, 89.3 * scale);
            cr.line_to(250.7 * scale, 87.4 * scale);
            cr.line_to(251.3 * scale, 85.1 * scale);
            cr.line_to(251.2 * scale, 82.8 * scale);
            cr.close_path();
        }

        private void draw_options_path(Cairo.Context cr, double scale) {
            cr.move_to(649.7 * scale, 79.4 * scale);
            cr.line_to(653.4 * scale, 61.5 * scale);
            cr.line_to(654.3 * scale, 58.8 * scale);
            cr.line_to(655.5 * scale, 57.2 * scale);
            cr.line_to(656.7 * scale, 56.1 * scale);
            cr.line_to(657.8 * scale, 55.3 * scale);
            cr.line_to(659.3 * scale, 54.6 * scale);
            cr.line_to(660.6 * scale, 54.2 * scale);
            cr.line_to(662.8 * scale, 54.1 * scale);
            cr.line_to(663.9 * scale, 54.1 * scale);
            cr.line_to(665.6 * scale, 54.4 * scale);
            cr.line_to(667.2 * scale, 55.1 * scale);
            cr.line_to(668.9 * scale, 56.2 * scale);
            cr.line_to(670.3 * scale, 57.5 * scale);
            cr.line_to(671.2 * scale, 58.8 * scale);
            cr.line_to(672.1 * scale, 60.1 * scale);
            cr.line_to(672.7 * scale, 62.2 * scale);
            cr.line_to(672.5 * scale, 65.0 * scale);
            cr.line_to(671.1 * scale, 71.5 * scale);
            cr.line_to(668.8 * scale, 81.8 * scale);
            cr.line_to(667.6 * scale, 86.9 * scale);
            cr.line_to(666.6 * scale, 89.5 * scale);
            cr.line_to(664.9 * scale, 91.2 * scale);
            cr.line_to(662.8 * scale, 92.4 * scale);
            cr.line_to(659.8 * scale, 93.2 * scale);
            cr.line_to(657.0 * scale, 93.2 * scale);
            cr.line_to(654.9 * scale, 92.6 * scale);
            cr.line_to(653.0 * scale, 91.5 * scale);
            cr.line_to(650.9 * scale, 89.7 * scale);
            cr.line_to(649.6 * scale, 87.8 * scale);
            cr.line_to(649.0 * scale, 85.5 * scale);
            cr.line_to(649.1 * scale, 83.2 * scale);
            cr.close_path();
        }

        private void draw_touchpad_path(Cairo.Context cr, double scale) {
            cr.move_to(295.3 * scale, 159.5 * scale);
            cr.line_to(271.6 * scale, 48.2 * scale);
            cr.line_to(270.8 * scale, 42.9 * scale);
            cr.line_to(270.5 * scale, 37.5 * scale);
            cr.line_to(270.8 * scale, 31.4 * scale);
            cr.line_to(271.3 * scale, 28.8 * scale);
            cr.line_to(272.6 * scale, 26.2 * scale);
            cr.line_to(274.5 * scale, 23.5 * scale);
            cr.line_to(277.8 * scale, 20.7 * scale);
            cr.line_to(282.5 * scale, 17.9 * scale);
            cr.line_to(287.7 * scale, 15.8 * scale);
            cr.line_to(293.8 * scale, 14.3 * scale);
            cr.line_to(306.1 * scale, 12.6 * scale);
            cr.line_to(329.9 * scale, 10.9 * scale);
            cr.line_to(362.8 * scale, 9.2 * scale);
            cr.line_to(392.2 * scale, 8.2 * scale);
            cr.line_to(424.8 * scale, 7.5 * scale);
            cr.line_to(489.0 * scale, 7.5 * scale);
            cr.line_to(504.9 * scale, 8.1 * scale);
            cr.line_to(530.3 * scale, 9.0 * scale);
            cr.line_to(563.1 * scale, 10.7 * scale);
            cr.line_to(587.1 * scale, 12.0 * scale);
            cr.line_to(602.8 * scale, 13.4 * scale);
            cr.line_to(608.7 * scale, 14.3 * scale);
            cr.line_to(612.9 * scale, 15.2 * scale);
            cr.line_to(616.2 * scale, 16.5 * scale);
            cr.line_to(620.9 * scale, 19.1 * scale);
            cr.line_to(623.5 * scale, 21.1 * scale);
            cr.line_to(626.2 * scale, 23.9 * scale);
            cr.line_to(628.4 * scale, 27.3 * scale);
            cr.line_to(629.2 * scale, 30.7 * scale);
            cr.line_to(629.4 * scale, 35.0 * scale);
            cr.line_to(629.2 * scale, 43.7 * scale);
            cr.line_to(628.7 * scale, 47.1 * scale);
            cr.line_to(627.7 * scale, 52.7 * scale);
            cr.line_to(604.1 * scale, 165.1 * scale);
            cr.line_to(603.1 * scale, 169.3 * scale);
            cr.line_to(601.7 * scale, 173.0 * scale);
            cr.line_to(600.0 * scale, 176.6 * scale);
            cr.line_to(597.6 * scale, 180.9 * scale);
            cr.line_to(594.8 * scale, 185.1 * scale);
            cr.line_to(590.8 * scale, 189.5 * scale);
            cr.line_to(587.1 * scale, 192.7 * scale);
            cr.line_to(582.9 * scale, 195.6 * scale);
            cr.line_to(579.0 * scale, 197.6 * scale);
            cr.line_to(574.9 * scale, 199.4 * scale);
            cr.line_to(570.2 * scale, 201.0 * scale);
            cr.line_to(567.0 * scale, 201.6 * scale);
            cr.line_to(561.3 * scale, 202.0 * scale);
            cr.line_to(342.8 * scale, 202.0 * scale);
            cr.line_to(335.7 * scale, 201.9 * scale);
            cr.line_to(331.5 * scale, 201.2 * scale);
            cr.line_to(326.6 * scale, 200.0 * scale);
            cr.line_to(322.9 * scale, 198.5 * scale);
            cr.line_to(318.9 * scale, 196.3 * scale);
            cr.line_to(314.1 * scale, 193.4 * scale);
            cr.line_to(309.5 * scale, 189.5 * scale);
            cr.line_to(305.0 * scale, 184.9 * scale);
            cr.line_to(301.4 * scale, 179.6 * scale);
            cr.line_to(298.8 * scale, 174.2 * scale);
            cr.line_to(297.0 * scale, 168.4 * scale);
            cr.close_path();
        }

        private void draw_dpad_up_path(Cairo.Context cr, double scale) {
            cr.move_to(191.6 * scale, 140.5 * scale);
            cr.line_to(174.6 * scale, 158.8 * scale);
            cr.line_to(172.6 * scale, 160.1 * scale);
            cr.line_to(169.2 * scale, 160.4 * scale);
            cr.line_to(165.8 * scale, 160.1 * scale);
            cr.line_to(164.5 * scale, 159.6 * scale);
            cr.line_to(146.9 * scale, 141.2 * scale);
            cr.line_to(145.7 * scale, 138.9 * scale);
            cr.curve_to(144.0 * scale, 129.1 * scale, 144.2 * scale, 119.0 * scale, 143.7 * scale, 109.1 * scale);
            cr.line_to(144.2 * scale, 106.5 * scale);
            cr.line_to(145.9 * scale, 103.9 * scale);
            cr.line_to(148.7 * scale, 100.7 * scale);
            cr.line_to(152.6 * scale, 98.6 * scale);
            cr.line_to(157.6 * scale, 97.3 * scale);
            cr.line_to(181.3 * scale, 97.3 * scale);
            cr.line_to(185.3 * scale, 97.9 * scale);
            cr.line_to(188.0 * scale, 99.5 * scale);
            cr.line_to(190.7 * scale, 102.2 * scale);
            cr.line_to(192.5 * scale, 104.9 * scale);
            cr.line_to(194.0 * scale, 107.5 * scale);
            cr.line_to(194.4 * scale, 110.2 * scale);
            cr.line_to(193.2 * scale, 136.4 * scale);
            cr.line_to(192.7 * scale, 138.2 * scale);
            cr.close_path();
        }

        private void draw_dpad_down_path(Cairo.Context cr, double scale) {
            cr.move_to(192.2 * scale, 204.1 * scale);
            cr.line_to(175.2 * scale, 185.8 * scale);
            cr.line_to(173.2 * scale, 184.5 * scale);
            cr.line_to(169.8 * scale, 184.2 * scale);
            cr.line_to(166.4 * scale, 184.5 * scale);
            cr.line_to(165.1 * scale, 185.0 * scale);
            cr.line_to(147.5 * scale, 203.4 * scale);
            cr.line_to(146.3 * scale, 205.7 * scale);
            cr.curve_to(144.6 * scale, 215.5 * scale, 144.8 * scale, 225.6 * scale, 144.3 * scale, 235.5 * scale);
            cr.line_to(144.8 * scale, 238.1 * scale);
            cr.line_to(146.5 * scale, 240.7 * scale);
            cr.line_to(149.3 * scale, 243.9 * scale);
            cr.line_to(153.2 * scale, 246.0 * scale);
            cr.line_to(158.2 * scale, 247.3 * scale);
            cr.line_to(181.9 * scale, 247.3 * scale);
            cr.line_to(185.9 * scale, 246.7 * scale);
            cr.line_to(188.6 * scale, 245.1 * scale);
            cr.line_to(191.3 * scale, 242.4 * scale);
            cr.line_to(193.1 * scale, 239.7 * scale);
            cr.line_to(194.6 * scale, 237.1 * scale);
            cr.line_to(195.0 * scale, 234.4 * scale);
            cr.line_to(193.8 * scale, 208.2 * scale);
            cr.line_to(193.3 * scale, 206.4 * scale);
            cr.close_path();
        }

        private void draw_dpad_left_path(Cairo.Context cr, double scale) {
            cr.move_to(138.1 * scale, 194.8 * scale);
            cr.line_to(156.5 * scale, 177.8 * scale);
            cr.line_to(157.8 * scale, 175.8 * scale);
            cr.line_to(158.1 * scale, 172.4 * scale);
            cr.line_to(157.8 * scale, 169.0 * scale);
            cr.line_to(157.3 * scale, 167.7 * scale);
            cr.line_to(138.9 * scale, 150.1 * scale);
            cr.line_to(136.6 * scale, 148.9 * scale);
            cr.curve_to(126.8 * scale, 147.2 * scale, 116.7 * scale, 147.4 * scale, 106.8 * scale, 146.9 * scale);
            cr.line_to(104.2 * scale, 147.4 * scale);
            cr.line_to(101.6 * scale, 149.1 * scale);
            cr.line_to(98.4 * scale, 151.9 * scale);
            cr.line_to(96.3 * scale, 155.8 * scale);
            cr.line_to(95.0 * scale, 160.8 * scale);
            cr.line_to(95.0 * scale, 184.5 * scale);
            cr.line_to(95.6 * scale, 188.5 * scale);
            cr.line_to(97.2 * scale, 191.2 * scale);
            cr.line_to(99.9 * scale, 193.9 * scale);
            cr.line_to(102.6 * scale, 195.7 * scale);
            cr.line_to(105.2 * scale, 197.2 * scale);
            cr.line_to(107.9 * scale, 197.6 * scale);
            cr.line_to(134.1 * scale, 196.4 * scale);
            cr.line_to(135.9 * scale, 195.9 * scale);
            cr.close_path();
        }

        private void draw_dpad_right_path(Cairo.Context cr, double scale) {
            cr.move_to(201.7 * scale, 194.8 * scale);
            cr.line_to(183.4 * scale, 177.8 * scale);
            cr.line_to(182.1 * scale, 175.8 * scale);
            cr.line_to(181.8 * scale, 172.4 * scale);
            cr.line_to(182.1 * scale, 169.0 * scale);
            cr.line_to(182.6 * scale, 167.7 * scale);
            cr.line_to(201.0 * scale, 150.1 * scale);
            cr.line_to(203.3 * scale, 148.9 * scale);
            cr.curve_to(213.1 * scale, 147.2 * scale, 223.2 * scale, 147.4 * scale, 233.1 * scale, 146.9 * scale);
            cr.line_to(235.7 * scale, 147.4 * scale);
            cr.line_to(238.3 * scale, 149.1 * scale);
            cr.line_to(241.5 * scale, 151.9 * scale);
            cr.line_to(243.6 * scale, 155.8 * scale);
            cr.line_to(244.9 * scale, 160.8 * scale);
            cr.line_to(244.9 * scale, 184.5 * scale);
            cr.line_to(244.3 * scale, 188.5 * scale);
            cr.line_to(242.7 * scale, 191.2 * scale);
            cr.line_to(240.0 * scale, 193.9 * scale);
            cr.line_to(237.3 * scale, 195.7 * scale);
            cr.line_to(234.7 * scale, 197.2 * scale);
            cr.line_to(232.0 * scale, 197.6 * scale);
            cr.line_to(205.8 * scale, 196.4 * scale);
            cr.line_to(204.0 * scale, 195.9 * scale);
            cr.close_path();
        }
    }
}
