/*
 * dbus-common.h - Common structures and declarations for the D-Bus bridge
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

#ifndef DBUS_COMMON_H
#define DBUS_COMMON_H

#include "dstx.h"
#include <dbus/dbus.h>
#include <pthread.h>
#include <stdatomic.h>
#include <stdbool.h>
#include <sys/time.h>

/* ================== Bridge configuration ================== */
#define BRIDGE_NAME "org.dstx.Bridge"
#define BRIDGE_PATH "/org/dstx/Bridge"
#define BRIDGE_INTERFACE "org.dstx.Bridge"
#define DSTX_CORE_VERSION "0.8.0"

/* Rate limiting configuration */
#define TELEMETRY_MIN_INTERVAL_US 16666   /* 60 Hz max */
#define BUTTON_MIN_INTERVAL_US 33333      /* 30 Hz max */
#define AXIS_MIN_INTERVAL_US 16666        /* 60 Hz max */
#define CONTROLLER_UPDATE_INTERVAL_US 100000 /* 10 Hz max */

/* Rate limiting state */
typedef struct {
    uint64_t last_telemetry_us;
    uint64_t last_button_us;
    uint64_t last_axis_us;
    uint64_t last_controller_update_us;
} rate_limit_t;

/* Global bridge state */
typedef struct {
    pthread_mutex_t lock;
    bool daemon_alive;
    controller_t slots[MAX_SLOTS];
    struct timeval last_update;
    rate_limit_t rate_limit[MAX_SLOTS];
} bridge_state_t;

/* Debug statistics */
extern _Atomic uint64_t g_signals_sent;
extern _Atomic uint64_t g_methods_called;
extern _Atomic uint64_t g_errors_occurred;
extern _Atomic uint64_t g_reconnections;

/* Global variables */
extern bridge_state_t g_state;
extern controller_t g_prev_state[MAX_SLOTS];
extern bool g_prev_daemon_alive;
extern DBusConnection *dbus_conn;
extern volatile bool worker_running;

/* Function prototypes used across multiple files */
uint64_t get_time_us(void);
bool should_emit_signal(uint64_t last_emit, uint64_t min_interval_us);
uint16_t pack_buttons(controller_t *c);
void copy_controller_state(controller_t *dst, controller_t *src);
bool telemetry_changed(controller_t *a, controller_t *b);
bool config_changed(controller_t *a, controller_t *b);

/* Signal handlers */
void emit_controller_signal(DBusConnection *conn, const char *signal_name, unsigned char slot);
void emit_daemon_status_signal(DBusConnection *conn, bool alive);
void emit_telemetry_signal(DBusConnection *conn, unsigned char slot,
                           int16_t lx, int16_t ly, int16_t rx, int16_t ry,
                           int16_t lt, int16_t rt, int16_t hatx, int16_t haty,
                           uint16_t buttons);
void emit_button_signal(DBusConnection *conn, unsigned char slot, uint16_t buttons);
void emit_axis_signal(DBusConnection *conn, unsigned char slot,
                      int16_t lx, int16_t ly, int16_t rx, int16_t ry,
                      int16_t lt, int16_t rt, int16_t hatx, int16_t haty);

/* Method handlers (declared in dbus-handlers.c) */
void register_method_handlers(DBusConnection *conn);

/* SHM functions (dbus-utils.c) */
typedef struct {
    shared_data_t *shm;
    int fd;
} shm_handle_t;

shm_handle_t open_shm_handle(DBusConnection *conn, DBusMessage *msg, unsigned char slot);
void close_shm_handle(shm_handle_t *h);
shared_data_t* open_shm_handle_any(DBusConnection *conn, DBusMessage *msg);
void close_shm_handle_any(shared_data_t *shm);
bool shm_request_sync(shared_data_t *shm, int request, const char *name,
                      int auto_enable, int auto_delay, char *out_msg, size_t msg_size);

/* Helper functions for accessing _Atomic types (defined in dbus-utils.c) */
bool atomic_load_bool(_Atomic bool *src);
void atomic_store_bool(_Atomic bool *dst, bool val);
uint8_t atomic_load_uint8(_Atomic uint8_t *src);
void atomic_store_uint8(_Atomic uint8_t *dst, uint8_t val);
uint32_t atomic_load_uint32(_Atomic uint32_t *src);
int32_t atomic_load_int32(_Atomic int32_t *src);

#endif /* DBUS_COMMON_H */
