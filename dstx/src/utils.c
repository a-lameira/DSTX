/*
 * utils.c - Utility functions for DSTX
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
#include "keys.h"
#include <pwd.h>
#include <time.h>
#include <sys/stat.h>
#include <sys/wait.h>
#include <libgen.h>
#include <dirent.h>
#include <limits.h>
#include <poll.h>
#include <stdarg.h>

int shm_fd = -1;
static struct termios orig_termios;

// ========================================================================
// LOG RATE LIMITING
// ========================================================================

// State structure for per-category rate limiting
typedef struct {
    uint64_t last_log_us[LOG_CAT_COUNT];   // last log timestamp (us)
    uint32_t counter[LOG_CAT_COUNT];       // call count since last reset
} log_rate_t;

static log_rate_t g_log_rate = {0};
static bool g_log_rate_initialized = false;

// Default interval for time-based rate limiting (1 second)
#define LOG_RATELIMIT_DEFAULT_INTERVAL_US 1000000ULL

void log_rate_init(void) {
    if (g_log_rate_initialized) return;
    memset(&g_log_rate, 0, sizeof(g_log_rate));
    g_log_rate_initialized = true;
}

bool log_ratelimit_time(log_category_t cat, uint64_t interval_us, int level, const char *fmt, ...) {
    if (!g_log_rate_initialized) {
        log_rate_init();
    }
    if (cat >= LOG_CAT_COUNT) {
        // Invalid category: log without rate limiting (for safety)
        va_list args;
        va_start(args, fmt);
        vsyslog(level, fmt, args);
        va_end(args);
        return true;
    }

    uint64_t now = get_monotonic_time_us();
    uint64_t last = g_log_rate.last_log_us[cat];
    
    if (now - last >= interval_us) {
        g_log_rate.last_log_us[cat] = now;
        va_list args;
        va_start(args, fmt);
        vsyslog(level, fmt, args);
        va_end(args);
        return true;
    }
    return false;
}

bool log_ratelimit_count(log_category_t cat, uint32_t every_n, int level, const char *fmt, ...) {
    if (!g_log_rate_initialized) {
        log_rate_init();
    }
    if (cat >= LOG_CAT_COUNT) {
        va_list args;
        va_start(args, fmt);
        vsyslog(level, fmt, args);
        va_end(args);
        return true;
    }

    g_log_rate.counter[cat]++;
    if (g_log_rate.counter[cat] % every_n == 0) {
        va_list args;
        va_start(args, fmt);
        vsyslog(level, fmt, args);
        va_end(args);
        return true;
    }
    return false;
}

void log_reset_category(log_category_t cat) {
    if (cat < LOG_CAT_COUNT) {
        g_log_rate.last_log_us[cat] = 0;
        g_log_rate.counter[cat] = 0;
    }
}

// ========================================================================
// LOW-LEVEL UTILITIES
// ========================================================================

void set_nonblocking(int fd) {
    if (fd < 0) return;
    int flags = fcntl(fd, F_GETFL, 0);
    if (flags != -1) fcntl(fd, F_SETFL, flags | O_NONBLOCK);
}

void enable_raw_mode(void) {
    tcgetattr(STDIN_FILENO, &orig_termios);
    struct termios raw = orig_termios;
    raw.c_lflag &= ~(ECHO | ICANON);
    tcsetattr(STDIN_FILENO, TCSANOW, &raw);
}

void disable_raw_mode(void) {
    printf("\033[?25h");
    tcsetattr(STDIN_FILENO, TCSANOW, &orig_termios);
}

// --- HELPER TO EXECUTE systemctl VIA FORK/EXEC ---
static int execute_systemctl(const char *action) {
    pid_t pid = fork();
    if (pid == -1) {
        syslog(LOG_ERR, "DSTX-UI: fork() failed: %s", strerror(errno));
        return -1;
    }
    if (pid == 0) {
        // Child process: execute systemctl
        execlp("systemctl", "systemctl", action, "dstx-daemon.service", (char*)NULL);
        // If we get here, error
        syslog(LOG_ERR, "DSTX-UI: execlp(systemctl) failed: %s", strerror(errno));
        _exit(127);
    }
    // Parent process: wait for completion
    int status;
    if (waitpid(pid, &status, 0) == -1) {
        syslog(LOG_ERR, "DSTX-UI: waitpid() failed: %s", strerror(errno));
        return -1;
    }
    if (WIFEXITED(status)) {
        return WEXITSTATUS(status);
    }
    return -1;
}

// --- SERVICE CONTROL ---

void start_service(void) {
    if (shm_ptr != NULL) {
        safe_shm_lock(&shm_ptr->proc_mutex);
        if (atomic_load(&shm_ptr->daemon_pid) > 0) {
            pthread_mutex_unlock(&shm_ptr->proc_mutex);
            if (atomic_load(&shm_ptr->heartbeat) > 0) {
                syslog(LOG_INFO, "DSTX-UI: Service already running (PID=%d, heartbeat=%d)",
                       atomic_load(&shm_ptr->daemon_pid),
                       atomic_load(&shm_ptr->heartbeat));
                return;
            }
        }
        pthread_mutex_unlock(&shm_ptr->proc_mutex);
    }
    
    if (is_daemon_alive()) return;

    syslog(LOG_INFO, "DSTX-UI: Starting service...");
    int ret = execute_systemctl("start");
    if (ret != 0) {
        syslog(LOG_WARNING, "DSTX-UI: systemctl start returned %d", ret);
    }

    int attempts = 30;
    while (attempts--) {
        if (try_connect_shm()) {
            for(int j=0; j<20; j++) {
                if (shm_ptr) {
                    uint32_t hb = atomic_load(&shm_ptr->heartbeat);
                    pid_t pid = atomic_load(&shm_ptr->daemon_pid);
                    
                    if (hb > 0 && pid > 0) {
                        syslog(LOG_INFO, "DSTX-UI: Daemon ready (PID=%d, heartbeat=%d)", 
                               pid, hb);
                        return;
                    }
                }
                usleep(50000);
            }
            return;
        }
        usleep(100000);
    }
    
    syslog(LOG_WARNING, "DSTX-UI: Could not connect to daemon after multiple attempts");
}

void stop_service(void) {
    syslog(LOG_INFO, "DSTX-UI: Stopping service...");
    int ret = execute_systemctl("stop");
    if (ret != 0) {
        syslog(LOG_WARNING, "DSTX-UI: systemctl stop returned %d", ret);
    }

    if (shm_ptr) {
        safe_shm_lock(&shm_ptr->proc_mutex);
        atomic_store(&shm_ptr->daemon_pid, 0);
        atomic_store(&shm_ptr->heartbeat, 0);
        for (int i = 0; i < MAX_SLOTS; i++) {
            atomic_store(&shm_ptr->slots[i].connected, false);
        }
        pthread_mutex_unlock(&shm_ptr->proc_mutex);
        disconnect_shm(); 
    }
    
    usleep(200000); 
}

void disconnect_shm(void) {
    if (shm_ptr != NULL && shm_ptr != MAP_FAILED) {
        munmap(shm_ptr, sizeof(shared_data_t));
        shm_ptr = NULL;
    }
    if (shm_fd != -1) {
        close(shm_fd);
        shm_fd = -1;
    }
}

bool try_connect_shm(void) {
    disconnect_shm();

    shm_fd = shm_open(SHM_PATH, O_RDWR, 0660);
    if (shm_fd == -1) {
        return false;
    }

    struct stat st;
    if (fstat(shm_fd, &st) == -1 || (size_t)st.st_size < sizeof(shared_data_t)) {
        close(shm_fd);
        shm_fd = -1;
        return false;
    }

    shm_ptr = mmap(0, sizeof(shared_data_t), PROT_READ | PROT_WRITE, MAP_SHARED, shm_fd, 0);
    if (shm_ptr == MAP_FAILED) {
        shm_ptr = NULL;
        close(shm_fd);
        shm_fd = -1;
        return false;
    }

    if (shm_ptr->magic != SHM_MAGIC_VALUE) {
        syslog(LOG_DEBUG, "DSTX-UI: Invalid magic number");
        disconnect_shm();
        return false;
    }

    pid_t daemon_pid = atomic_load(&shm_ptr->daemon_pid);
    
    if (daemon_pid <= 0) {
        syslog(LOG_DEBUG, "DSTX-UI: Invalid PID (%d)", daemon_pid);
        return false;
    }

    int hb_attempts = 20;
    uint32_t hb = 0;
    
    while (hb_attempts-- > 0) {
        hb = atomic_load(&shm_ptr->heartbeat);
        if (hb > 0) {
            syslog(LOG_DEBUG, "DSTX-UI: Heartbeat detected: %d", hb);
            break;
        }
        usleep(50000);
    }
    
    if (hb == 0) {
        syslog(LOG_WARNING, "DSTX-UI: Heartbeat never started");
        disconnect_shm();
        return false;
    }

    int kill_result = kill(daemon_pid, 0);
    if (kill_result == -1) {
        if (errno == ESRCH) {
            syslog(LOG_WARNING, "DSTX-UI: Process %d does not exist", daemon_pid);
            disconnect_shm();
            return false;
        }
        syslog(LOG_DEBUG, "DSTX-UI: kill returned %d (errno=%d) - assuming alive", 
               kill_result, errno);
    }

    syslog(LOG_INFO, "DSTX-UI: Connected to daemon PID %d (heartbeat=%d)", 
           daemon_pid, hb);
    return true;
}

bool is_daemon_alive(void) {
    if (!shm_ptr) return false;

    pid_t pid = atomic_load(&shm_ptr->daemon_pid);
    
    if (pid <= 0) return false;

    int kill_result = kill(pid, 0);
    if (kill_result != 0) {
        if (errno == ESRCH) {
            safe_shm_lock(&shm_ptr->proc_mutex);
            if (atomic_load(&shm_ptr->daemon_pid) == pid) {
                atomic_store(&shm_ptr->daemon_pid, 0);
                atomic_store(&shm_ptr->heartbeat, 0);
            }
            pthread_mutex_unlock(&shm_ptr->proc_mutex);
            return false;
        }
        return true;
    }

    uint32_t hb = atomic_load(&shm_ptr->heartbeat);
    if (hb == 0) {
        return false;
    }

    return true;
}

// ========================================================================
// CONVERSION FUNCTIONS (used by settings.c and other modules)
// ========================================================================

/* Converts slot_config_t to persistent fields of controller_t */
void slot_config_to_controller(const slot_config_t *cfg, controller_t *ctrl) {
    atomic_store(&ctrl->led_r, cfg->led_r);
    atomic_store(&ctrl->led_g, cfg->led_g);
    atomic_store(&ctrl->led_b, cfg->led_b);
    atomic_store(&ctrl->led_base_r, cfg->led_base_r);
    atomic_store(&ctrl->led_base_g, cfg->led_base_g);
    atomic_store(&ctrl->led_base_b, cfg->led_base_b);
    atomic_store(&ctrl->rumble_gain, cfg->rumble_gain);
    atomic_store(&ctrl->deadzone, cfg->deadzone);
    atomic_store(&ctrl->global_led_brightness, cfg->global_led_brightness);
    atomic_store(&ctrl->debounce_enabled, cfg->debounce_enabled);

    // Keymap (persistent) – not atomic, protected by mutex when necessary
    memcpy(ctrl->keymap, cfg->keymap, sizeof(ctrl->keymap));

    // Atomics
    atomic_store(&ctrl->emulate_active, cfg->emulate_active);
    atomic_store(&ctrl->is_uhid, cfg->is_uhid);
    atomic_store(&ctrl->led_reapply, cfg->led_reapply);
    atomic_store(&ctrl->rumble_active, cfg->rumble_active);
    atomic_store(&ctrl->invert_ly, cfg->invert_ly);
    atomic_store(&ctrl->invert_ry, cfg->invert_ry);
    atomic_store(&ctrl->sensitivity_left_preset, cfg->sensitivity_left_preset);
    atomic_store(&ctrl->sensitivity_right_preset, cfg->sensitivity_right_preset);
    atomic_store(&ctrl->led_static, (cfg->led_effect == 0));
    atomic_store(&ctrl->led_request_effect, cfg->led_effect);
    atomic_store(&ctrl->led_request_speed, cfg->led_effect_speed);
    atomic_store(&ctrl->led_request_brightness, cfg->led_effect_brightness);
    atomic_store(&ctrl->player_leds, cfg->player_leds);
    atomic_store(&ctrl->led_request_pending, true);
    
    // triggers_digital
    atomic_store(&ctrl->is_trigger_digital, cfg->treat_triggers_as_digital);

    // Request flags (request_*) are NOT restored from profile
    // They remain as they were (already zeroed during slot initialization)
}

/* Converts persistent fields of controller_t to slot_config_t */
void controller_to_slot_config(slot_config_t *cfg, const controller_t *ctrl) {
    // Atomic read of all _Atomic fields
    cfg->led_r = atomic_load(&ctrl->led_r);
    cfg->led_g = atomic_load(&ctrl->led_g);
    cfg->led_b = atomic_load(&ctrl->led_b);
    cfg->led_base_r = atomic_load(&ctrl->led_base_r);
    cfg->led_base_g = atomic_load(&ctrl->led_base_g);
    cfg->led_base_b = atomic_load(&ctrl->led_base_b);
    cfg->rumble_gain = atomic_load(&ctrl->rumble_gain);
    cfg->deadzone = atomic_load(&ctrl->deadzone);
    cfg->global_led_brightness = atomic_load(&ctrl->global_led_brightness);
    cfg->player_leds = atomic_load(&ctrl->player_leds);
    cfg->debounce_enabled = atomic_load(&ctrl->debounce_enabled);

    // Keymap (persistent) – not atomic, direct copy (protected by mutex)
    memcpy(cfg->keymap, ctrl->keymap, sizeof(cfg->keymap));

    cfg->emulate_active = atomic_load(&ctrl->emulate_active);
    cfg->is_uhid = atomic_load(&ctrl->is_uhid);
    cfg->led_reapply = atomic_load(&ctrl->led_reapply);
    cfg->rumble_active = atomic_load(&ctrl->rumble_active);
    cfg->invert_ly = atomic_load(&ctrl->invert_ly);
    cfg->invert_ry = atomic_load(&ctrl->invert_ry);
    cfg->sensitivity_left_preset = atomic_load(&ctrl->sensitivity_left_preset);
    cfg->sensitivity_right_preset = atomic_load(&ctrl->sensitivity_right_preset);

    cfg->led_effect = atomic_load(&ctrl->led_request_effect);
    cfg->led_effect_speed = atomic_load(&ctrl->led_request_speed);
    cfg->led_effect_brightness = atomic_load(&ctrl->led_request_brightness);
    cfg->treat_triggers_as_digital = atomic_load(&ctrl->is_trigger_digital);

    // Request flags (request_*) are NOT saved to profile
}

// ========================================================================
// INPUT NODE DISCOVERY (evdev)
// ========================================================================

int discover_all_input_nodes(const char *hidraw_path, char paths[][PATH_MAX], int max_nodes) {
    const char *hid_name = strrchr(hidraw_path, '/');
    if (hid_name) hid_name++; else hid_name = hidraw_path;

    char *base_path = NULL;
    if (asprintf(&base_path, "/sys/class/hidraw/%s/device", hid_name) < 0) {
        syslog(LOG_ERR, "discover: asprintf failed for base_path");
        return 0;
    }

    char *input_dir_path = NULL;
    if (asprintf(&input_dir_path, "%s/input", base_path) < 0) {
        syslog(LOG_ERR, "discover: asprintf failed for input_dir_path");
        free(base_path);
        return 0;
    }

    DIR *d = opendir(input_dir_path);
    int using_input_subdir = (d != NULL);
    if (!d) {
        free(input_dir_path);
        input_dir_path = NULL;
        d = opendir(base_path);
        if (!d) {
            syslog(LOG_WARNING, "discover: could not open %s", base_path);
            free(base_path);
            return 0;
        }
        syslog(LOG_DEBUG, "discover: using base directory %s", base_path);
    } else {
        syslog(LOG_DEBUG, "discover: using input subdirectory %s", input_dir_path);
    }

    int count = 0;
    struct dirent *dir;
    while ((dir = readdir(d)) != NULL && count < max_nodes) {
        if (dir->d_type != DT_DIR || strcmp(dir->d_name, ".") == 0 || strcmp(dir->d_name, "..") == 0)
            continue;
        if (strncmp(dir->d_name, "input", 5) != 0)
            continue;

        char *inputX_path = NULL;
        if (using_input_subdir) {
            if (asprintf(&inputX_path, "%s/%s", input_dir_path, dir->d_name) < 0)
                continue;
        } else {
            if (asprintf(&inputX_path, "%s/%s", base_path, dir->d_name) < 0)
                continue;
        }

        DIR *d2 = opendir(inputX_path);
        if (!d2) {
            free(inputX_path);
            continue;
        }

        struct dirent *dir2;
        while ((dir2 = readdir(d2)) != NULL && count < max_nodes) {
            if (strncmp(dir2->d_name, "event", 5) == 0) {
                snprintf(paths[count], PATH_MAX, "/dev/input/%s", dir2->d_name);
                count++;
            }
        }
        closedir(d2);
        free(inputX_path);
    }
    closedir(d);

    free(base_path);
    if (input_dir_path) free(input_dir_path);
    return count;
}

// ========================================================================
// SYNCHRONOUS PROFILE REQUESTS
// ========================================================================

bool profile_request_sync(shared_data_t *shm, int request, const char *name,
                          int auto_enable, int auto_delay, char *out_msg, size_t msg_size) {
    if (!shm) return false;
    
    safe_shm_lock(&shm->proc_mutex);
    atomic_store(&shm->profile_request, request);
    if (name) {
        strncpy(shm->profile_name, name, PROFILE_NAME_LEN - 1);
        shm->profile_name[PROFILE_NAME_LEN - 1] = '\0';
    } else {
        shm->profile_name[0] = '\0';
    }
    if (auto_enable >= 0) atomic_store(&shm->auto_save_enabled, auto_enable);
    if (auto_delay >= 0) atomic_store(&shm->auto_save_delay_ms, auto_delay);
    // Clear previous response
    atomic_store(&shm->profile_response, 0);
    shm->profile_response_msg[0] = '\0';
    pthread_mutex_unlock(&shm->proc_mutex);
    
    // Wait for response (1 second timeout)
    const int timeout_ms = 1000;
    const int step_ms = 20;
    int waited = 0;
    while (waited < timeout_ms) {
        usleep(step_ms * 1000);
        waited += step_ms;
        int resp = atomic_load(&shm->profile_response);
        if (resp != 0) {
            safe_shm_lock(&shm->proc_mutex);
            snprintf(out_msg, msg_size, "%s", shm->profile_response_msg);
            atomic_store(&shm->profile_response, 0);
            pthread_mutex_unlock(&shm->proc_mutex);
            return (resp == 1);
        }
    }
    snprintf(out_msg, msg_size, "Timeout waiting for daemon");
    return false;
}

// ========================================================================
// CLEANUP AND TIMERS
// ========================================================================

void cleanup(int sig) {
    (void)sig;
    keep_running = false;
    if (!is_daemon_mode) {
        disable_raw_mode();
    }
    exit(0);
}

double get_monotonic_time_sec(void) {
    struct timespec ts;
    clock_gettime(CLOCK_MONOTONIC, &ts);
    return ts.tv_sec + ts.tv_nsec / 1e9;
}

// ========================================================================
// SAFE_WRITE FUNCTIONS
// ========================================================================

/**
 * get_monotonic_time_us - Returns monotonic time in microseconds
 */
uint64_t get_monotonic_time_us(void) {
    struct timespec ts;
    clock_gettime(CLOCK_MONOTONIC, &ts);
    return (uint64_t)ts.tv_sec * 1000000 + ts.tv_nsec / 1000;
}

/**
 * safe_write - Writes all bytes or fails
 * Performs multiple write calls until all data is written
 * or an error occurs (except EINTR).
 * @return total number of bytes written on success, -1 on error.
 */
ssize_t safe_write(int fd, const void *buf, size_t count) {
    const char *p = (const char*)buf;
    size_t remaining = count;
    while (remaining > 0) {
        ssize_t w = write(fd, p, remaining);
        if (w < 0) {
            if (errno == EINTR) continue;
            return -1;
        }
        if (w == 0) {
            // Unexpected EOF (device closed)
            errno = EPIPE;
            return -1;
        }
        remaining -= w;
        p += w;
    }
    return (ssize_t)count;
}
