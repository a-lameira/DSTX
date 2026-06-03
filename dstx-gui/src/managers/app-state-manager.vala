/*
 * app-state-manager.vala - Application state management for DSTX GUI
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
 * - Manage application state transitions (splash, no service, no daemon, no controllers, main)
 * - Coordinate initialization order: Flatpak service check, D-Bus connection, daemon status, controller presence
 * - Handle daemon status changes with debounce and retry logic
 * - Provide retry mechanisms for controller checks
 */

// src/managers/app-state-manager.vala

using Dstx.Core;
using Dstx.Models;
using Dstx;

namespace Dstx.Managers {
    public enum AppState {
        SPLASH,
        NO_SERVICE,
        NO_DAEMON,
        NO_CONTROLLERS,
        MAIN
    }
    
    public class AppStateManager : Object {
        private unowned Gtk.Stack main_stack;
        private unowned Gtk.Label splash_status_label;
        private DBusClient dbus_client;
        private bool _initializing = true;
        
        public AppState current_state { get; private set; default = AppState.SPLASH; }
        
        public signal void state_changed(AppState new_state);
        public signal void transition_complete(AppState new_state);
        public signal void controllers_ready();
        public signal void daemon_offline();
        
        private uint status_update_timeout = 0;
        private uint retry_timeout = 0;
        private int retry_count = 0;
        private const int MAX_RETRIES = 5;
        private const uint RETRY_DELAY_MS = 500;
        
        // Debounce for daemon signal
        private uint daemon_debounce_timeout = 0;
        private bool pending_daemon_alive = false;
        
        // Prevent concurrent check_controllers execution
        private bool checking_controllers = false;
        
        public AppStateManager(Gtk.Stack main_stack, Gtk.Label splash_status_label, DBusClient dbus_client) {
            this.main_stack = main_stack;
            this.splash_status_label = splash_status_label;
            this.dbus_client = dbus_client;
            this.dbus_client.daemon_status_changed.connect(on_daemon_status_changed);
        }
        
        // ==================== INITIALIZATION ORDER ====================
        public async void initialize() {
            message("AppStateManager: Starting verification in defined order");
            
            // --- 1. Check Flatpak and service installation ---
            if (Core.is_flatpak()) {
                update_splash_status(_("Checking system components..."));
                bool installed = yield SystemServiceManager.are_system_components_installed();
                if (!installed) {
                    message("AppStateManager: System components not installed");
                    update_splash_status(_("System service not installed"));
                    _initializing = false;
                    transition_to_state(AppState.NO_SERVICE);
                    return;
                }
                message("AppStateManager: System components installed");
            }
            
            // --- 2. Check daemon version (if Flatpak and service installed) ---
            if (Core.is_flatpak()) {
                update_splash_status(_("Checking daemon version..."));
                int wait_count = 0;
                while (!dbus_client.is_connected && wait_count < 30) {
                    yield sleep(100);
                    wait_count++;
                }
                if (!dbus_client.is_connected) {
                    message("AppStateManager: D-Bus not connected, cannot check version");
                } else {
                    try {
                        string current_version = yield dbus_client.get_core_version();
                        string expected = SystemServiceManager.get_expected_version();
                        if (SystemServiceManager.is_outdated(current_version)) {
                            message("AppStateManager: Daemon version outdated: %s < %s", current_version, expected);
                        } else {
                            message("AppStateManager: Daemon version OK: %s", current_version);
                        }
                    } catch (Error e) {
                        warning("AppStateManager: Error getting daemon version: %s", e.message);
                    }
                }
            }
            
            // --- 3. Connect to D-Bus (if not already) ---
            update_splash_status(_("Connecting to D-Bus..."));
            int wait_count = 0;
            while (!dbus_client.is_connected && wait_count < 50) {
                yield sleep(100);
                wait_count++;
            }
            if (!dbus_client.is_connected) {
                update_splash_status(_("D-Bus connection failed"));
                yield sleep(500);
                _initializing = false;
                transition_to_state(AppState.NO_DAEMON);
                return;
            }
            
            // --- 4. Check if daemon is active ---
            update_splash_status(_("Checking daemon status..."));
            bool daemon_running = false;
            try {
                daemon_running = yield dbus_client.is_core_service_active();
                message("AppStateManager: daemon_running = %s", daemon_running ? "true" : "false");
            } catch (Error e) {
                warning("AppStateManager: Error checking daemon status: %s", e.message);
            }
            
            if (!daemon_running) {
                update_splash_status(_("Daemon is not running"));
                yield sleep(500);
                _initializing = false;
                transition_to_state(AppState.NO_DAEMON);
                return;
            }
            
            // --- 5. Check connected controllers ---
            _initializing = false;
            yield check_controllers_with_retry();
        }
        
        // ==================== CONTROLLER CHECK WITH RETRY ====================
        private async void check_controllers_with_retry() {
            retry_count = 0;
            yield check_state_with_retry();
        }
        
        private async void check_state_with_retry() {
            update_splash_status(_("Checking controllers... (attempt %d/%d)").printf(retry_count + 1, MAX_RETRIES));
            yield sleep(200);
            
            // Check again if daemon is still active
            bool daemon_running = false;
            try {
                daemon_running = yield dbus_client.is_core_service_active();
            } catch (Error e) {
                warning("AppStateManager: Error checking daemon status: %s", e.message);
            }
            
            if (!daemon_running) {
                retry_count++;
                if (retry_count < MAX_RETRIES) {
                    update_splash_status(_("Daemon not responding, retrying... (attempt %d/%d)").printf(retry_count, MAX_RETRIES));
                    yield sleep(RETRY_DELAY_MS);
                    check_state_with_retry();
                    return;
                } else {
                    transition_to_state(AppState.NO_DAEMON);
                    return;
                }
            }
            
            // Check if D-Bus proxy is alive
            if (!dbus_client.daemon_alive) {
                retry_count++;
                if (retry_count < MAX_RETRIES) {
                    update_splash_status(_("D-Bus bridge not ready, retrying... (attempt %d/%d)").printf(retry_count, MAX_RETRIES));
                    yield sleep(RETRY_DELAY_MS);
                    check_state_with_retry();
                    return;
                } else {
                    transition_to_state(AppState.NO_DAEMON);
                    return;
                }
            }
            
            // Get controller list
            try {
                var slots = yield dbus_client.get_controllers();
                if (slots.length == 0) {
                    // No controllers, but daemon is running
                    transition_to_state(AppState.NO_CONTROLLERS);
                } else {
                    transition_to_state(AppState.MAIN);
                    controllers_ready();
                }
            } catch (Error e) {
                warning("AppStateManager: Error getting controllers: %s", e.message);
                retry_count++;
                if (retry_count < MAX_RETRIES) {
                    update_splash_status(_("Error, retrying... (attempt %d/%d)").printf(retry_count, MAX_RETRIES));
                    yield sleep(RETRY_DELAY_MS);
                    check_state_with_retry();
                } else {
                    transition_to_state(AppState.NO_DAEMON);
                }
            }
        }
        
public async void retry_connection() {
    if (current_state == AppState.NO_DAEMON) {
        message("AppStateManager: Retrying connection after service start");
        yield check_controllers_with_delay();
    } else {
        message("AppStateManager: retry_connection called but current state is %s", current_state.to_string());
    }
}

        // ==================== DAEMON SIGNAL HANDLING WITH DEBOUNCE ====================
        private void on_daemon_status_changed(bool alive) {
            if (_initializing) return;
            
            // Debounce: if we receive multiple notifications in a row, process only the last one
            if (daemon_debounce_timeout != 0) {
                Source.remove(daemon_debounce_timeout);
                daemon_debounce_timeout = 0;
            }
            pending_daemon_alive = alive;
            daemon_debounce_timeout = Timeout.add(300, () => {
                process_daemon_status_change(pending_daemon_alive);
                daemon_debounce_timeout = 0;
                return Source.REMOVE;
            });
        }
        
        private void process_daemon_status_change(bool alive) {
            if (alive) {
                // Daemon came online
                if (current_state == AppState.NO_DAEMON || current_state == AppState.SPLASH) {
                    // Start check with delay
                    check_controllers_with_delay.begin();
                }
            } else {
                // Daemon went offline
                daemon_offline();
                transition_to_state(AppState.NO_DAEMON);
            }
        }
        
        private async void check_controllers_with_delay() {
            if (checking_controllers) {
                message("AppStateManager: Already checking controllers, ignoring");
                return;
            }
            checking_controllers = true;
            
            update_splash_status(_("Service detected, checking controllers..."));
            yield sleep(500);
            
            // Check if daemon is still active
            bool daemon_running = false;
            try {
                daemon_running = yield dbus_client.is_core_service_active();
            } catch (Error e) {
                warning("AppStateManager: Error checking daemon status: %s", e.message);
            }
            
            if (!daemon_running) {
                transition_to_state(AppState.NO_DAEMON);
                checking_controllers = false;
                return;
            }
            
            try {
                var slots = yield dbus_client.get_controllers();
                if (slots.length == 0) {
                    transition_to_state(AppState.NO_CONTROLLERS);
                } else if (current_state != AppState.MAIN) {
                    transition_to_state(AppState.MAIN);
                    controllers_ready();
                }
            } catch (Error e) {
                warning("AppStateManager: Error checking controllers: %s", e.message);
                // Don't transition, just log
            }
            checking_controllers = false;
        }
        
        // ==================== TRANSITION AND UTILITY METHODS ====================
        public void transition_to_state(AppState new_state) {
            if (current_state == new_state) return;
            
            var old_state = current_state;
            current_state = new_state;
            message("AppStateManager: State transition: %s -> %s", 
                    old_state.to_string(), new_state.to_string());
            state_changed(new_state);
            
            Idle.add(() => {
                switch (new_state) {
                    case AppState.SPLASH:
                        main_stack.set_visible_child_name("splash");
                        break;
                    case AppState.NO_SERVICE:
                        main_stack.set_visible_child_name("no_service");
                        break;
                    case AppState.NO_DAEMON:
                        main_stack.set_visible_child_name("no_daemon");
                        break;
                    case AppState.NO_CONTROLLERS:
                        main_stack.set_visible_child_name("no_controllers");
                        break;
                    case AppState.MAIN:
                        main_stack.set_visible_child_name("main");
                        break;
                }
                transition_complete(new_state);
                return Source.REMOVE;
            });
        }
        
        public void update_splash_status(string status) {
            if (status_update_timeout != 0) {
                Source.remove(status_update_timeout);
            }
            status_update_timeout = Timeout.add(50, () => {
                if (splash_status_label != null) {
                    splash_status_label.label = status;
                }
                status_update_timeout = 0;
                return Source.REMOVE;
            });
        }
        
        private async void sleep(uint ms) {
            var source = new TimeoutSource(ms);
            source.set_callback(() => {
                sleep.callback();
                return Source.REMOVE;
            });
            source.attach(null);
            yield;
        }
        
        public bool can_show_main_content() {
            return current_state == AppState.MAIN;
        }
        
        public bool has_controllers_check() {
            return current_state == AppState.MAIN || current_state == AppState.NO_CONTROLLERS;
        }
        
        public async void restart_check() {
            message("AppStateManager: Restarting full check");
            transition_to_state(AppState.SPLASH);
            yield sleep(500);
            yield initialize();
        }
        
        public void force_main() {
            if (current_state == AppState.NO_CONTROLLERS) {
                transition_to_state(AppState.MAIN);
            }
        }
    }
}
