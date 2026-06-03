/*
 * dbus-signals.c - D-Bus signal emission
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

#include "dbus-common.h"
#include <dbus/dbus.h>

void emit_controller_signal(DBusConnection *conn, const char *signal_name, unsigned char slot) {
    if (!conn) return;
    
    DBusMessage *msg = dbus_message_new_signal(BRIDGE_PATH, BRIDGE_INTERFACE, signal_name);
    if (!msg) {
        atomic_fetch_add(&g_errors_occurred, 1);
        return;
    }
    
    if (dbus_message_append_args(msg, DBUS_TYPE_BYTE, &slot, DBUS_TYPE_INVALID)) {
        if (dbus_connection_send(conn, msg, NULL)) {
            atomic_fetch_add(&g_signals_sent, 1);
        } else {
            atomic_fetch_add(&g_errors_occurred, 1);
        }
    } else {
        atomic_fetch_add(&g_errors_occurred, 1);
    }
    dbus_message_unref(msg);
}

void emit_daemon_status_signal(DBusConnection *conn, bool alive) {
    if (!conn) return;
    
    DBusMessage *msg = dbus_message_new_signal(BRIDGE_PATH, BRIDGE_INTERFACE, "DaemonStatusChanged");
    if (!msg) {
        atomic_fetch_add(&g_errors_occurred, 1);
        return;
    }
    
    dbus_bool_t dbus_alive = alive;
    if (dbus_message_append_args(msg, DBUS_TYPE_BOOLEAN, &dbus_alive, DBUS_TYPE_INVALID)) {
        if (dbus_connection_send(conn, msg, NULL)) {
            atomic_fetch_add(&g_signals_sent, 1);
        } else {
            atomic_fetch_add(&g_errors_occurred, 1);
        }
    } else {
        atomic_fetch_add(&g_errors_occurred, 1);
    }
    dbus_message_unref(msg);
}

void emit_telemetry_signal(DBusConnection *conn, unsigned char slot,
                           int16_t lx, int16_t ly, int16_t rx, int16_t ry,
                           int16_t lt, int16_t rt, int16_t hatx, int16_t haty,
                           uint16_t buttons) {
    if (!conn) return;
    
    DBusMessage *msg = dbus_message_new_signal(BRIDGE_PATH, BRIDGE_INTERFACE, "TelemetryUpdate");
    if (!msg) {
        atomic_fetch_add(&g_errors_occurred, 1);
        return;
    }
    
    if (dbus_message_append_args(msg,
        DBUS_TYPE_BYTE, &slot,
        DBUS_TYPE_INT16, &lx,
        DBUS_TYPE_INT16, &ly,
        DBUS_TYPE_INT16, &rx,
        DBUS_TYPE_INT16, &ry,
        DBUS_TYPE_INT16, &lt,
        DBUS_TYPE_INT16, &rt,
        DBUS_TYPE_INT16, &hatx,
        DBUS_TYPE_INT16, &haty,
        DBUS_TYPE_UINT16, &buttons,
        DBUS_TYPE_INVALID)) {
        if (dbus_connection_send(conn, msg, NULL)) {
            atomic_fetch_add(&g_signals_sent, 1);
        } else {
            atomic_fetch_add(&g_errors_occurred, 1);
        }
    } else {
        atomic_fetch_add(&g_errors_occurred, 1);
    }
    dbus_message_unref(msg);
}

void emit_button_signal(DBusConnection *conn, unsigned char slot, uint16_t buttons) {
    if (!conn) return;
    
    DBusMessage *msg = dbus_message_new_signal(BRIDGE_PATH, BRIDGE_INTERFACE, "ButtonUpdate");
    if (!msg) {
        atomic_fetch_add(&g_errors_occurred, 1);
        return;
    }
    
    if (dbus_message_append_args(msg,
        DBUS_TYPE_BYTE, &slot,
        DBUS_TYPE_UINT16, &buttons,
        DBUS_TYPE_INVALID)) {
        if (dbus_connection_send(conn, msg, NULL)) {
            atomic_fetch_add(&g_signals_sent, 1);
        } else {
            atomic_fetch_add(&g_errors_occurred, 1);
        }
    } else {
        atomic_fetch_add(&g_errors_occurred, 1);
    }
    dbus_message_unref(msg);
}

void emit_axis_signal(DBusConnection *conn, unsigned char slot,
                      int16_t lx, int16_t ly, int16_t rx, int16_t ry,
                      int16_t lt, int16_t rt, int16_t hatx, int16_t haty) {
    if (!conn) return;
    
    DBusMessage *msg = dbus_message_new_signal(BRIDGE_PATH, BRIDGE_INTERFACE, "AxisUpdate");
    if (!msg) {
        atomic_fetch_add(&g_errors_occurred, 1);
        return;
    }
    
    if (dbus_message_append_args(msg,
        DBUS_TYPE_BYTE, &slot,
        DBUS_TYPE_INT16, &lx,
        DBUS_TYPE_INT16, &ly,
        DBUS_TYPE_INT16, &rx,
        DBUS_TYPE_INT16, &ry,
        DBUS_TYPE_INT16, &lt,
        DBUS_TYPE_INT16, &rt,
        DBUS_TYPE_INT16, &hatx,
        DBUS_TYPE_INT16, &haty,
        DBUS_TYPE_INVALID)) {
        if (dbus_connection_send(conn, msg, NULL)) {
            atomic_fetch_add(&g_signals_sent, 1);
        } else {
            atomic_fetch_add(&g_errors_occurred, 1);
        }
    } else {
        atomic_fetch_add(&g_errors_occurred, 1);
    }
    dbus_message_unref(msg);
}
