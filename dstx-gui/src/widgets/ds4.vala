/*
 * ds4.vala - DualShock 4 controller rendering widget for DSTX GUI
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
 * - Render DualShock 4 controller SVG with button overlays
 * - Draw face buttons, L3/R3, L1/R1, Share, Options, Touchpad, D-pad, PS button
 * - Handle button highlighting based on controller state
 * - Support Xbox layout mapping when emulation is active
 */

// src/widgets/ds4.vala

using Cairo;
using Dstx.ViewModels;
using Dstx.Renderers;

namespace Dstx.Widgets {
    public class Ds4Widget : ControllerRenderer {
        // ==================== DIMENSIONS ====================
        protected override int CANVAS_WIDTH { get { return 900; } }
        protected override int CANVAS_HEIGHT { get { return 633; } }
        protected override int LEFT_STICK_CANVAS_X { get { return 320; } }
        protected override int RIGHT_STICK_CANVAS_X { get { return 580; } }
        protected override int STICK_CANVAS_Y { get { return 505; } }
        protected override int LEFT_TRIGGER_CANVAS_X { get { return 0; } }
        protected override int RIGHT_TRIGGER_CANVAS_X { get { return 900; } }
        protected override int TRIGGER_CANVAS_Y { get { return 0; } }
        public override string controller_display_name { get { return "DualShock 4"; } }

        // ==================== BUTTON COORDINATES ====================
        private const int PS_CIRCLE_X = 800;
        private const int PS_CIRCLE_Y = 169;
        private const int PS_CROSS_X = 733;
        private const int PS_CROSS_Y = 236;
        private const int PS_SQUARE_X = 666;
        private const int PS_SQUARE_Y = 169;
        private const int PS_TRIANGLE_X = 733;
        private const int PS_TRIANGLE_Y = 102;

        private const int XBOX_A_X = 733;
        private const int XBOX_A_Y = 236;
        private const int XBOX_B_X = 800;
        private const int XBOX_B_Y = 169;
        private const int XBOX_X_X = 666;
        private const int XBOX_X_Y = 169;
        private const int XBOX_Y_X = 733;
        private const int XBOX_Y_Y = 102;

        private const int L3_X = 305;
        private const int L3_Y = 293;
        private const int R3_X = 594;
        private const int R3_Y = 293;
        private const int PS_X = 450;
        private const int PS_Y = 298;

        private const int FACE_RADIUS_OUTER = 31;
        private const int L3_RADIUS_OUTER = 55;
        private const int L3_RADIUS_INNER = 36;
        private const int PS_RADIUS = 24;

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

        public Ds4Widget(ControllerViewModel view_model) {
            base(view_model);
        }

        protected override string get_base_svg_path() {
            return "/org/dstx/gui/icons/ds4/base.svg";
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

            draw_path_button(cr, ControllerViewModel.BTN_L1, scale);
            draw_path_button(cr, ControllerViewModel.BTN_R1, scale);
            draw_path_button(cr, ControllerViewModel.BTN_SHARE, scale);
            draw_path_button(cr, ControllerViewModel.BTN_OPTIONS, scale);
            draw_path_button(cr, ControllerViewModel.BTN_TOUCH, scale);
            draw_path_button(cr, ControllerViewModel.BTN_PS, scale);
            draw_path_button(cr, ControllerViewModel.BTN_DPAD_UP, scale);
            draw_path_button(cr, ControllerViewModel.BTN_DPAD_DOWN, scale);
            draw_path_button(cr, ControllerViewModel.BTN_DPAD_LEFT, scale);
            draw_path_button(cr, ControllerViewModel.BTN_DPAD_RIGHT, scale);
        }

        // ==================== DRAWING METHODS ====================
        private void draw_face_button(Cairo.Context cr, int btn, int x, int y, double scale) {
            if (!view_model.get_button_state(btn)) return;

            double r_outer = FACE_RADIUS_OUTER * scale;
            cr.save();

            set_face_color(cr, btn);
            cr.arc(x * scale, y * scale, r_outer, 0, 2 * Math.PI);
            cr.fill();

            if (!view_model.emulate_active) {
                cr.set_source_rgba(0, 0, 0, 0.9);
                cr.set_line_width(2.5);
                double r_inner = 20 * scale;
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
                        double size = r_inner * 1.55;
                        cr.rectangle(x * scale - size/2, y * scale - size/2, size, size);
                        cr.stroke();
                        break;
                    case ControllerViewModel.BTN_TRIANGLE:
                        double offset_x = 0;
                        double offset_y = -3;
                        double side = r_inner * 1.8;
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
            switch (btn) {
                case ControllerViewModel.BTN_CROSS: return "A";
                case ControllerViewModel.BTN_CIRCLE: return "B";
                case ControllerViewModel.BTN_SQUARE: return "X";
                case ControllerViewModel.BTN_TRIANGLE: return "Y";
                default: return "";
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
                    cr.set_source_rgba(0, 0, 0, 0.5);
                    cr.set_line_width(1.5);
                    draw_share_path(cr, scale);
                    cr.stroke();
                    break;
                case ControllerViewModel.BTN_OPTIONS:
                    cr.set_source_rgba(PS_COLOR_R, PS_COLOR_G, PS_COLOR_B, 0.9);
                    draw_options_path(cr, scale);
                    cr.fill();
                    cr.set_source_rgba(0, 0, 0, 0.5);
                    cr.set_line_width(1.5);
                    draw_options_path(cr, scale);
                    cr.stroke();
                    break;
                case ControllerViewModel.BTN_TOUCH:
                    cr.set_source_rgba(PS_COLOR_R, PS_COLOR_G, PS_COLOR_B, 0.6);
                    draw_touchpad_path(cr, scale);
                    cr.fill();
                    break;
                case ControllerViewModel.BTN_PS:
                    draw_ps_button(cr, scale);
                    break;
                case ControllerViewModel.BTN_DPAD_UP:
                    cr.set_source_rgba(PS_COLOR_R, PS_COLOR_G, PS_COLOR_B, 0.9);
                    draw_dpad_up_path(cr, scale);
                    cr.fill();
                    cr.set_source_rgba(0, 0, 0, 0.5);
                    cr.set_line_width(1.5);
                    draw_dpad_up_path(cr, scale);
                    cr.stroke();
                    break;
                case ControllerViewModel.BTN_DPAD_DOWN:
                    cr.set_source_rgba(PS_COLOR_R, PS_COLOR_G, PS_COLOR_B, 0.9);
                    draw_dpad_down_path(cr, scale);
                    cr.fill();
                    cr.set_source_rgba(0, 0, 0, 0.5);
                    cr.set_line_width(1.5);
                    draw_dpad_down_path(cr, scale);
                    cr.stroke();
                    break;
                case ControllerViewModel.BTN_DPAD_LEFT:
                    cr.set_source_rgba(PS_COLOR_R, PS_COLOR_G, PS_COLOR_B, 0.9);
                    draw_dpad_left_path(cr, scale);
                    cr.fill();
                    cr.set_source_rgba(0, 0, 0, 0.5);
                    cr.set_line_width(1.5);
                    draw_dpad_left_path(cr, scale);
                    cr.stroke();
                    break;
                case ControllerViewModel.BTN_DPAD_RIGHT:
                    cr.set_source_rgba(PS_COLOR_R, PS_COLOR_G, PS_COLOR_B, 0.9);
                    draw_dpad_right_path(cr, scale);
                    cr.fill();
                    cr.set_source_rgba(0, 0, 0, 0.5);
                    cr.set_line_width(1.5);
                    draw_dpad_right_path(cr, scale);
                    cr.stroke();
                    break;
            }
            cr.restore();
        }

        // ==================== PATHS ====================
        private void draw_l1_side(Cairo.Context cr, double scale) {
            cr.move_to(116.78 * scale, 24.95 * scale);
            cr.line_to(116.78 * scale, 17.70 * scale);
            cr.line_to(119.00 * scale, 16.33 * scale);
            cr.line_to(124.72 * scale, 14.53 * scale);
            cr.line_to(132.08 * scale, 12.67 * scale);
            cr.line_to(137.15 * scale, 11.44 * scale);
            cr.line_to(144.03 * scale, 10.34 * scale);
            cr.line_to(154.07 * scale, 9.23 * scale);
            cr.line_to(161.25 * scale, 8.36 * scale);
            cr.line_to(169.07 * scale, 7.71 * scale);
            cr.line_to(177.77 * scale, 7.51 * scale);
            cr.line_to(194.63 * scale, 7.59 * scale);
            cr.line_to(206.38 * scale, 8.28 * scale);
            cr.line_to(214.89 * scale, 8.97 * scale);
            cr.line_to(221.00 * scale, 9.89 * scale);
            cr.line_to(226.95 * scale, 10.65 * scale);
            cr.line_to(229.35 * scale, 11.00 * scale);
            cr.line_to(229.36 * scale, 22.35 * scale);
            cr.line_to(226.79 * scale, 22.00 * scale);
            cr.line_to(215.21 * scale, 20.81 * scale);
            cr.line_to(207.33 * scale, 19.89 * scale);
            cr.line_to(200.92 * scale, 19.38 * scale);
            cr.line_to(193.72 * scale, 19.05 * scale);
            cr.line_to(168.50 * scale, 19.05 * scale);
            cr.line_to(161.18 * scale, 19.21 * scale);
            cr.line_to(153.28 * scale, 19.78 * scale);
            cr.line_to(144.80 * scale, 20.48 * scale);
            cr.line_to(134.55 * scale, 21.78 * scale);
            cr.line_to(125.22 * scale, 23.29 * scale);
            cr.close_path();
        }

        private void draw_l1_top(Cairo.Context cr, double scale) {
            cr.move_to(116.78 * scale, 17.70 * scale);
            cr.line_to(118.93 * scale, 15.89 * scale);
            cr.line_to(120.62 * scale, 14.89 * scale);
            cr.line_to(123.88 * scale, 13.07 * scale);
            cr.line_to(126.70 * scale, 11.59 * scale);
            cr.line_to(130.16 * scale, 9.99 * scale);
            cr.line_to(134.68 * scale, 8.35 * scale);
            cr.line_to(138.11 * scale, 7.12 * scale);
            cr.line_to(142.55 * scale, 5.57 * scale);
            cr.line_to(146.26 * scale, 4.38 * scale);
            cr.line_to(150.99 * scale, 3.17 * scale);
            cr.line_to(155.36 * scale, 2.31 * scale);
            cr.line_to(160.50 * scale, 1.51 * scale);
            cr.line_to(164.29 * scale, 1.13 * scale);
            cr.line_to(169.16 * scale, 0.67 * scale);
            cr.line_to(173.73 * scale, 0.23 * scale);
            cr.line_to(177.65 * scale, 0.13 * scale);
            cr.line_to(182.17 * scale, 0.13 * scale);
            cr.line_to(186.00 * scale, 0.32 * scale);
            cr.line_to(190.25 * scale, 0.59 * scale);
            cr.line_to(195.14 * scale, 1.12 * scale);
            cr.line_to(199.66 * scale, 1.67 * scale);
            cr.line_to(203.80 * scale, 2.26 * scale);
            cr.line_to(207.09 * scale, 2.95 * scale);
            cr.line_to(211.33 * scale, 3.96 * scale);
            cr.line_to(215.40 * scale, 5.03 * scale);
            cr.line_to(219.69 * scale, 6.32 * scale);
            cr.line_to(222.91 * scale, 7.27 * scale);
            cr.line_to(225.90 * scale, 8.47 * scale);
            cr.line_to(229.39 * scale, 9.56 * scale);
            cr.line_to(229.38 * scale, 10.98 * scale);
            cr.line_to(226.98 * scale, 10.64 * scale);
            cr.line_to(221.03 * scale, 9.88 * scale);
            cr.line_to(214.92 * scale, 8.96 * scale);
            cr.line_to(206.41 * scale, 8.28 * scale);
            cr.line_to(194.66 * scale, 7.59 * scale);
            cr.line_to(177.80 * scale, 7.51 * scale);
            cr.line_to(169.10 * scale, 7.71 * scale);
            cr.line_to(161.28 * scale, 8.36 * scale);
            cr.line_to(154.10 * scale, 9.23 * scale);
            cr.line_to(144.06 * scale, 10.34 * scale);
            cr.line_to(137.18 * scale, 11.44 * scale);
            cr.line_to(132.11 * scale, 12.67 * scale);
            cr.line_to(124.75 * scale, 14.53 * scale);
            cr.line_to(119.03 * scale, 16.33 * scale);
            cr.close_path();
        }

        private void draw_r1_side(Cairo.Context cr, double scale) {
            cr.move_to(670.25 * scale, 22.63 * scale);
            cr.line_to(670.25 * scale, 11.41 * scale);
            cr.line_to(672.14 * scale, 10.42 * scale);
            cr.line_to(676.79 * scale, 9.31 * scale);
            cr.line_to(683.19 * scale, 8.20 * scale);
            cr.line_to(688.84 * scale, 7.43 * scale);
            cr.line_to(695.45 * scale, 6.87 * scale);
            cr.line_to(704.11 * scale, 6.67 * scale);
            cr.line_to(712.97 * scale, 6.56 * scale);
            cr.line_to(725.24 * scale, 6.71 * scale);
            cr.line_to(733.44 * scale, 7.09 * scale);
            cr.line_to(743.36 * scale, 7.86 * scale);
            cr.line_to(752.51 * scale, 9.08 * scale);
            cr.line_to(762.53 * scale, 11.00 * scale);
            cr.line_to(772.39 * scale, 13.74 * scale);
            cr.line_to(781.87 * scale, 16.69 * scale);
            cr.line_to(781.87 * scale, 24.73 * scale);
            cr.line_to(780.71 * scale, 24.44 * scale);
            cr.line_to(771.73 * scale, 22.97 * scale);
            cr.line_to(762.92 * scale, 21.78 * scale);
            cr.line_to(753.08 * scale, 20.71 * scale);
            cr.line_to(741.80 * scale, 20.06 * scale);
            cr.line_to(724.26 * scale, 19.25 * scale);
            cr.line_to(710.34 * scale, 19.25 * scale);
            cr.line_to(696.85 * scale, 19.63 * scale);
            cr.line_to(686.24 * scale, 20.60 * scale);
            cr.close_path();
        }

        private void draw_r1_top(Cairo.Context cr, double scale) {
            cr.move_to(670.25 * scale, 11.41 * scale);
            cr.line_to(671.19 * scale, 10.42 * scale);
            cr.line_to(672.67 * scale, 9.19 * scale);
            cr.line_to(674.97 * scale, 7.90 * scale);
            cr.line_to(678.20 * scale, 6.68 * scale);
            cr.line_to(686.09 * scale, 4.25 * scale);
            cr.line_to(690.29 * scale, 3.19 * scale);
            cr.line_to(695.71 * scale, 2.16 * scale);
            cr.line_to(700.56 * scale, 1.40 * scale);
            cr.line_to(703.83 * scale, 0.96 * scale);
            cr.line_to(708.37 * scale, 0.54 * scale);
            cr.line_to(714.02 * scale, 0.17 * scale);
            cr.line_to(719.80 * scale, 0.00 * scale);
            cr.line_to(725.58 * scale, 0.00 * scale);
            cr.line_to(726.55 * scale, 0.05 * scale);
            cr.line_to(734.25 * scale, 0.46 * scale);
            cr.line_to(740.76 * scale, 1.31 * scale);
            cr.line_to(746.05 * scale, 2.32 * scale);
            cr.line_to(750.96 * scale, 3.54 * scale);
            cr.line_to(755.88 * scale, 5.06 * scale);
            cr.line_to(760.57 * scale, 6.73 * scale);
            cr.line_to(765.19 * scale, 8.64 * scale);
            cr.line_to(770.51 * scale, 11.12 * scale);
            cr.line_to(778.01 * scale, 15.55 * scale);
            cr.line_to(781.87 * scale, 16.67 * scale);
            cr.line_to(772.37 * scale, 13.73 * scale);
            cr.line_to(762.49 * scale, 10.98 * scale);
            cr.line_to(752.46 * scale, 9.79 * scale);
            cr.line_to(743.31 * scale, 7.85 * scale);
            cr.line_to(733.39 * scale, 7.09 * scale);
            cr.line_to(725.19 * scale, 6.71 * scale);
            cr.line_to(712.92 * scale, 6.56 * scale);
            cr.line_to(704.06 * scale, 6.67 * scale);
            cr.line_to(695.40 * scale, 6.86 * scale);
            cr.line_to(688.79 * scale, 7.73 * scale);
            cr.line_to(683.14 * scale, 8.20 * scale);
            cr.line_to(676.74 * scale, 9.30 * scale);
            cr.line_to(672.09 * scale, 10.41 * scale);
            cr.line_to(670.14 * scale, 11.41 * scale);
            cr.close_path();
        }

        private void draw_share_path(Cairo.Context cr, double scale) {
            double x = 570.69 * 0.49;
            double y = 190.15 * 0.49;
            cr.move_to(x * scale, y * scale);
            y -= 56.125 * 0.49;
            cr.line_to(x * scale, y * scale);
            x -= 0.6875 * 0.49; y -= 4.71875 * 0.49;
            cr.line_to(x * scale, y * scale);
            x -= 1.8437 * 0.49; y -= 5.03125 * 0.49;
            cr.line_to(x * scale, y * scale);
            x -= 3.2813 * 0.49; y -= 4.53125 * 0.49;
            cr.line_to(x * scale, y * scale);
            x -= 3.5937 * 0.49; y -= 3.3125 * 0.49;
            cr.line_to(x * scale, y * scale);
            x -= 4.3438 * 0.49; y -= 3.28125 * 0.49;
            cr.line_to(x * scale, y * scale);
            x -= 4.4062 * 0.49; y -= 2.4375 * 0.49;
            cr.line_to(x * scale, y * scale);
            x -= 3.3349 * 0.49; y -= 1.59439 * 0.49;
            cr.line_to(x * scale, y * scale);
            x -= 3.6902 * 0.49; y -= 0.92807 * 0.49;
            cr.line_to(x * scale, y * scale);
            x -= 4.3089 * 0.49; y -= 0.37565 * 0.49;
            cr.line_to(x * scale, y * scale);
            x -= 3.8449 * 0.49; y += 0.19887 * 0.49;
            cr.line_to(x * scale, y * scale);
            x -= 4.0711 * 0.49; y += 0.54299 * 0.49;
            cr.line_to(x * scale, y * scale);
            x -= 4.9688 * 0.49; y += 1.96875 * 0.49;
            cr.line_to(x * scale, y * scale);
            x -= 4.5 * 0.49; y += 2.375 * 0.49;
            cr.line_to(x * scale, y * scale);
            x -= 3.8437 * 0.49; y += 2.75 * 0.49;
            cr.line_to(x * scale, y * scale);
            x -= 3.4688 * 0.49; y += 3.6875 * 0.49;
            cr.line_to(x * scale, y * scale);
            x -= 2.4375 * 0.49; y += 3.59375 * 0.49;
            cr.line_to(x * scale, y * scale);
            x -= 2.3437 * 0.49; y += 4.46875 * 0.49;
            cr.line_to(x * scale, y * scale);
            x -= 1.0313 * 0.49; y += 4.28125 * 0.49;
            cr.line_to(x * scale, y * scale);
            x -= 0.5937 * 0.49; y += 7.4375 * 0.49;
            cr.line_to(x * scale, y * scale);
            y += 49.63726 * 0.49;
            cr.line_to(x * scale, y * scale);
            x += 0.4375 * 0.49; y += 4.67524 * 0.49;
            cr.line_to(x * scale, y * scale);
            x += 1.7812 * 0.49; y += 4.5625 * 0.49;
            cr.line_to(x * scale, y * scale);
            x += 3 * 0.49; y += 4.125 * 0.49;
            cr.line_to(x * scale, y * scale);
            x += 3.125 * 0.49; y += 3.46875 * 0.49;
            cr.line_to(x * scale, y * scale);
            x += 4.2188 * 0.49; y += 3.84375 * 0.49;
            cr.line_to(x * scale, y * scale);
            x += 5.0625 * 0.49; y += 3 * 0.49;
            cr.line_to(x * scale, y * scale);
            x += 5.6562 * 0.49; y += 1.59375 * 0.49;
            cr.line_to(x * scale, y * scale);
            x += 4.9688 * 0.49; y += 0.53125 * 0.49;
            cr.line_to(x * scale, y * scale);
            x += 5.5625 * 0.49;
            cr.line_to(x * scale, y * scale);
            x += 5.0312 * 0.49; y -= 0.5 * 0.49;
            cr.line_to(x * scale, y * scale);
            x += 4.8438 * 0.49; y -= 1.46875 * 0.49;
            cr.line_to(x * scale, y * scale);
            x += 4.6562 * 0.49; y -= 2.84375 * 0.49;
            cr.line_to(x * scale, y * scale);
            x += 3.625 * 0.49; y -= 3.25 * 0.49;
            cr.line_to(x * scale, y * scale);
            x += 2.7188 * 0.49; y -= 3.125 * 0.49;
            cr.line_to(x * scale, y * scale);
            x += 2.4687 * 0.49; y -= 3.375 * 0.49;
            cr.line_to(x * scale, y * scale);
            x += 1.7188 * 0.49; y -= 3.40625 * 0.49;
            cr.line_to(x * scale, y * scale);
            x += 1.4687 * 0.49; y -= 3.46875 * 0.49;
            cr.line_to(x * scale, y * scale);
            cr.close_path();
        }

        private void draw_options_path(Cairo.Context cr, double scale) {
            double x = 1266.30 * 0.49;
            double y = 190.88 * 0.49;
            cr.move_to(x * scale, y * scale);
            y -= 56.125 * 0.49;
            cr.line_to(x * scale, y * scale);
            x += 0.6875 * 0.49; y -= 4.71876 * 0.49;
            cr.line_to(x * scale, y * scale);
            x += 1.8437 * 0.49; y -= 5.03125 * 0.49;
            cr.line_to(x * scale, y * scale);
            x += 3.2813 * 0.49; y -= 4.53125 * 0.49;
            cr.line_to(x * scale, y * scale);
            x += 3.5937 * 0.49; y -= 3.3125 * 0.49;
            cr.line_to(x * scale, y * scale);
            x += 4.3438 * 0.49; y -= 3.28125 * 0.49;
            cr.line_to(x * scale, y * scale);
            x += 4.4062 * 0.49; y -= 2.4375 * 0.49;
            cr.line_to(x * scale, y * scale);
            x += 3.3349 * 0.49; y -= 1.59439 * 0.49;
            cr.line_to(x * scale, y * scale);
            x += 3.6902 * 0.49; y -= 0.92806 * 0.49;
            cr.line_to(x * scale, y * scale);
            x += 4.3089 * 0.49; y -= 0.37566 * 0.49;
            cr.line_to(x * scale, y * scale);
            x += 3.8449 * 0.49; y += 0.19887 * 0.49;
            cr.line_to(x * scale, y * scale);
            x += 4.0711 * 0.49; y += 0.54299 * 0.49;
            cr.line_to(x * scale, y * scale);
            x += 4.9688 * 0.49; y += 1.96875 * 0.49;
            cr.line_to(x * scale, y * scale);
            x += 4.5 * 0.49; y += 2.375 * 0.49;
            cr.line_to(x * scale, y * scale);
            x += 3.8437 * 0.49; y += 2.75 * 0.49;
            cr.line_to(x * scale, y * scale);
            x += 3.4688 * 0.49; y += 3.6875 * 0.49;
            cr.line_to(x * scale, y * scale);
            x += 2.4375 * 0.49; y += 3.59375 * 0.49;
            cr.line_to(x * scale, y * scale);
            x += 2.3437 * 0.49; y += 4.46875 * 0.49;
            cr.line_to(x * scale, y * scale);
            x += 1.0313 * 0.49; y += 4.28126 * 0.49;
            cr.line_to(x * scale, y * scale);
            x += 0.5937 * 0.49; y += 7.4375 * 0.49;
            cr.line_to(x * scale, y * scale);
            y += 49.63726 * 0.49;
            cr.line_to(x * scale, y * scale);
            x -= 0.4375 * 0.49; y += 4.67524 * 0.49;
            cr.line_to(x * scale, y * scale);
            x -= 1.7812 * 0.49; y += 4.5625 * 0.49;
            cr.line_to(x * scale, y * scale);
            x -= 3 * 0.49; y += 4.125 * 0.49;
            cr.line_to(x * scale, y * scale);
            x -= 3.125 * 0.49; y += 3.46875 * 0.49;
            cr.line_to(x * scale, y * scale);
            x -= 4.2188 * 0.49; y += 3.84375 * 0.49;
            cr.line_to(x * scale, y * scale);
            x -= 5.0625 * 0.49; y += 3 * 0.49;
            cr.line_to(x * scale, y * scale);
            x -= 5.6562 * 0.49; y += 1.59375 * 0.49;
            cr.line_to(x * scale, y * scale);
            x -= 4.9688 * 0.49; y += 0.53125 * 0.49;
            cr.line_to(x * scale, y * scale);
            x -= 5.5625 * 0.49;
            cr.line_to(x * scale, y * scale);
            x -= 5.0312 * 0.49; y -= 0.5 * 0.49;
            cr.line_to(x * scale, y * scale);
            x -= 4.8438 * 0.49; y -= 1.46875 * 0.49;
            cr.line_to(x * scale, y * scale);
            x -= 4.6562 * 0.49; y -= 2.84375 * 0.49;
            cr.line_to(x * scale, y * scale);
            x -= 3.625 * 0.49; y -= 3.25 * 0.49;
            cr.line_to(x * scale, y * scale);
            x -= 2.7188 * 0.49; y -= 3.125 * 0.49;
            cr.line_to(x * scale, y * scale);
            x -= 2.4687 * 0.49; y -= 3.375 * 0.49;
            cr.line_to(x * scale, y * scale);
            x -= 1.7188 * 0.49; y -= 3.40625 * 0.49;
            cr.line_to(x * scale, y * scale);
            x -= 1.4687 * 0.49; y -= 3.46875 * 0.49;
            cr.line_to(x * scale, y * scale);
            cr.close_path();
        }

        private void draw_touchpad_path(Cairo.Context cr, double scale) {
            double x = 624.93 * 0.49;
            double y = 58.88 * 0.49;
            cr.move_to(x * scale, y * scale);
            x += 586.50 * 0.49;
            cr.line_to(x * scale, y * scale);
            x += 0.4062 * 0.49; y += 0.375 * 0.49;
            cr.line_to(x * scale, y * scale);
            y += 298.625 * 0.49;
            cr.line_to(x * scale, y * scale);
            x -= 0.275 * 0.49; y += 6.74753 * 0.49;
            cr.line_to(x * scale, y * scale);
            x -= 0.7955 * 0.49; y += 5.65685 * 0.49;
            cr.line_to(x * scale, y * scale);
            x -= 1.7236 * 0.49; y += 5.48008 * 0.49;
            cr.line_to(x * scale, y * scale);
            x -= 2.7401 * 0.49; y += 4.59619 * 0.49;
            cr.line_to(x * scale, y * scale);
            x -= 4.0658 * 0.49; y += 4.86136 * 0.49;
            cr.line_to(x * scale, y * scale);
            x -= 4.6846 * 0.49; y += 4.06586 * 0.49;
            cr.line_to(x * scale, y * scale);
            x -= 5.7452 * 0.49; y += 3.18198 * 0.49;
            cr.line_to(x * scale, y * scale);
            x -= 5.1266 * 0.49; y += 1.5468 * 0.49;
            cr.line_to(x * scale, y * scale);
            x -= 5.1265 * 0.49; y += 0.70711 * 0.49;
            cr.line_to(x * scale, y * scale);
            x = 657.94 * 0.49;
            cr.line_to(x * scale, y * scale);
            x -= 6.0104 * 0.49; y -= 0.17678 * 0.49;
            cr.line_to(x * scale, y * scale);
            x -= 5.3033 * 0.49; y -= 1.19324 * 0.49;
            cr.line_to(x * scale, y * scale);
            x -= 5.4801 * 0.49; y -= 2.2539 * 0.49;
            cr.line_to(x * scale, y * scale);
            x -= 4.3311 * 0.49; y -= 2.87263 * 0.49;
            cr.line_to(x * scale, y * scale);
            x -= 4.2426 * 0.49; y -= 3.7565 * 0.49;
            cr.line_to(x * scale, y * scale);
            x -= 4.0659 * 0.49; y -= 4.64039 * 0.49;
            cr.line_to(x * scale, y * scale);
            x -= 3.1819 * 0.49; y -= 5.3033 * 0.49;
            cr.line_to(x * scale, y * scale);
            x -= 1.3955 * 0.49; y -= 4.05327 * 0.49;
            cr.line_to(x * scale, y * scale);
            x -= 0.375 * 0.49; y -= 4.25 * 0.49;
            cr.line_to(x * scale, y * scale);
            cr.close_path();
        }

        private void draw_dpad_up_path(Cairo.Context cr, double scale) {
            cr.move_to(189.17 * scale, 137.87 * scale);
            cr.line_to(171.71 * scale, 155.33 * scale);
            cr.line_to(170.00 * scale, 156.49 * scale);
            cr.line_to(168.47 * scale, 157.05 * scale);
            cr.line_to(166.51 * scale, 157.29 * scale);
            cr.line_to(164.73 * scale, 157.05 * scale);
            cr.line_to(163.14 * scale, 156.24 * scale);
            cr.line_to(161.30 * scale, 154.77 * scale);
            cr.line_to(145.56 * scale, 136.71 * scale);
            cr.line_to(144.09 * scale, 134.87 * scale);
            cr.line_to(143.17 * scale, 132.55 * scale);
            cr.line_to(141.15 * scale, 107.98 * scale);
            cr.line_to(141.36 * scale, 104.86 * scale);
            cr.line_to(142.10 * scale, 102.62 * scale);
            cr.line_to(143.69 * scale, 99.96 * scale);
            cr.line_to(145.65 * scale, 97.72 * scale);
            cr.line_to(147.89 * scale, 95.95 * scale);
            cr.line_to(150.06 * scale, 94.74 * scale);
            cr.line_to(151.89 * scale, 93.98 * scale);
            cr.line_to(154.19 * scale, 93.61 * scale);
            cr.line_to(178.26 * scale, 93.61 * scale);
            cr.line_to(181.29 * scale, 94.01 * scale);
            cr.line_to(184.26 * scale, 94.96 * scale);
            cr.line_to(186.87 * scale, 96.40 * scale);
            cr.line_to(189.62 * scale, 98.79 * scale);
            cr.line_to(191.40 * scale, 100.72 * scale);
            cr.line_to(192.56 * scale, 103.04 * scale);
            cr.line_to(193.14 * scale, 105.68 * scale);
            cr.line_to(193.36 * scale, 109.32 * scale);
            cr.line_to(193.18 * scale, 113.40 * scale);
            cr.line_to(191.43 * scale, 133.94 * scale);
            cr.line_to(190.94 * scale, 135.54 * scale);
            cr.line_to(190.27 * scale, 136.64 * scale);
            cr.close_path();
        }

        private void draw_dpad_down_path(Cairo.Context cr, double scale) {
            cr.move_to(144.88 * scale, 199.19 * scale);
            cr.line_to(162.34 * scale, 181.73 * scale);
            cr.line_to(164.05 * scale, 180.57 * scale);
            cr.line_to(165.58 * scale, 180.01 * scale);
            cr.line_to(167.54 * scale, 179.77 * scale);
            cr.line_to(169.32 * scale, 180.01 * scale);
            cr.line_to(170.91 * scale, 180.81 * scale);
            cr.line_to(172.75 * scale, 182.28 * scale);
            cr.line_to(188.49 * scale, 200.35 * scale);
            cr.line_to(189.96 * scale, 202.19 * scale);
            cr.line_to(190.88 * scale, 204.51 * scale);
            cr.line_to(192.90 * scale, 229.08 * scale);
            cr.line_to(192.69 * scale, 232.20 * scale);
            cr.line_to(191.95 * scale, 234.43 * scale);
            cr.line_to(190.36 * scale, 237.10 * scale);
            cr.line_to(188.40 * scale, 239.33 * scale);
            cr.line_to(186.16 * scale, 241.11 * scale);
            cr.line_to(183.99 * scale, 242.30 * scale);
            cr.line_to(182.15 * scale, 243.07 * scale);
            cr.line_to(179.85 * scale, 243.43 * scale);
            cr.line_to(155.78 * scale, 243.43 * scale);
            cr.line_to(152.75 * scale, 243.04 * scale);
            cr.line_to(149.78 * scale, 242.09 * scale);
            cr.line_to(147.17 * scale, 240.65 * scale);
            cr.line_to(144.42 * scale, 238.26 * scale);
            cr.line_to(142.64 * scale, 236.33 * scale);
            cr.line_to(141.48 * scale, 234.00 * scale);
            cr.line_to(140.90 * scale, 231.37 * scale);
            cr.line_to(140.68 * scale, 227.72 * scale);
            cr.line_to(140.87 * scale, 223.65 * scale);
            cr.line_to(142.61 * scale, 203.10 * scale);
            cr.line_to(143.10 * scale, 201.51 * scale);
            cr.line_to(143.77 * scale, 200.41 * scale);
            cr.close_path();
        }

        private void draw_dpad_left_path(Cairo.Context cr, double scale) {
            cr.move_to(136.87 * scale, 147.03 * scale);
            cr.line_to(154.33 * scale, 164.49 * scale);
            cr.line_to(155.49 * scale, 166.20 * scale);
            cr.line_to(156.04 * scale, 167.73 * scale);
            cr.line_to(156.29 * scale, 169.69 * scale);
            cr.line_to(156.04 * scale, 171.47 * scale);
            cr.line_to(155.24 * scale, 173.06 * scale);
            cr.line_to(153.77 * scale, 174.90 * scale);
            cr.line_to(135.71 * scale, 190.64 * scale);
            cr.line_to(133.87 * scale, 192.11 * scale);
            cr.line_to(131.54 * scale, 193.03 * scale);
            cr.line_to(106.98 * scale, 195.05 * scale);
            cr.line_to(103.86 * scale, 194.84 * scale);
            cr.line_to(101.62 * scale, 194.10 * scale);
            cr.line_to(98.96 * scale, 192.51 * scale);
            cr.line_to(96.72 * scale, 190.55 * scale);
            cr.line_to(94.94 * scale, 188.31 * scale);
            cr.line_to(93.75 * scale, 186.14 * scale);
            cr.line_to(92.98 * scale, 184.30 * scale);
            cr.line_to(92.61 * scale, 182.00 * scale);
            cr.line_to(92.61 * scale, 157.93 * scale);
            cr.line_to(93.01 * scale, 154.90 * scale);
            cr.line_to(93.96 * scale, 151.93 * scale);
            cr.line_to(95.40 * scale, 149.32 * scale);
            cr.line_to(97.79 * scale, 146.57 * scale);
            cr.line_to(99.72 * scale, 144.79 * scale);
            cr.line_to(102.04 * scale, 143.63 * scale);
            cr.line_to(104.68 * scale, 143.05 * scale);
            cr.line_to(108.32 * scale, 142.83 * scale);
            cr.line_to(112.40 * scale, 143.02 * scale);
            cr.line_to(132.95 * scale, 144.76 * scale);
            cr.line_to(134.54 * scale, 145.25 * scale);
            cr.line_to(135.64 * scale, 145.92 * scale);
            cr.close_path();
        }

        private void draw_dpad_right_path(Cairo.Context cr, double scale) {
            cr.move_to(197.69 * scale, 190.94 * scale);
            cr.line_to(180.23 * scale, 173.48 * scale);
            cr.line_to(179.07 * scale, 171.77 * scale);
            cr.line_to(178.52 * scale, 170.24 * scale);
            cr.line_to(178.27 * scale, 168.28 * scale);
            cr.line_to(178.52 * scale, 166.50 * scale);
            cr.line_to(179.32 * scale, 164.91 * scale);
            cr.line_to(180.79 * scale, 163.07 * scale);
            cr.line_to(198.85 * scale, 147.33 * scale);
            cr.line_to(200.69 * scale, 145.86 * scale);
            cr.line_to(203.02 * scale, 144.95 * scale);
            cr.line_to(227.58 * scale, 142.92 * scale);
            cr.line_to(230.70 * scale, 143.14 * scale);
            cr.line_to(232.94 * scale, 143.87 * scale);
            cr.line_to(235.60 * scale, 145.46 * scale);
            cr.line_to(237.84 * scale, 147.42 * scale);
            cr.line_to(239.61 * scale, 149.66 * scale);
            cr.line_to(240.80 * scale, 151.83 * scale);
            cr.line_to(241.57 * scale, 153.67 * scale);
            cr.line_to(241.94 * scale, 155.97 * scale);
            cr.line_to(241.94 * scale, 180.04 * scale);
            cr.line_to(241.54 * scale, 183.07 * scale);
            cr.line_to(240.59 * scale, 186.04 * scale);
            cr.line_to(239.15 * scale, 188.33 * scale);
            cr.line_to(236.76 * scale, 191.64 * scale);
            cr.line_to(234.83 * scale, 193.18 * scale);
            cr.line_to(232.50 * scale, 194.34 * scale);
            cr.line_to(229.87 * scale, 194.92 * scale);
            cr.line_to(226.23 * scale, 195.14 * scale);
            cr.line_to(222.15 * scale, 194.95 * scale);
            cr.line_to(201.60 * scale, 193.21 * scale);
            cr.line_to(200.01 * scale, 192.72 * scale);
            cr.line_to(198.91 * scale, 192.04 * scale);
            cr.close_path();
        }
    }
}
