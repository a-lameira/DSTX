/*
 * dbus-systemd.h - Systemd D-Bus communication interface
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

#ifndef DBUS_SYSTEMD_H
#define DBUS_SYSTEMD_H

#include <dbus/dbus.h>
#include <stdbool.h>

#define DSTX_UNIT "dstx-daemon.service"

int systemd_start_unit(DBusConnection *conn, const char *unit, const char *mode);
int systemd_stop_unit(DBusConnection *conn, const char *unit, const char *mode);
int systemd_restart_unit(DBusConnection *conn, const char *unit, const char *mode);
bool systemd_unit_is_active(DBusConnection *conn, const char *unit);
bool systemd_unit_is_enabled(DBusConnection *conn, const char *unit);
int systemd_enable_unit(DBusConnection *conn, const char *unit, bool enable);

#endif
