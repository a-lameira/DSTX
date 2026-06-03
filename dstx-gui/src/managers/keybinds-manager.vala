/*
 * keybinds-manager.vala - Manages button mappings (keybinds) and button layouts
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
 * - Manage button keybinds (physical to logical mapping)
 * - Apply Switch layout (swap A/B and X/Y)
 * - Apply Xbox layout (restore A/B/X/Y identity)
 */

// src/managers/keybinds-manager.vala

using Dstx.Core;

namespace Dstx.Managers {
    /**
     * KeybindsManager - Manages button mappings (keybinds)
     * and button layouts (Switch/Xbox).
     */
    public class KeybindsManager : Object {
        private DBusClient dbus;
        
        public KeybindsManager(DBusClient dbus) {
            this.dbus = dbus;
        }
        
        /**
         * Gets the current keymap for a slot.
         * @param slot Slot number (0-3)
         * @return Array of uint8 with PHY_BTN_COUNT elements (0=LOGICAL_BTN_NONE, 1..18)
         */
        public async uint8[] get_keymap(uint8 slot) throws Error {
            return yield dbus.get_keymap(slot);
        }
        
        /**
         * Sets an individual keybind.
         * @param slot Slot number
         * @param physical Physical button index (0..PHY_BTN_COUNT-1)
         * @param logical Logical button index (0..LOGICAL_BTN_COUNT-1, 0 = NONE)
         */
        public async void set_keybind(uint8 slot, uint8 physical, uint8 logical) throws Error {
            yield dbus.set_keybind(slot, physical, logical);
        }
        
        /**
         * Restores the keymap to identity mapping (physical -> corresponding logical).
         * @param slot Slot number
         */
        public async void reset_keybinds(uint8 slot) throws Error {
            yield dbus.reset_keybinds(slot);
        }
        
        // ==================== LAYOUT METHODS ====================
        
        /**
         * Applies Nintendo Switch layout (swaps A/B and X/Y buttons).
         * @param slot Slot number (0-3)
         */
        public async void apply_switch_layout(uint8 slot) throws Error {
            yield dbus.apply_switch_layout(slot);
        }
        
        /**
         * Applies Xbox layout (restores A/B/X/Y identity).
         * @param slot Slot number (0-3)
         */
        public async void apply_xbox_layout(uint8 slot) throws Error {
            yield dbus.apply_xbox_layout(slot);
        }
    }
}
