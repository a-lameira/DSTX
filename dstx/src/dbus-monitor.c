/*
 * dbus-monitor.c - Daemon monitoring and signal emission
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
#include <sys/mman.h>
#include <sys/stat.h>
#include <fcntl.h>
#include <errno.h>
#include <signal.h>

/* Global variables defined here */
_Atomic uint64_t g_signals_sent = 0;
_Atomic uint64_t g_methods_called = 0;
_Atomic uint64_t g_errors_occurred = 0;
_Atomic uint64_t g_reconnections = 0;

bridge_state_t g_state = {
    .lock = PTHREAD_MUTEX_INITIALIZER,
    .daemon_alive = false,
    .last_update = {0, 0},
    .rate_limit = {{0, 0, 0, 0}}
};

controller_t g_prev_state[MAX_SLOTS] = {0};
bool g_prev_daemon_alive = false;
DBusConnection *dbus_conn = NULL;
volatile bool worker_running = true;

void *daemon_monitor(void *arg) {
    (void)arg;
    shared_data_t *shm_ptr = NULL;
    int shm_fd = -1;
    uint32_t last_heartbeat = 0;
    struct timeval last_heartbeat_time = {0, 0};
    bool last_alive_state = false;

    syslog(LOG_INFO, "Monitor thread started.");

    while (worker_running) {
        if (!shm_ptr) {
            shm_fd = shm_open(SHM_PATH, O_RDWR, 0660);
            if (shm_fd != -1) {
                struct stat st;
                if (fstat(shm_fd, &st) == 0 && (size_t)st.st_size >= sizeof(shared_data_t)) {
                    shm_ptr = mmap(NULL, sizeof(shared_data_t), PROT_READ | PROT_WRITE,
                                   MAP_SHARED, shm_fd, 0);
                    if (shm_ptr == MAP_FAILED) {
                        shm_ptr = NULL;
                        close(shm_fd);
                        shm_fd = -1;
                        syslog(LOG_ERR, "Failed to map SHM");
                    } else if (shm_ptr->magic != SHM_MAGIC_VALUE) {
                        syslog(LOG_ERR, "SHM magic mismatch");
                        munmap(shm_ptr, sizeof(shared_data_t));
                        shm_ptr = NULL;
                        close(shm_fd);
                        shm_fd = -1;
                    } else {
                        syslog(LOG_INFO, "SHM mapped successfully");
                    }
                } else {
                    close(shm_fd);
                    shm_fd = -1;
                }
            }
        }

        bool alive = false;
        if (shm_ptr) {
            uint32_t current_hb = atomic_load_uint32(&shm_ptr->heartbeat);
            struct timeval now;
            gettimeofday(&now, NULL);
            
            if (current_hb != last_heartbeat) {
                last_heartbeat = current_hb;
                last_heartbeat_time = now;
                alive = true;
            } else {
                long diff_ms = (now.tv_sec - last_heartbeat_time.tv_sec) * 1000 +
                               (now.tv_usec - last_heartbeat_time.tv_usec) / 1000;
                alive = (diff_ms <= 1000);
            }
            
            if (alive) {
                pid_t pid = atomic_load_int32(&shm_ptr->daemon_pid);
                if (pid <= 0 || (kill(pid, 0) != 0 && errno == ESRCH)) {
                    alive = false;
                }
            }

            if (alive) {
                pthread_mutex_lock(&shm_ptr->proc_mutex);
                pthread_mutex_lock(&g_state.lock);
                
                g_state.daemon_alive = true;
                
                for (int i = 0; i < MAX_SLOTS; i++) {
                    controller_t *src = &shm_ptr->slots[i];
                    controller_t *dst = &g_state.slots[i];
                    controller_t *prev = &g_prev_state[i];
                    
                    copy_controller_state(dst, src);
                    
                    bool dst_connected = atomic_load_bool(&dst->connected);
                    bool prev_connected = atomic_load_bool(&prev->connected);
                    
                    if (dst_connected != prev_connected) {
                        if (dst_connected) {
                            emit_controller_signal(dbus_conn, "ControllerConnected", i);
                            syslog(LOG_INFO, "Controller connected on slot %d", i);
                        } else {
                            emit_controller_signal(dbus_conn, "ControllerDisconnected", i);
                            syslog(LOG_INFO, "Controller disconnected from slot %d", i);
                        }
                    }
                    
                    if (dst_connected && config_changed(dst, prev)) {
                        uint64_t now_us = get_time_us();
                        if (should_emit_signal(g_state.rate_limit[i].last_controller_update_us, 
                                                CONTROLLER_UPDATE_INTERVAL_US)) {
                            emit_controller_signal(dbus_conn, "ControllerUpdated", i);
                            g_state.rate_limit[i].last_controller_update_us = now_us;
                        }
                    }
                    
                    if (dst_connected) {
                        uint16_t buttons = pack_buttons(dst);
                        uint16_t prev_buttons = pack_buttons(prev);
                        
                        bool buttons_changed = (buttons != prev_buttons);
                        bool axes_changed = telemetry_changed(dst, prev);
                        
                        if (buttons_changed || axes_changed) {
                            uint64_t now_us = get_time_us();
                            
                            if (should_emit_signal(g_state.rate_limit[i].last_telemetry_us, 
                                                    TELEMETRY_MIN_INTERVAL_US)) {
                                emit_telemetry_signal(dbus_conn, i,
                                                      dst->LX, dst->LY,
                                                      dst->RX, dst->RY,
                                                      dst->LT, dst->RT,
                                                      dst->HATX, dst->HATY,
                                                      buttons);
                                g_state.rate_limit[i].last_telemetry_us = now_us;
                            }
                            
                            if (buttons_changed && 
                                should_emit_signal(g_state.rate_limit[i].last_button_us, 
                                                    BUTTON_MIN_INTERVAL_US)) {
                                emit_button_signal(dbus_conn, i, buttons);
                                g_state.rate_limit[i].last_button_us = now_us;
                            }
                            
                            if (axes_changed && 
                                should_emit_signal(g_state.rate_limit[i].last_axis_us, 
                                                    AXIS_MIN_INTERVAL_US)) {
                                emit_axis_signal(dbus_conn, i,
                                                 dst->LX, dst->LY,
                                                 dst->RX, dst->RY,
                                                 dst->LT, dst->RT,
                                                 dst->HATX, dst->HATY);
                                g_state.rate_limit[i].last_axis_us = now_us;
                            }
                        }
                    }
                    
                    copy_controller_state(prev, dst);
                }
                
                gettimeofday(&g_state.last_update, NULL);
                pthread_mutex_unlock(&g_state.lock);
                pthread_mutex_unlock(&shm_ptr->proc_mutex);

                if (!last_alive_state) {
                    pid_t pid = atomic_load_int32(&shm_ptr->daemon_pid);
                    syslog(LOG_INFO, "Daemon is online (PID %d)", pid);
                    
                    if (!g_prev_daemon_alive) {
                        emit_daemon_status_signal(dbus_conn, true);
                        g_prev_daemon_alive = true;
                    }
                }
            } else {
                if (last_alive_state) {
                    syslog(LOG_INFO, "Daemon went offline");
                    if (g_prev_daemon_alive) {
                        emit_daemon_status_signal(dbus_conn, false);
                        g_prev_daemon_alive = false;
                    }
                    memset(&g_prev_state, 0, sizeof(g_prev_state));
                    memset(&g_state.rate_limit, 0, sizeof(g_state.rate_limit));
                }
                
                pthread_mutex_lock(&g_state.lock);
                g_state.daemon_alive = false;
                pthread_mutex_unlock(&g_state.lock);
                
                if (shm_ptr) {
                    munmap(shm_ptr, sizeof(shared_data_t));
                    shm_ptr = NULL;
                }
                if (shm_fd != -1) {
                    close(shm_fd);
                    shm_fd = -1;
                }
            }
        } else {
            if (last_alive_state) {
                syslog(LOG_INFO, "Daemon offline (no SHM)");
                if (g_prev_daemon_alive) {
                    emit_daemon_status_signal(dbus_conn, false);
                    g_prev_daemon_alive = false;
                }
            }
            pthread_mutex_lock(&g_state.lock);
            g_state.daemon_alive = false;
            pthread_mutex_unlock(&g_state.lock);
        }

        last_alive_state = (shm_ptr && alive);
        usleep(100000);
    }

    if (shm_ptr) munmap(shm_ptr, sizeof(shared_data_t));
    if (shm_fd != -1) close(shm_fd);
    syslog(LOG_INFO, "Monitor thread exiting");
    return NULL;
}
