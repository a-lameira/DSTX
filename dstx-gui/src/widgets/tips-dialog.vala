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
                _("Initial development"),
                _("DSTX Service"),
                _("Multiple Controllers"),
                _("Emulation Modes"),
                "UINPUT",
                "UHID",
                _("Gyroscope and Accelerometer"),
                _("Detailed Information"),
                _("Terminal Version")
            };
            string[] general_descs = {
                _("This software is in its initial stage of development. This means it has been little tested. Expect bugs and issues, and if you find a bug, please report it in the 'Issues' section of the repository so that developers can become aware of the problem. Remember that this software provides absolutely no warranty, and any issues arising from its use are the sole responsibility of the user."),
                _("DSTX is a system service. This graphical interface is just a front-end to this service. This means that if you close this window, your LED and emulation settings will continue to work. Note that after installing the program, you need to restart your session (logout/login or restart) for the service settings to become valid."),
                _("You can connect up to 4 controllers simultaneously. Each will appear in the left sidebar. Each controller has its own independent settings. Change LED mode, rumble and deadzone individually."),
                _("DSTX creates a virtual Xbox 360 device that is recognised by the vast majority of games, enabling unsupported controllers to work in games with Xbox (Xinput) controller support. In doing so, the program turns a disadvantage (lack of native support) into a possible advantage (control over all aspects of the gamepad exposed to the game). DSTX offers two emulation modes, UINPUT and UHID."),
                _("UINPUT is a Linux kernel module that allows the creation of virtual devices from user space. It is the traditional and tested method for emulating virtual controllers, enabling support for all the capabilities of a gamepad."),
                _("UHID is a relatively new Linux kernel module that allows the creation of HID devices from user space. Currently, the UHID mode implementation is experimental and is limited to input events (buttons, axes), with no rumble support. In some scenarios, using UHID can mitigate double input issues."),
                _("Gyroscope emulation, while possible, introduces a series of technical complexities that are not planned for the initial version of the program. At present, DSTX does not support gyroscope emulation."),
                _("Click the information button (ⓘ) on the top bar to see technical details of the selected controller."),
                _("DSTX can also be used from the terminal with the command <tt>dstx</tt>. A terminal graphical interface (TUI) is provided.")
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
                _("Using the profile dialog, you can create, delete, save, and load configuration profiles. If the 'auto-save' option is enabled, any changes to the settings will be automatically saved to the current profile."),
                _("Gamepad settings apply to the emulated device, not the real controller. Emulation must be active for the settings to be available and take effect."),
                _("You can choose the method for creating the virtual Xbox 360 device (UINPUT or UHID). Note that UHID is experimental and does not support rumble."),
                _("In UINPUT emulation mode, you can enable or disable the rumble feature and set the intensity (gain) of vibration effects (0 to 100%)."),
                _("For the analog sticks, there are settings for deadzone, sensitivity and Y-axis inversion."),
                _(_("8 sensitivity modes are available for the analog sticks, each with a different response curve:\n• <b>Default</b> – linear 1:1 curve, natural controller response;\n• <b>Precision</b> – logarithmic curve, smooths movements in the center, allowing greater control over small displacements;\n• <b>Rapid</b> – exponential curve, accentuates movements, allowing quick responses with small displacements, favouring shorter reaction time;\n• <b>Smooth</b> – 'S' curve, starts smooth, accelerates in the middle, smooths at the end;\n• <b>Aggressive</b> – inverted 'S' curve, responds aggressively at the beginning and smooths at the end, favouring quick reflexes;\n• <b>Sniper</b> – extreme logarithmic curve, millimetric control in the centre with a very smooth response;\n• <b>Racing</b> – reduced linear curve, maintains proportionality, but with a longer travel;\n• <b>FPS</b> – attenuated inverted 'S' curve, precision in the centre and fast response at the edges.")),
                _("DSTX offers a feature to switch the trigger mode from analog to digital. The Xbox 360 controller has only analog triggers, and most games expect analog triggers and do not recognize digital triggers. However, in some niche cases, it is useful to output digital triggers instead of analog ones."),
                _("For the buttons there is a Debounce option (noise filtering) to attenuate double input originating from the hardware.")
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
                _("General connection Issues"),
                _("Detection by games"),
                _("Steam Input")
            };
            string[] connection_descs = {
                _("This program supports USB and Bluetooth connections. Generally, the connection is successful most of the time. However, in some scenarios the controllers may not be connected correctly by the program. In these cases, we recommend that the controllers be disconnected and reconnected. Some attempts may be necessary."),
                _("In most cases, games automatically detect the virtual controller created by DSTX. If a game fails to detect the controller, restarting the game usually resolves the issue."),
                _("The DSTX works perfectly with Steam games. Steam even detects the virtual controller as a native controller. However, if 'Steam Input' is enabled, there may be unwanted interference. To avoid issues, we recommend disabling Steam Input when using the DSTX with Steam games, and vice versa.")
            };
            container.append(create_tip_card(_("Connection"), connection_titles, connection_descs));
            
            // DualShock 4
            string[] ds4_titles = {
                _("USB connections"),
                _("Bluetooth connections")
            };
            string[] ds4_descs = {
                _("The DualShock 4 controller has known bugs caused by the kernel driver when connected via USB. Depending on the context, this can result in erratic behavior of the LEDs and rumble function, as well as double-input issues when connected via USB."),
                _("The DualShock 4 controller performs more stably and predictably when connected to DSTX via Bluetooth. At this time, we recommend using this connection method to minimize unwanted behavior.")
            };
            container.append(create_tip_card("DualShock 4", ds4_titles, ds4_descs));

            // DualSense
            string[] dualsense_titles = {
                _("Specific Issues")
            };
            string[] dualsense_descs = {
                _("The DualSense controller shows consistent behaviour between USB and Bluetooth connection modes. Generally speaking, it is the controller that has worked most consistently and stably with DSTX so far. However, in some cases, the controller may not connect properly to the program via Bluetooth, particularly with regard to the LED functionality. If the connection fails, simply disconnect and reconnect the controller.")
            };
            container.append(create_tip_card("DualSense", dualsense_titles, dualsense_descs));

            // Nintendo Switch Pro
            string[] nsw_titles = {
                _("USB connections"),
                _("Bluetooth connections")
            };
            string[] nsw_descs = {
                _("The Nintendo Switch Pro Controller generally works best when connected via USB. A known issue is that when you unplug the USB cable from the controller, it automatically reconnects via Bluetooth. In this case, disconnect the controller through your system’s Bluetooth device manager."),
                _("The Nintendo Switch Pro controller has some bugs related to Bluetooth connections, notably an offset in the X and Y values of the analog axes. Further testing is needed to determine the exact cause of the bug, but for now, the program applies empirically determined corrections to these offsets. If you are experiencing issues with incorrect analog stick values over Bluetooth connections, please file a bug report.")
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
            page.set_icon_name("preferences-color-symbolic");

            var container = new Gtk.Box(Orientation.VERTICAL, 24);
            container.set_halign(Align.FILL);
            container.set_valign(Align.START);
            container.margin_top = 24;
            container.margin_bottom = 24;
            container.margin_start = 24;
            container.margin_end = 24;

            // LED Effects
            string[] effects_titles = {
                _("LED System"),
                _("Static Mode"),
                _("Dynamic Mode"),
                _("Brightness Adjustment"),
                _("Player LEDs (DualSense)")
            };
            string[] effects_descs = {
                _("For DualShock 4 and DualSense controllers, DSTX offers a complete LED configuration system. Two modes are available: Static and Dynamic."),
                _("In static mode, you can choose a fixed colour for your controller's LED. For efficiency, the program writes the selected colour to the LED only once on the controller. This means that if another program (Steam, OpenRGB, the kernel driver, etc.) also writes an LED colour to your controller, it will overwrite the configured colour. To avoid this, the 'Reapply LED' feature is offered, which monitors these third-party write events and reapplies the colour configured in DSTX on demand."),
                _("In dynamic mode, you can choose from eight available effects. Depending on the selected effect, you can configure the base colour and speed. Note that using effects at a high speed can affect battery life on Bluetooth connections."),
                _("The brightness adjustment controls the intensity of the brightness for both operating modes of the LED system. For dynamic mode, keep in mind that the lower the brightness, the lower the resolution of the effects."),
                _("The DualSense has player indicator LEDs that can be set from 0 to 4.")
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
                _("Oscillating effects of the base colour with speed adjustment."),
                _("These effects do not use the base colour. Rainbow goes through the entire colour spectrum, and Wave alternates between cyan, yellow and magenta tones."),
                _("The LED shows the battery level: green for charged, yellow for medium, red for low."),
                _("The LED changes colour according to the intensity of trigger pressure."),
                _("The LED changes colour according to the buttons pressed.")
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
