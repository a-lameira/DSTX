/*
 * main.c - DSTX main entry point
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

#include "dstx.h"
#include "led.h"
#include "axes.h"
#include "settings.h"
#include "keys.h"
#include "commands.h"
#include <grp.h>  
#include <errno.h>

shared_data_t *shm_ptr = NULL;
volatile bool keep_running = true;
bool is_daemon_mode = false;

/**
 * Handler for configuration reload signal (SIGHUP)
 */
void handle_reload(int sig) {
    (void)sig;
    if (shm_ptr) {
        atomic_store(&shm_ptr->request_reload, true);
        syslog(LOG_INFO, "DSTX: SIGHUP received - reloading configuration");
    }
}

/**
 * Handler to toggle debug mode (SIGUSR1)
 * Toggles between LOG_INFO and LOG_DEBUG on the daemon at runtime.
 */
static void handle_sigusr1(int sig) {
    (void)sig;
    static int debug_enabled = 0;
    debug_enabled = !debug_enabled;
    if (debug_enabled) {
        setlogmask(LOG_UPTO(LOG_DEBUG));
        syslog(LOG_INFO, "DSTX: DEBUG mode enabled (SIGUSR1)");
    } else {
        setlogmask(LOG_UPTO(LOG_INFO));
        syslog(LOG_INFO, "DSTX: DEBUG mode disabled (SIGUSR1)");
    }
}

int main(int argc, char **argv) {
    // 0. Initial signal settings
    signal(SIGPIPE, SIG_IGN);
    
    // ========================================================================
    // DAEMON MODE (--daemon)
    // ========================================================================
    if (argc > 1 && strcmp(argv[1], "--daemon") == 0) {
        is_daemon_mode = true;
        
        // Initialize log rate limiting system
        log_rate_init();
        
        // Shared memory initialization as daemon
        bool needs_init = false;
        shm_fd = shm_open(SHM_PATH, O_RDWR, 0660);
        
        if (shm_fd == -1 && errno == ENOENT) {
            shm_fd = shm_open(SHM_PATH, O_CREAT | O_RDWR, 0660);
            needs_init = true;
        }
        
        if (shm_fd == -1) {
            fprintf(stderr, "Critical Error: SHM inaccessible (%s).\n", strerror(errno));
            exit(1);
        }
        
        if (ftruncate(shm_fd, sizeof(shared_data_t)) == -1) {
            perror("ftruncate");
            exit(1);
        }
        
        struct group *grp = getgrnam("dstx");
        if (grp) {
            fchown(shm_fd, 0, grp->gr_gid);
        }
        fchmod(shm_fd, 0660);
        
        shm_ptr = mmap(0, sizeof(shared_data_t), PROT_READ | PROT_WRITE, MAP_SHARED, shm_fd, 0);
        if (shm_ptr == MAP_FAILED) {
            perror("mmap");
            exit(1);
        }
        
        if (mlock(shm_ptr, sizeof(shared_data_t)) != 0) {
            syslog(LOG_WARNING, "DSTX: mlock failed (%s). Shared memory may be paged to disk, affecting performance.", strerror(errno));
            // Continue normally, not critical
        } else {
            syslog(LOG_DEBUG, "DSTX: Shared memory locked in RAM successfully");
        }
        
        // Mutex and SHM state initialization
        pthread_mutexattr_t attr;
        pthread_mutexattr_init(&attr);
        pthread_mutexattr_setpshared(&attr, PTHREAD_PROCESS_SHARED);
        pthread_mutexattr_setrobust(&attr, PTHREAD_MUTEX_ROBUST);
        pthread_mutexattr_settype(&attr, PTHREAD_MUTEX_RECURSIVE);
        
        pid_t old_pid = atomic_load(&shm_ptr->daemon_pid);
        bool shm_is_dirty = false;
        
        if (shm_ptr->magic != SHM_MAGIC_VALUE) {
            syslog(LOG_INFO, "DSTX: Invalid SHM magic - initializing new one");
            shm_is_dirty = true;
        } else if (old_pid > 0 && kill(old_pid, 0) == -1 && errno == ESRCH) {
            syslog(LOG_WARNING, "DSTX: Detected dead previous process (PID %d). Resetting SHM.", old_pid);
            shm_is_dirty = true;
        }
        
        if (needs_init || shm_is_dirty) {
            memset(shm_ptr, 0, sizeof(shared_data_t));
            pthread_mutex_init(&shm_ptr->proc_mutex, &attr);
            atomic_thread_fence(memory_order_release);
            shm_ptr->magic = SHM_MAGIC_VALUE;
            atomic_store(&shm_ptr->daemon_pid, 0);
            atomic_store(&shm_ptr->heartbeat, 0);
            shm_ptr->free_slots_bitmap = 0xFF;
            syslog(LOG_INFO, "DSTX: SHM initialized with magic 0x%08X", SHM_MAGIC_VALUE);
        }
        
        pthread_mutexattr_destroy(&attr);
        
        // Initialize slots
        safe_shm_lock(&shm_ptr->proc_mutex);
        for (int i = 0; i < MAX_SLOTS; i++) {
            // If rumble gain not initialized, set default 100
            uint8_t gain = atomic_load(&shm_ptr->slots[i].rumble_gain);
            if (gain == 0) {
                atomic_store(&shm_ptr->slots[i].rumble_gain, 100);
            }
            atomic_store(&shm_ptr->slots[i].connected, false);
            
            // Base and current LED
            atomic_store(&shm_ptr->slots[i].led_base_r, 0);
            atomic_store(&shm_ptr->slots[i].led_base_g, 0);
            atomic_store(&shm_ptr->slots[i].led_base_b, 255);
            atomic_store(&shm_ptr->slots[i].led_r, 0);
            atomic_store(&shm_ptr->slots[i].led_g, 0);
            atomic_store(&shm_ptr->slots[i].led_b, 255);
            
            // LED requests
            atomic_store(&shm_ptr->slots[i].led_request_effect, 0);
            atomic_store(&shm_ptr->slots[i].led_request_speed, 5);
            atomic_store(&shm_ptr->slots[i].led_request_brightness, 80);
            atomic_store(&shm_ptr->slots[i].led_request_pending, false);
            atomic_store(&shm_ptr->slots[i].led_static, true);
            atomic_store(&shm_ptr->slots[i].led_dirty, true);
            
            atomic_store(&shm_ptr->slots[i].external_retry_count, 0);
            atomic_store(&shm_ptr->slots[i].player_leds, 0);
            atomic_store(&shm_ptr->slots[i].global_led_brightness, 100);
            atomic_store(&shm_ptr->slots[i].debounce_enabled, false);
            
            atomic_init(&shm_ptr->slots[i].rumble_active, true);
            atomic_init(&shm_ptr->slots[i].led_reapply, true);
            
            // Layout request flags
            atomic_init(&shm_ptr->slots[i].request_switch_layout, false);
            atomic_init(&shm_ptr->slots[i].request_xbox_layout, false);
            atomic_init(&shm_ptr->slots[i].request_reset_all_keybinds, false);
            
            atomic_init(&shm_ptr->slots[i].is_uhid, false);
            shm_ptr->slots[i].uinput_fd = -1;
            shm_ptr->slots[i].uhid_fd = -1;
            shm_ptr->slots[i].uhid_output_pending = false;
            memset(shm_ptr->slots[i].uhid_output_buf, 0, sizeof(shm_ptr->slots[i].uhid_output_buf));
            
            atomic_store(&shm_ptr->slots[i].deadzone, 0);
            
            atomic_init(&shm_ptr->slots[i].invert_ly, false);
            atomic_init(&shm_ptr->slots[i].invert_ry, false);
            atomic_init(&shm_ptr->slots[i].sensitivity_left_preset, SENS_PRESET_DEFAULT);
            atomic_init(&shm_ptr->slots[i].sensitivity_right_preset, SENS_PRESET_DEFAULT);
            atomic_init(&shm_ptr->slots[i].is_trigger_digital, false);
            
            // Watchdog
            atomic_init(&shm_ptr->slots[i].worker_heartbeat, 0ULL);
            atomic_init(&shm_ptr->slots[i].worker_stop, false);
            
            memset(&shm_ptr->slots[i].last_external_retry, 0, sizeof(struct timeval));
            memset(shm_ptr->slots[i].product_name, 0, sizeof(shm_ptr->slots[i].product_name));
            memset(shm_ptr->slots[i].uniq, 0, sizeof(shm_ptr->slots[i].uniq));
            memset(shm_ptr->slots[i].driver, 0, sizeof(shm_ptr->slots[i].driver));
            shm_ptr->slots[i].num_input_nodes = 0;
            for (int j = 0; j < MAX_INPUT_NODES; j++) {
                memset(shm_ptr->slots[i].input_nodes[j].path, 0, PATH_MAX);
                memset(shm_ptr->slots[i].input_nodes[j].name, 0, 128);
            }
            
            keys_get_default_map(TYPE_DS4, shm_ptr->slots[i].keymap);
        }
        
        init_axis_system();
        syslog(LOG_INFO, "AXIS: Sensitivity system initialized");
        
        atomic_store(&shm_ptr->heartbeat, 1);
        atomic_thread_fence(memory_order_release);
        pid_t my_pid = getpid();
        atomic_store(&shm_ptr->daemon_pid, my_pid);
        syslog(LOG_INFO, "DSTX: PID %d registered in SHM - daemon ready", my_pid);
        pthread_mutex_unlock(&shm_ptr->proc_mutex);
        
        openlog("dstx-daemon", LOG_PID | LOG_NDELAY, LOG_DAEMON);
        syslog(LOG_INFO, "DSTX: Daemon started - PID %d, slots %d, heartbeat active", getpid(), MAX_SLOTS);
        
        settings_init(shm_ptr);
        
        signal(SIGINT, cleanup);
        signal(SIGTERM, cleanup);
        signal(SIGHUP, handle_reload);
        signal(SIGUSR1, handle_sigusr1);
        syslog(LOG_INFO, "DSTX: Signal handlers configured (SIGHUP for reload, SIGUSR1 for debug toggle)");
        
        run_daemon_loop();
        
        settings_shutdown();
        syslog(LOG_INFO, "DSTX: Settings thread finalized");
        
        return 0;
    }
    
    // ========================================================================
    // CLI MODE (command line commands)
    // ========================================================================
    if (argc > 1) {
        // Process CLI command and exit
        int ret = process_cli_command(argc - 1, argv + 1);
        exit(ret);
    }
    
    // ========================================================================
    // TUI MODE (interactive interface)
    // ========================================================================
    // Initialize rate limiting system (useful for TUI logs)
    log_rate_init();
    
    // Try to connect to existing shared memory
    if (!try_connect_shm()) {
        syslog(LOG_WARNING, "DSTX-UI: Daemon not running, trying to start...");
        start_service();
        if (!try_connect_shm()) {
            fprintf(stderr, "Error: Could not connect to DSTX daemon.\n");
            exit(1);
        }
    }
    
    // Verify magic number
    if (shm_ptr->magic != SHM_MAGIC_VALUE) {
        fprintf(stderr, "Error: Shared memory corrupted.\n");
        exit(1);
    }
    
    // Wait for daemon to become ready
    int pid_attempts = 20;
    while (atomic_load(&shm_ptr->daemon_pid) == 0 && pid_attempts--) {
        usleep(100000);
    }
    
    if (!is_daemon_alive()) {
        syslog(LOG_WARNING, "DSTX-UI: Daemon in waiting state or inaccessible - PID=%d", 
               atomic_load(&shm_ptr->daemon_pid));
    } else {
        syslog(LOG_INFO, "DSTX-UI: Connected to daemon PID %d", atomic_load(&shm_ptr->daemon_pid));
    }
    
    signal(SIGINT, cleanup);
    signal(SIGTERM, cleanup);
    
    syslog(LOG_INFO, "DSTX-UI: Starting interface loop");
    run_ui_loop();
    
    return 0;
}
