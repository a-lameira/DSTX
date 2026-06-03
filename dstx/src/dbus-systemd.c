/*
 * dbus-systemd.c - Direct systemd communication via D-Bus
 * Simplified and robust version.
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

#include "dbus-systemd.h"
#include <syslog.h>
#include <string.h>
#include <stdarg.h>

/* Sends a simple method (no parameters) and returns the job path if any */
static int send_simple_unit_method(DBusConnection *conn, const char *method, const char *unit, const char *mode) {
    DBusMessage *msg = dbus_message_new_method_call(
        "org.freedesktop.systemd1",
        "/org/freedesktop/systemd1",
        "org.freedesktop.systemd1.Manager",
        method);
    if (!msg) return -1;

    if (!dbus_message_append_args(msg,
                                  DBUS_TYPE_STRING, &unit,
                                  DBUS_TYPE_STRING, &mode,
                                  DBUS_TYPE_INVALID)) {
        dbus_message_unref(msg);
        return -1;
    }

    DBusError err;
    dbus_error_init(&err);
    DBusMessage *reply = dbus_connection_send_with_reply_and_block(conn, msg, 10000, &err);
    dbus_message_unref(msg);

    if (dbus_error_is_set(&err)) {
        syslog(LOG_ERR, "systemd %s error: %s", method, err.message);
        dbus_error_free(&err);
        return -1;
    }

    const char *job_path = NULL;
    if (!dbus_message_get_args(reply, NULL, DBUS_TYPE_OBJECT_PATH, &job_path, DBUS_TYPE_INVALID)) {
        dbus_message_unref(reply);
        return -1;
    }
    dbus_message_unref(reply);
    return 0;
}

int systemd_start_unit(DBusConnection *conn, const char *unit, const char *mode) {
    return send_simple_unit_method(conn, "StartUnit", unit, mode);
}

int systemd_stop_unit(DBusConnection *conn, const char *unit, const char *mode) {
    return send_simple_unit_method(conn, "StopUnit", unit, mode);
}

int systemd_restart_unit(DBusConnection *conn, const char *unit, const char *mode) {
    return send_simple_unit_method(conn, "RestartUnit", unit, mode);
}

/* Checks if the unit is active */
bool systemd_unit_is_active(DBusConnection *conn, const char *unit) {
    DBusMessage *msg = dbus_message_new_method_call(
        "org.freedesktop.systemd1",
        "/org/freedesktop/systemd1",
        "org.freedesktop.systemd1.Manager",
        "GetUnit");
    if (!msg) return false;
    if (!dbus_message_append_args(msg, DBUS_TYPE_STRING, &unit, DBUS_TYPE_INVALID)) {
        dbus_message_unref(msg);
        return false;
    }

    DBusError err;
    dbus_error_init(&err);
    DBusMessage *reply = dbus_connection_send_with_reply_and_block(conn, msg, 5000, &err);
    dbus_message_unref(msg);
    if (!reply) {
        if (dbus_error_is_set(&err)) dbus_error_free(&err);
        return false;
    }

    const char *unit_path = NULL;
    if (!dbus_message_get_args(reply, NULL, DBUS_TYPE_OBJECT_PATH, &unit_path, DBUS_TYPE_INVALID)) {
        dbus_message_unref(reply);
        return false;
    }
    dbus_message_unref(reply);
    if (!unit_path) return false;

    /* Now get the ActiveState property */
    msg = dbus_message_new_method_call(
        "org.freedesktop.systemd1",
        unit_path,
        "org.freedesktop.DBus.Properties",
        "Get");
    if (!msg) return false;
    const char *interface = "org.freedesktop.systemd1.Unit";
    const char *property = "ActiveState";
    if (!dbus_message_append_args(msg,
                                  DBUS_TYPE_STRING, &interface,
                                  DBUS_TYPE_STRING, &property,
                                  DBUS_TYPE_INVALID)) {
        dbus_message_unref(msg);
        return false;
    }

    reply = dbus_connection_send_with_reply_and_block(conn, msg, 5000, &err);
    dbus_message_unref(msg);
    if (!reply) {
        if (dbus_error_is_set(&err)) dbus_error_free(&err);
        return false;
    }

    DBusMessageIter iter, var_iter;
    dbus_message_iter_init(reply, &iter);
    if (dbus_message_iter_get_arg_type(&iter) != DBUS_TYPE_VARIANT) {
        dbus_message_unref(reply);
        return false;
    }
    dbus_message_iter_recurse(&iter, &var_iter);
    const char *state = NULL;
    if (dbus_message_iter_get_arg_type(&var_iter) == DBUS_TYPE_STRING) {
        dbus_message_iter_get_basic(&var_iter, &state);
    }
    bool active = (state && strcmp(state, "active") == 0);
    dbus_message_unref(reply);
    return active;
}

/* Checks if the unit is enabled */
bool systemd_unit_is_enabled(DBusConnection *conn, const char *unit) {
    DBusMessage *msg = dbus_message_new_method_call(
        "org.freedesktop.systemd1",
        "/org/freedesktop/systemd1",
        "org.freedesktop.systemd1.Manager",
        "GetUnitFileState");
    if (!msg) return false;
    if (!dbus_message_append_args(msg, DBUS_TYPE_STRING, &unit, DBUS_TYPE_INVALID)) {
        dbus_message_unref(msg);
        return false;
    }

    DBusError err;
    dbus_error_init(&err);
    DBusMessage *reply = dbus_connection_send_with_reply_and_block(conn, msg, 5000, &err);
    dbus_message_unref(msg);
    if (!reply) {
        if (dbus_error_is_set(&err)) dbus_error_free(&err);
        return false;
    }

    const char *state = NULL;
    if (!dbus_message_get_args(reply, NULL, DBUS_TYPE_STRING, &state, DBUS_TYPE_INVALID)) {
        dbus_message_unref(reply);
        return false;
    }
    bool enabled = (state && (strcmp(state, "enabled") == 0 || strcmp(state, "enabled-runtime") == 0));
    dbus_message_unref(reply);
    return enabled;
}

/* Enables or disables the unit */
int systemd_enable_unit(DBusConnection *conn, const char *unit, bool enable) {
    const char *method = enable ? "EnableUnitFiles" : "DisableUnitFiles";
    DBusMessage *msg = dbus_message_new_method_call(
        "org.freedesktop.systemd1",
        "/org/freedesktop/systemd1",
        "org.freedesktop.systemd1.Manager",
        method);
    if (!msg) return -1;

    DBusMessageIter iter, array_iter;
    dbus_message_iter_init_append(msg, &iter);
    dbus_message_iter_open_container(&iter, DBUS_TYPE_ARRAY, DBUS_TYPE_STRING_AS_STRING, &array_iter);
    dbus_message_iter_append_basic(&array_iter, DBUS_TYPE_STRING, &unit);
    dbus_message_iter_close_container(&iter, &array_iter);

    dbus_bool_t runtime = FALSE;
    dbus_message_iter_append_basic(&iter, DBUS_TYPE_BOOLEAN, &runtime);

    if (enable) {
        dbus_bool_t force = FALSE;
        dbus_message_iter_append_basic(&iter, DBUS_TYPE_BOOLEAN, &force);
    }

    DBusError err;
    dbus_error_init(&err);
    DBusMessage *reply = dbus_connection_send_with_reply_and_block(conn, msg, 10000, &err);
    dbus_message_unref(msg);
    if (!reply) {
        if (dbus_error_is_set(&err)) {
            syslog(LOG_ERR, "systemd %s failed: %s", method, err.message);
            dbus_error_free(&err);
        }
        return -1;
    }

    /* Response: EnableUnitFiles returns (bool changes, array of symlinks) */
    /* DisableUnitFiles returns (bool changes) */
    int ret = 0;
    if (enable) {
        DBusMessageIter reply_iter;
        dbus_message_iter_init(reply, &reply_iter);
        if (dbus_message_iter_get_arg_type(&reply_iter) == DBUS_TYPE_BOOLEAN) {
            /* Ignore the actual value */
            ret = 0;
        } else {
            ret = -1;
        }
    } else {
        dbus_bool_t changes;
        if (dbus_message_get_args(reply, NULL, DBUS_TYPE_BOOLEAN, &changes, DBUS_TYPE_INVALID)) {
            ret = 0;
        } else {
            ret = -1;
        }
    }
    dbus_message_unref(reply);
    return ret;
}
