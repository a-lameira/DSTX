/*
 * system-service-manager.vala - System service installation and management for DSTX GUI
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
 * - Check if system components (dstx daemon) are installed in Flatpak environment
 * - Install/uninstall system components using pkexec and bundled scripts
 * - Copy binaries and scripts to persistent user data directory
 * - Version comparison and update management
 */

// src/core/system-service-manager.vala

using GLib;
using Posix;

namespace Dstx.Core {
    public class SystemServiceManager : Object {
        private static string get_app_data_dir() {
            string home = Environment.get_home_dir();
            return @"$home/.var/app/org.dstx.gui";
        }

        public static async bool are_system_components_installed() {
            if (!Core.is_flatpak()) return true;
            try {
                string output;
                int status;
                Process.spawn_command_line_sync(
                    "flatpak-spawn --host test -f /usr/local/bin/dstx",
                    out output, null, out status
                );
                bool installed = (status == 0);
                warning("are_system_components_installed: %s", installed ? "yes" : "no");
                return installed;
            } catch (Error e) {
                warning("Error checking system components: %s", e.message);
                return false;
            }
        }

        private static async bool copy_file_to_persistent_dir(string sandbox_path, string persistent_path) {
            try {
                string dest_dir = Path.get_dirname(persistent_path);
                if (!FileUtils.test(dest_dir, FileTest.IS_DIR)) {
                    DirUtils.create_with_parents(dest_dir, 0755);
                }

                string cp_cmd = @"cp -f \"$sandbox_path\" \"$persistent_path\"";
                int status;
                Process.spawn_command_line_sync(cp_cmd, null, null, out status);
                if (status != 0) {
                    warning("Failed to copy %s to %s", sandbox_path, persistent_path);
                    return false;
                }

                Posix.chmod(persistent_path, 0755);
                warning("Copied %s -> %s", sandbox_path, persistent_path);
                return true;
            } catch (Error e) {
                warning("Failed to copy %s to %s: %s", sandbox_path, persistent_path, e.message);
                return false;
            }
        }

        private static async bool copy_scripts_to_persistent_dir() {
            string data_dir = get_app_data_dir();
            bool ok = true;
            ok &= yield copy_file_to_persistent_dir("/app/bin/install-system-components.sh",
                                                     @"$data_dir/install-dstx.sh");
            ok &= yield copy_file_to_persistent_dir("/app/bin/uninstall-system-components.sh",
                                                     @"$data_dir/uninstall-dstx.sh");
            return ok;
        }

        public static async bool install_system_components() {
            if (!Core.is_flatpak()) {
                warning("install_system_components: not flatpak, skipping");
                return false;
            }
            try {
                string data_dir = get_app_data_dir();
                string bin_dir = @"$data_dir/bin";
                warning("Data dir: %s", data_dir);
                warning("Bin dir: %s", bin_dir);

                if (!FileUtils.test(bin_dir, FileTest.IS_DIR)) {
                    DirUtils.create_with_parents(bin_dir, 0755);
                }

                if (!FileUtils.test("/app/bin/dstx", FileTest.EXISTS)) {
                    warning("Binary /app/bin/dstx not found inside sandbox");
                    return false;
                }
                warning("Found /app/bin/dstx inside sandbox");

                warning("Copying scripts...");
                bool ok = yield copy_scripts_to_persistent_dir();
                if (!ok) {
                    warning("Failed to copy scripts");
                    return false;
                }
                
                warning("Copying binaries...");
                ok &= yield copy_file_to_persistent_dir("/app/bin/dstx",
                                                         @"$bin_dir/dstx");
                
                if (!ok) {
                    warning("Failed to copy dstx binary");
                    return false;
                }
                
                if (FileUtils.test("/app/bin/dstx-dbus", FileTest.EXISTS)) {
                    yield copy_file_to_persistent_dir("/app/bin/dstx-dbus",
                                                        @"$bin_dir/dstx-dbus");
                } else {
                    warning("dstx-dbus not found in sandbox, continuing without bridge");
                }

                string script_path = @"$data_dir/install-dstx.sh";
                string cmd = @"flatpak-spawn --host pkexec bash $script_path $bin_dir";
                warning("Executing: %s", cmd);
                int status;
                Process.spawn_command_line_sync(cmd, null, null, out status);
                warning("Installation script exited with status %d", status);
                return status == 0;
            } catch (Error e) {
                warning("Installation error: %s", e.message);
                return false;
            }
        }

        public static async bool uninstall_system_components() {
            if (!Core.is_flatpak()) return false;
            try {
                string data_dir = get_app_data_dir();
                string script_path = @"$data_dir/uninstall-dstx.sh";
                if (!FileUtils.test(script_path, FileTest.EXISTS)) {
                    warning("Uninstall script not found, attempting to copy scripts...");
                    bool copied = yield copy_scripts_to_persistent_dir();
                    if (!copied || !FileUtils.test(script_path, FileTest.EXISTS)) {
                        warning("Uninstall script still missing, aborting uninstall");
                        return false;
                    }
                }
                string cmd = @"flatpak-spawn --host pkexec bash $script_path";
                warning("Uninstall command: %s", cmd);
                int status;
                Process.spawn_command_line_sync(cmd, null, null, out status);
                warning("Uninstall script exited with status %d", status);
                return status == 0;
            } catch (Error e) {
                warning("Uninstallation error: %s", e.message);
                return false;
            }
        }

        // ==================== VERSIONING ====================

        public static string get_expected_version() {
            return "0.7.0";  // Must be synchronized with the D-Bus bridge version
        }

        public static int compare_versions(string a, string b) {
            string[] parts_a = a.split(".");
            string[] parts_b = b.split(".");
            int max_len = int.max(parts_a.length, parts_b.length);
            
            for (int i = 0; i < max_len; i++) {
                int va = (i < parts_a.length) ? int.parse(parts_a[i]) : 0;
                int vb = (i < parts_b.length) ? int.parse(parts_b[i]) : 0;
                if (va != vb) return (va < vb) ? -1 : 1;
            }
            return 0;
        }

        public static bool is_outdated(string current_version) {
            return compare_versions(current_version, get_expected_version()) < 0;
        }

        public static async bool update_system_components() {
            // Ensure scripts are available before any operation
            bool scripts_ok = yield copy_scripts_to_persistent_dir();
            if (!scripts_ok) {
                warning("Failed to copy scripts needed for update");
                return false;
            }

            bool uninstalled = yield uninstall_system_components();
            if (!uninstalled) return false;
            
            bool installed = yield install_system_components();
            if (!installed) return false;
            
            return true;
        }
    }
}
