/*
 * display.c - Terminal user interface rendering for DSTX
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
 */

#include "dstx.h"
#include "display.h"
#include <ctype.h>
#include <string.h>
#include <stdio.h>
#include <sys/ioctl.h>
#include <libgen.h>
#include <signal.h>

char selected_dev_path[128] = "";

// --- Variables for profile list mode ---
static bool list_mode = false;
static char g_profiles_list[4096] = {0};

// --- Help system static data ---
static bool help_mode = false;
#define TOTAL_HELP_PAGES 4
static const char *help_pages[TOTAL_HELP_PAGES] = {
    // Page 0: General TUI commands
    "DSTX TUI HELP - PAGE 1/4: GENERAL COMMANDS\n"
    "\n"
    "  exit, q            - Quit the TUI\n"
    "  info               - Show device information screen\n"
    "  profiles           - List available profiles\n"
    "  start              - Start the DSTX daemon service\n"
    "  stop               - Stop the DSTX daemon service\n"
    "  setup              - Run infrastructure setup script\n"
    "  help               - Show this help (navigate with ← / → )\n"
    "\n\n\n\n\n\n\n\n\n"
    "Press LEFT/RIGHT arrows to change page. Any other key exits help.\n",

    // Page 1: Slot commands (part 1)
    "DSTX TUI HELP - PAGE 2/4: SLOT COMMANDS (1/3)\n"
    "\n"
    "  ::LED::\n"
    "  <RRGGBB>                      - Set LED color (e.g., ff00aa)\n"
    "  ledfx <effect> [speed]        - LED effect (0=static, 1-8 effects, 1-10 speed)\n"
    "  brightness <0-100>            - Global LED brightness\n"
    "  reapply on|off|status         - Auto-reapply LED on external changes\n"
    "  pled <0-5>                    - Player LED indicator (DualSense only)\n\n"
    "  ::EMULATION::\n"
    "  emulation on|off              - Enable/disable virtual device emulation\n"
    "  uhid on|off                   - Use UHID instead of uinput\n\n"
    "  ::KEYBINDS::\n"
    "  keybind <phy> <log>           - Map physical button to logical button\n"
    "  keymap                        - Show current button mapping\n"
    "  reset-keybinds                - Reset all button mappings to identity\n"
    "\n"
    "Press LEFT/RIGHT arrows to change page. Any other key exits help.\n",

    // Page 2: Slot commands (part 2)
    "DSTX TUI HELP - PAGE 3/4: SLOT COMMANDS (2/3)\n"
    "\n"
    "  ::RUMBLE::\n"
    "  rumble on|off|status          - Enable/disable rumble feedback\n"
    "  gain <0-100>                  - Rumble gain (strength)\n\n"
    "  ::STICKS::\n"
    "  invert ly|ry on|off           - Invert Y axis for left/right stick\n"
    "  invert status                 - Show inversion status\n"
    "  sensitivity left|right <0-7>  - Set stick sensitivity preset\n"
    "  sensitivity status            - Show current sensitivity\n"
    "  deadzone <0-100>              - Stick deadzone percentage\n\n"
    "  ::BUTTONS::\n"
    "  triggers-digital on|off|status- Digital trigger mode (L2/R2 as buttons)\n"
    "  debounce on|off               - Enable/disable button debounce\n"
    "  layout switch|xbox            - Button layout (Nintendo Switch Pro only)\n"
    "\n"
    "Press LEFT/RIGHT arrows to change page. Any other key exits help.\n",

    // Page 3: Slot commands (part 3) and examples
    "DSTX TUI HELP - PAGE 4/4: SLOT COMMANDS (3/3) & EXAMPLES\n"
    "\n"
    "  ::PROFILES::\n"
    "  profile save|load|delete <name>   - Manage profiles\n"
    "  profile list                      - List available profiles\n"
    "  auto-save on|off                  - Enable/disable profile auto-save\n\n"    
    "  ::EXAMPLES::\n"
    "  color ff0000                      - Set LED to red\n"
    "  brightness 80                     - Set brightness to 80%\n"
    "  sensitivity left 2                - Set left stick sensitivity preset 2\n"
    "  triggers-digital on               - Make L2/R2 act as digital buttons\n"
    "  ledfx 3 7                         - Start effect 3, speed 7\n"
    "  profile load myprofile            - Load profile 'myprofile'\n"

    "\n\n\n\n"
    "Press LEFT/RIGHT arrows to change page. Any other key exits help.\n"
};

// --- Window Management and Helpers ---

void force_terminal_size(int r, int c) {
    printf("\033[8;%d;%dt", r, c);
    fflush(stdout);
}

void get_binary_path(char *out_dir, size_t size) {
    char path[512];
    ssize_t len = readlink("/proc/self/exe", path, sizeof(path) - 1);
    if (len != -1) {
        path[len] = '\0';
        char *dname = dirname(path);
        strncpy(out_dir, dname, size - 1);
        out_dir[size - 1] = '\0';
    } else {
        strncpy(out_dir, ".", size - 1);
        out_dir[size - 1] = '\0';
    }
}

bool check_window_sanity(void) {
    struct winsize w;
    if (ioctl(STDOUT_FILENO, TIOCGWINSZ, &w) == -1) return true;
    if (w.ws_col < MIN_COLS || w.ws_row < MIN_ROWS) {
        printf(HOME CLEAR_SCREEN "\n\n  " CLR_RED "![ERROR] WINDOW TOO SMALL" CLR_RESET "\n");
        printf("  Minimum size: " CLR_CYAN "%dx%d" CLR_RESET " | Current: " CLR_YELLOW "%dx%d" CLR_RESET "\n",
               MIN_COLS, MIN_ROWS, w.ws_col, w.ws_row);
        fflush(stdout);
        return false;
    }
    return true;
}

int update_and_get_slot_idx(shared_data_t *shm) {
    if (selected_dev_path[0] != '\0') {
        for (int i = 0; i < MAX_SLOTS; i++) {
            if (shm->slots[i].connected && strcmp(shm->slots[i].dev_path, selected_dev_path) == 0) return i;
        }
    }
    for (int i = 0; i < MAX_SLOTS; i++) {
        if (shm->slots[i].connected && shm->slots[i].dev_path[0] != '\0') {
            strncpy(selected_dev_path, shm->slots[i].dev_path, sizeof(selected_dev_path) - 1);
            return i;
        }
    }
    return -1;
}

// --- Draw a border ---
void draw_border(int r1, int c1, int r2, int c2, const char* color) {
    printf("%s", color);
    // Corners and horizontal lines
    printf("\033[%d;%dH╭", r1, c1);
    for (int i = c1 + 1; i < c2; i++) printf("─");
    printf("╮");
    printf("\033[%d;%dH╰", r2, c1);
    for (int i = c1 + 1; i < c2; i++) printf("─");
    printf("╯");
    // Vertical lines
    for (int i = r1 + 1; i < r2; i++) {
        printf("\033[%d;%dH│", i, c1);
        printf("\033[%d;%dH│", i, c2);
    }
    printf(CLR_RESET);
}

// --- Render face buttons with controller-specific mapping ---
static void render_face_buttons(controller_t *s, int row, int col) {
    printf("\033[%d;%dH %sBTN:%s ", row, col, CLR_LABEL, CLR_RESET);
    printf("%s", CLR_GRAY);
    printf(" ");

    if (s->type == TYPE_NSW_PRO) {
        // Nintendo Switch Pro - Xbox/Nintendo layout
        // Mapping: Square→X, Triangle→Y, Circle→B, Cross→A
        const char *square_symbol = "X";
        const char *triangle_symbol = "Y";
        const char *circle_symbol = "B";
        const char *cross_symbol = "A";

        // Button X
        printf("%s", s->square ? CLR_BLUE : CLR_GRAY);
        printf("%s", square_symbol);
        printf("%s", CLR_GRAY);
        printf("   ");

        // Button Y
        printf("%s", s->triangle ? CLR_YELLOW : CLR_GRAY);
        printf("%s", triangle_symbol);
        printf("%s", CLR_GRAY);
        printf("   ");

        // Button B
        printf("%s", s->circle ? CLR_RED : CLR_GRAY);
        printf("%s", circle_symbol);
        printf("%s", CLR_GRAY);
        printf("   ");

        // Button A
        printf("%s", s->cross ? CLR_GREEN : CLR_GRAY);
        printf("%s", cross_symbol);
        printf("%s", CLR_RESET);

    } else {
        // PlayStation Controllers (DS4, DualSense) - Original layout
        // Symbols: □ (square), △ (triangle), ○ (circle), ⨉ (cross)

        // Button □ (Square)
        printf("%s", s->square ? CLR_PURPLE : CLR_GRAY);
        printf("%s", s->square ? "■" : "□");
        printf("%s", CLR_GRAY);
        printf("   ");

        // Button △ (Triangle)
        printf("%s", s->triangle ? CLR_GREEN : CLR_GRAY);
        printf("%s", s->triangle ? "▲" : "△");
        printf("%s", CLR_GRAY);
        printf("   ");

        // Button ○ (Circle)
        printf("%s", s->circle ? CLR_RED : CLR_GRAY);
        printf("%s", s->circle ? "●" : "○");
        printf("%s", CLR_GRAY);
        printf("   ");

        // Button ⨉ (Cross)
        printf("%s", s->cross ? CLR_CYAN : CLR_GRAY);
        printf("%s", s->cross ? "⨉" : "⨉");
        printf("%s", CLR_RESET);
    }
}

// --- Render system buttons with controller-specific mapping ---
static void render_system_buttons(controller_t *s, int row, int col) {
    printf("\033[%d;%dH %sSYS:%s ", row, col, CLR_LABEL, CLR_RESET);
    printf("%s", CLR_GRAY);
    printf("   ");

    if (s->type == TYPE_NSW_PRO) {
        // Nintendo Switch Pro - System buttons in Switch style
        // Share → Minus (-)
        // PS → Home (house)
        // Options → Plus (+)

        // Minus button (Share)
        printf("%s", s->Share ? CLR_CYAN : CLR_GRAY);
        printf("%s", s->Share ? "-" : "-");
        printf("%s", CLR_GRAY);
        printf("   ");

        // Home button (PS)
        printf("%s", s->PS ? CLR_CYAN : CLR_GRAY);
        printf("%s", s->PS ? "⌂" : "⌂");
        printf("%s", CLR_GRAY);
        printf("   ");

        // Plus button (Options)
        printf("%s", s->Options ? CLR_CYAN : CLR_GRAY);
        printf("%s", s->Options ? "+" : "+");
        printf("%s", CLR_RESET);

    } else {
        // PlayStation Controllers - Original system buttons
        // Share, PS, Options

        // Share button
        printf("%s", s->Share ? CLR_CYAN : CLR_GRAY);
        printf("%s", s->Share ? "◧" : "◨");
        printf("%s", CLR_GRAY);
        printf("   ");

        // PS button
        printf("%s", s->PS ? CLR_CYAN : CLR_GRAY);
        printf("%s", s->PS ? "◈" : "◇");
        printf("%s", CLR_GRAY);
        printf("   ");

        // Options button
        printf("%s", s->Options ? CLR_CYAN : CLR_GRAY);
        printf("%s", s->Options ? "◨" : "◧");
        printf("%s", CLR_RESET);
    }
}

// --- Render the information screen ---
static void render_info_screen(shared_data_t *shm, int idx) {
    if (idx < 0 || idx >= MAX_SLOTS || !shm->slots[idx].connected) {
        printf("\033[10;21H" "No controller connected" CLR_RESET);
        printf("\033[12;22H" CLR_GRAY "Press any key" CLR_RESET);
        return;
    }
    controller_t *s = &shm->slots[idx];
    int row = 3;
    int col = 3;

    printf("\033[%d;%dH" CLR_BOLD "Device Information - Slot %d" CLR_RESET, row, col, idx);
    row += 2;

    printf("\033[%d;%dH" CLR_LABEL "HIDRAW:   " CLR_RESET "%s", row, col, s->dev_path);
    row++;
    printf("\033[%d;%dH" CLR_LABEL "Product:  " CLR_RESET "%s", row, col, s->product_name[0] ? s->product_name : "N/A");
    row++;
    printf("\033[%d;%dH" CLR_LABEL "Driver:   " CLR_RESET "%s", row, col, s->driver[0] ? s->driver : "N/A");
    row++;
    printf("\033[%d;%dH" CLR_LABEL "Address:   " CLR_RESET "%s", row, col, s->uniq[0] ? s->uniq : "N/A");
    row++;
    printf("\033[%d;%dH" CLR_LABEL "Connection:" CLR_RESET " %s", row, col, s->is_bluetooth ? "Bluetooth" : "USB");
    row++;
    printf("\033[%d;%dH" CLR_LABEL "Battery:  " CLR_RESET "%d%%", row, col, s->battery);
    row++;
    printf("\033[%d;%dH" CLR_LABEL "evdev nodes:" CLR_RESET, row, col);
    row++;

    if (s->num_input_nodes > 0) {
        for (int i = 0; i < s->num_input_nodes && i < MAX_INPUT_NODES; i++) {
            if (row > 20) { // Leave one line for the return message (line 22)
                break;
            }
            // Display node path
            printf("\033[%d;%dH  %s", row, col, s->input_nodes[i].path);
            row++;
            if (row > 20) break;
            // Display indented node name
            char display_name[64];
            strncpy(display_name, s->input_nodes[i].name, 63);
            display_name[63] = '\0';
            printf(CLR_GRAY "\033[%d;%dH    %s" CLR_RESET, row, col, display_name);
            row++;
        }
    } else {
        printf("\033[%d;%dH  No input nodes found", row, col);
        row++;
    }

    // Bottom line with instruction (line 22)
    printf("\033[22;2H" CLR_GRAY "Press any key to return" CLR_RESET);
}

// --- Render the profile list screen ---
static void render_list_screen(void) {
    int row = 3;
    int col = 3;

    printf("\033[%d;%dH" CLR_BOLD "Available Profiles" CLR_RESET, row, col);
    row += 2;

    char line[256];
    const char *ptr = g_profiles_list;
    while (*ptr && row <= 21) { // space up to line 21 (line 22 is message)
        const char *nl = strchr(ptr, '\n');
        if (nl) {
            size_t len = nl - ptr;
            if (len >= sizeof(line)) len = sizeof(line) - 1;
            strncpy(line, ptr, len);
            line[len] = '\0';
            ptr = nl + 1;
        } else {
            strncpy(line, ptr, sizeof(line) - 1);
            line[sizeof(line) - 1] = '\0';
            ptr += strlen(ptr);
        }
        if (line[0] != '\0') {
            printf("\033[%d;%dH  %s", row, col, line);
            row++;
        }
    }

    printf("\033[22;2H" CLR_GRAY "Press any key to return" CLR_RESET);
}

// --- Public functions for list mode control ---
void display_show_profiles(const char *list) {
    strncpy(g_profiles_list, list, sizeof(g_profiles_list) - 1);
    g_profiles_list[sizeof(g_profiles_list) - 1] = '\0';
    list_mode = true;
}

bool display_is_list_mode(void) {
    return list_mode;
}

void display_set_list_mode(bool mode) {
    list_mode = mode;
}

// --- Interface Components ---

void draw_stick_mockup(int16_t x, int16_t y, const char* label, int row, int col) {
    const int16_t DEADZONE = 3000;
    const int16_t THRESHOLD_50 = 16384;
    int16_t fx = (x > -DEADZONE && x < DEADZONE) ? 0 : x;
    int16_t fy = (y > -DEADZONE && y < DEADZONE) ? 0 : y;
    const char* border_color = (abs(x) > THRESHOLD_50 || abs(y) > THRESHOLD_50) ? CLR_LABEL : CLR_GRAY;

    int gx = ((int32_t)(fx + 32768) * 12) / 65535;
    int gy = ((int32_t)(fy + 32768) * 6) / 65535;

    if (fx == 0) gx = 6;
    if (fy == 0) gy = 3;

    printf("\033[%d;%dH%s%s%s", row, col, CLR_LABEL, label, CLR_RESET);
    printf("\033[%d;%dH%s╭─────────────╮", row + 1, col, border_color);
    for(int i = 0; i < 7; i++) {
        printf("\033[%d;%dH│", row + 2 + i, col);
        for(int j = 0; j < 13; j++) {
            if (i == gy && j == gx) printf(CLR_BOLD CLR_CYAN "⦿" CLR_RESET "%s", border_color);
            else if (i == 3 && j == 6) printf("·");
            else printf(" ");
        }
        printf("│");
    }
    printf("\033[%d;%dH╰─────────────╯" CLR_RESET, row + 9, col);
    printf("\033[%d;%dH%sX:%-6d Y:%-6d%s", row + 10, col + 1, CLR_GRAY, x, y, CLR_RESET);
}

void draw_mockup_bar(int16_t value, int row, int col, const char* label) {
    int max_len = 15;
    int filled = (value * max_len) / 255;

    printf("\033[%d;%dH %s%s%s %s", row, col, CLR_LABEL, label, CLR_RESET, CLR_GRAY);
    for (int i = 0; i < max_len; i++) {
        if (i < filled) printf(CLR_CYAN "▰");
        else printf("▱");
    }
    printf(CLR_RESET);
}

void render_offline_screen(bool is_frozen) {
    int col = 20;

    // Content line 1
    printf(CLR_RED);
    printf("\033[11;%dH            %-38s  ", col, is_frozen ? "SERVICE FROZEN" : "SERVICE STOPPED");

    // Content line 2 (empty)
    printf("\033[12;%dH                                           ", col);

    // Content line 3
    printf("\033[13;%dH   %-38s    ", col, is_frozen ? "The daemon is not responding." : "Type 'start' to run the service");

    // Content line 4
    if (is_frozen) {
        printf("\033[14;%dH  %-38s    ", col, "Try: sudo systemctl restart");
    } else {
        printf("\033[14;%dH                                            ", col);
    }

    // Content line 5 (empty)
    printf("\033[15;%dH                                            ", col);

    // Bottom frame
    printf("\033[16;%dH" CLR_RESET, col);
}

// --- Main rendering function ---
void render_full_ui(shared_data_t *shm, int idx, const char *cmd_line, bool alive, bool info_mode) {
    static int spin = 0;
    const char *braille[] = {"⠋", "⠙", "⠹", "⠸", "⠼", "⠴", "⠦", "⠧"};

    // Initial clear and header (line 1)
    printf(HOME CLR_BOLD CLR_CYAN " ◈ DSTX 0.8.0 " CLR_RESET "│ ");

    pid_t current_pid = atomic_load(&shm->daemon_pid);
    if (alive) {
        printf(CLR_GREEN "● " CLR_RESET CLR_GRAY "(%d)" CLR_RESET, current_pid);
    } else {
        if (current_pid > 0) {
            char proc_path[256];
            snprintf(proc_path, sizeof(proc_path), "/proc/%d", current_pid);
            if (access(proc_path, F_OK) == 0) {
                printf(CLR_YELLOW "● " CLR_RESET);
            } else {
                printf(CLR_RED "●" CLR_RESET);
            }
        } else {
            printf(CLR_RED "●" CLR_RESET);
        }
    }

    printf("                                      ");
    for (int i = 0; i < MAX_SLOTS; i++) {
        printf("%s%s  " CLR_RESET, (i == idx) ? CLR_LABEL : CLR_GRAY, (shm->slots[i].connected && alive) ? "●" : "○");
    }
    printf(CLEAR_LINE "\n");

    // ===== BORDER COLOR SELECTION =====
    const char *border_color = CLR_GRAY; // fallback
    if (!alive) {
        border_color = CLR_RED;
    } else if (idx == -1) {
        border_color = CLR_GREEN;
    } else {
        // For any connected controller, border is purple
        border_color = CLR_PURPLE;
    }

    // Draw main border (lines 2 to 24, columns 1 to 65)
    draw_border(2, 1, 23, 77, border_color);

    // ===== MODE-SPECIFIC CONTENT =====
    if (!alive) {
        render_offline_screen(false);
    }
    else if (list_mode) {
        // Profile list screen
        // Clear inner area
        for (int r = 3; r <= 22; r++) {
            printf("\033[%d;2H%*s", r, 63, "");
        }
        render_list_screen();
    }
    else if (info_mode) {
        render_info_screen(shm, idx);
    }
    else if (idx == -1) {
        // "Waiting for connection" mode - clear area
        for (int row = 3; row <= 22; row++) {
            printf("\033[%d;2H", row);
            for (int col = 2; col <= 64; col++) printf(" ");
        }
        // Centered message
        printf("\033[12;24H" CLR_CYAN "%s " CLR_GRAY " [ WAITING FOR CONNECTION... ]" CLR_RESET, braille[spin]);
        spin = (spin + 1) % 8;
    }
    else {
        // Normal mode with connected controller
        controller_t *s = &shm->slots[idx];

        // ===== STATUS LINE (line 3, column 2) =====
        int col = 2; // track current column (only visible characters)

        // Controller name with minimum padding of 10
        const char* type_str;
        if (s->type == TYPE_DS4) type_str = "DUALSHOCK4";
        else if (s->type == TYPE_DUALSENSE) type_str = "DUALSENSE";
        else type_str = "NINTENDO SWITCH PRO";
        int name_len = strlen(type_str);
        if (name_len < 10) {
            printf("\033[3;2H %-10s", type_str); // initial space + name with padding
            col += 1 + 10; // space + 10 characters
        } else {
            printf("\033[3;2H %s", type_str); // initial space + name
            col += 1 + name_len;
        }
        printf(CLR_RESET);

        // First separator
        printf(" │ ");
        col += 3;

        // Connection type (BT/USB)
        printf(CLR_YELLOW "%s" CLR_RESET, s->is_bluetooth ? "BT" : "USB");
        col += s->is_bluetooth ? 2 : 3;

        // LED: only if NOT Nintendo Switch Pro
        if (s->type != TYPE_NSW_PRO) {
            printf(" │ LED: ");
            col += 8;
            printf("\033[48;2;%d;%d;%dm    " CLR_RESET, s->led_r, s->led_g, s->led_b);
            col += 4; // four colored spaces
        }

        // Emulation
        printf(" │ Emulation: ");
        col += 8;
        if (s->emulate_active) {
            printf(CLR_GREEN "ON" CLR_RESET);
            printf(" ");
            col += 3; // "ON " = 3
        } else {
            printf(CLR_GRAY "OFF" CLR_RESET);
            col += 3;
        }

        // Battery
        printf("│ Bat: ");
        col += 7;
        printf("%3d%%", s->battery);
        col += 4; // always 4 characters (e.g., "100%")
        printf(CLR_RESET);

        // Fill with spaces up to column 64
        int spaces = 64 - col;
        if (spaces > 0) {
            printf("%*s", spaces, "");
        }

        // Device path (line 4, column 2) - truncated to fit
        char truncated[63];
        snprintf(truncated, sizeof(truncated), "%s", s->dev_path);
        int path_len = strlen(truncated);
        printf("\033[4;2H" CLR_GRAY " %s" CLR_RESET, truncated);
        // Fill up to column 64
        printf("%*s", 64 - (2 + path_len), "");

        // ===== ANALOG STICKS =====
        draw_stick_mockup(s->LX, s->LY, "   LS ANALOG", 7, 7);
        draw_stick_mockup(s->RX, s->RY, "   RS ANALOG", 7, 27);

        // ===== BUTTONS AND TRIGGERS =====
        int c2 = 50;  // Fixed column

        // Line 6: L1 and R1
        printf("\033[7;%dH %sL1%s   %s%s%s     %sR1%s   %s%s%s",
            c2,
            CLR_LABEL, CLR_RESET,
            CLR_GRAY, s->L1 ? CLR_CYAN "▰▰" : "▱▱", CLR_RESET,
            CLR_LABEL, CLR_RESET,
            CLR_GRAY, s->R1 ? CLR_CYAN "▰▰" : "▱▱", CLR_RESET);

        // Line 7: L3 and R3
        printf("\033[8;%dH %sL3%s   %s%s%s     %sR3%s   %s%s%s",
            c2,
            CLR_LABEL, CLR_RESET,
            CLR_GRAY, s->L3 ? CLR_CYAN "▰▰" : "▱▱", CLR_RESET,
            CLR_LABEL, CLR_RESET,
            CLR_GRAY, s->R3 ? CLR_CYAN "▰▰" : "▱▱", CLR_RESET);

        // Line 9: L2 (bar)
        draw_mockup_bar(s->LT, 10, c2, "L2  ");

        // Line 10: R2 (bar)
        draw_mockup_bar(s->RT, 11, c2, "R2  ");

        // Line 12: D-PAD
        printf("\033[13;%dH %sPAD:%s ", c2, CLR_LABEL, CLR_RESET);
        printf("%s", CLR_GRAY);
        printf(" ");
        printf("%s", (s->HATX < 0) ? CLR_CYAN : CLR_GRAY);
        printf("%s", (s->HATX < 0) ? "◀" : "◁");
        printf("%s", CLR_GRAY);
        printf("   ");
        printf("%s", (s->HATY < 0) ? CLR_CYAN : CLR_GRAY);
        printf("%s", (s->HATY < 0) ? "▲" : "△");
        printf("%s", CLR_GRAY);
        printf("   ");
        printf("%s", (s->HATY > 0) ? CLR_CYAN : CLR_GRAY);
        printf("%s", (s->HATY > 0) ? "▼" : "▽");
        printf("%s", CLR_GRAY);
        printf("   ");
        printf("%s", (s->HATX > 0) ? CLR_CYAN : CLR_GRAY);
        printf("%s", (s->HATX > 0) ? "▶" : "▷");
        printf("%s", CLR_RESET);

        // Line 14: Face buttons
        render_face_buttons(s, 15, c2);

        // Line 16: System buttons
        render_system_buttons(s, 17, c2);

        // ===== STATUS FIELDS (lines 18, 19 and 20) =====
        {
            int row = 20;
            int col_status = 7;
            // Line 20
            printf("\033[%d;%dH", row, col_status);
            // UHID
            printf("%s[%s] UHID%s       ", CLR_LABEL, s->is_uhid ? "X" : " ", CLR_RESET);
            col_status += 10;
            printf(" │ ");
            col_status += 3;
            // Rumble
            printf("%s[%s] Rumble%s  ", CLR_LABEL, s->rumble_active ? "X" : " ", CLR_RESET);
            col_status += 12;
            printf(" │ ");
            col_status += 3;
            // L Inverted
            printf("%s[%s] L-Inversion%s ", CLR_LABEL, s->invert_ly ? "X" : " ", CLR_RESET);
            col_status += 12;
            printf(" │ ");
            col_status += 3;
            // L Sensitivity
            printf("%sL-Sens: %d%s", CLR_LABEL, s->sensitivity_left_preset, CLR_RESET);

            // Line 21
            row = 21;
            col_status = 7;
            printf("\033[%d;%dH", row, col_status);
            // Digital L/R
            printf("%s[%s] Digital L/R%s", CLR_LABEL, s->is_trigger_digital ? "X" : " ", CLR_RESET);
            col_status += 14;
            printf(" │ ");
            col_status += 3;
            // Gain
            printf("%sGain: %3d%%%s  ", CLR_LABEL, s->rumble_gain, CLR_RESET);
            col_status += 12;
            printf(" │ ");
            col_status += 3;
            // R Inverted
            printf("%s[%s] R-Inversion%s ", CLR_LABEL, s->invert_ry ? "X" : " ", CLR_RESET);
            col_status += 12;
            printf(" │ ");
            col_status += 3;
            // R Sensitivity
            printf("%sR-Sens: %d%s", CLR_LABEL, s->sensitivity_right_preset, CLR_RESET);

            // Line 22
            row = 22;
            col_status = 7;
            printf("\033[%d;%dH", row, col_status);
            // Deadzone
            printf("%sDeadzone: %3d%%%s ", CLR_LABEL, s->deadzone, CLR_RESET);
            col_status += 16;
            printf(" │ ");
            col_status += 3;

            // Conditional fields: only for DS4/DualSense (not NSW Pro)
            if (s->type != TYPE_NSW_PRO) {
                // Debounce
                printf("%s[%s] Debounce%s", CLR_LABEL, s->debounce_enabled ? "X" : " ", CLR_RESET);
                col_status += 14;
                printf(" │ ");
                col_status += 3;
                // Brightness
                printf("%sBrightness: %3d%%%s", CLR_LABEL, s->global_led_brightness, CLR_RESET);
                col_status += 14;
                printf(" │ ");
                col_status += 3;
                // Led Effect
                int effect = s->led_request_effect;
                printf("%sEffect: %d%s", CLR_LABEL, effect, CLR_RESET);
            } else {
                // For NSW Pro, fill with spaces to maintain layout
                printf("%*s", 12, "");
                printf(" │ ");
                printf("%*s", 16, "");
                printf(" │ ");
            }
        }
    }

    // ===== COMMAND LINE (line 25) =====
    printf("\033[25;1H" CLR_BOLD " command " CLR_CYAN "❯ " CLR_RESET "%s" CLEAR_LINE, cmd_line);
    fflush(stdout);
}

// ============================================================================
// Help screen rendering (called from ui.c when help_mode is active)
// ============================================================================

void render_help_screen(int page) {
    // Clear screen and draw a border
    printf(HOME CLEAR_SCREEN);
    draw_border(2, 1, 23, 77, CLR_CYAN);

    int row = 3;
    int col = 3;
    const char *content = help_pages[page];
    char line[256];
    const char *ptr = content;

    while (*ptr && row <= 22) {
        const char *nl = strchr(ptr, '\n');
        if (nl) {
            size_t len = nl - ptr;
            if (len >= sizeof(line)) len = sizeof(line) - 1;
            strncpy(line, ptr, len);
            line[len] = '\0';
            ptr = nl + 1;
        } else {
            strncpy(line, ptr, sizeof(line) - 1);
            line[sizeof(line) - 1] = '\0';
            ptr += strlen(ptr);
        }

        // Apply color styling
        if (strstr(line, "DSTX TUI HELP") != NULL) {
            printf(CLR_BOLD CLR_CYAN "\033[%d;%dH%s" CLR_RESET, row, col, line);
        } else if (strstr(line, "Press LEFT/RIGHT") != NULL) {
            printf(CLR_YELLOW "\033[%d;%dH%s" CLR_RESET, row, col, line);
        } else if ((line[0] == ' ' || line[0] == '\t') &&
                   (strstr(line, "::") != NULL)) {
            printf(CLR_LABEL "\033[%d;%dH%s" CLR_RESET, row, col, line);
        } else {
            printf("\033[%d;%dH%s", row, col, line);
        }
        row++;
    }

    // Page indicator at bottom
    printf(CLR_GRAY "\033[23;30HPage %d/%d" CLR_RESET, page + 1, TOTAL_HELP_PAGES);

    // Keep the command line area clean
    printf("\033[25;1H%*s", 70, "");
    fflush(stdout);
}

void display_set_help_mode(bool enabled) {
    help_mode = enabled;
}

bool display_is_help_mode(void) {
    return help_mode;
}
