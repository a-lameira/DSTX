/*
 * settings.h - Profile and persistent configuration management (singleton thread)
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

#ifndef SETTINGS_H
#define SETTINGS_H

#include "dstx.h"

/**
 * settings_init - Initializes the singleton configuration thread.
 * @param shm: Pointer to already mapped shared memory.
 *
 * Creates a dedicated thread that manages all profile aspects:
 * - Reading/writing JSON files (disk I/O)
 * - Synchronization between SHM and the active profile
 * - Processing UI/D-Bus requests (load/save/delete/list/auto-save)
 * - Automatic saving with debounce
 * - inotify monitoring for external profile file edits
 *
 * The thread is completely asynchronous and does not block the main daemon loop.
 */
void settings_init(shared_data_t *shm);

/**
 * settings_shutdown - Terminates the configuration thread.
 *
 * Waits for thread completion, saves the active profile if needed,
 * releases resources and closes file descriptors. Must be called before
 * unmapping shared memory and shutting down the daemon.
 */
void settings_shutdown(void);

#endif // SETTINGS_H
