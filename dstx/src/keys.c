/*
 * keys.c - Keybind system implementation for DSTX
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
 * - Associates a controller's physical button to any logical button
 * - Validates keymap indices read from SHM.
 */

#include "keys.h"
#include <syslog.h>

void keys_get_default_map(controller_type_t type, uint8_t *map_out) {
    (void)type; // Reserved for future variations (e.g., controller-specific mappings)
    
    // Identity mapping: each physical button produces the logical button of same index
    // The enums physical_button_t and logical_button_t are aligned in order:
    // CROSS, CIRCLE, SQUARE, TRIANGLE, L1, R1, L2, R2, SHARE, OPTIONS,
    // L3, R3, PS, TOUCH, DPAD_UP, DPAD_DOWN, DPAD_LEFT, DPAD_RIGHT
    // LOGICAL_BTN_NONE = 0, so the first logical button (CROSS) is 1.
    for (int i = 0; i < PHY_BTN_COUNT; i++) {
        map_out[i] = i + 1;  // i+1 → corresponding logical_button_t
    }
}

void keys_apply_map(controller_t *slot, const uint8_t *keymap,
                    const uint8_t *raw_buttons_phy_state) {
    if (!slot || !keymap || !raw_buttons_phy_state) return;
    
    // 1. Zero all logical buttons
    slot->cross = 0;
    slot->circle = 0;
    slot->square = 0;
    slot->triangle = 0;
    slot->L1 = 0;
    slot->R1 = 0;
    slot->L2 = 0;
    slot->R2 = 0;
    slot->Share = 0;
    slot->Options = 0;
    slot->L3 = 0;
    slot->R3 = 0;
    slot->PS = 0;
    slot->touch_btn = 0;
    slot->dpad_up = 0;
    slot->dpad_down = 0;
    slot->dpad_left = 0;
    slot->dpad_right = 0;
    
    // 2. Apply mapping for each pressed physical button
    for (int phy = 0; phy < PHY_BTN_COUNT; phy++) {
        if (!raw_buttons_phy_state[phy]) continue;
        
        uint8_t logical = keymap[phy];
        
        // Ignore mapping to NONE (0)
        if (logical == LOGICAL_BTN_NONE) continue;
        
        // Safety validation: ensure logical value is within known range
        if (logical >= LOGICAL_BTN_COUNT) {
            syslog(LOG_WARNING, "keys: invalid logical value %d in keymap[%d], ignoring",
                   logical, phy);
            continue;
        }
        
        switch (logical) {
            case LOGICAL_BTN_CROSS:
                slot->cross = 1;
                break;
            case LOGICAL_BTN_CIRCLE:
                slot->circle = 1;
                break;
            case LOGICAL_BTN_SQUARE:
                slot->square = 1;
                break;
            case LOGICAL_BTN_TRIANGLE:
                slot->triangle = 1;
                break;
            case LOGICAL_BTN_L1:
                slot->L1 = 1;
                break;
            case LOGICAL_BTN_R1:
                slot->R1 = 1;
                break;
            case LOGICAL_BTN_L2:
                slot->L2 = 1;
                break;
            case LOGICAL_BTN_R2:
                slot->R2 = 1;
                break;
            case LOGICAL_BTN_SHARE:
                slot->Share = 1;
                break;
            case LOGICAL_BTN_OPTIONS:
                slot->Options = 1;
                break;
            case LOGICAL_BTN_L3:
                slot->L3 = 1;
                break;
            case LOGICAL_BTN_R3:
                slot->R3 = 1;
                break;
            case LOGICAL_BTN_PS:
                slot->PS = 1;
                break;
            case LOGICAL_BTN_TOUCH:
                slot->touch_btn = 1;
                break;
            case LOGICAL_BTN_DPAD_UP:
                slot->dpad_up = 1;
                break;
            case LOGICAL_BTN_DPAD_DOWN:
                slot->dpad_down = 1;
                break;
            case LOGICAL_BTN_DPAD_LEFT:
                slot->dpad_left = 1;
                break;
            case LOGICAL_BTN_DPAD_RIGHT:
                slot->dpad_right = 1;
                break;
            default:
                // Should never reach here due to validation above, but kept for safety
                syslog(LOG_WARNING, "keys: unhandled logical value %d (phy=%d)", logical, phy);
                break;
        }
    }
    
    // 3. Recalculate HATX and HATY from dpad_* fields
    slot->HATX = (slot->dpad_right ? 1 : (slot->dpad_left ? -1 : 0));
    slot->HATY = (slot->dpad_up ? -1 : (slot->dpad_down ? 1 : 0));
}

// ========================================================================
// LAYOUT FUNCTIONS (ABSOLUTE DEFINITION, NOT DEPENDENT ON PREVIOUS STATE)
// ========================================================================

void keys_set_xbox_layout(controller_t *slot) {
    if (!slot) return;
    uint8_t *map = slot->keymap;
    // Absolutely set Xbox layout (identity)
    map[PHY_BTN_CROSS]   = LOGICAL_BTN_CROSS;
    map[PHY_BTN_CIRCLE]  = LOGICAL_BTN_CIRCLE;
    map[PHY_BTN_SQUARE]  = LOGICAL_BTN_SQUARE;
    map[PHY_BTN_TRIANGLE] = LOGICAL_BTN_TRIANGLE;
    // Other buttons remain unchanged
}

void keys_set_switch_layout(controller_t *slot) {
    if (!slot) return;
    uint8_t *map = slot->keymap;
    // Absolutely set Switch layout (A↔B, X↔Y)
    map[PHY_BTN_CROSS]   = LOGICAL_BTN_CIRCLE;
    map[PHY_BTN_CIRCLE]  = LOGICAL_BTN_CROSS;
    map[PHY_BTN_SQUARE]  = LOGICAL_BTN_TRIANGLE;
    map[PHY_BTN_TRIANGLE] = LOGICAL_BTN_SQUARE;
    // Other buttons remain unchanged
}

void keys_reset_all_keybinds(controller_t *slot) {
    if (!slot) return;
    // Restore entire keymap to identity
    keys_get_default_map(slot->type, slot->keymap);
}
