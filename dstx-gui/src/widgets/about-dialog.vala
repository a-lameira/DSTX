/*
 * about-dialog.vala - Factory for the "About" dialog of DSTX GUI
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
 * - Create and configure the DSTX About dialog
 */

// src/widgets/about-dialog.vala

using Gtk;

namespace Dstx.Widgets {
    /**
     * Adw.AboutDialog is a sealed class, so it cannot be inherited.
     * This class provides a static method to create and configure the dialog.
     */
    public class AboutDialog {
        /**
         * Creates and configures the DSTX "About" dialog
         * @return Configured Adw.AboutDialog
         */
        public static Adw.AboutDialog create() {
            var about = new Adw.AboutDialog() {
                application_name = "DSTX",
                application_icon = "dstx",
                version = "0.7.0",
                developer_name = "André Lameira",
                copyright = "© 2026 André Lameira",
                license_type = Gtk.License.GPL_3_0,
                website = "https://dstxapp.org",
                issue_url = "https://github.com/a-lameira/DSTX/issues",
                support_url = "https://discord.gg/dstx"
            };

            string[] developers = { "André Lameira" };
            string[] artists = { "André Lameira, Renata Rabbat" };

            about.developers = developers;
            about.artists = artists;
            about.translator_credits = "André Lameira";

            return about;
        }
    }
}
