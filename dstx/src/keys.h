/*
 * keys.h - Keybind system (button remapping) for DSTX
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
 * Provides functions to map physical buttons to logical ones,
 * allowing complete controller remapping.
 *
 * Layout functions (set_xbox_layout, set_switch_layout, reset_all_keybinds)
 * are used exclusively by the daemon to process client interface requests.
 */

#ifndef KEYS_H
#define KEYS_H

#include "dstx.h"

/**
 * keys_get_default_map - Fills a keymap array with identity mapping
 * @param type: Controller type (currently unused, reserved for future variations)
 * @param map_out: Array of size PHY_BTN_COUNT that will receive the mappings
 *
 * Identity mapping means physical button X produces logical button X.
 * Example: PHY_BTN_CROSS → LOGICAL_BTN_CROSS, PHY_BTN_DPAD_UP → LOGICAL_BTN_DPAD_UP.
 * The array is filled with values of type logical_button_t (uint8_t).
 */
void keys_get_default_map(controller_type_t type, uint8_t *map_out);

/**
 * keys_apply_map - Applies a keymap to the logical button fields of controller_t
 * @param slot: Pointer to controller_t that will receive the logical buttons
 * @param keymap: Mapping array (PHY_BTN_COUNT entries) defining the correspondence
 * @param raw_buttons_phy_state: Array of size PHY_BTN_COUNT, each element 0 or 1,
 *        representing the raw state of each physical button (no debounce, no mapping)
 *
 * This function zeros all logical button fields (cross, circle, square, triangle, L1, etc.)
 * and, for each pressed physical button, activates the corresponding logical button
 * according to the keymap. After processing, it recalculates HATX and HATY from dpad_*.
 */
void keys_apply_map(controller_t *slot, const uint8_t *keymap,
                    const uint8_t *raw_buttons_phy_state);

/**
 * keys_set_xbox_layout - Sets Xbox layout (identity) for face buttons
 * @param slot: Pointer to controller_t
 *
 * Absolutely sets the mappings:
 *   CROSS   → CROSS
 *   CIRCLE  → CIRCLE
 *   SQUARE  → SQUARE
 *   TRIANGLE → TRIANGLE
 *
 * Preserves all other mappings (L1, R1, etc.).
 * Idempotent – applying multiple times causes no side effects.
 */
void keys_set_xbox_layout(controller_t *slot);

/**
 * keys_set_switch_layout - Sets Switch layout (swapped A/B and X/Y) for face buttons
 * @param slot: Pointer to controller_t
 *
 * Absolutely sets the mappings:
 *   CROSS   → CIRCLE
 *   CIRCLE  → CROSS
 *   SQUARE  → TRIANGLE
 *   TRIANGLE → SQUARE
 *
 * Preserves all other mappings (L1, R1, etc.).
 * Idempotent – applying multiple times causes no side effects.
 */
void keys_set_switch_layout(controller_t *slot);

/**
 * keys_reset_all_keybinds - Restores identity mapping for ALL buttons
 * @param slot: Pointer to controller_t
 *
 * Completely resets the slot's keymap to identity mapping,
 * discarding any custom keybinds or applied layouts.
 * Used by the reset-keybinds command (via request_reset_all_keybinds).
 */
void keys_reset_all_keybinds(controller_t *slot);

#endif // KEYS_H
