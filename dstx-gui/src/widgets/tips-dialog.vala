/*
 * tips-dialog.vala - Tips and tricks dialog for DSTX GUI
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
 * - Provide tips and tricks dialog for DSTX
 * - Display general tips, controller-specific information, and LED effects
 */

// src/widgets/tips-dialog.vala

using Gtk;

namespace Dstx.Widgets {
    /**
     * TipsDialog - Tips and tricks dialog for DSTX
     */
    public class TipsDialog : Adw.PreferencesDialog {
        public TipsDialog() {
            Object(
                title: _("Tips and Tricks"),
                content_width: 700,
                content_height: 600
            );

            build_ui();
        }

        private void build_ui() {
            var general_page = create_general_page();
            add(general_page);

            var controllers_page = create_controllers_page();
            add(controllers_page);

            var led_page = create_led_page();
            add(led_page);
        }

        // ==================== HELPER METHOD TO CREATE CARDS ====================

        private Adw.Bin create_tip_card(string card_title, string[] titles, string[] descriptions) {
            assert(titles.length == descriptions.length);

            var card = new Adw.Bin();
            card.add_css_class("tip-card");
            card.set_halign(Align.FILL);
            card.set_valign(Align.START);

            var card_box = new Gtk.Box(Orientation.VERTICAL, 12);
            card_box.set_halign(Align.FILL);
            card_box.set_valign(Align.START);
            card_box.margin_top = 16;
            card_box.margin_bottom = 16;
            card_box.margin_start = 20;
            card_box.margin_end = 20;

            var title_label = new Gtk.Label(null);
            title_label.set_markup(@"<b><big>$(card_title)</big></b>");
            title_label.set_halign(Align.START);
            title_label.set_valign(Align.START);
            title_label.set_xalign(0.0f);
            title_label.add_css_class("tip-card-title");
            title_label.set_selectable(false);
            card_box.append(title_label);

            var separator = new Gtk.Separator(Orientation.HORIZONTAL);
            separator.set_halign(Align.FILL);
            card_box.append(separator);

            for (int i = 0; i < titles.length; i++) {
                var item_box = new Gtk.Box(Orientation.VERTICAL, 4);
                item_box.set_halign(Align.FILL);
                item_box.set_valign(Align.START);
                item_box.set_margin_top(4);
                item_box.set_margin_bottom(4);

                var item_title = new Gtk.Label(null);
                item_title.set_markup(@"<b>$(titles[i])</b>");
                item_title.set_halign(Align.START);
                item_title.set_valign(Align.START);
                item_title.set_xalign(0.0f);
                item_title.add_css_class("tip-item-title");
                item_title.set_selectable(false);
                item_box.append(item_title);

                var item_desc = new Gtk.Label(null);
                item_desc.set_markup(descriptions[i]);
                item_desc.set_wrap(true);
                item_desc.set_wrap_mode(Pango.WrapMode.WORD);
                item_desc.set_halign(Align.FILL);
                item_desc.set_valign(Align.START);
                item_desc.set_xalign(0.0f);
                item_desc.set_selectable(false);
                item_desc.add_css_class("tip-item-desc");
                item_box.append(item_desc);

                card_box.append(item_box);
            }

            card.set_child(card_box);
            return card;
        }

        // ==================== PAGES ====================

        private Adw.PreferencesPage create_general_page() {
            var page = new Adw.PreferencesPage();
            page.set_title(_("General"));
            page.set_icon_name("dialog-information-symbolic");

            var container = new Gtk.Box(Orientation.VERTICAL, 24);
            container.set_halign(Align.FILL);
            container.set_valign(Align.START);
            container.margin_top = 24;
            container.margin_bottom = 24;
            container.margin_start = 24;
            container.margin_end = 24;

            // General Tips
            string[] general_titles = {
                _("Still young"),
                _("Runs in the background"),
                _("Up to 4 players"),
                _("Two emulation engines"),
                "UINPUT",
                "UHID",
                _("Gyro? Not yet"),
                _("Controller info in one click"),
                _("Terminal power")
            };
            string[] general_descs = {
                _("DSTX is fresh out of the oven — expect a few rough edges. Found a bug? Please report it on GitHub. No warranty, but we'll do our best to fix it."),
                _("DSTX runs as a system service. Close the window? No worries — your LED colors and emulation keep working. After install, log out and back in once — that's it."),
                _("Connect up to 4 controllers at once. Each appears in the left panel with its own independent settings. Customize LED, rumble, deadzone per controller."),
                _("DSTX creates a virtual Xbox 360 pad — works with almost any game. Two modes: <b>UINPUT</b> (full features, rumble included) and <b>UHID</b> (experimental, no rumble but can fix double inputs)."),
                _("The classic, rock‑solid method. Creates virtual devices from user space. Full gamepad capabilities, great compatibility."),
                _("Newer kernel module, still experimental. Only handles buttons and axes (no rumble). Can help if you're experiencing double inputs with UINPUT."),
                _("Gyroscope emulation is technically possible but complex — not planned for now. Maybe in a future release!"),
                _("Click the <b>ⓘ</b> button in the top bar to see technical details of your controller: driver, serial, input nodes."),
                _("Prefer the command line? Run <tt>dstx</tt> in your terminal — a full TUI (text interface) is included.")
            };
            container.append(create_tip_card(_("General Tips"), general_titles, general_descs));

            // Settings
            string[] config_titles = {
                _("Profiles"),
                _("Emulation"),
                _("Emulation Mode"),
                "Rumble",
                _("Analog Sticks"),
                _("Stick Sensitivity"),
                _("Triggers"),
                _("Buttons")
            };
            string[] config_descs = {
                _("Create, save, load, or delete profiles. Turn on <b>auto‑save</b> and every change is automatically stored in the current profile."),
                _("Only LED talks directly to your hardware. All other settings apply to the emulated Xbox controller. Keep emulation ON for them to work."),
                _("You choose how the virtual Xbox pad is created. UINPUT is stable and feature‑complete (rumble included). UHID is experimental (no rumble) but can help with double‑input weirdness."),
                _("In UINPUT mode, you can enable/disable rumble and adjust vibration intensity (gain) from 0 to 100%."),
                _("Fine‑tune deadzone (how far you must push before it reacts), sensitivity presets, and invert Y‑axis for left and right sticks independently."),
                _(_("8 curves available:\n• <b>Default</b> – linear, natural\n• <b>Precision</b> – smooth in the center for tiny moves\n• <b>Rapid</b> – fast response, great for reflexes\n• <b>Smooth</b> – S‑curve: gentle start, faster middle\n• <b>Aggressive</b> – inverted S, quick initial snap\n• <b>Sniper</b> – ultra‑smooth for aiming\n• <b>Racing</b> – linear but longer travel\n• <b>FPS</b> – balanced precision + speed")),
                _("Flip L2/R2 from analog to digital (on/off). Most games expect analog, but in some niche cases digital can be useful."),
                _("Debounce filters out electrical noise, reducing accidental double presses from the hardware.")
            };
            container.append(create_tip_card(_("Settings"), config_titles, config_descs));

            var clamp = new Adw.Clamp();
            clamp.set_maximum_size(800);
            clamp.set_tightening_threshold(600);
            clamp.set_child(container);

            var row = new Adw.ActionRow();
            row.set_activatable(false);
            row.set_selectable(false);
            row.set_child(clamp);
            row.set_halign(Align.FILL);

            var group = new Adw.PreferencesGroup();
            group.add(row);
            page.add(group);

            return page;
        }

        private Adw.PreferencesPage create_controllers_page() {
            var page = new Adw.PreferencesPage();
            page.set_title(_("Controllers"));
            page.set_icon_name("input-gaming-symbolic");

            var container = new Gtk.Box(Orientation.VERTICAL, 24);
            container.set_halign(Align.FILL);
            container.set_valign(Align.START);
            container.margin_top = 24;
            container.margin_bottom = 24;
            container.margin_start = 24;
            container.margin_end = 24;

            // Connection
            string[] connection_titles = {
                _("Connection hiccups"),
                _("Game not seeing the controller?"),
                _("Steam Input conflict")
            };
            string[] connection_descs = {
                _("USB and Bluetooth usually work great. If a controller isn't detected, try disconnecting and reconnecting it a couple of times."),
                _("Most games auto‑detect the virtual Xbox pad. If one doesn't, restart the game — that often fixes it."),
                _("DSTX works great with Steam games, but if <b>Steam Input</b> is on, it can interfere. Disable Steam Input when using DSTX, or disable DSTX emulation when using Steam Input.")
            };
            container.append(create_tip_card(_("Connection"), connection_titles, connection_descs));
            
            // DualShock 4
            string[] ds4_titles = {
                _("USB quirks"),
                _("Bluetooth connections")
            };
            string[] ds4_descs = {
                _("The kernel driver has some bugs over USB — LEDs and rumble may act weird, and double inputs can happen — it's a known issue."),
                _("DualShock 4 behaves much better over Bluetooth. We recommend using Bluetooth for the best experience.")
            };
            container.append(create_tip_card("DualShock 4", ds4_titles, ds4_descs));

            // DualSense
            string[] dualsense_titles = {
                _("Solid performer")
            };
            string[] dualsense_descs = {
                _("DualSense is the most stable controller so far — USB and Bluetooth both work well. On rare occasions, Bluetooth LED control may fail; just disconnect and reconnect.")
            };
            container.append(create_tip_card("DualSense", dualsense_titles, dualsense_descs));

            // Nintendo Switch Pro
            string[] nsw_titles = {
                _("USB works best"),
                _("Bluetooth quirks")
            };
            string[] nsw_descs = {
                _("Best experience is over USB. One catch: unplugging USB automatically reconnects via Bluetooth. If that happens, manually disconnect the controller in your system's Bluetooth settings."),
                _("Over Bluetooth, analog sticks may show a slight offset (Kernel-related). DSTX applies empirical corrections, but if you still see wrong values, please file a bug report.")
            };
            container.append(create_tip_card(_("Nintendo Switch Pro"), nsw_titles, nsw_descs));

            var clamp = new Adw.Clamp();
            clamp.set_maximum_size(800);
            clamp.set_tightening_threshold(600);
            clamp.set_child(container);

            var row = new Adw.ActionRow();
            row.set_activatable(false);
            row.set_selectable(false);
            row.set_child(clamp);
            row.set_halign(Align.FILL);

            var group = new Adw.PreferencesGroup();
            group.add(row);
            page.add(group);

            return page;
        }

        private Adw.PreferencesPage create_led_page() {
            var page = new Adw.PreferencesPage();
            page.set_title("LED");
            page.set_icon_name("image-adjust-color-symbolic");

            var container = new Gtk.Box(Orientation.VERTICAL, 24);
            container.set_halign(Align.FILL);
            container.set_valign(Align.START);
            container.margin_top = 24;
            container.margin_bottom = 24;
            container.margin_start = 24;
            container.margin_end = 24;

            // LED Effects
            string[] effects_titles = {
                _("Light it up"),
                _("Static Mode"),
                _("Dynamic Mode"),
                _("Brightness Adjustment"),
                _("Player LEDs (DualSense)")
            };
            string[] effects_descs = {
                _("Only for DualShock 4 and DualSense. Two modes: Static (fixed color) and Dynamic (moving effects)."),
                _("Pick any color. The LED is written only once, so other apps (Steam, OpenRGB) may overwrite it. Turn on <b>Reapply LED</b> to fight back and keep your color."),
                _("Choose from 8 effects. Depending on the effect, you can set a base color and speed. High speed = more battery drain over Bluetooth."),
                _("Brightness affects both static and dynamic modes. Lower brightness in dynamic mode reduces effect resolution."),
                _("DualSense has small player indicator LEDs (0–4). Set which number lights up.")
            };
            container.append(create_tip_card(_("LED Effects"), effects_titles, effects_descs));

            // Specific Effects
            string[] specific_titles = {
                _("Breathing, Pulse and Blink"),
                _("Rainbow and Wave"),
                _("Battery"),
                _("Triggers"),
                _("Buttons")
            };
            string[] specific_descs = {
                _("Oscillate your base color — speed adjustable."),
                _("Rainbow cycles through the spectrum. Wave alternates between cyan, yellow, and magenta — no base color used."),
                _("LED shows battery level: green = full, yellow = medium, red = low."),
                _("LED changes color based on how hard you pull L2/R2."),
                _("Color reacts to button presses.")
            };
            container.append(create_tip_card(_("Specific Effects"), specific_titles, specific_descs));

            var clamp = new Adw.Clamp();
            clamp.set_maximum_size(800);
            clamp.set_tightening_threshold(600);
            clamp.set_child(container);

            var row = new Adw.ActionRow();
            row.set_activatable(false);
            row.set_selectable(false);
            row.set_child(clamp);
            row.set_halign(Align.FILL);

            var group = new Adw.PreferencesGroup();
            group.add(row);
            page.add(group);

            return page;
        }
    }
}
