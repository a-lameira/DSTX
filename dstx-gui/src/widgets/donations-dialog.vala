/*
 * donations-dialog.vala - Donation dialog to support the DSTX project
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
 * - Provide donation options (Ko-fi, PayPal, GitHub Sponsors, PIX)
 * - Handle clipboard copy for PIX key
 * - Open URLs in external browser
 */

// src/widgets/donations-dialog.vala

using Gtk;

namespace Dstx.Widgets {
    /**
     * DonationsDialog - Donation dialog to support the DSTX project
     */
    public class DonationsDialog : Adw.PreferencesDialog {
        private Gtk.Window? parent = null;

        public DonationsDialog(Gtk.Window? parent_window = null) {
            Object(
                title: _("Support the DSTX Project"),
                content_width: 650,
                content_height: 550
            );

            this.parent = parent_window;
            build_ui();
        }

        private void build_ui() {
            var page = new Adw.PreferencesPage();
            page.set_title(_("Donations"));

            var info_group = new Adw.PreferencesGroup();
            info_group.set_title(_("Contribute"));
            info_group.set_description(_("DSTX is an open source and free software project. Your donation helps keep development active and improves the software."));

            page.add(info_group);

            var donate_group = new Adw.PreferencesGroup();
            donate_group.set_title(_("Donation Platforms"));

            // Ko-fi
            donate_group.add(create_donation_row(
                "Ko-fi",
                _("Support with coffee ☕"),
                "https://ko-fi.com/alameira",
                _("Donate on Ko-fi")
            ));

            // PayPal
            donate_group.add(create_donation_row(
                "PayPal",
                _("One-time or recurring donation"),
                "https://paypal.me/a-lameira",
                _("Donate on PayPal")
            ));

            // GitHub Sponsors
            donate_group.add(create_donation_row(
                "GitHub Sponsors",
                _("Support via GitHub"),
                "https://github.com/sponsors/dstx",
                _("GitHub Sponsors")
            ));

            // PIX (Brazil)
            donate_group.add(create_pix_row());

            page.add(donate_group);

            var thanks_group = new Adw.PreferencesGroup();
            thanks_group.set_title(_("Thank you for considering supporting the project! 💜"));

            page.add(thanks_group);

            add(page);
        }

        private Adw.ActionRow create_donation_row(string title, string subtitle, string url, string button_label) {
            var row = new Adw.ActionRow();
            row.set_title(title);
            row.set_subtitle(subtitle);

            var button = new Gtk.Button.with_label(button_label);
            button.add_css_class("suggested-action");
            button.add_css_class("compact-button");
            button.clicked.connect(() => open_url(url));

            var icon = new Gtk.Image.from_icon_name("help-about-symbolic");
            row.add_prefix(icon);
            row.add_suffix(button);
            row.set_activatable_widget(button);

            return row;
        }

        private Adw.ActionRow create_pix_row() {
            var row = new Adw.ActionRow();
            row.set_title(_("PIX (Brazil)"));
            row.set_subtitle(_("Key: dstx@dstxapp.org"));

            var button = new Gtk.Button.with_label(_("Copy Key"));
            button.add_css_class("suggested-action");
            button.add_css_class("compact-button");
            button.clicked.connect(() => {
                if (parent != null) {
                    var clipboard = parent.get_clipboard();
                    clipboard.set_text("dstx@dstxapp.org");

                    var success_dialog = new Adw.AlertDialog(
                        _("Key copied!"),
                        _("The PIX key has been copied to the clipboard.")
                    );
                    success_dialog.add_response("ok", _("OK"));
                    success_dialog.set_default_response("ok");
                    success_dialog.set_close_response("ok");
                    success_dialog.present(parent);
                }
            });

            var icon = new Gtk.Image.from_icon_name("help-about-symbolic");
            row.add_prefix(icon);
            row.add_suffix(button);
            row.set_activatable_widget(button);

            return row;
        }

        private void open_url(string url) {
            try {
                var launcher = new Gtk.UriLauncher(url);
                if (parent != null) {
                    launcher.launch.begin(parent, null, (obj, res) => {
                        try {
                            launcher.launch.end(res);
                        } catch (Error e) {
                            warning(_("Error opening link: %s"), e.message);
                        }
                    });
                } else {
                    launcher.launch.begin(null, null, (obj, res) => {
                        try {
                            launcher.launch.end(res);
                        } catch (Error e) {
                            warning(_("Error opening link: %s"), e.message);
                        }
                    });
                }
            } catch (Error e) {
                warning(_("Error creating launcher: %s"), e.message);
            }
        }
    }
}
