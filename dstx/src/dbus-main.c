/*
 * dbus-main.c - D-Bus bridge entry point
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
#include <signal.h>
#include <syslog.h>
#include <unistd.h>
#include <pthread.h>

/* Global variables (defined in dbus-monitor.c) */
extern _Atomic uint64_t g_signals_sent;
extern _Atomic uint64_t g_methods_called;
extern _Atomic uint64_t g_errors_occurred;
extern _Atomic uint64_t g_reconnections;
extern bridge_state_t g_state;
extern controller_t g_prev_state[MAX_SLOTS];
extern bool g_prev_daemon_alive;
extern DBusConnection *dbus_conn;
extern volatile bool worker_running;
extern void *daemon_monitor(void *arg);

static pthread_t worker_thread;
volatile bool keep_running = true;

static void signal_handler(int sig) {
    if (sig == SIGINT || sig == SIGTERM) {
        syslog(LOG_INFO, "Received signal %d, shutting down", sig);
        keep_running = false;
        worker_running = false;
    }
}

static void dbus_cleanup(void) {
    if (dbus_conn) {
        dbus_connection_unref(dbus_conn);
        dbus_conn = NULL;
    }
}

static bool setup_dbus(void) {
    DBusError err;
    dbus_error_init(&err);

    dbus_conn = dbus_bus_get(DBUS_BUS_SYSTEM, &err);
    if (!dbus_conn) {
        syslog(LOG_ERR, "Failed to connect to system bus: %s", err.message);
        dbus_error_free(&err);
        return false;
    }

    int ret = dbus_bus_request_name(dbus_conn, BRIDGE_NAME,
                                     DBUS_NAME_FLAG_REPLACE_EXISTING, &err);
    if (ret != DBUS_REQUEST_NAME_REPLY_PRIMARY_OWNER) {
        syslog(LOG_ERR, "Failed to request bus name '%s': %s", BRIDGE_NAME, 
               err.message ? err.message : "unknown");
        dbus_error_free(&err);
        dbus_connection_unref(dbus_conn);
        dbus_conn = NULL;
        return false;
    }

    register_method_handlers(dbus_conn);

    syslog(LOG_INFO, "D-Bus setup successful: %s @ %s", BRIDGE_NAME, BRIDGE_PATH);
    return true;
}

int main(int argc, char **argv) {
    (void)argc;
    (void)argv;

    openlog("dstx-dbus-bridge", LOG_PID | LOG_NDELAY, LOG_DAEMON);
    
    atomic_init(&g_signals_sent, 0);
    atomic_init(&g_methods_called, 0);
    atomic_init(&g_errors_occurred, 0);
    atomic_init(&g_reconnections, 0);
    
    syslog(LOG_INFO, "=== DSTX D-Bus Bridge Starting ===");
    syslog(LOG_INFO, "sizeof(controller_t)=%zu, sizeof(shared_data_t)=%zu",
           sizeof(controller_t), sizeof(shared_data_t));

    signal(SIGINT, signal_handler);
    signal(SIGTERM, signal_handler);

    if (pthread_create(&worker_thread, NULL, daemon_monitor, NULL) != 0) {
        syslog(LOG_ERR, "Failed to create monitor thread");
        return 1;
    }

    while (keep_running) {
        if (setup_dbus()) {
            break;
        }
        syslog(LOG_WARNING, "D-Bus setup failed, retrying in 2 seconds...");
        sleep(2);
    }

    if (!keep_running) {
        pthread_join(worker_thread, NULL);
        closelog();
        return 0;
    }

    syslog(LOG_INFO, "Bridge started successfully");
    
    time_t last_stats_log = time(NULL);

    while (keep_running) {
        if (dbus_connection_read_write_dispatch(dbus_conn, 0) == FALSE) {
            syslog(LOG_ERR, "D-Bus connection lost, reconnecting...");
            dbus_cleanup();
            atomic_fetch_add(&g_reconnections, 1);
            
            bool reconnected = false;
            for (int retry = 0; retry < 10 && keep_running; retry++) {
                sleep(1);
                if (setup_dbus()) {
                    syslog(LOG_INFO, "Reconnected to D-Bus");
                    reconnected = true;
                    break;
                }
            }
            if (!reconnected) {
                syslog(LOG_ERR, "Failed to reconnect, exiting");
                break;
            }
        }
        
        time_t now = time(NULL);
        if (now - last_stats_log >= 60) {
            syslog(LOG_INFO, "Stats: signals=%lu, methods=%lu, errors=%lu, reconnects=%lu",
                   atomic_load(&g_signals_sent),
                   atomic_load(&g_methods_called),
                   atomic_load(&g_errors_occurred),
                   atomic_load(&g_reconnections));
            last_stats_log = now;
        }
        
        usleep(10000);
    }

    syslog(LOG_INFO, "Shutting down");
    worker_running = false;
    pthread_join(worker_thread, NULL);
    dbus_cleanup();
    closelog();
    return 0;
}
