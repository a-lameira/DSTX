/*
 * i18n.vala - Internationalization helper functions for string translation
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
 * - Provide gettext-based translation functions for the application
 * - Support standard translation, context-based translation, and plural forms
 */

// /src/i18n.vala

using GLib;

namespace Dstx {
    /**
     * Internationalization - Helper functions for string translation
     */
    
    private const string GETTEXT_PACKAGE = "dstx-gui";
    
    /**
     * Translates a string using the application's gettext domain.
     */
    public static inline string _(string msg) {
        return GLib.dgettext(GETTEXT_PACKAGE, msg);
    }
    
    /**
     * Translates a string with a context.
     */
    public static inline string C_(string ctx, string msg) {
        string indexed = @"$(ctx)\x04$(msg)";
        string translated = GLib.dgettext(GETTEXT_PACKAGE, indexed);
        if (translated == indexed || translated == "") {
            return msg;
        }
        return translated;
    }
    
    /**
     * Translates plural strings.
     */
    public static inline string ngettext(string singular, string plural, ulong n) {
        return GLib.dngettext(GETTEXT_PACKAGE, singular, plural, n);
    }
}
