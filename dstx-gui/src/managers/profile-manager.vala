/*
 * profile-manager.vala - Profile management operations via D-Bus
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
 * - Provide async methods for profile operations via D-Bus
 * - List, load, save, delete profiles
 * - Configure automatic saving
 */

// src/managers/profile-manager.vala

using Dstx.Core;

namespace Dstx.Managers {
    /**
     * ProfileManager - Manages profile operations via D-Bus
     * 
     * Provides async methods to list, load, save, delete profiles
     * and configure auto-saving.
     */
    public class ProfileManager : Object {
        private DBusClient dbus;
        
        /**
         * Constructor
         * @param dbus Connected D-Bus client
         */
        public ProfileManager(DBusClient dbus) {
            this.dbus = dbus;
        }
        
        /**
         * Gets the list of available profile names
         * @return Array of profile names
         * @throws Error If D-Bus communication fails
         */
        public async string[] get_profile_list() throws Error {
            string raw = yield dbus.list_profiles();
            string[] lines = raw.split("\n");
            var list = new Gee.ArrayList<string>();
            foreach (string line in lines) {
                string trimmed = line.strip();
                if (trimmed != "") {
                    list.add(trimmed);
                }
            }
            return list.to_array();
        }
        
        /**
         * Loads a profile by name
         * @param name Profile name
         * @throws Error If profile does not exist or communication fails
         */
        public async void load_profile(string name) throws Error {
            yield dbus.load_profile(name);
        }
        
        /**
         * Saves the current configuration to a profile
         * @param name Profile name (creates or overwrites)
         * @throws Error If communication fails
         */
        public async void save_profile(string name) throws Error {
            yield dbus.save_profile(name);
        }
        
        /**
         * Deletes an existing profile
         * @param name Profile name
         * @throws Error If profile does not exist or communication fails
         */
        public async void delete_profile(string name) throws Error {
            yield dbus.delete_profile(name);
        }
        
        /**
         * Configures automatic saving
         * @param enable Enable/disable
         * @param delay_ms Debounce delay in ms (100-10000)
         * @return Status message returned by the daemon
         * @throws Error If communication fails
         */
        public async string set_auto_save(bool enable, int delay_ms) throws Error {
            return yield dbus.set_auto_save(enable, delay_ms);
        }
    }
}
