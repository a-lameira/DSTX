/*
 * locale-manager.vala - Locale and internationalization management for DSTX GUI
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
 * - Manage application locale and language settings
 * - Provide language selection and persistence
 * - Initialize gettext translations
 * - Handle system and custom language modes
 */

// src/core/locale-manager.vala

using GLib;

namespace Dstx.Core {
    public class LocaleManager : Object {
        private static LocaleManager? instance = null;
        private SettingsManager settings;
        
        private const string GETTEXT_PACKAGE = "dstx-gui";
        private const string LOCALEDIR = "";
        
        public const string[] LANGUAGE_CODES = {
            "",        // 0: System
            "pt_BR",   // 1: Portuguese (Brazil)
            "en_US",   // 2: English
            "es_ES",   // 3: Spanish
            "fr",      // 4: French
            "de",      // 5: German
            "it",      // 6: Italian
            "ru"       // 7: Russian
        };
        
        public const string[] LANGUAGE_NAMES_NATIVE = {
            "System",
            "Português (Brasil)",
            "English",
            "Español",
            "Français",
            "Deutsch",
            "Italiano",
            "Русский"
        };
        
        public const string[] LANGUAGE_NAMES_ENGLISH = {
            "System",
            "Portuguese (Brazil)",
            "English",
            "Spanish",
            "French",
            "German",
            "Italian",
            "Russian"
        };
        
        public signal void language_changed(int old_id, int new_id);
        
        private LocaleManager() {
            settings = SettingsManager.get_default();
        }
        
        public static LocaleManager get_default() {
            if (instance == null) {
                instance = new LocaleManager();
            }
            return instance;
        }
        
        private string get_locale_dir() {
            if (LOCALEDIR != "") {
                return LOCALEDIR;
            }
            if (FileUtils.test("/app/share/locale", FileTest.EXISTS)) {
                return "/app/share/locale";
            }
            if (FileUtils.test("/usr/share/locale", FileTest.EXISTS)) {
                return "/usr/share/locale";
            }
            return "/usr/share/locale";
        }
        
        public int get_current_language_id() {
            return settings.get_language();
        }
        
        public void set_language(int lang_id) {
            if (lang_id < 0 || lang_id >= LANGUAGE_CODES.length) return;
            
            int old_id = get_current_language_id();
            if (old_id == lang_id) return;
            
            settings.set_language(lang_id);
            apply_language(lang_id);
            language_changed(old_id, lang_id);
        }
        
        public void apply_language(int lang_id) {
            string lang_code = LANGUAGE_CODES[lang_id];
            string locale_dir = get_locale_dir();
            
            // Clear only variables that may conflict (keep LANG and LC_MESSAGES as they are)
            Environment.unset_variable("LC_ALL");
            Environment.unset_variable("LANGUAGE");
            
            // Configure the translation domain
            Intl.bindtextdomain(GETTEXT_PACKAGE, locale_dir);
            Intl.bind_textdomain_codeset(GETTEXT_PACKAGE, "UTF-8");
            Intl.textdomain(GETTEXT_PACKAGE);
            
            if (lang_code != "") {
                // Explicit language: set LANGUAGE and use system default locale
                Environment.set_variable("LANGUAGE", lang_code, true);
                // Do not change LANG or LC_MESSAGES – leave environment as is
            } else {
                // System mode: get the list of preferred languages
                string[] langs = GLib.Intl.get_language_names();
                string system_lang = "";
                foreach (string lang in langs) {
                    if (lang == "C" || lang == "C.UTF-8" || lang == "POSIX" || lang == "")
                        continue;
                    system_lang = lang;
                    break;
                }
                if (system_lang == "") {
                    system_lang = "en_US";
                }
                // Strip the language code (keep only the part before the dot)
                system_lang = system_lang.replace(".UTF-8", "").replace(".utf8", "");
                Environment.set_variable("LANGUAGE", system_lang, true);
            }
            
            // Apply the environment's default locale (don't force C.UTF-8)
            Intl.setlocale(LocaleCategory.ALL, "");
            // Re-apply the domain
            Intl.textdomain(GETTEXT_PACKAGE);
            
            // Translation test
            string test_msg = _("Initializing DSTX...");
            message("LocaleManager: Translation test: '%s' (lang_code=%s)", test_msg, lang_code);
            message("LocaleManager: LANGUAGE=%s, LANG=%s",
                    Environment.get_variable("LANGUAGE") ?? "(unset)",
                    Environment.get_variable("LANG") ?? "(unset)");
        }
        
        public void initialize() {
            int saved_lang = get_current_language_id();
            apply_language(saved_lang);
            message("LocaleManager: Initialized with language %d (%s)", saved_lang, LANGUAGE_CODES[saved_lang]);
        }
        
        public string get_language_native_name(int lang_id) {
            if (lang_id < 0 || lang_id >= LANGUAGE_NAMES_NATIVE.length)
                return LANGUAGE_NAMES_NATIVE[0];
            return _(LANGUAGE_NAMES_NATIVE[lang_id]);
        }
        
        public string get_language_english_name(int lang_id) {
            if (lang_id < 0 || lang_id >= LANGUAGE_NAMES_ENGLISH.length)
                return LANGUAGE_NAMES_ENGLISH[0];
            return LANGUAGE_NAMES_ENGLISH[lang_id];
        }
        
        public string[] get_all_native_names() {
            string[] names = {};
            for (int i = 0; i < LANGUAGE_NAMES_NATIVE.length; i++) {
                names += get_language_native_name(i);
            }
            return names;
        }
        
        public string[] get_all_codes() {
            return LANGUAGE_CODES;
        }
        
        public string get_language_code(int lang_id) {
            if (lang_id < 0 || lang_id >= LANGUAGE_CODES.length)
                return LANGUAGE_CODES[0];
            return LANGUAGE_CODES[lang_id];
        }
        
        public bool is_language_available(int lang_id) {
            return lang_id >= 0 && lang_id < LANGUAGE_CODES.length;
        }
        
        public string get_locale_dir_path() {
            return get_locale_dir();
        }
        
        public void diagnose() {
            message("=== LocaleManager Diagnostic ===");
            message("LOCALEDIR constant: '%s'", LOCALEDIR);
            message("Resolved locale dir: %s", get_locale_dir());
            message("Current LANGUAGE: %s", Environment.get_variable("LANGUAGE") ?? "(unset)");
            message("Current LANG: %s", Environment.get_variable("LANG") ?? "(unset)");
            message("Current LC_ALL: %s", Environment.get_variable("LC_ALL") ?? "(unset)");
            message("Current LC_MESSAGES: %s", Environment.get_variable("LC_MESSAGES") ?? "(unset)");
            
            foreach (string code in LANGUAGE_CODES) {
                if (code != "") {
                    string mo_path = Path.build_filename(get_locale_dir(), code, "LC_MESSAGES", GETTEXT_PACKAGE + ".mo");
                    message("MO file for %s: %s", code, FileUtils.test(mo_path, FileTest.EXISTS) ? "EXISTS" : "NOT FOUND");
                }
            }
            message("================================");
        }
    }
}
