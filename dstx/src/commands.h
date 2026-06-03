/*
 * commands.h - Command line interface for DSTX
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

#ifndef COMMANDS_H
#define COMMANDS_H

#include <stdbool.h>

/*
 * process_cli_command - Process command line arguments in CLI mode.
 * @param argc: Number of arguments (from main)
 * @param argv: Argument vector
 * @return 0 on success, 1 on error (message printed automatically)
 *
 * This function is called when the program is invoked with arguments that are
 * not --daemon (handled separately) and not TUI mode (zero arguments).
 * It connects to shared memory, executes the command, and prints output.
 */
int process_cli_command(int argc, char **argv);

#endif // COMMANDS_H
