/*
 * led.h - LED effect system for DSTX
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

#ifndef LED_H
#define LED_H

#include "dstx.h"
#include <pthread.h>
#include <time.h>

// ========================================================================
// TIMING CONSTANTS
// ========================================================================
#define LEDFX_UPDATE_INTERVAL_US 16000  // 16ms = ~60Hz (used in daemon)

// ========================================================================
// LED EFFECT TYPES (kept for UI compatibility)
// ========================================================================
typedef enum {
    LEDFX_STATIC = 0,
    LEDFX_BREATH,
    LEDFX_RAINBOW,
    LEDFX_PULSE,
    LEDFX_STROBE,
    LEDFX_WAVE,
    LEDFX_BATTERY,
    LEDFX_TRIGGER,
    LEDFX_BUTTON_PRESS,
    LEDFX_COUNT
} led_effect_t;

// ========================================================================
// PUBLIC FUNCTIONS (SINGLE INTERFACE FOR THE DAEMON)
// ========================================================================

/**
 * ledfx_init - Initializes the effect system
 * Called once at daemon startup
 */
void ledfx_init(void);

/**
 * ledfx_cleanup - Cleans up effect system resources
 * Called at daemon shutdown
 */
void ledfx_cleanup(void);

/**
 * ledfx_process_requests - Processes pending UI requests
 * Reads SHM and updates internal effect state
 * Should be called periodically (before update)
 */
void ledfx_process_requests(void);

/**
 * ledfx_update_slot - Updates the effect for a specific slot
 * @param slot_idx: Slot index
 * @param current_time: Current time in seconds (monotonic)
 *
 * Calculates the new color based on the current effect and writes to SHM
 * Returns: true if the color was changed
 */
bool ledfx_update_slot(int slot_idx, double current_time);

/**
 * ledfx_get_effect_name - Returns effect name for UI display
 * @param effect: Effect type
 */
const char* ledfx_get_effect_name(led_effect_t effect);

#endif // LED_H
