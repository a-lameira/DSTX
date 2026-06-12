/*
 * application.vala - Main application class for DSTX GUI
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
 * - Application lifecycle management (activate, startup, shutdown)
 * - Global CSS provider management and dynamic updates
 * - Theme, locale, and settings initialization
 * - Global actions and keyboard shortcuts setup
 */

// src/application.vala
using Dstx.Core;
using Dstx.Managers;
using Dstx.Widgets;

namespace Dstx {
    public class Application : Adw.Application {
        private DBusClient dbus_client;
        private MainWindow? main_window = null;
        private string custom_css;
        private string default_css;
        private Gtk.CssProvider? global_provider = null;
        
        public Application() {
            Object(
                application_id: "org.dstx.gui",
                flags: ApplicationFlags.DEFAULT_FLAGS
            );
            
            custom_css = """
    /* ===== CARD STYLES ===== */
	.controller-card {
    		background-color: @sidebar_bg_color;
    		border-radius: 9px;
    		transition: all 200ms ease;
    		border: 1px solid transparent;
    		box-shadow: 0 1px 3px rgba(0, 0, 0, 0.0);
    		margin-bottom: 8px;
	}
    
    .controller-card:hover {
        background-color: alpha(@card_bg_color, 0.5);
        border-color: alpha(@card_bg_color, 0.5);
        box-shadow: 0 2px 6px rgba(0, 0, 0, 0.15);
    }
    
	.controller-card.selected-card {
    		background-color: alpha(@card_bg_color, 1.0);
    		border-color: alpha(@sidebar_bg_color, 1.0);
    		box-shadow: 0 3px 9px rgba(0, 0, 0, 0.1),
	}
    
    .controller-icon {
        color: @theme_text_color;
        opacity: 0.9;
    }
    
    .controller-name {
        font-size: 1.1em;
        font-weight: 700;
        color: @theme_text_color;
        margin-bottom: 4px;
    }
    
    .connection-status {
        font-size: 0.95em;
        margin-bottom: 2px;
    }
    
    .connection-status.bluetooth {
        color: @theme_text_color;
    }
    
    .connection-status.usb {
        color: @theme_text_color;
    }
    
    .emulation-status {
        font-size: 0.95em;
        margin-bottom: 2px;
    }
    
    .emulation-status.active {
        color: #2ec27e;
        font-weight: 600;
    }
    
    .emulation-status.inactive {
        color: #77767b;
    }
    
    .battery-percentage {
        font-size: 0.95em;
        font-weight: 500;
    }
    
    .card-title {
        font-size: 0.85em;
        font-weight: 600;
        opacity: 0.8;
        letter-spacing: 0.5px;
        color: @theme_fg_color;
        margin-bottom: 4px;
        margin-top: 8px;
    }
    
    .color-preview {
        border-radius: 4px;
        border: 1px solid @borders;
        min-width: 24px;
        min-height: 24px;
        transition: all 200ms ease;
    }
    
    .color-preview:hover {
        border-color: @accent_bg_color;
        box-shadow: 0 0 4px alpha(@accent_bg_color, 0.5);
    }
    
    #quick_status_box {
        background-color: alpha(@theme_fg_color, 0.05);
        border-radius: 12px;
        padding: 8px 16px;
        margin-top: 12px;
        border: 1px solid alpha(@borders, 0.3);
        transition: all 200ms ease;
    }
    
    #quick_status_box:hover {
        background-color: alpha(@theme_fg_color, 0.08);
        border-color: alpha(@accent_bg_color, 0.3);
    }
    
    #quick_status_box image {
        color: @theme_fg_color;
        opacity: 0.7;
    }
    
    #quick_battery_label {
        font-weight: 500;
    }
    
    .caption {
        font-size: 0.9em;
    }
    
    .dim-label {
        opacity: 0.7;
    }
    /* Compact buttons */
.compact-button {
    margin-top: 4px;
    margin-bottom: 4px;
    padding-top: 2px;
    padding-bottom: 2px;
    min-height: 28px;
}
    
/* ===== STYLES FOR TIPS DIALOG ===== */

/* Main card - no background and no hover */
.tip-card {
    background-color: transparent;
    border-radius: 0px;
    transition: none;
}

.tip-card:hover {
    background-color: transparent;
}

/* Disable text selection on all labels in the dialog */
.tip-card label,
.tip-card-title,
.tip-item-title,
.tip-item-desc {
    user-select: none;
    -gtk-user-select: none;
}

/* Card title */
.tip-card-title {
    font-weight: bold;
    font-size: 1.15em;
    margin-bottom: 6px;
    color: @window_fg_color;
}

/* Title of each item */
.tip-item-title {
    font-weight: 600;
    font-size: 1.0em;
    margin-top: 4px;
    margin-bottom: 2px;
    color: @window_fg_color;
}

/* Description of each item */
.tip-item-desc {
    font-size: 0.9em;
    line-height: 1.45;
    text-align: justify;
    color: alpha(@window_fg_color, 0.85);
}

/* Spacing between cards */
.tip-card + .tip-card {
    margin-top: 24px;
}
    
    * {
        transition: background-color 200ms ease,
                   border-color 200ms ease,
                   box-shadow 200ms ease,
                   transform 200ms ease,
                   opacity 200ms ease;
    }
""";
            
            default_css = custom_css;
        }
        
        protected override void activate() {
            if (main_window == null) {
                dbus_client = new DBusClient();
                main_window = new MainWindow(dbus_client);
                main_window.set_application(this);
                
                global_provider = new Gtk.CssProvider();
                global_provider.load_from_string(custom_css);
                
                var display = Gdk.Display.get_default();
                if (display != null) {
                    Gtk.StyleContext.add_provider_for_display(
                        display,
                        global_provider,
                        Gtk.STYLE_PROVIDER_PRIORITY_APPLICATION
                    );
                }
            }
            
            main_window.present();
        }
        
        protected override void shutdown() {
            var settings_manager = SettingsManager.get_default();
            settings_manager.sync();
            base.shutdown();
        }
        
        public void update_global_css(string new_css) {
            if (global_provider == null) return;
            
            var display = Gdk.Display.get_default();
            if (display != null) {
                Gtk.StyleContext.remove_provider_for_display(display, global_provider);
            }
            
            global_provider = new Gtk.CssProvider();
            try {
                global_provider.load_from_string(new_css);
                
                if (display != null) {
                    Gtk.StyleContext.add_provider_for_display(
                        display,
                        global_provider,
                        Gtk.STYLE_PROVIDER_PRIORITY_APPLICATION
                    );
                }
                
                message("Application: Global CSS updated");
            } catch (Error e) {
                warning("Application: Error loading CSS: %s", e.message);
            }
        }
        
        public void restore_default_css() {
            update_global_css(default_css);
            message("Application: Default CSS restored");
        }
        
        public string get_default_css() {
            return default_css;
        }
        
        protected override void startup() {
            base.startup();
            
            var locale_manager = LocaleManager.get_default();
            locale_manager.initialize();
            
            var settings_manager = SettingsManager.get_default();
            message(Dstx._("Application: Configuration loaded from: %s"), 
                    Environment.get_user_config_dir() + "/dstx/settings.json");
            
            var theme_manager = ThemeManager.get_default();
            
            int saved_theme_mode = settings_manager.get_theme();
            string custom_theme_id = settings_manager.get_custom_theme();
            string custom_theme_name = settings_manager.get_custom_theme_name();
            int accent_index = settings_manager.get_custom_accent_index();
            Gdk.RGBA accent_color = settings_manager.get_custom_accent_color();
            
            message("Application: Saved theme mode: %d", saved_theme_mode);
            
            if (saved_theme_mode == 3) {
                theme_manager.set_ui_mode(3);
                theme_manager.selected_accent_index = accent_index;
                theme_manager.apply_theme(custom_theme_id, accent_color);
                message("Application: Custom theme '%s' applied (accent index %d)", 
                        custom_theme_id, accent_index);
            } else {
                theme_manager.set_ui_mode(saved_theme_mode);
                message("Application: Theme mode %d applied", saved_theme_mode);
            }
            
            var quit_action = new GLib.SimpleAction("quit", null);
            quit_action.activate.connect(() => {
                settings_manager.sync();
                if (main_window != null) {
                    main_window.close();
                }
            });
            this.add_action(quit_action);
            this.set_accels_for_action("app.quit", {"<Ctrl>q"});
            
            message("Application: Startup completed");
        }
    }
}
