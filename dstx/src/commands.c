/*
 * commands.c - Command line interface for DSTX
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
 * Allows executing all operations available in the TUI via scripts
 * or command line, without entering interactive mode.
 *
 * Supports batch mode: dstx <slot> --command1 args --command2 args ...
 *
 * - All numeric parameters are validated before writing to SHM.
 * - Ranges checked: deadzone (0-100), gain (0-100), brightness (0-100),
 *   sensitivity preset (0-SENS_PRESET_COUNT-1), player LEDs (0-5),
 *   LED effect (0-LEDFX_COUNT-1), speed (1-10), effect brightness (0-100).
 * - Keybinds check physical and logical limits.
 * - Colors in RRGGBB format are syntactically validated.
 */

#include "dstx.h"
#include "axes.h"
#include "keys.h"
#include "led.h"
#include <ctype.h>
#include <getopt.h>   // only for simple parsing, but we'll use manual
#include <stdarg.h>

// ----------------------------------------------------------------------
// Internal helper functions
// ----------------------------------------------------------------------

static bool str_to_bool(const char *s) {
    if (!s) return false;
    if (strcmp(s, "on") == 0 || strcmp(s, "1") == 0) return true;
    if (strcmp(s, "off") == 0 || strcmp(s, "0") == 0) return false;
    return false; // default
}

static void print_error(const char *fmt, ...) {
    va_list args;
    va_start(args, fmt);
    fprintf(stderr, "Error: ");
    vfprintf(stderr, fmt, args);
    fprintf(stderr, "\n");
    va_end(args);
}

static void print_ok(const char *msg) {
    printf("%s\n", msg);
}

static void print_keymap(controller_t *slot) {
    const char *logical_names[] = {
        "NONE", "CROSS", "CIRCLE", "SQUARE", "TRIANGLE",
        "L1", "R1", "L2", "R2", "SHARE", "OPTIONS",
        "L3", "R3", "PS", "TOUCH", "UP", "DOWN", "LEFT", "RIGHT"
    };
    printf("Keymap for slot %ld:\n", slot - shm_ptr->slots);
    for (int i = 0; i < PHY_BTN_COUNT; i++) {
        uint8_t log = slot->keymap[i];
        const char *log_name = (log < LOGICAL_BTN_COUNT) ? logical_names[log] : "?";
        printf("  PHY_%02d -> %s (%d)\n", i, log_name, log);
    }
}

// ----------------------------------------------------------------------
// Global command handlers (no slot)
// ----------------------------------------------------------------------

static int cmd_slots(shared_data_t *shm) {
    printf("Occupied slots:\n");
    for (int i = 0; i < MAX_SLOTS; i++) {
        if (atomic_load(&shm->slots[i].connected)) {
            const char *type = "Unknown";
            switch (shm->slots[i].type) {
                case TYPE_DS4: type = "DualShock 4"; break;
                case TYPE_DUALSENSE: type = "DualSense"; break;
                case TYPE_NSW_PRO: type = "Nintendo Switch Pro"; break;
            }
            printf("  Slot %d: %s (%s)\n", i, type,
                   shm->slots[i].is_bluetooth ? "Bluetooth" : "USB");
        }
    }
    return 0;
}

static int cmd_profile(shared_data_t *shm, int argc, char **argv) {
    // Syntax: profile load|save|delete|list [name]
    if (argc < 1) {
        print_error("Usage: profile load|save|delete|list [name]");
        return 1;
    }
    char *sub = argv[0];
    char resp[4096];
    bool ok = false;
    if (strcmp(sub, "list") == 0) {
        ok = profile_request_sync(shm, 4, NULL, -1, -1, resp, sizeof(resp));
        if (ok) {
            printf("Available profiles:\n%s", resp);
            return 0;
        } else {
            print_error("%s", resp);
            return 1;
        }
    } else if (strcmp(sub, "load") == 0 || strcmp(sub, "save") == 0 || strcmp(sub, "delete") == 0) {
        if (argc < 2) {
            print_error("Usage: profile %s <name>", sub);
            return 1;
        }
        int req = (strcmp(sub, "load") == 0) ? 1 :
                  (strcmp(sub, "save") == 0) ? 2 : 3;
        ok = profile_request_sync(shm, req, argv[1], -1, -1, resp, sizeof(resp));
        if (ok) {
            print_ok(resp);
            return 0;
        } else {
            print_error("%s", resp);
            return 1;
        }
    } else {
        print_error("Unknown subcommand: %s", sub);
        return 1;
    }
}

static int cmd_auto_save(shared_data_t *shm, int argc, char **argv) {
    // auto-save on|off|delay <ms>
    if (argc < 1) {
        print_error("Usage: auto-save on|off|delay <ms>");
        return 1;
    }
    char *sub = argv[0];
    char resp[512];
    bool ok = false;
    if (strcmp(sub, "on") == 0) {
        ok = profile_request_sync(shm, 5, NULL, 1, -1, resp, sizeof(resp));
    } else if (strcmp(sub, "off") == 0) {
        ok = profile_request_sync(shm, 5, NULL, 0, -1, resp, sizeof(resp));
    } else if (strcmp(sub, "delay") == 0) {
        if (argc < 2) {
            print_error("Usage: auto-save delay <ms> (100-10000)");
            return 1;
        }
        int delay = atoi(argv[1]);
        if (delay < 100 || delay > 10000) {
            print_error("Delay must be between 100 and 10000 ms");
            return 1;
        }
        ok = profile_request_sync(shm, 5, NULL, -1, delay, resp, sizeof(resp));
    } else {
        print_error("Invalid subcommand: %s", sub);
        return 1;
    }
    if (ok) {
        print_ok(resp);
        return 0;
    } else {
        print_error("%s", resp);
        return 1;
    }
}

static int cmd_help(shared_data_t *shm, int argc, char **argv) {
    (void)shm; (void)argc; (void)argv;
    printf("\nDSTX Command Line Interface Help\n");
    printf("=================================\n\n");
    
    printf("GLOBAL COMMANDS (no slot number):\n");
    printf("  slots                         - List connected controllers and their slots\n");
    printf("  profile load <name>           - Load profile from disk\n");
    printf("  profile save <name>           - Save current configuration to profile\n");
    printf("  profile delete <name>         - Delete profile\n");
    printf("  profile list                  - List available profiles\n");
    printf("  auto-save on|off              - Enable/disable automatic profile saving\n");
    printf("  auto-save delay <ms>          - Set auto-save delay (100-10000 ms)\n");
    printf("  help                          - Show this help message\n\n");
    
    printf("SLOT COMMANDS (use with: dstx <slot> <command> [args]):\n");
    printf("  color <RRGGBB>                - Set LED color (e.g., color ff00aa)\n");
    printf("  emulation on|off              - Enable/disable virtual device emulation\n");
    printf("  uhid on|off                   - Use UHID instead of uinput for emulation\n");
    printf("  keybind <phy> <log>           - Map physical button to logical button\n");
    printf("  keymap                        - Show current button mapping\n");
    printf("  reset-keybinds                - Reset all button mappings to identity\n");
    printf("  invert ly|ry on|off           - Invert Y axis for left/right stick\n");
    printf("  invert status                 - Show inversion status\n");
    printf("  sensitivity left|right <0-7>  - Set stick sensitivity preset (0-7)\n");
    printf("  sensitivity status            - Show current sensitivity presets\n");
    printf("  triggers-digital on|off|status- Digital trigger mode (L2/R2 as buttons)\n");
    printf("  ledfx <effect> [speed] [bright] - LED effect (0=static, 1-8 effects)\n");
    printf("  brightness <0-100>            - Global LED brightness\n");
    printf("  deadzone <0-100>              - Stick deadzone percentage\n");
    printf("  gain <0-100>                  - Rumble gain (strength)\n");
    printf("  rumble on|off|status          - Enable/disable rumble feedback\n");
    printf("  debounce on|off               - Enable/disable button debounce filtering\n");
    printf("  reapply on|off|status         - Auto-reapply LED on external changes\n");
    printf("  pled <0-5>                    - Player LED indicator (DualSense only)\n");
    printf("  layout switch|xbox            - Button layout (Nintendo Switch Pro only)\n\n");
    
    printf("EXAMPLES:\n");
    printf("  dstx 0 color ff0000           - Set slot 0 LED to red\n");
    printf("  dstx 1 sensitivity left 2     - Set left stick sensitivity preset 2 on slot 1\n");
    printf("  dstx 2 --uhid on --rumble off - Batch commands on slot 2\n");
    printf("  dstx slots                    - List all slots\n");
    printf("  dstx profile load myprofile   - Load profile 'myprofile'\n");
    printf("  dstx auto-save delay 3000     - Set auto-save delay to 3 seconds\n\n");
    
    return 0;
}

// ----------------------------------------------------------------------
// Slot command handlers
// ----------------------------------------------------------------------

static int cmd_color(controller_t *slot, int argc, char **argv) {
    if (argc < 1) {
        print_error("Usage: color <RRGGBB>");
        return 1;
    }
    unsigned int r, g, b;
    if (sscanf(argv[0], "%02x%02x%02x", &r, &g, &b) != 3) {
        print_error("Invalid color. Use format RRGGBB (e.g., ff00aa)");
        return 1;
    }
    // r,g,b already 0-255 due to %02x
    safe_shm_lock(&shm_ptr->proc_mutex);
    atomic_store(&slot->led_base_r, (uint8_t)r);
    atomic_store(&slot->led_base_g, (uint8_t)g);
    atomic_store(&slot->led_base_b, (uint8_t)b);
    atomic_store(&slot->led_r, (uint8_t)r);
    atomic_store(&slot->led_g, (uint8_t)g);
    atomic_store(&slot->led_b, (uint8_t)b);
    atomic_store(&slot->led_static, true);
    atomic_store(&slot->led_request_pending, false);
    atomic_store(&slot->led_dirty, true);
    pthread_mutex_unlock(&shm_ptr->proc_mutex);
    print_ok("Color applied");
    return 0;
}

static int cmd_emulation(controller_t *slot, int argc, char **argv) {
    if (argc < 1) {
        print_error("Usage: emulation on|off");
        return 1;
    }
    bool val = str_to_bool(argv[0]);
    atomic_store(&slot->emulate_active, val);
    print_ok(val ? "Emulation enabled" : "Emulation disabled");
    return 0;
}

static int cmd_uhid(controller_t *slot, int argc, char **argv) {
    if (argc < 1) {
        print_error("Usage: uhid on|off");
        return 1;
    }
    bool val = str_to_bool(argv[0]);
    atomic_store(&slot->is_uhid, val);
    // Force recreation of virtual device
    atomic_store(&slot->emulate_active, false);
    atomic_store(&slot->emulate_active, true);
    print_ok(val ? "UHID mode enabled" : "uinput mode enabled");
    return 0;
}

static int cmd_keybind(controller_t *slot, int argc, char **argv) {
    if (argc < 2) {
        print_error("Usage: keybind <phy> <log>");
        return 1;
    }
    int phy = atoi(argv[0]);
    int log = atoi(argv[1]);
    if (phy < 0 || phy >= PHY_BTN_COUNT || log < 0 || log >= LOGICAL_BTN_COUNT) {
        print_error("Invalid values. Range: phy 0-%d, log 0-%d", PHY_BTN_COUNT-1, LOGICAL_BTN_COUNT-1);
        return 1;
    }

    // Apply keybind directly (no flag, as it's immediate action)
    safe_shm_lock(&shm_ptr->proc_mutex);
    slot->keymap[phy] = log;
    atomic_store(&slot->led_dirty, true);
    pthread_mutex_unlock(&shm_ptr->proc_mutex);
    print_ok("Keybind applied");
    return 0;
}

static int cmd_keymap(controller_t *slot, int argc, char **argv) {
    (void)argc; (void)argv;
    print_keymap(slot);
    return 0;
}

static int cmd_reset_all_keybinds(controller_t *slot, int argc, char **argv) {
    (void)argc; (void)argv;
    atomic_store(&slot->request_reset_all_keybinds, true);
    print_ok("Full keybind reset request sent");
    return 0;
}

static int cmd_invert(controller_t *slot, int argc, char **argv) {
    if (argc < 2) {
        print_error("Usage: invert ly|ry on|off   or invert status");
        return 1;
    }
    char *which = argv[0];
    if (strcmp(which, "status") == 0) {
        bool ly = atomic_load(&slot->invert_ly);
        bool ry = atomic_load(&slot->invert_ry);
        printf("Slot %ld: L Y invert=%s, R Y invert=%s\n",
               slot - shm_ptr->slots, ly ? "ON" : "OFF", ry ? "ON" : "OFF");
        return 0;
    }
    if (argc < 2) {
        print_error("Usage: invert ly|ry on|off");
        return 1;
    }
    bool val = str_to_bool(argv[1]);
    if (strcmp(which, "ly") == 0) {
        atomic_store(&slot->invert_ly, val);
        print_ok(val ? "Y inversion (L) enabled" : "Y inversion (L) disabled");
    } else if (strcmp(which, "ry") == 0) {
        atomic_store(&slot->invert_ry, val);
        print_ok(val ? "Y inversion (R) enabled" : "Y inversion (R) disabled");
    } else {
        print_error("Invalid axis. Use ly or ry");
        return 1;
    }
    return 0;
}

static int cmd_sensitivity(controller_t *slot, int argc, char **argv) {
    if (argc < 1) {
        print_error("Usage: sensitivity left|right <preset>  or sensitivity status");
        return 1;
    }
    char *which = argv[0];
    if (strcmp(which, "status") == 0) {
        uint8_t left = atomic_load(&slot->sensitivity_left_preset);
        uint8_t right = atomic_load(&slot->sensitivity_right_preset);
        printf("Sensitivity: L=%s (%d), R=%s (%d)\n",
               get_sensitivity_preset_name(left), left,
               get_sensitivity_preset_name(right), right);
        return 0;
    }
    if (argc < 2) {
        print_error("Usage: sensitivity left|right <0-7>");
        return 1;
    }
    int preset = atoi(argv[1]);
    if (preset < 0 || preset >= SENS_PRESET_COUNT) {
        print_error("Invalid preset. Use 0-%d", SENS_PRESET_COUNT-1);
        return 1;
    }
    if (strcmp(which, "left") == 0) {
        apply_sensitivity_preset_left(slot, preset);
        print_ok("Left sensitivity changed");
    } else if (strcmp(which, "right") == 0) {
        apply_sensitivity_preset_right(slot, preset);
        print_ok("Right sensitivity changed");
    } else {
        print_error("Use left or right");
        return 1;
    }
    return 0;
}

static int cmd_triggers_digital(controller_t *slot, int argc, char **argv) {
    if (argc < 1) {
        print_error("Usage: triggers-digital on|off|status");
        return 1;
    }
    char *sub = argv[0];
    if (strcmp(sub, "status") == 0) {
        bool val = atomic_load(&slot->is_trigger_digital);
        printf("Triggers in %s mode\n", val ? "DIGITAL" : "ANALOG");
        return 0;
    }
    bool val = str_to_bool(sub);
    atomic_store(&slot->is_trigger_digital, val);
    print_ok(val ? "Digital mode enabled" : "Analog mode enabled");
    return 0;
}

static int cmd_ledfx(controller_t *slot, int argc, char **argv) {
    if (argc < 1) {
        print_error("Usage: ledfx <effect> [speed] [brightness]");
        return 1;
    }
    int effect = atoi(argv[0]);
    if (effect < 0 || effect >= LEDFX_COUNT) {
        print_error("Invalid effect. Use 0-%d", LEDFX_COUNT-1);
        return 1;
    }
    uint8_t speed = 5, brightness = 80;
    if (argc >= 2) speed = atoi(argv[1]);
    if (argc >= 3) brightness = atoi(argv[2]);
    if (speed < 1 || speed > 10) speed = 5;
    if (brightness < 1 || brightness > 100) brightness = 80;

    safe_shm_lock(&shm_ptr->proc_mutex);
    if (effect == 0) {
        atomic_store(&slot->led_static, true);
        atomic_store(&slot->led_request_pending, false);
        // Set static color from base (using atomic_store)
        uint8_t base_r = atomic_load(&slot->led_base_r);
        uint8_t base_g = atomic_load(&slot->led_base_g);
        uint8_t base_b = atomic_load(&slot->led_base_b);
        atomic_store(&slot->led_r, base_r);
        atomic_store(&slot->led_g, base_g);
        atomic_store(&slot->led_b, base_b);
        atomic_store(&slot->led_dirty, true);
    } else {
        atomic_store(&slot->led_static, false);
        atomic_store(&slot->led_request_effect, effect);
        atomic_store(&slot->led_request_speed, speed);
        atomic_store(&slot->led_request_brightness, brightness);
        atomic_store(&slot->led_request_pending, true);
    }
    pthread_mutex_unlock(&shm_ptr->proc_mutex);
    print_ok(effect == 0 ? "Static mode enabled" : "Effect requested");
    return 0;
}

static int cmd_brightness(controller_t *slot, int argc, char **argv) {
    if (argc < 1) {
        print_error("Usage: brightness <0-100>");
        return 1;
    }
    int b = atoi(argv[0]);
    if (b < 0 || b > 100) {
        print_error("Brightness must be between 0 and 100");
        return 1;
    }
    safe_shm_lock(&shm_ptr->proc_mutex);
    atomic_store(&slot->global_led_brightness, (uint8_t)b);
    atomic_store(&slot->led_dirty, true);
    pthread_mutex_unlock(&shm_ptr->proc_mutex);
    print_ok("Brightness changed");
    return 0;
}

static int cmd_deadzone(controller_t *slot, int argc, char **argv) {
    if (argc < 1) {
        print_error("Usage: deadzone <0-100>");
        return 1;
    }
    int dz = atoi(argv[0]);
    if (dz < 0 || dz > 100) {
        print_error("Deadzone must be between 0 and 100");
        return 1;
    }
    safe_shm_lock(&shm_ptr->proc_mutex);
    atomic_store(&slot->deadzone, (uint8_t)dz);
    pthread_mutex_unlock(&shm_ptr->proc_mutex);
    print_ok("Deadzone changed");
    return 0;
}

static int cmd_gain(controller_t *slot, int argc, char **argv) {
    if (argc < 1) {
        print_error("Usage: gain <0-100>");
        return 1;
    }
    int g = atoi(argv[0]);
    if (g < 0 || g > 100) {
        print_error("Gain must be between 0 and 100");
        return 1;
    }
    safe_shm_lock(&shm_ptr->proc_mutex);
    atomic_store(&slot->rumble_gain, (uint8_t)g);
    pthread_mutex_unlock(&shm_ptr->proc_mutex);
    print_ok("Gain changed");
    return 0;
}

static int cmd_rumble(controller_t *slot, int argc, char **argv) {
    if (argc < 1) {
        print_error("Usage: rumble on|off|status");
        return 1;
    }
    char *sub = argv[0];
    if (strcmp(sub, "status") == 0) {
        bool val = atomic_load(&slot->rumble_active);
        printf("Rumble %s\n", val ? "ACTIVE" : "INACTIVE");
        return 0;
    }
    bool val = str_to_bool(sub);
    atomic_store(&slot->rumble_active, val);
    if (!val) {
        safe_shm_lock(&shm_ptr->proc_mutex);
        atomic_store(&slot->rumble_strong, 0);
        atomic_store(&slot->rumble_weak, 0);
        atomic_store(&slot->rumble_dirty, true);
        pthread_mutex_unlock(&shm_ptr->proc_mutex);
    }
    print_ok(val ? "Rumble enabled" : "Rumble disabled");
    return 0;
}

static int cmd_debounce(controller_t *slot, int argc, char **argv) {
    if (argc < 1) {
        print_error("Usage: debounce on|off");
        return 1;
    }
    bool val = str_to_bool(argv[0]);
    safe_shm_lock(&shm_ptr->proc_mutex);
    atomic_store(&slot->debounce_enabled, val);
    pthread_mutex_unlock(&shm_ptr->proc_mutex);
    print_ok(val ? "Debounce enabled" : "Debounce disabled");
    return 0;
}

static int cmd_reapply(controller_t *slot, int argc, char **argv) {
    if (argc < 1) {
        print_error("Usage: reapply on|off|status");
        return 1;
    }
    char *sub = argv[0];
    if (strcmp(sub, "status") == 0) {
        bool val = atomic_load(&slot->led_reapply);
        printf("Auto-reapply: %s\n", val ? "ACTIVE" : "INACTIVE");
        return 0;
    }
    bool val = str_to_bool(sub);
    atomic_store(&slot->led_reapply, val);
    print_ok(val ? "Reapply enabled" : "Reapply disabled");
    return 0;
}

static int cmd_pled(controller_t *slot, int argc, char **argv) {
    if (argc < 1) {
        print_error("Usage: pled <0-5>");
        return 1;
    }
    int p = atoi(argv[0]);
    if (p < 0 || p > 5) {
        print_error("Invalid mode. Use 0-5");
        return 1;
    }
    if (slot->type != TYPE_DUALSENSE) {
        print_error("Player LEDs are exclusive to DualSense");
        return 1;
    }
    safe_shm_lock(&shm_ptr->proc_mutex);
    atomic_store(&slot->player_leds, (uint8_t)p);
    atomic_store(&slot->led_dirty, true);
    pthread_mutex_unlock(&shm_ptr->proc_mutex);
    print_ok(p == 0 ? "Player LEDs turned off" : "Player LEDs configured");
    return 0;
}

static int cmd_layout(controller_t *slot, int argc, char **argv) {
    if (argc < 1) {
        print_error("Usage: layout switch|xbox");
        return 1;
    }
    char *sub = argv[0];
    if (strcmp(sub, "switch") == 0) {
        if (slot->type != TYPE_NSW_PRO) {
            print_error("Switch layout is only available for Nintendo Switch Pro");
            return 1;
        }
        atomic_store(&slot->request_switch_layout, true);
        print_ok("Switch layout request sent");
    } else if (strcmp(sub, "xbox") == 0) {
        if (slot->type != TYPE_NSW_PRO) {
            print_error("Xbox layout is standard for other controllers");
            return 1;
        }
        atomic_store(&slot->request_xbox_layout, true);
        print_ok("Xbox layout (face) request sent");
    } else {
        print_error("Usage: layout switch|xbox");
        return 1;
    }
    return 0;
}

// ----------------------------------------------------------------------
// Dispatch table for slot commands
// ----------------------------------------------------------------------
typedef struct {
    const char *name;
    int (*handler)(controller_t *slot, int argc, char **argv);
} slot_command_t;

static const slot_command_t slot_commands[] = {
    { "color",                cmd_color },
    { "emulation",            cmd_emulation },
    { "uhid",                 cmd_uhid },
    { "keybind",              cmd_keybind },
    { "keymap",               cmd_keymap },
    { "reset-keybinds",       cmd_reset_all_keybinds },
    { "invert",               cmd_invert },
    { "sensitivity",          cmd_sensitivity },
    { "triggers-digital",     cmd_triggers_digital },
    { "ledfx",                cmd_ledfx },
    { "brightness",           cmd_brightness },
    { "deadzone",             cmd_deadzone },
    { "gain",                 cmd_gain },
    { "rumble",               cmd_rumble },
    { "debounce",             cmd_debounce },
    { "reapply",              cmd_reapply },
    { "pled",                 cmd_pled },
    { "layout",               cmd_layout },
    { NULL, NULL }
};

// ----------------------------------------------------------------------
// Execute a single slot command (with its specific arguments)
// ----------------------------------------------------------------------
static int execute_slot_command(controller_t *slot, const char *cmd_name, int cmd_argc, char **cmd_argv) {
    for (const slot_command_t *sc = slot_commands; sc->name; sc++) {
        if (strcmp(sc->name, cmd_name) == 0) {
            return sc->handler(slot, cmd_argc, cmd_argv);
        }
    }
    print_error("Unknown slot command: %s", cmd_name);
    return 1;
}

// ----------------------------------------------------------------------
// Main CLI entry point
// ----------------------------------------------------------------------
int process_cli_command(int argc, char **argv) {
    bool wait_mode = false;
    if (argc > 0 && strcmp(argv[argc-1], "--wait") == 0) {
        wait_mode = true;
        argc--;
    }

    openlog("dstx-cli", LOG_PID | LOG_NDELAY, LOG_USER);

    // Connect to shared memory
    if (!try_connect_shm()) {
        print_error("Could not connect to DSTX daemon. Make sure the service is running.");
        closelog();
        return 1;
    }

    if (shm_ptr->magic != SHM_MAGIC_VALUE) {
        print_error("Shared memory corrupted.");
        closelog();
        return 1;
    }

    if (!is_daemon_alive()) {
        print_error("DSTX daemon is not responding. Run 'dstx start' or restart the service.");
        closelog();
        return 1;
    }

    // First argument can be a number (slot) or a global command
    char *first = argv[0];
    
    // Help command detection (global)
    if (strcmp(first, "help") == 0 || strcmp(first, "--help") == 0 || strcmp(first, "-h") == 0) {
        int ret = cmd_help(shm_ptr, argc, argv);
        if (wait_mode) {
            printf("\nPress ENTER to exit...");
            fflush(stdout);
            getchar();
        }
        closelog();
        return ret;
    }

    char *endptr;
    long slot_num = strtol(first, &endptr, 10);
    bool is_slot_cmd = (*endptr == '\0' && slot_num >= 0 && slot_num < MAX_SLOTS);

    if (is_slot_cmd) {
        int idx = (int)slot_num;
        // Check if slot is connected
        if (!atomic_load(&shm_ptr->slots[idx].connected)) {
            print_error("Slot %d is not connected", idx);
            closelog();
            return 1;
        }
        controller_t *slot = &shm_ptr->slots[idx];

        // Batch mode: if there are more than one argument and the next starts with "--"
        // or if there are multiple commands.
        if (argc >= 2 && (argc > 2 || strncmp(argv[1], "--", 2) == 0)) {
            // Process each token starting with "--"
            int ret = 0;
            int i = 1;
            while (i < argc) {
                if (strncmp(argv[i], "--", 2) != 0) {
                    print_error("Expected command starting with '--', got: %s", argv[i]);
                    ret = 1;
                    break;
                }
                const char *cmd_name = argv[i] + 2; // remove "--"
                i++;
                // Collect arguments until next "--" or end
                int cmd_argc = 0;
                char **cmd_argv = NULL;
                if (i < argc && strncmp(argv[i], "--", 2) != 0) {
                    cmd_argv = &argv[i];
                    while (i < argc && strncmp(argv[i], "--", 2) != 0) {
                        cmd_argc++;
                        i++;
                    }
                }
                int cmd_ret = execute_slot_command(slot, cmd_name, cmd_argc, cmd_argv);
                if (cmd_ret != 0) ret = cmd_ret;
            }
            if (wait_mode) {
                printf("\nPress ENTER to exit...");
                fflush(stdout);
                getchar();
            }
            closelog();
            return ret;
        } else if (argc == 2) {
            // Simple mode with only one command (without "--") – compatibility
            char *arg = argv[1];
            // Check if it's a color (6 hex digits)
            bool is_color = (strlen(arg) == 6);
            if (is_color) {
                for (int i = 0; i < 6; i++) {
                    if (!isxdigit(arg[i])) {
                        is_color = false;
                        break;
                    }
                }
            }
            if (is_color) {
                int ret = cmd_color(slot, 1, &arg);
                if (wait_mode) {
                    printf("\nPress ENTER to exit...");
                    fflush(stdout);
                    getchar();
                }
                closelog();
                return ret;
            } else {
                // Look up in command table
                for (const slot_command_t *sc = slot_commands; sc->name; sc++) {
                    if (strcmp(sc->name, arg) == 0) {
                        int ret = sc->handler(slot, 0, NULL);
                        if (wait_mode) {
                            printf("\nPress ENTER to exit...");
                            fflush(stdout);
                            getchar();
                        }
                        closelog();
                        return ret;
                    }
                }
                print_error("Unknown slot command: %s", arg);
                closelog();
                return 1;
            }
        } else {
            print_error("Usage: dstx <slot> <command> [args...]   or   dstx <slot> --command1 ...");
            closelog();
            return 1;
        }
    } else {
        // Global command
        if (strcmp(first, "slots") == 0) {
            int ret = cmd_slots(shm_ptr);
            if (wait_mode) {
                printf("\nPress ENTER to exit...");
                fflush(stdout);
                getchar();
            }
            closelog();
            return ret;
        } else if (strcmp(first, "profile") == 0) {
            int ret = cmd_profile(shm_ptr, argc - 1, argv + 1);
            if (wait_mode) {
                printf("\nPress ENTER to exit...");
                fflush(stdout);
                getchar();
            }
            closelog();
            return ret;
        } else if (strcmp(first, "auto-save") == 0) {
            int ret = cmd_auto_save(shm_ptr, argc - 1, argv + 1);
            if (wait_mode) {
                printf("\nPress ENTER to exit...");
                fflush(stdout);
                getchar();
            }
            closelog();
            return ret;
        } else if (strcmp(first, "help") == 0 || strcmp(first, "--help") == 0 || strcmp(first, "-h") == 0) {
            // Already handled above, but keep for completeness
            int ret = cmd_help(shm_ptr, argc, argv);
            if (wait_mode) {
                printf("\nPress ENTER to exit...");
                fflush(stdout);
                getchar();
            }
            closelog();
            return ret;
        } else {
            print_error("Unknown global command: %s", first);
            fprintf(stderr, "Available global commands: slots, profile, auto-save, help\n");
            closelog();
            return 1;
        }
    }
}
