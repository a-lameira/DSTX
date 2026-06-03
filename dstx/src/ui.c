/*
 * ui.c - Terminal user interface (TUI) for DSTX
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
 * Responsible for drawing the interface, processing interactive commands
 * and sending requests to the daemon via shared memory.
 *
 * Commands follow the same syntax as CLI (commands.c):
 * - Space-separated words (e.g., "uhid on", "invert ly on")
 * - Status commands: "<command> status"
 * - Color: "color RRGGBB" (also accepts just hex for compatibility)
 * - TUI-exclusive commands: info, profiles, start, stop, setup, exit, help
 */

#include "dstx.h"
#include "display.h"
#include "led.h"
#include "axes.h"
#include "keys.h"
#include <ctype.h>
#include <string.h>
#include <stdio.h>
#include <sys/ioctl.h>
#include <libgen.h>
#include <signal.h>
#include <time.h>
#include <stdarg.h>
#include <sys/wait.h>

// Structure to manage notifications
typedef struct {
    char message[256];
    struct timespec expiry_time;
    bool active;
} notification_t;

static notification_t current_notification = {0};
static bool info_mode = false;
static int help_page = 0;            // Current help page (0..TOTAL_HELP_PAGES-1)

void show_notification(const char *format, ...) {
    va_list args;
    va_start(args, format);
    vsnprintf(current_notification.message, sizeof(current_notification.message), format, args);
    va_end(args);
    
    struct timespec now;
    clock_gettime(CLOCK_MONOTONIC, &now);
    current_notification.expiry_time.tv_sec = now.tv_sec + 5;
    current_notification.expiry_time.tv_nsec = now.tv_nsec;
    current_notification.active = true;
}

void render_notification(void) {
    if (!current_notification.active) {
        printf("\033[24;3H%*s", 62, "");
        return;
    }
    
    struct timespec now;
    clock_gettime(CLOCK_MONOTONIC, &now);
    if (now.tv_sec > current_notification.expiry_time.tv_sec ||
        (now.tv_sec == current_notification.expiry_time.tv_sec && 
         now.tv_nsec > current_notification.expiry_time.tv_nsec)) {
        current_notification.active = false;
        printf("\033[24;3H%*s", 62, "");
        return;
    }
    
    char msg[60];
    strncpy(msg, current_notification.message, 59);
    msg[59] = '\0';
    int len = strlen(msg);
    printf("\033[24;3H%s%s%s", CLR_GREEN, msg, CLR_RESET);
    if (len < 62) {
        printf("\033[24;%dH%*s", 3 + len, 62 - len, "");
    }
}

/**
 * execute_command - Executes an external command via fork/exec, waiting for completion.
 * @param argv: NULL-terminated argument list (first argument is the path).
 * @return Command exit code, or -1 on error.
 */
static int execute_command(char *const argv[]) {
    pid_t pid = fork();
    if (pid == -1) {
        syslog(LOG_ERR, "UI: fork() failed: %s", strerror(errno));
        return -1;
    }
    
    if (pid == 0) {
        // Child process: execute command
        execvp(argv[0], argv);
        // If we get here, error
        _exit(127);
    }
    
    // Parent process: wait for child
    int status;
    if (waitpid(pid, &status, 0) == -1) {
        syslog(LOG_ERR, "UI: waitpid() failed: %s", strerror(errno));
        return -1;
    }
    
    if (WIFEXITED(status)) {
        return WEXITSTATUS(status);
    }
    return -1;
}

void run_ui_loop(void) {
    printf(ALT_BUFFER_ON);
    force_terminal_size(MIN_ROWS, MIN_COLS);
    enable_raw_mode();
    printf(HIDE_CURSOR);

    char cmd_line[MY_MAX_INPUT] = {0};
    int cmd_len = 0;
    int last_idx = -2;
    bool was_alive = false;
    bool was_insane = false;

    uint32_t last_heartbeat = 0;
    struct timeval last_heartbeat_time;
    gettimeofday(&last_heartbeat_time, NULL);
    bool hb_is_moving = true;
    struct timeval last_reconnect = {0, 0};

    while (keep_running) {
        if (!check_window_sanity()) { 
            was_insane = true; 
            usleep(250000); 
            continue; 
        }
        if (was_insane) { 
            printf(CLEAR_SCREEN HOME); 
            was_insane = false; 
        }

        shared_data_t snap; 
        bool alive = false;
        int current_idx = -1;
        pid_t snapped_pid = 0; 

        // Reconnection with rate limiting
        if (shm_ptr == NULL) {
            struct timeval now;
            gettimeofday(&now, NULL);
            long elapsed = (now.tv_sec - last_reconnect.tv_sec) * 1000000L +
                           (now.tv_usec - last_reconnect.tv_usec);
            if (last_reconnect.tv_sec == 0 || elapsed > 500000) {
                try_connect_shm();
                gettimeofday(&last_reconnect, NULL);
            }
        }

        if (shm_ptr != NULL && shm_ptr->magic == SHM_MAGIC_VALUE) {
            uint32_t current_hb = atomic_load(&shm_ptr->heartbeat);
            struct timeval now;
            gettimeofday(&now, NULL);

            if (current_hb != last_heartbeat) {
                last_heartbeat = current_hb;
                last_heartbeat_time = now;
                hb_is_moving = true;
            } else {
                long diff_ms = (now.tv_sec - last_heartbeat_time.tv_sec) * 1000 + 
                               (now.tv_usec - last_heartbeat_time.tv_usec) / 1000;
                if (diff_ms > 1000) {
                    hb_is_moving = false;
                }
            }

            if (!hb_is_moving && !is_daemon_alive()) {
                disconnect_shm();
                usleep(10000);
            }

            if (shm_ptr != NULL) {
                safe_shm_lock(&shm_ptr->proc_mutex);
                memcpy(&snap, shm_ptr, sizeof(shared_data_t));
                pthread_mutex_unlock(&shm_ptr->proc_mutex);

                snapped_pid = atomic_load(&snap.daemon_pid);
                if (snapped_pid > 0) {
                    char proc_path[256];
                    snprintf(proc_path, sizeof(proc_path), "/proc/%d", snapped_pid);
                    if (access(proc_path, F_OK) == 0) {
                        alive = true;
                        current_idx = update_and_get_slot_idx(&snap);
                    }
                    else if (kill(snapped_pid, 0) == 0) {
                        alive = true;
                        current_idx = update_and_get_slot_idx(&snap);
                    }
                    else if (hb_is_moving) {
                        alive = true;
                        current_idx = update_and_get_slot_idx(&snap);
                    }
                }
            }
        }

        if (current_idx != last_idx || alive != was_alive) {
            printf(CLEAR_SCREEN); 
            last_idx = current_idx; 
            was_alive = alive;
        }

        // Render either normal UI or help screen
        if (display_is_help_mode()) {
            render_help_screen(help_page);
        } else {
            render_full_ui(&snap, current_idx, cmd_line, alive, info_mode);
        }
        render_notification();

        // ===== COMMAND LINE (line 25) with help indicator =====
        // Position cursor at line 25, column 1
        printf("\033[25;1H" CLR_BOLD " command " CLR_CYAN "❯ " CLR_RESET);
        // Print command truncated to 59 characters (leaves space for [help] at col 71)
        int cmd_display_len = strlen(cmd_line);
        if (cmd_display_len > 59) {
            printf("%.59s...", cmd_line);
        } else {
            printf("%-59s", cmd_line);
        }
        // Print help indicator in gray at column 71
        printf(CLR_GRAY "\033[25;71H[help]" CLR_RESET);
        // Clear from column 78 to end of line (optional, but keeps line clean)
        printf("\033[25;78H\033[K");
        fflush(stdout);

        fd_set fds; 
        FD_ZERO(&fds); 
        FD_SET(STDIN_FILENO, &fds);
        struct timeval tv = {0, 50000}; 

        if (select(STDIN_FILENO + 1, &fds, NULL, NULL, &tv) > 0) {
            unsigned char c;
            if (read(STDIN_FILENO, &c, 1) == 1) {
                // Help mode handling (highest priority)
                if (display_is_help_mode()) {
                    if (c == '\033') {
                        char seq[2];
                        if (read(STDIN_FILENO, &seq[0], 1) > 0 && read(STDIN_FILENO, &seq[1], 1) > 0) {
                            if (seq[0] == '[') {
                                if (seq[1] == 'C') { // Right arrow -> next page
                                    if (help_page + 1 < TOTAL_HELP_PAGES) {
                                        help_page++;
                                    }
                                } else if (seq[1] == 'D') { // Left arrow -> previous page
                                    if (help_page > 0) {
                                        help_page--;
                                    }
                                }
                            }
                        }
                    } else {
                        // Any other key exits help mode
                        display_set_help_mode(false);
                        printf(CLEAR_SCREEN);
                    }
                    continue; // Skip other input processing
                }

                if (info_mode) {
                    info_mode = false;
                    printf(CLEAR_SCREEN);
                    continue;
                }
                if (display_is_list_mode()) {
                    display_set_list_mode(false);
                    printf(CLEAR_SCREEN);
                    continue;
                }

                if (c == '\033') { 
                    char seq[2];
                    if (read(STDIN_FILENO, &seq[0], 1) > 0 && read(STDIN_FILENO, &seq[1], 1) > 0) {
                        if (seq[1] == 'C' || seq[1] == 'D') {
                            if (shm_ptr != NULL) {
                                int step = (seq[1] == 'C') ? 1 : -1;
                                for(int i = 1; i <= MAX_SLOTS; i++) {
                                    int t = (current_idx + (step * i) + MAX_SLOTS) % MAX_SLOTS;
                                    if (snap.slots[t].connected) { 
                                        strncpy(selected_dev_path, snap.slots[t].dev_path, 127);
                                        break; 
                                    }
                                }
                            }
                        }
                    }
                    continue;
                }

                if (c == '\n' || c == '\r') {
                    if (cmd_len > 0) {
                        cmd_line[cmd_len] = '\0';
                        
                        // =================================================================
                        // TUI-exclusive commands (not in CLI)
                        // =================================================================
                        if (strcmp(cmd_line, "exit") == 0 || strcmp(cmd_line, "q") == 0) {
                            keep_running = false;
                        }
                        else if (strcmp(cmd_line, "info") == 0) {
                            info_mode = true;
                            printf(CLEAR_SCREEN);
                        }
                        else if (strcmp(cmd_line, "profiles") == 0) {
                            char resp_msg[4096];
                            bool ok = profile_request_sync(shm_ptr, 4, NULL, -1, -1, resp_msg, sizeof(resp_msg));
                            if (ok && resp_msg[0] != '\0') {
                                display_show_profiles(resp_msg);
                                printf(CLEAR_SCREEN);
                            } else {
                                show_notification("Error getting profile list: %s", resp_msg);
                            }
                        }
                        else if (strcmp(cmd_line, "start") == 0) {
                            start_service(); 
                            show_notification("✓ Service started");
                            printf(CLEAR_SCREEN);
                        }
                        else if (strcmp(cmd_line, "stop") == 0) {
                            stop_service(); 
                            selected_dev_path[0] = '\0'; 
                            show_notification("✓ Service stopped");
                            printf(CLEAR_SCREEN);
                        }
                        else if (strcmp(cmd_line, "setup") == 0) {
                            char bin_dir[512];
                            get_binary_path(bin_dir, sizeof(bin_dir));
                            char script_path[1024];
                            snprintf(script_path, sizeof(script_path), "%s/dstx-daemon.sh", bin_dir);
                            
                            // Check if script exists
                            if (access(script_path, X_OK) != 0) {
                                show_notification("Script %s not found or not executable", script_path);
                            } else {
                                printf(ALT_BUFFER_OFF SHOW_CURSOR); 
                                disable_raw_mode();
                                
                                // Execute script via sudo + bash using fork/exec
                                char *argv[] = {"sudo", "bash", script_path, NULL};
                                int ret = execute_command(argv);
                                if (ret != 0) {
                                    syslog(LOG_WARNING, "UI: setup returned code %d", ret);
                                }
                                
                                printf("\nPress ENTER to return..."); 
                                while(getchar() != '\n');
                                enable_raw_mode(); 
                                printf(ALT_BUFFER_ON HIDE_CURSOR CLEAR_SCREEN);
                            }
                        }
                        else if (strcmp(cmd_line, "help") == 0) {
                            display_set_help_mode(true);
                            help_page = 0;
                            printf(CLEAR_SCREEN);
                        }
                        // =================================================================
                        // Profile commands (CLI compatible)
                        // =================================================================
                        else if (strncmp(cmd_line, "profile ", 8) == 0) {
                            char subcmd[32], arg[PROFILE_NAME_LEN];
                            int parsed = sscanf(cmd_line + 8, "%31s %63s", subcmd, arg);
                            char resp_msg[512];
                            if (strcmp(subcmd, "load") == 0 && parsed >= 2) {
                                profile_request_sync(shm_ptr, 1, arg, -1, -1, resp_msg, sizeof(resp_msg));
                                show_notification("%s", resp_msg);
                            }
                            else if (strcmp(subcmd, "save") == 0 && parsed >= 2) {
                                profile_request_sync(shm_ptr, 2, arg, -1, -1, resp_msg, sizeof(resp_msg));
                                show_notification("%s", resp_msg);
                            }
                            else if (strcmp(subcmd, "delete") == 0 && parsed >= 2) {
                                profile_request_sync(shm_ptr, 3, arg, -1, -1, resp_msg, sizeof(resp_msg));
                                show_notification("%s", resp_msg);
                            }
                            else if (strcmp(subcmd, "list") == 0) {
                                profile_request_sync(shm_ptr, 4, NULL, -1, -1, resp_msg, sizeof(resp_msg));
                                if (resp_msg[0] != '\0') {
                                    display_show_profiles(resp_msg);
                                    printf(CLEAR_SCREEN);
                                } else {
                                    show_notification("%s", resp_msg);
                                }
                            }
                            else {
                                show_notification("Usage: profile load|save|delete|list <name>");
                            }
                        }
                        else if (strncmp(cmd_line, "auto-save", 9) == 0) {
                            char resp_msg[512];
                            int delay;
                            if (strcmp(cmd_line, "auto-save on") == 0) {
                                profile_request_sync(shm_ptr, 5, NULL, 1, -1, resp_msg, sizeof(resp_msg));
                                show_notification("%s", resp_msg);
                            }
                            else if (strcmp(cmd_line, "auto-save off") == 0) {
                                profile_request_sync(shm_ptr, 5, NULL, 0, -1, resp_msg, sizeof(resp_msg));
                                show_notification("%s", resp_msg);
                            }
                            else if (sscanf(cmd_line, "auto-save delay %d", &delay) == 1 && delay >= 100 && delay <= 10000) {
                                profile_request_sync(shm_ptr, 5, NULL, -1, delay, resp_msg, sizeof(resp_msg));
                                show_notification("%s", resp_msg);
                            }
                            else {
                                show_notification("Usage: auto-save on/off | auto-save delay <ms> (100-10000)");
                            }
                        }
                        // =================================================================
                        // Slot commands (when a controller is connected)
                        // =================================================================
                        else if (current_idx != -1) {
                            safe_shm_lock(&shm_ptr->proc_mutex);
                            
                            // ----- UHID -----
                            if (strcmp(cmd_line, "uhid on") == 0) {
                                atomic_store(&shm_ptr->slots[current_idx].is_uhid, true);
                                atomic_store(&shm_ptr->slots[current_idx].emulate_active, false);
                                atomic_store(&shm_ptr->slots[current_idx].emulate_active, true);
                                show_notification("✓ UHID mode enabled for slot %d", current_idx);
                            }
                            else if (strcmp(cmd_line, "uhid off") == 0) {
                                atomic_store(&shm_ptr->slots[current_idx].is_uhid, false);
                                atomic_store(&shm_ptr->slots[current_idx].emulate_active, false);
                                atomic_store(&shm_ptr->slots[current_idx].emulate_active, true);
                                show_notification("✓ uinput mode enabled for slot %d", current_idx);
                            }
                            
                            // ----- Y-axis inversion -----
                            else if (strcmp(cmd_line, "invert ly on") == 0) {
                                atomic_store(&shm_ptr->slots[current_idx].invert_ly, true);
                                show_notification("✓ Y inversion (L) ENABLED on slot %d", current_idx);
                            }
                            else if (strcmp(cmd_line, "invert ly off") == 0) {
                                atomic_store(&shm_ptr->slots[current_idx].invert_ly, false);
                                show_notification("✓ Y inversion (L) DISABLED on slot %d", current_idx);
                            }
                            else if (strcmp(cmd_line, "invert ry on") == 0) {
                                atomic_store(&shm_ptr->slots[current_idx].invert_ry, true);
                                show_notification("✓ Y inversion (R) ENABLED on slot %d", current_idx);
                            }
                            else if (strcmp(cmd_line, "invert ry off") == 0) {
                                atomic_store(&shm_ptr->slots[current_idx].invert_ry, false);
                                show_notification("✓ Y inversion (R) DISABLED on slot %d", current_idx);
                            }
                            else if (strcmp(cmd_line, "invert status") == 0) {
                                bool ly = atomic_load(&shm_ptr->slots[current_idx].invert_ly);
                                bool ry = atomic_load(&shm_ptr->slots[current_idx].invert_ry);
                                show_notification("Slot %d: L Y invert=%s, R Y invert=%s", current_idx,
                                                  ly ? "ON" : "OFF", ry ? "ON" : "OFF");
                            }
                            
                            // ----- Digital triggers -----
                            else if (strcmp(cmd_line, "triggers-digital on") == 0) {
                                atomic_store(&shm_ptr->slots[current_idx].is_trigger_digital, true);
                                show_notification("✓ Triggers (L2/R2) in DIGITAL mode");
                            }
                            else if (strcmp(cmd_line, "triggers-digital off") == 0) {
                                atomic_store(&shm_ptr->slots[current_idx].is_trigger_digital, false);
                                show_notification("✓ Triggers (L2/R2) in ANALOG mode (default)");
                            }
                            else if (strcmp(cmd_line, "triggers-digital status") == 0) {
                                bool digital = atomic_load(&shm_ptr->slots[current_idx].is_trigger_digital);
                                show_notification("Slot %d: Triggers in %s mode", current_idx, digital ? "DIGITAL" : "ANALOG");
                            }
                            
                            // ----- Stick sensitivity -----
                            else if (strncmp(cmd_line, "sensitivity left ", 17) == 0) {
                                int preset = atoi(cmd_line + 17);
                                if (preset >= 0 && preset < SENS_PRESET_COUNT) {
                                    apply_sensitivity_preset_left(&shm_ptr->slots[current_idx], preset);
                                    show_notification("✓ LEFT stick: %s", get_sensitivity_preset_name(preset));
                                } else {
                                    show_notification("Invalid preset. Use 0-%d", SENS_PRESET_COUNT-1);
                                }
                            }
                            else if (strncmp(cmd_line, "sensitivity right ", 18) == 0) {
                                int preset = atoi(cmd_line + 18);
                                if (preset >= 0 && preset < SENS_PRESET_COUNT) {
                                    apply_sensitivity_preset_right(&shm_ptr->slots[current_idx], preset);
                                    show_notification("✓ RIGHT stick: %s", get_sensitivity_preset_name(preset));
                                } else {
                                    show_notification("Invalid preset. Use 0-%d", SENS_PRESET_COUNT-1);
                                }
                            }
                            else if (strcmp(cmd_line, "sensitivity status") == 0 || strcmp(cmd_line, "sensitivity") == 0) {
                                uint8_t left = atomic_load(&shm_ptr->slots[current_idx].sensitivity_left_preset);
                                uint8_t right = atomic_load(&shm_ptr->slots[current_idx].sensitivity_right_preset);
                                show_notification("Sensitivity: L=%s, R=%s", 
                                                  get_sensitivity_preset_name(left),
                                                  get_sensitivity_preset_name(right));
                            }
                            
                            // ----- Layout (Nintendo Switch Pro) -----
                            else if (strcmp(cmd_line, "layout switch") == 0) {
                                if (shm_ptr->slots[current_idx].type == TYPE_NSW_PRO) {
                                    atomic_store(&shm_ptr->slots[current_idx].request_switch_layout, true);
                                    show_notification("✓ Switch layout request sent for slot %d", current_idx);
                                } else {
                                    show_notification("✗ Command valid only for Nintendo Switch Pro");
                                }
                            }
                            else if (strcmp(cmd_line, "layout xbox") == 0) {
                                if (shm_ptr->slots[current_idx].type == TYPE_NSW_PRO) {
                                    atomic_store(&shm_ptr->slots[current_idx].request_xbox_layout, true);
                                    show_notification("✓ Xbox layout (face) request sent for slot %d", current_idx);
                                } else {
                                    show_notification("✗ Command valid only for Nintendo Switch Pro");
                                }
                            }
                            
                            // ----- Reset keybinds (request) -----
                            else if (strcmp(cmd_line, "reset-keybinds") == 0) {
                                atomic_store(&shm_ptr->slots[current_idx].request_reset_all_keybinds, true);
                                show_notification("✓ Full keybind reset request sent for slot %d", current_idx);
                            }
                            
                            // ----- Keymap and keybinds -----
                            else if (strcmp(cmd_line, "keymap") == 0) {
                                char msg[256];
                                int off = 0;
                                off += snprintf(msg + off, sizeof(msg)-off, "Keymap: ");
                                for (int i = 0; i < PHY_BTN_COUNT && off < (int)sizeof(msg)-32; i++) {
                                    uint8_t logical = shm_ptr->slots[current_idx].keymap[i];
                                    const char *logical_name = "INV";
                                    if (logical < LOGICAL_BTN_COUNT) {
                                        switch (logical) {
                                            case LOGICAL_BTN_NONE:      logical_name = "NONE"; break;
                                            case LOGICAL_BTN_CROSS:     logical_name = "CROSS"; break;
                                            case LOGICAL_BTN_CIRCLE:    logical_name = "CIRCLE"; break;
                                            case LOGICAL_BTN_SQUARE:    logical_name = "SQUARE"; break;
                                            case LOGICAL_BTN_TRIANGLE:  logical_name = "TRIANGLE"; break;
                                            case LOGICAL_BTN_L1:        logical_name = "L1"; break;
                                            case LOGICAL_BTN_R1:        logical_name = "R1"; break;
                                            case LOGICAL_BTN_L2:        logical_name = "L2"; break;
                                            case LOGICAL_BTN_R2:        logical_name = "R2"; break;
                                            case LOGICAL_BTN_SHARE:     logical_name = "SHARE"; break;
                                            case LOGICAL_BTN_OPTIONS:   logical_name = "OPTIONS"; break;
                                            case LOGICAL_BTN_L3:        logical_name = "L3"; break;
                                            case LOGICAL_BTN_R3:        logical_name = "R3"; break;
                                            case LOGICAL_BTN_PS:        logical_name = "PS"; break;
                                            case LOGICAL_BTN_TOUCH:     logical_name = "TOUCH"; break;
                                            case LOGICAL_BTN_DPAD_UP:   logical_name = "UP"; break;
                                            case LOGICAL_BTN_DPAD_DOWN: logical_name = "DOWN"; break;
                                            case LOGICAL_BTN_DPAD_LEFT: logical_name = "LEFT"; break;
                                            case LOGICAL_BTN_DPAD_RIGHT:logical_name = "RIGHT"; break;
                                            default: logical_name = "?"; break;
                                        }
                                    }
                                    off += snprintf(msg + off, sizeof(msg)-off, "%s ", logical_name);
                                }
                                show_notification("%s", msg);
                            }
                            else if (strncmp(cmd_line, "keybind ", 8) == 0) {
                                int physical, logical;
                                if (sscanf(cmd_line + 8, "%d %d", &physical, &logical) == 2) {
                                    if (physical >= 0 && physical < PHY_BTN_COUNT &&
                                        logical >= 0 && logical < LOGICAL_BTN_COUNT) {
                                        shm_ptr->slots[current_idx].keymap[physical] = logical;
                                        atomic_store(&shm_ptr->slots[current_idx].led_dirty, true);
                                        show_notification("✓ Mapping %d -> %d applied", physical, logical);
                                    } else {
                                        show_notification("Invalid values. Use 0..%d and 0..%d", PHY_BTN_COUNT-1, LOGICAL_BTN_COUNT-1);
                                    }
                                } else {
                                    show_notification("Usage: keybind <physical> <logical> (e.g., keybind 0 1)");
                                }
                            }
                            
                            // ----- Emulation -----
                            else if (strcmp(cmd_line, "emulation on") == 0) {
                                atomic_store(&shm_ptr->slots[current_idx].emulate_active, true);
                                show_notification("✓ Emulation enabled for slot %d", current_idx);
                            }
                            else if (strcmp(cmd_line, "emulation off") == 0) {
                                atomic_store(&shm_ptr->slots[current_idx].emulate_active, false);
                                show_notification("✓ Emulation disabled for slot %d", current_idx);
                            }
                            
                            // ----- Debounce -----
                            else if (strcmp(cmd_line, "debounce on") == 0) {
                                atomic_store(&shm_ptr->slots[current_idx].debounce_enabled, true);
                                show_notification("✓ Debounce enabled on slot %d", current_idx);
                            }
                            else if (strcmp(cmd_line, "debounce off") == 0) {
                                atomic_store(&shm_ptr->slots[current_idx].debounce_enabled, false);
                                show_notification("✓ Debounce disabled on slot %d", current_idx);
                            }
                            
                            // ----- Rumble -----
                            else if (strcmp(cmd_line, "rumble on") == 0) {
                                atomic_store(&shm_ptr->slots[current_idx].rumble_active, true);
                                show_notification("✓ Rumble ENABLED on slot %d", current_idx);
                            }
                            else if (strcmp(cmd_line, "rumble off") == 0) {
                                atomic_store(&shm_ptr->slots[current_idx].rumble_active, false);
                                atomic_store(&shm_ptr->slots[current_idx].rumble_strong, 0);
                                atomic_store(&shm_ptr->slots[current_idx].rumble_weak, 0);
                                atomic_store(&shm_ptr->slots[current_idx].rumble_dirty, true);
                                show_notification("✓ Rumble DISABLED on slot %d", current_idx);
                            }
                            else if (strcmp(cmd_line, "rumble status") == 0) {
                                if (atomic_load(&shm_ptr->slots[current_idx].rumble_active)) {
                                    show_notification("Slot %d: Rumble ACTIVE", current_idx);
                                } else {
                                    show_notification("Slot %d: Rumble INACTIVE", current_idx);
                                }
                            }
                            
                            // ----- Rumble gain -----
                            else if (strncmp(cmd_line, "gain ", 5) == 0) {
                                int g = atoi(cmd_line + 5);
                                if (g >= 0 && g <= 100) { 
                                    atomic_store(&shm_ptr->slots[current_idx].rumble_gain, (uint8_t)g);
                                    show_notification("✓ Gain set to %d%% on slot %d", g, current_idx);
                                } else {
                                    show_notification("Gain must be 0-100");
                                }
                            }
                            
                            // ----- Deadzone -----
                            else if (strncmp(cmd_line, "deadzone ", 9) == 0) {
                                int dz = atoi(cmd_line + 9);
                                if (dz >= 0 && dz <= 100) {
                                    atomic_store(&shm_ptr->slots[current_idx].deadzone, (uint8_t)dz);
                                    show_notification("✓ Deadzone set to %d%% on slot %d", dz, current_idx);
                                } else {
                                    show_notification("Deadzone must be 0-100");
                                }
                            }
                            
                            // ----- Reapply (LED reapplication) -----
                            else if (strcmp(cmd_line, "reapply on") == 0) {
                                atomic_store(&shm_ptr->slots[current_idx].led_reapply, true);
                                show_notification("✓ Reaction to interventions ENABLED on slot %d", current_idx);
                            }
                            else if (strcmp(cmd_line, "reapply off") == 0) {
                                atomic_store(&shm_ptr->slots[current_idx].led_reapply, false);
                                show_notification("✓ Reaction to interventions DISABLED on slot %d", current_idx);
                            }
                            else if (strcmp(cmd_line, "reapply status") == 0) {
                                if (atomic_load(&shm_ptr->slots[current_idx].led_reapply)) {
                                    show_notification("Slot %d: Reaction to interventions ACTIVE", current_idx);
                                } else {
                                    show_notification("Slot %d: Reaction to interventions INACTIVE", current_idx);
                                }
                            }
                            
                            // ----- Player LEDs (DualSense) -----
                            else if (strncmp(cmd_line, "pled ", 5) == 0) {
                                int mode = atoi(cmd_line + 5);
                                if (shm_ptr->slots[current_idx].type != TYPE_DUALSENSE) {
                                    show_notification("✗ Player LEDs are exclusive to DualSense");
                                }
                                else if (mode >= 0 && mode <= 5) {
                                    atomic_store(&shm_ptr->slots[current_idx].player_leds, (uint8_t)mode);
                                    atomic_store(&shm_ptr->slots[current_idx].led_static, true);
                                    atomic_store(&shm_ptr->slots[current_idx].led_dirty, true);
                                    if (mode == 0) {
                                        show_notification("✓ Player LEDs turned off on slot %d", current_idx);
                                    } else {
                                        show_notification("✓ Player LEDs: Player %d on slot %d", mode, current_idx);
                                    }
                                } else {
                                    show_notification("Usage: pled <0-5> (0=off, 1-5=player)");
                                }
                            }
                            
                            // ----- LED color (CLI format "color RRGGBB" or just hex) -----
                            else if (strncmp(cmd_line, "color ", 6) == 0) {
                                unsigned int r, g, b;
                                if (sscanf(cmd_line + 6, "%02x%02x%02x", &r, &g, &b) == 3) {
                                    atomic_store(&shm_ptr->slots[current_idx].led_static, true);
                                    atomic_store(&shm_ptr->slots[current_idx].led_request_pending, false);
                                    atomic_store(&shm_ptr->slots[current_idx].led_request_effect, 0);
                                    atomic_store(&shm_ptr->slots[current_idx].led_base_r, (uint8_t)r);
                                    atomic_store(&shm_ptr->slots[current_idx].led_base_g, (uint8_t)g);
                                    atomic_store(&shm_ptr->slots[current_idx].led_base_b, (uint8_t)b);
                                    atomic_store(&shm_ptr->slots[current_idx].led_r, (uint8_t)r);
                                    atomic_store(&shm_ptr->slots[current_idx].led_g, (uint8_t)g);
                                    atomic_store(&shm_ptr->slots[current_idx].led_b, (uint8_t)b);
                                    atomic_store(&shm_ptr->slots[current_idx].led_dirty, true);
                                    show_notification("✓ Color #%02x%02x%02x applied on slot %d", r, g, b, current_idx);
                                } else {
                                    show_notification("Invalid format. Use color RRGGBB (e.g., color ff00aa)");
                                }
                            }
                            else if (strlen(cmd_line) == 6 && strspn(cmd_line, "0123456789abcdefABCDEF") == 6) {
                                unsigned int r, g, b;
                                if (sscanf(cmd_line, "%02x%02x%02x", &r, &g, &b) == 3) {
                                    atomic_store(&shm_ptr->slots[current_idx].led_static, true);
                                    atomic_store(&shm_ptr->slots[current_idx].led_request_pending, false);
                                    atomic_store(&shm_ptr->slots[current_idx].led_request_effect, 0);
                                    atomic_store(&shm_ptr->slots[current_idx].led_base_r, (uint8_t)r);
                                    atomic_store(&shm_ptr->slots[current_idx].led_base_g, (uint8_t)g);
                                    atomic_store(&shm_ptr->slots[current_idx].led_base_b, (uint8_t)b);
                                    atomic_store(&shm_ptr->slots[current_idx].led_r, (uint8_t)r);
                                    atomic_store(&shm_ptr->slots[current_idx].led_g, (uint8_t)g);
                                    atomic_store(&shm_ptr->slots[current_idx].led_b, (uint8_t)b);
                                    atomic_store(&shm_ptr->slots[current_idx].led_dirty, true);
                                    show_notification("✓ Color #%02x%02x%02x applied on slot %d", r, g, b, current_idx);
                                }
                            }
                            
                            // ----- LED effects (ledfx) -----
                            else if (strncmp(cmd_line, "ledfx", 5) == 0) {
                                int effect_num = 0, speed = 5, brightness = 80;
                                int parsed = sscanf(cmd_line + 5, "%d %d %d", &effect_num, &speed, &brightness);
                                if (parsed >= 1 && effect_num >= 0 && effect_num < LEDFX_COUNT) {
                                    if (effect_num == 0) {
                                        atomic_store(&shm_ptr->slots[current_idx].led_static, true);
                                        atomic_store(&shm_ptr->slots[current_idx].led_request_pending, false);
                                        uint8_t base_r = atomic_load(&shm_ptr->slots[current_idx].led_base_r);
                                        uint8_t base_g = atomic_load(&shm_ptr->slots[current_idx].led_base_g);
                                        uint8_t base_b = atomic_load(&shm_ptr->slots[current_idx].led_base_b);
                                        atomic_store(&shm_ptr->slots[current_idx].led_r, base_r);
                                        atomic_store(&shm_ptr->slots[current_idx].led_g, base_g);
                                        atomic_store(&shm_ptr->slots[current_idx].led_b, base_b);
                                        atomic_store(&shm_ptr->slots[current_idx].led_dirty, true);
                                        show_notification("✓ Static mode enabled for slot %d", current_idx);
                                    } else {
                                        atomic_store(&shm_ptr->slots[current_idx].led_static, false);
                                        atomic_store(&shm_ptr->slots[current_idx].led_request_effect, effect_num);
                                        atomic_store(&shm_ptr->slots[current_idx].led_request_speed, (uint8_t)speed);
                                        atomic_store(&shm_ptr->slots[current_idx].led_request_brightness, (uint8_t)brightness);
                                        atomic_store(&shm_ptr->slots[current_idx].led_request_pending, true);
                                        show_notification("✓ Effect %d requested for slot %d", effect_num, current_idx);
                                    }
                                } else {
                                    show_notification("Effects: 1..%d | Usage: ledfx <n> [speed] [brightness]", LEDFX_COUNT - 1);
                                }
                            }
                            
                            // ----- Global LED brightness -----
                            else if (strncmp(cmd_line, "brightness ", 11) == 0) {
                                int b = atoi(cmd_line + 11);
                                if (b >= 0 && b <= 100) {
                                    atomic_store(&shm_ptr->slots[current_idx].global_led_brightness, (uint8_t)b);
                                    atomic_store(&shm_ptr->slots[current_idx].led_dirty, true);
                                    show_notification("✓ Global brightness set to %d%% on slot %d", b, current_idx);
                                } else {
                                    show_notification("Brightness must be 0-100");
                                }
                            }
                            
                            pthread_mutex_unlock(&shm_ptr->proc_mutex);
                        }
                        cmd_len = 0; 
                        memset(cmd_line, 0, MY_MAX_INPUT); 
                    }
                } 
                else if ((c == 127 || c == 8) && cmd_len > 0) {
                    cmd_line[--cmd_len] = '\0';
                }
                else if (cmd_len < MY_MAX_INPUT - 1 && isprint(c)) { 
                    cmd_line[cmd_len++] = (char)c; 
                    cmd_line[cmd_len] = '\0'; 
                }
            }
        }
    }

    printf(SHOW_CURSOR ALT_BUFFER_OFF);
    disable_raw_mode();
}
