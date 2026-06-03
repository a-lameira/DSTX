/*
 * flatpak-utils.vala - Flatpak detection utilities for DSTX GUI
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
 * - Detect if the application is running inside a Flatpak sandbox
 */

// src/core/flatpak-utils.vala

namespace Dstx.Core {
    public static bool is_flatpak() {
        return FileUtils.test("/.flatpak-info", FileTest.EXISTS);
    }
}
