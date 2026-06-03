/*
 * display.h - Terminal display interface for DSTX
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

#ifndef DISPLAY_H
#define DISPLAY_H

#include "dstx.h"
#include <stdbool.h>
#include <sys/time.h>

// --- Color and Terminal Definitions ---
#define CLR_RESET      "\033[0m"
#define CLR_GREEN      "\033[1;32m"
#define CLR_RED        "\033[1;31m"
#define CLR_WHITE      "\033[1;37m"
#define CLR_YELLOW     "\033[1;33m"
#define CLR_CYAN       "\033[1;36m"
#define CLR_BLUE       "\033[1;34m"
#define CLR_PURPLE     "\033[1;35m"
#define CLR_GRAY       "\033[90m"
#define CLR_BOLD       "\033[1m"
#define CLR_LABEL      "\033[38;2;170;150;255m"
#define HOME           "\033[H"
#define CLEAR_SCREEN   "\033[2J"
#define CLEAR_LINE     "\033[K"
#define HIDE_CURSOR    "\033[?25l"
#define SHOW_CURSOR    "\033[?25h"

#define ALT_BUFFER_ON  "\033[?1049h"
#define ALT_BUFFER_OFF "\033[?1049l"

#define MIN_COLS 77
#define MIN_ROWS 25
#define TOTAL_HELP_PAGES 4

// Shared global variable (defined in display.c)
extern char selected_dev_path[128];

// Display function prototypes
void force_terminal_size(int r, int c);
void get_binary_path(char *out_dir, size_t size);
bool check_window_sanity(void);
int update_and_get_slot_idx(shared_data_t *shm);
void render_full_ui(shared_data_t *shm, int idx, const char *cmd_line, bool alive, bool info_mode);

// Profile list mode
void display_show_profiles(const char *list);
bool display_is_list_mode(void);
void display_set_list_mode(bool mode);

// Help system
void render_help_screen(int page);
void display_set_help_mode(bool enabled);
bool display_is_help_mode(void);

#endif // DISPLAY_H
