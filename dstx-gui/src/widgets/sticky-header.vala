/*
 * sticky-header.vala - Sticky header for accent color selection in appearance page
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
 * - Create and manage a sticky header bar with accent color buttons
 * - Monitor scroll position and attach/detach sticky header with hysteresis
 * - Handle page visibility and custom mode state
 * - Provide accent color selection via buttons in the sticky header
 */

// src/widgets/sticky-header.vala

using Gtk;
using Gdk;
using Adw;
using Gee;

namespace Dstx.Widgets {

    public delegate Gdk.RGBA[] GetAccentColorsFunc();
    public delegate int GetSelectedIndexFunc();
    public delegate Gdk.RGBA GetSelectedColorFunc();
    public delegate void AccentSelectedCallback(int index, Gdk.RGBA color);

    public class StickyHeader : Object {
        private weak PreferencesDialog? dialog = null;
        private weak ToolbarView? toolbar_view = null;
        private Adw.HeaderBar? sticky_header = null;
        private Gtk.Box? sticky_accent_box = null;
        
        private bool is_attached = false;
        private bool is_visible = false;
        private double scroll_position = 0;
        private double last_evaluated_scroll = -1;
        private Gtk.Adjustment? target_adjustment = null;
        private ulong scroll_handler_id = 0;
        private uint scroll_monitor_enabled = 0;
        private uint sticky_update_timeout = 0;
        private uint creation_destruction_timeout = 0;
        private uint retry_timeout = 0;
        private int retry_count = 0;
        private bool is_active_page = false;
        private bool is_custom_mode = false;
        
        private GetAccentColorsFunc get_accent_colors;
        private GetSelectedIndexFunc get_selected_index;
        private GetSelectedColorFunc get_selected_color;
        private AccentSelectedCallback on_accent_selected;
        
        private const int THRESHOLD = 150;
        private const int HYSTERESIS = 50;
        private const uint SCROLL_EVALUATION_THROTTLE_MS = 16;
        private const uint CREATION_DESTRUCTION_DELAY_MS = 100;
        private const uint STICKY_UPDATE_DELAY_MS = 50;
        private const uint MAX_RETRY_ATTEMPTS = 5;
        private const uint RETRY_BASE_DELAY_MS = 200;
        
        private uint page_switch_timeout = 0;
        private uint adjustment_retry_timeout = 0;
        private int adjustment_retry_count = 0;
        private const uint ADJUSTMENT_RETRY_DELAY_MS = 200;
        private const uint MAX_ADJUSTMENT_RETRIES = 5;
        
        // Hysteresis
        private bool pending_attach = false;
        private bool pending_detach = false;
        private uint hysteresis_timeout = 0;
        private const uint HYSTERESIS_DELAY_MS = 80;
        
        public StickyHeader(PreferencesDialog dialog,
                            owned GetAccentColorsFunc get_accent_colors,
                            owned GetSelectedIndexFunc get_selected_index,
                            owned GetSelectedColorFunc get_selected_color,
                            owned AccentSelectedCallback on_accent_selected) {
            this.dialog = dialog;
            this.get_accent_colors = (owned) get_accent_colors;
            this.get_selected_index = (owned) get_selected_index;
            this.get_selected_color = (owned) get_selected_color;
            this.on_accent_selected = (owned) on_accent_selected;
            
            message("StickyHeader: Initialized");
            find_toolbar_view();
        }
        
        public void enable_scroll_monitoring() {
            scroll_monitor_enabled++;
            message("StickyHeader: enable_scroll_monitoring, counter=%u", scroll_monitor_enabled);
            if (scroll_monitor_enabled == 1 && target_adjustment == null) {
                identify_target_adjustment();
            } else if (scroll_monitor_enabled == 1 && target_adjustment != null) {
                update_current_scroll_position();
            }
        }
        
        public void disable_scroll_monitoring() {
            if (scroll_monitor_enabled > 0) scroll_monitor_enabled--;
            message("StickyHeader: disable_scroll_monitoring, counter=%u", scroll_monitor_enabled);
            if (scroll_monitor_enabled == 0) {
                if (scroll_handler_id != 0 && target_adjustment != null) {
                    target_adjustment.disconnect(scroll_handler_id);
                    scroll_handler_id = 0;
                }
                target_adjustment = null;
                scroll_position = 0;
                last_evaluated_scroll = -1;
                if (adjustment_retry_timeout != 0) {
                    Source.remove(adjustment_retry_timeout);
                    adjustment_retry_timeout = 0;
                }
                adjustment_retry_count = 0;
                cancel_hysteresis();
            }
        }
        
        public void force_reevaluate() {
            message("StickyHeader: force_reevaluate requested");
            if (is_active_page && is_custom_mode) {
                identify_target_adjustment();
                update_current_scroll_position();
                evaluate_and_update_header();
            }
        }
        
        public void update_buttons() {
            schedule_sticky_update();
        }
        
        public void set_page_active(bool active) {
            message("StickyHeader: set_page_active = %s", active.to_string());
            is_active_page = active;
            if (!is_active_page) {
                disable_scroll_monitoring();
                if (retry_timeout != 0) {
                    Source.remove(retry_timeout);
                    retry_timeout = 0;
                }
                if (is_attached) {
                    destroy_sticky_header();
                }
                cancel_hysteresis();
            } else {
                if (is_custom_mode) {
                    enable_scroll_monitoring();
                    update_current_scroll_position();
                    evaluate_and_update_header();
                }
            }
        }
        
        public void set_custom_mode(bool custom) {
            message("StickyHeader: set_custom_mode = %s", custom.to_string());
            is_custom_mode = custom;
            if (!custom && is_attached) {
                schedule_destruction();
            } else if (custom && is_active_page) {
                enable_scroll_monitoring();
                update_current_scroll_position();
                evaluate_and_update_header();
            } else if (!custom) {
                disable_scroll_monitoring();
            }
        }
        
        public bool get_visible() {
            return is_attached && is_visible;
        }
        
        private void update_current_scroll_position() {
            if (target_adjustment != null) {
                scroll_position = target_adjustment.get_value();
                last_evaluated_scroll = scroll_position;
                message("StickyHeader: scroll_position updated = %.1f", scroll_position);
            }
        }
        
        private void find_toolbar_view() {
            if (dialog == null) {
                warning("StickyHeader: dialog is null");
                return;
            }
            message("StickyHeader: Looking for ToolbarView...");
            var found = find_toolbar_view_recursive(dialog);
            if (found != null) {
                toolbar_view = found;
                message("StickyHeader: ToolbarView found");
                setup_page_monitoring();
            } else {
                message("StickyHeader: ToolbarView not found, scheduling retry");
                schedule_retry_find_toolbar();
            }
        }
        
        private void schedule_retry_find_toolbar() {
            if (retry_timeout != 0) Source.remove(retry_timeout);
            if (retry_count >= MAX_RETRY_ATTEMPTS) {
                warning("StickyHeader: Maximum retry attempts reached, giving up on finding ToolbarView");
                retry_count = 0;
                return;
            }
            uint delay = RETRY_BASE_DELAY_MS * (retry_count + 1);
            message("StickyHeader: Attempt %d to find ToolbarView in %u ms", retry_count+1, delay);
            retry_timeout = Timeout.add(delay, () => {
                var found = find_toolbar_view_recursive(dialog);
                if (found != null) {
                    toolbar_view = found;
                    message("StickyHeader: ToolbarView found on attempt %d", retry_count+1);
                    setup_page_monitoring();
                    if (is_custom_mode && is_active_page) {
                        enable_scroll_monitoring();
                        update_current_scroll_position();
                        evaluate_and_update_header();
                    }
                    retry_timeout = 0;
                    retry_count = 0;
                } else {
                    retry_count++;
                    schedule_retry_find_toolbar();
                }
                return Source.REMOVE;
            });
        }
        
        private ToolbarView? find_toolbar_view_recursive(Widget widget) {
            if (widget == null) return null;
            if (widget is ToolbarView) return widget as ToolbarView;
            var child = widget.get_first_child();
            while (child != null) {
                var result = find_toolbar_view_recursive(child);
                if (result != null) return result;
                child = child.get_next_sibling();
            }
            return null;
        }
        
        private void setup_page_monitoring() {
            if (dialog == null) return;
            dialog.notify["visible-page"].connect(() => {
                schedule_page_update();
            });
            message("StickyHeader: Page monitoring configured");
        }
        
        private void schedule_page_update() {
            if (page_switch_timeout != 0) Source.remove(page_switch_timeout);
            page_switch_timeout = Timeout.add(50, () => {
                evaluate_and_update_header();
                page_switch_timeout = 0;
                return Source.REMOVE;
            });
        }
        
        // ==================== Scroll monitoring ====================
        
        private void identify_target_adjustment() {
            if (!is_active_page) {
                message("StickyHeader: Inactive page, ignoring adjustment identification");
                return;
            }
            if (dialog == null) {
                warning("StickyHeader: dialog is null, cannot identify adjustment");
                return;
            }
            
            if (target_adjustment != null && scroll_handler_id != 0) {
                message("StickyHeader: Already monitoring a valid adjustment");
                return;
            }
            
            message("StickyHeader: Collecting scroll adjustments...");
            var valid_adjustments = new ArrayList<Gtk.Adjustment>();
            collect_valid_vadjustments(dialog, valid_adjustments);
            message("StickyHeader: Found %u adjustments with real scroll", valid_adjustments.size);
            
            if (valid_adjustments.size == 0) {
                warning("StickyHeader: No adjustment with scroll found");
                schedule_adjustment_retry();
                return;
            }
            
            Gtk.Adjustment? best_adj = null;
            double max_upper = 0;
            foreach (var adj in valid_adjustments) {
                double upper = adj.get_upper();
                if (upper > max_upper) {
                    max_upper = upper;
                    best_adj = adj;
                }
            }
            
            if (best_adj != null) {
                target_adjustment = best_adj;
                message("StickyHeader: Target adjustment selected (upper=%.1f, page_size=%.1f)",
                        max_upper, target_adjustment.get_page_size());
                
                if (scroll_handler_id != 0) {
                    target_adjustment.disconnect(scroll_handler_id);
                    scroll_handler_id = 0;
                }
                
                scroll_handler_id = target_adjustment.notify["value"].connect(() => {
                    if (scroll_monitor_enabled == 0 || !is_active_page) return;
                    double new_position = target_adjustment.get_value();
                    if (Math.fabs(new_position - scroll_position) > 1.0) {
                        scroll_position = new_position;
                        if (last_evaluated_scroll < 0 || Math.fabs(scroll_position - last_evaluated_scroll) > 5.0) {
                            last_evaluated_scroll = scroll_position;
                            evaluate_and_update_header();
                        } else {
                            Timeout.add(SCROLL_EVALUATION_THROTTLE_MS, () => {
                                if (Math.fabs(scroll_position - last_evaluated_scroll) > 1.0) {
                                    last_evaluated_scroll = scroll_position;
                                    evaluate_and_update_header();
                                }
                                return Source.REMOVE;
                            });
                        }
                    }
                });
                
                scroll_position = target_adjustment.get_value();
                last_evaluated_scroll = scroll_position;
                message("StickyHeader: Scroll monitoring activated, initial position=%.1f", scroll_position);
                adjustment_retry_count = 0;
            } else {
                warning("StickyHeader: No suitable adjustment found");
                schedule_adjustment_retry();
            }
        }
        
        private void collect_valid_vadjustments(Widget widget, ArrayList<Gtk.Adjustment> list) {
            if (widget == null) return;
            if (widget is ScrolledWindow) {
                var sw = widget as ScrolledWindow;
                var vadj = sw.get_vadjustment();
                if (vadj != null) {
                    double upper = vadj.get_upper();
                    double page_size = vadj.get_page_size();
                    if (upper > page_size + 1.0) {
                        list.add(vadj);
                        message("StickyHeader: Valid adjustment found (upper=%.1f, page=%.1f)", upper, page_size);
                    } else {
                        message("StickyHeader: Ignored adjustment (upper=%.1f, page=%.1f) - no scroll", upper, page_size);
                    }
                }
            }
            var child = widget.get_first_child();
            while (child != null) {
                collect_valid_vadjustments(child, list);
                child = child.get_next_sibling();
            }
        }
        
        private void schedule_adjustment_retry() {
            if (adjustment_retry_timeout != 0) return;
            if (adjustment_retry_count >= MAX_ADJUSTMENT_RETRIES) {
                warning("StickyHeader: Maximum retry attempts to find adjustment reached");
                adjustment_retry_count = 0;
                return;
            }
            adjustment_retry_count++;
            message("StickyHeader: Attempt %d/%u to find adjustment in %u ms",
                    adjustment_retry_count, MAX_ADJUSTMENT_RETRIES, ADJUSTMENT_RETRY_DELAY_MS);
            adjustment_retry_timeout = Timeout.add(ADJUSTMENT_RETRY_DELAY_MS, () => {
                if (is_active_page && is_custom_mode) {
                    identify_target_adjustment();
                }
                adjustment_retry_timeout = 0;
                return Source.REMOVE;
            });
        }
        
        // ==================== Hysteresis ====================
        
        private void cancel_hysteresis() {
            if (hysteresis_timeout != 0) {
                Source.remove(hysteresis_timeout);
                hysteresis_timeout = 0;
            }
            pending_attach = false;
            pending_detach = false;
        }
        
        private void schedule_attach() {
            if (pending_attach) return;
            cancel_hysteresis();
            pending_attach = true;
            message("StickyHeader: Scheduling attach (hysteresis)");
            hysteresis_timeout = Timeout.add(HYSTERESIS_DELAY_MS, () => {
                if (pending_attach && !is_attached && should_header_exist()) {
                    message("StickyHeader: Confirming attach after hysteresis");
                    schedule_creation();
                }
                pending_attach = false;
                hysteresis_timeout = 0;
                return Source.REMOVE;
            });
        }
        
        private void schedule_detach() {
            if (pending_detach) return;
            cancel_hysteresis();
            pending_detach = true;
            message("StickyHeader: Scheduling detach (hysteresis)");
            hysteresis_timeout = Timeout.add(HYSTERESIS_DELAY_MS, () => {
                if (pending_detach && is_attached && !should_header_exist()) {
                    message("StickyHeader: Confirming detach after hysteresis");
                    schedule_destruction();
                }
                pending_detach = false;
                hysteresis_timeout = 0;
                return Source.REMOVE;
            });
        }
        
        // ==================== Header creation and destruction ====================
        
        private void evaluate_and_update_header() {
            bool should_exist = should_header_exist();
            message("StickyHeader: evaluate_and_update_header, should_exist=%s, is_attached=%s, scroll=%.1f",
                    should_exist.to_string(), is_attached.to_string(), scroll_position);
            
            if (should_exist && !is_attached) {
                // Schedule with hysteresis
                schedule_attach();
            } else if (!should_exist && is_attached) {
                schedule_detach();
            } else if (is_attached) {
                update_header_visibility();
                // If attached and state hasn't changed, cancel any pending hysteresis
                cancel_hysteresis();
            } else {
                // Not attached and should not exist: cancel any pending hysteresis
                cancel_hysteresis();
            }
        }
        
        private bool should_header_exist() {
            if (!is_active_page) return false;
            if (!is_custom_mode) return false;
            bool exists;
            if (is_attached) {
                // If already attached, only detach if scroll is below the lower threshold
                exists = scroll_position > (THRESHOLD - HYSTERESIS);
            } else {
                // If not attached, only attach if scroll is above the upper threshold
                exists = scroll_position > (THRESHOLD + HYSTERESIS);
            }
            message("StickyHeader: should_header_exist = %s (scroll=%.1f, attached=%s)",
                    exists.to_string(), scroll_position, is_attached.to_string());
            return exists;
        }
        
        private void schedule_creation() {
            if (creation_destruction_timeout != 0) Source.remove(creation_destruction_timeout);
            creation_destruction_timeout = Timeout.add(CREATION_DESTRUCTION_DELAY_MS, () => {
                create_sticky_header();
                creation_destruction_timeout = 0;
                return Source.REMOVE;
            });
            message("StickyHeader: Sticky header creation scheduled");
        }
        
        private void create_sticky_header() {
            if (is_attached) {
                message("StickyHeader: Already attached, ignoring creation");
                return;
            }
            if (toolbar_view == null) {
                warning("StickyHeader: toolbar_view is null, cannot create sticky header");
                return;
            }
            
            message("StickyHeader: Creating sticky header...");
            sticky_header = new Adw.HeaderBar();
            sticky_header.set_show_start_title_buttons(false);
            sticky_header.set_show_end_title_buttons(false);
            sticky_header.add_css_class("flat");
            sticky_header.add_css_class("sticky-header");
            
            string transition_css = """
                .sticky-header {
                    transition: opacity 200ms ease-in-out;
                }
            """;
            try {
                var provider = new Gtk.CssProvider();
                provider.load_from_string(transition_css);
                var display = Gdk.Display.get_default();
                if (display != null) {
                    Gtk.StyleContext.add_provider_for_display(display, provider, Gtk.STYLE_PROVIDER_PRIORITY_APPLICATION);
                }
            } catch (Error e) {
                warning("StickyHeader: Error loading transition CSS: %s", e.message);
            }
            
            sticky_accent_box = new Gtk.Box(Orientation.HORIZONTAL, 4);
            sticky_accent_box.halign = Align.CENTER;
            sticky_accent_box.margin_start = 12;
            sticky_accent_box.margin_end = 12;
            sticky_accent_box.hexpand = true;
            sticky_header.set_title_widget(sticky_accent_box);
            sticky_header.set_size_request(-1, 46);
            
            populate_sticky_buttons();
            toolbar_view.add_top_bar(sticky_header);
            sticky_header.set_opacity(1.0);
            
            is_attached = true;
            is_visible = true;
            message("StickyHeader: Sticky header created and attached successfully");
            cancel_hysteresis(); // clear pending state
        }
        
        private void schedule_destruction() {
            if (creation_destruction_timeout != 0) Source.remove(creation_destruction_timeout);
            creation_destruction_timeout = Timeout.add(CREATION_DESTRUCTION_DELAY_MS, () => {
                destroy_sticky_header();
                creation_destruction_timeout = 0;
                return Source.REMOVE;
            });
            message("StickyHeader: Sticky header destruction scheduled");
        }
        
        private void destroy_sticky_header() {
            if (!is_attached) {
                message("StickyHeader: Not attached, ignoring destruction");
                return;
            }
            message("StickyHeader: Destroying sticky header...");
            if (sticky_accent_box != null) {
                Widget? child = sticky_accent_box.get_first_child();
                while (child != null) {
                    var next = child.get_next_sibling();
                    sticky_accent_box.remove(child);
                    child.destroy();
                    child = next;
                }
                sticky_accent_box = null;
            }
            if (toolbar_view != null && sticky_header != null) {
                toolbar_view.remove(sticky_header);
                sticky_header.destroy();
            }
            sticky_header = null;
            is_attached = false;
            is_visible = false;
            message("StickyHeader: Sticky header destroyed");
            cancel_hysteresis();
        }
        
        private void update_header_visibility() {
            if (!is_attached || sticky_header == null) return;
            bool should_show = should_header_exist();
            sticky_header.set_opacity(should_show ? 1.0 : 0.0);
            is_visible = should_show;
            message("StickyHeader: Visibility updated to %s", should_show.to_string());
        }
        
        // ==================== Sticky header buttons ====================
        
        private void populate_sticky_buttons() {
            if (sticky_accent_box == null) return;
            
            Widget? child = sticky_accent_box.get_first_child();
            while (child != null) {
                var next = child.get_next_sibling();
                sticky_accent_box.remove(child);
                child.destroy();
                child = next;
            }
            
            if (is_custom_mode) {
                Gdk.RGBA[] colors = get_accent_colors();
                int max_colors = int.min(colors.length, 10);
                message("StickyHeader: Populating %d color buttons", max_colors);
                for (int i = 0; i < max_colors; i++) {
                    var button = create_sticky_accent_button(colors[i], i);
                    sticky_accent_box.append(button);
                }
            } else {
                message("StickyHeader: Non-custom mode, no buttons added");
            }
            sticky_accent_box.set_halign(Align.CENTER);
        }
        
        private Button create_sticky_accent_button(Gdk.RGBA color, int index) {
            var button = new Button();
            button.set_size_request(38, 38);
            button.add_css_class("flat");
            button.add_css_class("accent-button");
            
            string no_hover_css = """
                button.accent-button {
                    background: transparent;
                    border: none;
                    padding: 0;
                    margin: 0;
                }
                button.accent-button:hover {
                    background-color: transparent;
                    box-shadow: none;
                }
            """;
            try {
                var hover_provider = new Gtk.CssProvider();
                hover_provider.load_from_string(no_hover_css);
                var display = Gdk.Display.get_default();
                if (display != null) {
                    Gtk.StyleContext.add_provider_for_display(display, hover_provider, Gtk.STYLE_PROVIDER_PRIORITY_USER);
                }
            } catch (Error e) {
                warning("StickyHeader: Error applying button CSS: %s", e.message);
            }
            
            var drawing = new DrawingArea();
            drawing.set_size_request(34, 34);
            drawing.set_margin_start(2);
            drawing.set_margin_end(2);
            drawing.set_margin_top(2);
            drawing.set_margin_bottom(2);
            drawing.add_css_class("accent-swatch");
            drawing.set_halign(Align.CENTER);
            drawing.set_valign(Align.CENTER);
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
                if (index == get_selected_index()) {
                    int selection_radius = circle_radius + 3;
                    var sel_color = get_selected_color();
                    cr.set_source_rgba(sel_color.red, sel_color.green, sel_color.blue, 1.0);
                    cr.set_line_width(3.0);
                    cr.arc(center_x, center_y, selection_radius, 0, 2 * Math.PI);
                    cr.stroke();
                }
            });
            
            button.clicked.connect(() => {
                message("StickyHeader: Color %d selected", index);
                on_accent_selected(index, color);
                schedule_sticky_update();
            });
            
            button.set_halign(Align.CENTER);
            return button;
        }
        
        private void schedule_sticky_update() {
            if (!is_attached) return;
            if (sticky_update_timeout != 0) Source.remove(sticky_update_timeout);
            sticky_update_timeout = Timeout.add(STICKY_UPDATE_DELAY_MS, () => {
                if (is_attached) populate_sticky_buttons();
                sticky_update_timeout = 0;
                return Source.REMOVE;
            });
        }
        
        ~StickyHeader() {
            message("StickyHeader: Destroying and cleaning resources");
            if (creation_destruction_timeout != 0) Source.remove(creation_destruction_timeout);
            if (sticky_update_timeout != 0) Source.remove(sticky_update_timeout);
            if (page_switch_timeout != 0) Source.remove(page_switch_timeout);
            if (retry_timeout != 0) Source.remove(retry_timeout);
            if (adjustment_retry_timeout != 0) Source.remove(adjustment_retry_timeout);
            cancel_hysteresis();
            disable_scroll_monitoring();
            destroy_sticky_header();
        }
    }
}
