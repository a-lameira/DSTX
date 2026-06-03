/*
 * daemon.c - DSTX daemon main loop
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
 * Manages device discovery, worker thread creation,
 * hotplug via inotify.
 */

#include "dstx.h"
#include "led.h"
#include "axes.h"
#include "keys.h"
#include <syslog.h>
#include <dirent.h>
#include <poll.h>
#include <errno.h>
#include <sys/inotify.h>
#include <limits.h>
#include <pthread.h>
#include <sys/time.h>
#include <fcntl.h>
#include <libgen.h>
#include <stdio.h>

// UHID function declarations (defined in uhid.c)
extern int uhid_create(controller_t *slot, int index);
extern void uhid_destroy(int fd);
extern void uhid_handle_events(int fd, controller_t *slot);
extern int uhid_send_input(int fd, const uint8_t *data, size_t size);
extern size_t uhid_build_input_report(controller_t *slot, uint8_t *buf, size_t buf_size);

// Timeout and retry constants
#define POLL_TIMEOUT_MS 100
#define HOTPLUG_RETRY_DELAY_MS 50
#define HOTPLUG_MAX_RETRIES 4
#define HOTPLUG_INITIAL_DELAY_MS 50

// ===== BLUETOOTH CONSTANTS =====
#define BT_CONNECT_RETRY_DELAY_MS 100
#define BT_CONNECT_MAX_RETRIES 20
#define BT_POLL_TIMEOUT_MS 100
#define BT_HANDSHAKE_TIMEOUT_MS 100
#define BT_STABILIZE_DELAY_MS 750

// ===== NSW PRO CONSTANT =====
#define NSW_SLEEP_MS 4

// Maximum input nodes per device
#ifndef MAX_INPUT_NODES
#define MAX_INPUT_NODES 8
#endif

typedef struct {
    int slot_index;
    char path[128];
} thread_args_t;

// --- FREE SLOT BITMAP ---
static int find_free_slot(shared_data_t *shm) {
    for (int i = 0; i < MAX_SLOTS; i++) {
        if (shm->free_slots_bitmap & (1 << i)) {
            return i;
        }
    }
    return -1;
}

static void mark_slot_busy(shared_data_t *shm, int slot) {
    if (slot >= 0 && slot < MAX_SLOTS) {
        shm->free_slots_bitmap &= ~(1 << slot);
    }
}

static void mark_slot_free(shared_data_t *shm, int slot) {
    if (slot >= 0 && slot < MAX_SLOTS) {
        shm->free_slots_bitmap |= (1 << slot);
    }
}

// ===== CHECK BLUETOOTH READINESS =====
static bool is_bt_ready(int fd) {
    struct pollfd pfd = { .fd = fd, .events = POLLIN };
    
    int ret = poll(&pfd, 1, BT_HANDSHAKE_TIMEOUT_MS);
    
    if (ret > 0 && (pfd.revents & POLLIN)) {
        char buf[64];
        ssize_t r = read(fd, buf, sizeof(buf));
        
        if (r > 0) {
            syslog(LOG_DEBUG, "DSTX: Handshake OK - Received %zd bytes", r);
            return true;
        }
    }
    return false;
}

// --- HELPER FUNCTIONS ---
static void try_register_control(const char *path, pthread_t *threads) {
    int fd_check = open(path, O_RDWR | O_NONBLOCK);
    if (fd_check < 0) return;

    struct hidraw_devinfo info;
    if (ioctl(fd_check, HIDIOCGRAWINFO, &info) < 0) {
        close(fd_check);
        return;
    }
    close(fd_check);

    int type = -1;
    if (info.vendor == 0x054c) { 
        if (info.product == 0x09cc || info.product == 0x05c4) type = TYPE_DS4;
        else if (info.product == 0x0ce6) type = TYPE_DUALSENSE;
    } else if (info.vendor == 0x057e && info.product == 0x2009) { 
        type = TYPE_NSW_PRO;
    }
    
    if (type == -1) return;

    safe_shm_lock(&shm_ptr->proc_mutex);

    // Anti-ghost logic: if the same device path is already connected but still accessible, skip.
    for (int i = 0; i < MAX_SLOTS; i++) {
        if (atomic_load(&shm_ptr->slots[i].connected)) {
            if (strcmp(shm_ptr->slots[i].dev_path, path) == 0) {
                if (access(path, F_OK) == 0) {
                    pthread_mutex_unlock(&shm_ptr->proc_mutex);
                    return;
                } else {
                    atomic_store(&shm_ptr->slots[i].connected, false);
                    mark_slot_free(shm_ptr, i);
                }
            }
        }
    }

    int free_slot = find_free_slot(shm_ptr);

    if (free_slot != -1) {
        // ===== BEFORE REUSING THE SLOT, WAIT FOR PREVIOUS THREAD =====
        if (threads[free_slot] != 0) {
            // Release mutex before waiting for old thread to finish
            pthread_mutex_unlock(&shm_ptr->proc_mutex);
            
            int ret = pthread_join(threads[free_slot], NULL);
            if (ret != 0 && ret != ESRCH) {
                syslog(LOG_WARNING, "DSTX: pthread_join on slot %d reuse failed: %s",
                       free_slot, strerror(ret));
            }
            threads[free_slot] = 0;
            
            // Reacquire mutex to continue slot configuration
            safe_shm_lock(&shm_ptr->proc_mutex);
        }

        // ===== SAVE COMPLETE PERSISTENT CONFIGURATION =====
        slot_config_t saved_config;
        controller_to_slot_config(&saved_config, &shm_ptr->slots[free_slot]);

        syslog(LOG_DEBUG, "REGISTER_SAVE_SLOT %d: emulate=%d is_uhid=%d debounce=%d "
               "led_reapply=%d rumble_active=%d invert_ly=%d invert_ry=%d "
               "sensitivity_left=%d sensitivity_right=%d led_effect=%d led_speed=%d player_leds=%d",
               free_slot, saved_config.emulate_active, saved_config.is_uhid,
               saved_config.debounce_enabled, saved_config.led_reapply, saved_config.rumble_active,
               saved_config.invert_ly, saved_config.invert_ry,
               saved_config.sensitivity_left_preset, saved_config.sensitivity_right_preset,
               saved_config.led_effect, saved_config.led_effect_speed, saved_config.player_leds);

        // ===== ZERO THE SLOT (ONLY STATE FIELDS THAT WILL BE RESET) =====
        memset(&shm_ptr->slots[free_slot], 0, sizeof(controller_t));

        // ===== NON-PERSISTENT FIELDS (MUST BE FILLED ON EACH CONNECTION) =====
        snprintf(shm_ptr->slots[free_slot].dev_path, 128, "%s", path);
        shm_ptr->slots[free_slot].type = type;
        shm_ptr->slots[free_slot].is_bluetooth = (info.bustype == 0x05);
        atomic_store(&shm_ptr->slots[free_slot].connected, true);

        // ===== RESTORE ALL PERSISTENT CONFIGURATION =====
        slot_config_to_controller(&saved_config, &shm_ptr->slots[free_slot]);

        syslog(LOG_DEBUG, "REGISTER_RESTORE_SLOT %d: emulate=%d is_uhid=%d debounce=%d "
               "led_reapply=%d rumble_active=%d invert_ly=%d invert_ry=%d "
               "sensitivity_left=%d sensitivity_right=%d led_effect=%d led_speed=%d player_leds=%d",
               free_slot, atomic_load(&shm_ptr->slots[free_slot].emulate_active),
               atomic_load(&shm_ptr->slots[free_slot].is_uhid),
               atomic_load(&shm_ptr->slots[free_slot].debounce_enabled),
               atomic_load(&shm_ptr->slots[free_slot].led_reapply),
               atomic_load(&shm_ptr->slots[free_slot].rumble_active),
               atomic_load(&shm_ptr->slots[free_slot].invert_ly),
               atomic_load(&shm_ptr->slots[free_slot].invert_ry),
               atomic_load(&shm_ptr->slots[free_slot].sensitivity_left_preset),
               atomic_load(&shm_ptr->slots[free_slot].sensitivity_right_preset),
               atomic_load(&shm_ptr->slots[free_slot].led_request_effect),
               atomic_load(&shm_ptr->slots[free_slot].led_request_speed),
               atomic_load(&shm_ptr->slots[free_slot].player_leds));

        // ===== STATE FIELDS THAT ARE NOT PERSISTED (REINITIALIZE) =====
        shm_ptr->slots[free_slot].active_effect_id = -1;
        shm_ptr->slots[free_slot].active_effect_type = 0;
        shm_ptr->slots[free_slot].uinput_fd = -1;
        shm_ptr->slots[free_slot].uhid_fd = -1;
        atomic_store(&shm_ptr->slots[free_slot].external_retry_count, 0);
        memset(&shm_ptr->slots[free_slot].last_external_retry, 0, sizeof(struct timeval));
        atomic_store(&shm_ptr->slots[free_slot].battery, 100);
        shm_ptr->slots[free_slot].output_seq = 0;
        atomic_init(&shm_ptr->slots[free_slot].writing_output, false);

        // ===== WATCHDOG: reset heartbeat and stop flag =====
        atomic_init(&shm_ptr->slots[free_slot].worker_heartbeat, 0ULL);
        atomic_init(&shm_ptr->slots[free_slot].worker_stop, false);

        // Mark led_dirty only if not NSW Pro
        if (type != TYPE_NSW_PRO) {
            atomic_store(&shm_ptr->slots[free_slot].led_dirty, true);
        } else {
            atomic_store(&shm_ptr->slots[free_slot].led_dirty, false);
        }

        // NOTE: emulate_active has already been restored from profile.
        // Do not force 'true' here.

        mark_slot_busy(shm_ptr, free_slot);
        pthread_mutex_unlock(&shm_ptr->proc_mutex);

        thread_args_t *a = malloc(sizeof(thread_args_t));
        if (a) {
            a->slot_index = free_slot;
            snprintf(a->path, 128, "%s", path);
            
            if (pthread_create(&threads[free_slot], NULL, controller_worker, a) != 0) {
                syslog(LOG_ERR, "DSTX: Failed to create thread for slot %d", free_slot);
                safe_shm_lock(&shm_ptr->proc_mutex);
                atomic_store(&shm_ptr->slots[free_slot].connected, false);
                mark_slot_free(shm_ptr, free_slot);
                pthread_mutex_unlock(&shm_ptr->proc_mutex);
                free(a);
                threads[free_slot] = 0;
            }
        }
    } else {
        pthread_mutex_unlock(&shm_ptr->proc_mutex);
        syslog(LOG_WARNING, "DSTX: Slot limit reached.");
    }
}

static void scan_existing_devices(pthread_t *threads) {
    DIR *d = opendir("/dev");
    if (!d) return;
    struct dirent *dir;
    while ((dir = readdir(d)) != NULL) {
        if (strncmp(dir->d_name, "hidraw", 6) == 0) {
            char path[PATH_MAX];
            snprintf(path, sizeof(path), "/dev/%s", dir->d_name);
            try_register_control(path, threads);
        }
    }
    closedir(d);
}

// ===== FUNCTION TO DISCOVER INPUT NODES WITH RETRY =====
static bool discover_input_nodes_with_retry(controller_t *slot, const char *hidraw_path, int max_retries) {
    char input_paths[MAX_INPUT_NODES][PATH_MAX] = { {0} };
    int num_input_nodes = 0;
    int retry_count = 0;
    
    syslog(LOG_INFO, "NSW: Discovering input nodes for %s", hidraw_path);
    
    while (num_input_nodes == 0 && retry_count < max_retries) {
        if (retry_count > 0) {
            usleep(200000);
            syslog(LOG_DEBUG, "NSW: Retrying discovery (attempt %d/%d)", 
                   retry_count + 1, max_retries);
        }
        
        num_input_nodes = discover_all_input_nodes(hidraw_path, input_paths, MAX_INPUT_NODES);
        retry_count++;
    }
    
    if (num_input_nodes == 0) {
        syslog(LOG_ERR, "NSW: Could not find input nodes after %d attempts", max_retries);
        return false;
    }
    
    // Store input nodes
    safe_shm_lock(&shm_ptr->proc_mutex);
    slot->num_input_nodes = 0;
    for (int i = 0; i < num_input_nodes && i < MAX_INPUT_NODES; i++) {
        strcpy(slot->input_nodes[i].path, input_paths[i]);

        int ev_fd = open(input_paths[i], O_RDONLY);
        if (ev_fd >= 0) {
            char ev_name[128];
            if (ioctl(ev_fd, EVIOCGNAME(sizeof(ev_name)), ev_name) >= 0) {
                ev_name[sizeof(ev_name)-1] = '\0';
                size_t copylen = strnlen(ev_name, sizeof(slot->input_nodes[i].name)-1);
                memcpy(slot->input_nodes[i].name, ev_name, copylen);
                slot->input_nodes[i].name[copylen] = '\0';
            } else {
                snprintf(slot->input_nodes[i].name, sizeof(slot->input_nodes[i].name), "Unknown");
            }
            close(ev_fd);
        } else {
            snprintf(slot->input_nodes[i].name, sizeof(slot->input_nodes[i].name), "Inaccessible");
        }
        slot->num_input_nodes++;
    }
    pthread_mutex_unlock(&shm_ptr->proc_mutex);

    for (int i = 0; i < num_input_nodes; i++) {
        syslog(LOG_INFO, "NSW: Input node found: %s - %s", 
               slot->input_nodes[i].path, slot->input_nodes[i].name);
    }
    
    return true;
}

// ===== CONTROLLER WORKER =====
void *controller_worker(void *arg) {
    thread_args_t *args = (thread_args_t *)arg;
    int idx = args->slot_index;
    char path[128];
    snprintf(path, sizeof(path), "%s", args->path);
    free(args);

    // ===== 1. OPEN HIDRAW DEVICE =====
    int fd = open(path, O_RDWR | O_NONBLOCK | O_CLOEXEC);
    if (fd < 0) {
        syslog(LOG_ERR, "DSTX: Failed to open %s: %s", path, strerror(errno));
        safe_shm_lock(&shm_ptr->proc_mutex);
        atomic_store(&shm_ptr->slots[idx].connected, false);
        mark_slot_free(shm_ptr, idx);
        pthread_mutex_unlock(&shm_ptr->proc_mutex);
        return NULL;
    }
    
    // ===== 2. GET INFO AND UPDATE CONNECTION TYPE =====
    struct hidraw_devinfo info;
    if (ioctl(fd, HIDIOCGRAWINFO, &info) == 0) {
        shm_ptr->slots[idx].is_bluetooth = (info.bustype == 0x05);
        syslog(LOG_INFO, "DSTX: Device %s - %s", 
               path, shm_ptr->slots[idx].is_bluetooth ? "Bluetooth" : "USB");
    }

    controller_t *slot = &shm_ptr->slots[idx];
    
    syslog(LOG_DEBUG, "WORKER_START_SLOT %d: emulate=%d is_uhid=%d debounce=%d "
           "led_reapply=%d rumble_active=%d invert_ly=%d invert_ry=%d "
           "sensitivity_left=%d sensitivity_right=%d led_effect=%d led_speed=%d player_leds=%d",
           idx, atomic_load(&slot->emulate_active), atomic_load(&slot->is_uhid),
           atomic_load(&slot->debounce_enabled), atomic_load(&slot->led_reapply), atomic_load(&slot->rumble_active),
           atomic_load(&slot->invert_ly), atomic_load(&slot->invert_ry),
           atomic_load(&slot->sensitivity_left_preset), atomic_load(&slot->sensitivity_right_preset),
           atomic_load(&slot->led_request_effect), atomic_load(&slot->led_request_speed),
           atomic_load(&slot->player_leds));

    // ===== 3. FOR BLUETOOTH: WAIT FOR HID HANDSHAKE =====
    if (shm_ptr->slots[idx].is_bluetooth) {
        syslog(LOG_INFO, "DSTX: Bluetooth detected on %s. Waiting for HID handshake...", path);
        
        bool handshake_ok = false;
        int retries = 0;
        
        while (retries < BT_CONNECT_MAX_RETRIES && !handshake_ok) {
            handshake_ok = is_bt_ready(fd);
            if (!handshake_ok) {
                usleep(BT_CONNECT_RETRY_DELAY_MS * 1000);
            }
            retries++;
        }
        
        if (!handshake_ok) {
            syslog(LOG_ERR, "DSTX: Bluetooth %s did not send HID handshake after %d ms, aborting",
                   path, retries * BT_CONNECT_RETRY_DELAY_MS);
            close(fd);
            safe_shm_lock(&shm_ptr->proc_mutex);
            atomic_store(&shm_ptr->slots[idx].connected, false);
            mark_slot_free(shm_ptr, idx);
            pthread_mutex_unlock(&shm_ptr->proc_mutex);
            return NULL;
        }
        
        syslog(LOG_INFO, "DSTX: Bluetooth %s HID handshake OK after %d ms",
               path, retries * BT_CONNECT_RETRY_DELAY_MS);
        
        // Flush read buffer
        char flush_buf[256];
        while (read(fd, flush_buf, sizeof(flush_buf)) > 0) {}
        
        // Extra stabilization
        syslog(LOG_INFO, "DSTX: Bluetooth: waiting %d ms for stabilization...", BT_STABILIZE_DELAY_MS);
        usleep(BT_STABILIZE_DELAY_MS * 1000);
    }
    
    // ===== METADATA EXTRACTION (FOR ALL TYPES) =====
    // Product name
    char prod[256];
    if (ioctl(fd, HIDIOCGRAWNAME(sizeof(prod)), prod) >= 0) {
        prod[sizeof(prod)-1] = '\0';
        safe_shm_lock(&shm_ptr->proc_mutex);
        size_t copylen = strnlen(prod, sizeof(slot->product_name)-1);
        memcpy(slot->product_name, prod, copylen);
        slot->product_name[copylen] = '\0';
        pthread_mutex_unlock(&shm_ptr->proc_mutex);
        syslog(LOG_INFO, "DSTX: Product name: %s", slot->product_name);
    }
    
    // Serial number
    char uniq[64];
    if (ioctl(fd, HIDIOCGRAWUNIQ(sizeof(uniq)), uniq) >= 0) {
        uniq[sizeof(uniq)-1] = '\0';
        safe_shm_lock(&shm_ptr->proc_mutex);
        size_t copylen = strnlen(uniq, sizeof(slot->uniq)-1);
        memcpy(slot->uniq, uniq, copylen);
        slot->uniq[copylen] = '\0';
        pthread_mutex_unlock(&shm_ptr->proc_mutex);
        syslog(LOG_INFO, "DSTX: Serial number: %s", slot->uniq);
    }
    
    // Driver via sysfs
    const char *hid_name = strrchr(path, '/');
    if (hid_name) hid_name++; else hid_name = path;
    char *sysfs_path = NULL;
    if (asprintf(&sysfs_path, "/sys/class/hidraw/%s/device/uevent", hid_name) >= 0) {
        FILE *f = fopen(sysfs_path, "r");
        if (f) {
            char line[256];
            while (fgets(line, sizeof(line), f)) {
                if (strncmp(line, "DRIVER=", 7) == 0) {
                    line[strcspn(line, "\n")] = 0;
                    safe_shm_lock(&shm_ptr->proc_mutex);
                    size_t copylen = strnlen(line + 7, sizeof(slot->driver)-1);
                    memcpy(slot->driver, line + 7, copylen);
                    slot->driver[copylen] = '\0';
                    pthread_mutex_unlock(&shm_ptr->proc_mutex);
                    syslog(LOG_INFO, "DSTX: Driver: %s", slot->driver);
                    break;
                }
            }
            fclose(f);
        }
        free(sysfs_path);
    }
    
    // ===== 4. FOR NSW PRO: INITIALIZE AND SWITCH TO EVDEV =====
    if (slot->type == TYPE_NSW_PRO) {
        // Discover input nodes
        if (!discover_input_nodes_with_retry(slot, path, 20)) {
            syslog(LOG_ERR, "NSW: Input node discovery failed");
            close(fd);
            safe_shm_lock(&shm_ptr->proc_mutex);
            atomic_store(&shm_ptr->slots[idx].connected, false);
            mark_slot_free(shm_ptr, idx);
            pthread_mutex_unlock(&shm_ptr->proc_mutex);
            return NULL;
        }
        
        // Initialize NSW Pro
        if (!nsw_init(fd, slot)) {
            syslog(LOG_ERR, "DSTX: NSW Pro initialization failed for %s", path);
            close(fd);
            safe_shm_lock(&shm_ptr->proc_mutex);
            atomic_store(&shm_ptr->slots[idx].connected, false);
            mark_slot_free(shm_ptr, idx);
            pthread_mutex_unlock(&shm_ptr->proc_mutex);
            return NULL;
        }
        
        // Close HIDRAW fd - we no longer need it
        close(fd);
        
        // Open event device
        int event_fd = -1;
        for (int i = 0; i < slot->num_input_nodes; i++) {
            if (strstr(slot->input_nodes[i].path, "event") != NULL &&
                strstr(slot->input_nodes[i].name, "IMU") == NULL) {
                event_fd = open(slot->input_nodes[i].path, O_RDWR | O_NONBLOCK);
                if (event_fd >= 0) {
                    syslog(LOG_INFO, "NSW: Opening event device: %s (%s)", 
                           slot->input_nodes[i].path, slot->input_nodes[i].name);
                    break;
                }
            }
        }
        
        // If main event not found, try any event node
        if (event_fd < 0) {
            for (int i = 0; i < slot->num_input_nodes; i++) {
                if (strstr(slot->input_nodes[i].path, "event") != NULL) {
                    event_fd = open(slot->input_nodes[i].path, O_RDWR | O_NONBLOCK);
                    if (event_fd >= 0) {
                        syslog(LOG_INFO, "NSW: Using alternative event node: %s", 
                               slot->input_nodes[i].path);
                        break;
                    }
                }
            }
        }
        
        if (event_fd < 0) {
            syslog(LOG_ERR, "NSW: Could not open event device");
            safe_shm_lock(&shm_ptr->proc_mutex);
            atomic_store(&shm_ptr->slots[idx].connected, false);
            mark_slot_free(shm_ptr, idx);
            pthread_mutex_unlock(&shm_ptr->proc_mutex);
            return NULL;
        }
        
        // Replace main fd with event fd
        fd = event_fd;
        
        // Update path to reflect we are using the event device
        for (int i = 0; i < slot->num_input_nodes; i++) {
            if (strstr(slot->input_nodes[i].path, "event") != NULL) {
                snprintf(slot->dev_path, sizeof(slot->dev_path), "%s", 
                         slot->input_nodes[i].path);
                break;
            }
        }
        
        syslog(LOG_INFO, "NSW: Now using event device fd=%d", fd);
        
    } else {
        // For DS4/DualSense: discover input nodes after stabilization
        char input_paths[MAX_INPUT_NODES][PATH_MAX] = { {0} };
        int num_input_nodes = 0;
        int retry_count = 0;
        const int max_retries = 10;
        
        while (num_input_nodes == 0 && retry_count < max_retries) {
            if (retry_count > 0) {
                usleep(100000);
                syslog(LOG_DEBUG, "DSTX: Retrying input node discovery for %s (attempt %d)", 
                       path, retry_count + 1);
            }
            num_input_nodes = discover_all_input_nodes(path, input_paths, MAX_INPUT_NODES);
            retry_count++;
        }
        
        // Store input nodes
        safe_shm_lock(&shm_ptr->proc_mutex);
        slot->num_input_nodes = 0;
        for (int i = 0; i < num_input_nodes && i < MAX_INPUT_NODES; i++) {
            strcpy(slot->input_nodes[i].path, input_paths[i]);

            int ev_fd = open(input_paths[i], O_RDONLY);
            if (ev_fd >= 0) {
                char ev_name[128];
                if (ioctl(ev_fd, EVIOCGNAME(sizeof(ev_name)), ev_name) >= 0) {
                    ev_name[sizeof(ev_name)-1] = '\0';
                    size_t copylen = strnlen(ev_name, sizeof(slot->input_nodes[i].name)-1);
                    memcpy(slot->input_nodes[i].name, ev_name, copylen);
                    slot->input_nodes[i].name[copylen] = '\0';
                } else {
                    snprintf(slot->input_nodes[i].name, sizeof(slot->input_nodes[i].name), "Unknown");
                }
                close(ev_fd);
            } else {
                snprintf(slot->input_nodes[i].name, sizeof(slot->input_nodes[i].name), "Inaccessible");
            }
            slot->num_input_nodes++;
        }
        pthread_mutex_unlock(&shm_ptr->proc_mutex);

        for (int i = 0; i < num_input_nodes; i++) {
            syslog(LOG_INFO, "DSTX: Input node found: %s - %s", 
                   slot->input_nodes[i].path, slot->input_nodes[i].name);
        }
    }

    int inotify_fd = -1;
    int inotify_wd = -1;
    
    controller_type_t ctype = shm_ptr->slots[idx].type;
    if (ctype == TYPE_DS4 || ctype == TYPE_DUALSENSE) {
        inotify_fd = inotify_init1(IN_NONBLOCK | IN_CLOEXEC);
        if (inotify_fd >= 0) {
            inotify_wd = inotify_add_watch(inotify_fd, path, IN_MODIFY);
            if (inotify_wd < 0) {
                syslog(LOG_ERR, "DSTX: Failed to add watch for %s: %s", path, strerror(errno));
                close(inotify_fd);
                inotify_fd = -1;
            } else {
                syslog(LOG_INFO, "DSTX: Monitoring %s for modifications", path);
            }
        }
    }

    int ufd = -1;
    int uhid_fd = -1;

    unsigned char buf[MAX_BUF];
    struct timeval last_rumble_out = {0};
    struct timeval last_led_out = {0};
    struct timeval last_daemon_write = {0};
    
    struct pollfd fds[3];
    fds[0].fd = fd;
    fds[0].events = POLLIN | POLLHUP | POLLERR;
    fds[1].fd = -1;
    fds[1].events = POLLIN;
    fds[2].fd = inotify_fd;
    fds[2].events = POLLIN;

    syslog(LOG_INFO, "DSTX: Thread started for %s (Slot %d)", 
           (slot->type == TYPE_NSW_PRO) ? slot->dev_path : path, idx);

    // --- Initial output with retry (only for non-NSW) ---
    if (slot->type != TYPE_NSW_PRO) {
        atomic_store(&slot->writing_output, true);
        send_output_report(fd, slot);
        atomic_store(&slot->writing_output, false);
        gettimeofday(&last_daemon_write, NULL);
        
        for (int i = 0; i < 3; i++) {
            usleep(50000);
            atomic_store(&slot->writing_output, true);
            send_output_report(fd, slot);
            atomic_store(&slot->writing_output, false);
            gettimeofday(&last_daemon_write, NULL);
            syslog(LOG_DEBUG, "DSTX: Configuration retry %d for slot %d", i+1, idx);
        }
    }
    
    gettimeofday(&last_rumble_out, NULL);
    gettimeofday(&last_led_out, NULL);
    
    if (slot->type != TYPE_NSW_PRO) {
        uint8_t r = atomic_load(&slot->led_r);
        uint8_t g = atomic_load(&slot->led_g);
        uint8_t b = atomic_load(&slot->led_b);
        syslog(LOG_INFO, "DSTX: Initial configuration sent (4x) for slot %d - LED=%d,%d,%d", 
               idx, r, g, b);
    }

    // ===== TIMER FOR EFFECTS UPDATE =====
    struct timeval last_effects_update = {0};
    gettimeofday(&last_effects_update, NULL);
    
    static pthread_mutex_t requests_mutex = PTHREAD_MUTEX_INITIALIZER;
    bool has_led = (slot->type != TYPE_NSW_PRO);

    // ===== MAIN THREAD LOOP =====
    while (keep_running) {
        // ===== WATCHDOG HEARTBEAT =====
        atomic_store(&slot->worker_heartbeat, get_monotonic_time_us());
        
        // ===== CHECK IF STOP WAS REQUESTED =====
        if (atomic_load(&slot->worker_stop)) {
            syslog(LOG_INFO, "DSTX: Worker thread for slot %d received stop signal", idx);
            break;
        }
        
        bool local_led_dirty = false;
        bool emu_req = false;
        bool use_uhid = false;

        safe_shm_lock(&shm_ptr->proc_mutex);
        bool should_continue = atomic_load(&slot->connected);
        emu_req = atomic_load(&slot->emulate_active);
        use_uhid = atomic_load(&slot->is_uhid);
        if (has_led) {
            local_led_dirty = atomic_load(&slot->led_dirty);
        }
        pthread_mutex_unlock(&shm_ptr->proc_mutex);

        // Periodic log of current values (every ~10 seconds, rate-limited)
        static int loop_counter = 0;
        if (++loop_counter % 100 == 0) {
            log_ratelimit_time(LOG_CAT_WORKER, 5000000, LOG_DEBUG,
                               "WORKER_LOOP_SLOT %d: emulate=%d is_uhid=%d debounce=%d "
                               "led_reapply=%d rumble_active=%d invert_ly=%d invert_ry=%d "
                               "sensitivity_left=%d sensitivity_right=%d led_effect=%d led_speed=%d player_leds=%d",
                               idx, emu_req, use_uhid, atomic_load(&slot->debounce_enabled),
                               atomic_load(&slot->led_reapply), atomic_load(&slot->rumble_active),
                               atomic_load(&slot->invert_ly), atomic_load(&slot->invert_ry),
                               atomic_load(&slot->sensitivity_left_preset), atomic_load(&slot->sensitivity_right_preset),
                               atomic_load(&slot->led_request_effect), atomic_load(&slot->led_request_speed),
                               atomic_load(&slot->player_leds));
        }

        if (!should_continue) break;

        // ===== PROCESS LAYOUT REQUESTS (one-shot) =====
        safe_shm_lock(&shm_ptr->proc_mutex);
        if (atomic_exchange(&slot->request_switch_layout, false)) {
            keys_set_switch_layout(slot);
            atomic_store(&slot->led_dirty, true);
            syslog(LOG_INFO, "Switch layout applied on slot %d", idx);
        }
        if (atomic_exchange(&slot->request_xbox_layout, false)) {
            keys_set_xbox_layout(slot);
            atomic_store(&slot->led_dirty, true);
            syslog(LOG_INFO, "Xbox layout applied on slot %d", idx);
        }
        if (atomic_exchange(&slot->request_reset_all_keybinds, false)) {
            keys_reset_all_keybinds(slot);
            atomic_store(&slot->led_dirty, true);
            syslog(LOG_INFO, "Full keybind reset applied on slot %d", idx);
        }
        pthread_mutex_unlock(&shm_ptr->proc_mutex);

        // ===== NSW PRO MONITORING - TERMINATE THREAD IF DISCONNECTED =====
        if (slot->type == TYPE_NSW_PRO) {
            if (!nsw_monitor(slot, fd)) {
                syslog(LOG_WARNING, "DSTX: NSW Pro slot %d disconnected, terminating thread", idx);
                break;
            }
        }

        // ===== VIRTUAL DEVICE MANAGEMENT =====
        if (emu_req) {
            if (use_uhid) {
                if (ufd >= 0) {
                    syslog(LOG_WARNING, "DSTX: UINPUT still exists while creating UHID - destroying");
                    ioctl(ufd, UI_DEV_DESTROY);
                    close(ufd);
                    ufd = -1;
                    slot->uinput_fd = -1;
                }
                
                if (uhid_fd < 0) {
                    uhid_fd = uhid_create(slot, idx);
                    if (uhid_fd >= 0) {
                        fds[1].fd = uhid_fd;
                        fds[1].events = POLLIN;
                        safe_shm_lock(&shm_ptr->proc_mutex);
                        slot->uhid_fd = uhid_fd;
                        pthread_mutex_unlock(&shm_ptr->proc_mutex);
                        syslog(LOG_INFO, "DSTX: UHID created for slot %d (fd=%d)", idx, uhid_fd);
                        
                        // ===== UHID SUPPORT FOR NSW PRO =====
                        if (slot->type == TYPE_NSW_PRO) {
                            nsw_set_uhid_fd(slot, uhid_fd);
                        }
                    }
                }
            } else {
                if (uhid_fd >= 0) {
                    // ===== UHID SUPPORT FOR NSW PRO (BEFORE DESTROY) =====
                    if (slot->type == TYPE_NSW_PRO) {
                        nsw_set_uhid_fd(slot, -1);
                    }
                    
                    syslog(LOG_WARNING, "DSTX: UHID still exists while creating uinput - destroying");
                    uhid_destroy(uhid_fd);
                    uhid_fd = -1;
                    slot->uhid_fd = -1;
                }
                
                if (ufd < 0) {
                    ufd = setup_uinput_indexed(idx, slot);
                    if (ufd >= 0) {
                        fds[1].fd = ufd;
                        fds[1].events = POLLIN;
                        safe_shm_lock(&shm_ptr->proc_mutex);
                        slot->uinput_fd = ufd;
                        pthread_mutex_unlock(&shm_ptr->proc_mutex);
                        syslog(LOG_INFO, "DSTX: uinput created for slot %d (fd=%d)", idx, ufd);
                    }
                }
            }
        } else {
            if (ufd >= 0) {
                syslog(LOG_INFO, "DSTX: Destroying uinput for slot %d", idx);
                ioctl(ufd, UI_DEV_DESTROY);
                close(ufd);
                ufd = -1;
                fds[1].fd = -1;
                safe_shm_lock(&shm_ptr->proc_mutex);
                slot->uinput_fd = -1;
                pthread_mutex_unlock(&shm_ptr->proc_mutex);
            }
            if (uhid_fd >= 0) {
                // ===== UHID SUPPORT FOR NSW PRO (BEFORE DESTROY) =====
                if (slot->type == TYPE_NSW_PRO) {
                    nsw_set_uhid_fd(slot, -1);
                }
                
                syslog(LOG_INFO, "DSTX: Destroying UHID for slot %d", idx);
                uhid_destroy(uhid_fd);
                uhid_fd = -1;
                fds[1].fd = -1;
                safe_shm_lock(&shm_ptr->proc_mutex);
                slot->uhid_fd = -1;
                pthread_mutex_unlock(&shm_ptr->proc_mutex);
            }
        }

        // ===== EFFECTS PROCESSING =====
        struct timeval now;
        gettimeofday(&now, NULL);
        long effects_elapsed = (now.tv_sec - last_effects_update.tv_sec) * 1000000L +
                               (now.tv_usec - last_effects_update.tv_usec);
        
        if (has_led && effects_elapsed >= LEDFX_UPDATE_INTERVAL_US) {
            if (pthread_mutex_trylock(&requests_mutex) == 0) {
                ledfx_process_requests();
                pthread_mutex_unlock(&requests_mutex);
            }
            double current_time = get_monotonic_time_sec();
            ledfx_update_slot(idx, current_time);
            last_effects_update = now;
        }

        // ===== MAIN POLL =====
        int poll_ret;
        
        if (slot->type == TYPE_NSW_PRO) {
            // NSW Pro: monitor both evdev and uinput/UHID
            int nfds = 1;
            if (ufd >= 0 || uhid_fd >= 0) nfds = 2;
            
            struct pollfd nsw_fds[2];
            nsw_fds[0].fd = fd;
            nsw_fds[0].events = POLLIN | POLLHUP | POLLERR;
            nsw_fds[1].fd = (ufd >= 0) ? ufd : (uhid_fd >= 0) ? uhid_fd : -1;
            nsw_fds[1].events = POLLIN;
            
            poll_ret = poll(nsw_fds, nfds, 0);
            
            if (poll_ret > 0) {
                // Data from evdev device (controller inputs)
                if (nsw_fds[0].revents & POLLIN) {
                    // Protect access to keymap, deadzone, invert_*, etc.
                    safe_shm_lock(&shm_ptr->proc_mutex);
                    nsw_read_events(slot, use_uhid ? uhid_fd : ufd);
                    pthread_mutex_unlock(&shm_ptr->proc_mutex);
                }
                
                // Rumble events from uinput/UHID
                if (nsw_fds[1].revents & POLLIN) {
                    if (ufd >= 0) {
                        struct input_event ev;
                        if (read(ufd, &ev, sizeof(ev)) > 0) {
                            safe_shm_lock(&shm_ptr->proc_mutex);
                            if (ev.type == EV_UINPUT && ev.code == UI_FF_UPLOAD) {
                                rumble_handle_ff_upload(ufd, &ev, slot);
                            } else {
                                rumble_handle_ff_event(&ev, slot);
                            }
                            pthread_mutex_unlock(&shm_ptr->proc_mutex);
                        }
                    }
                    if (uhid_fd >= 0) {
                        uhid_handle_events(uhid_fd, slot);
                    }
                }
                
                // Detect disconnection
                if (nsw_fds[0].revents & (POLLHUP | POLLERR)) {
                    break;
                }
            }
            
            // Fixed sleep to avoid busy-wait
            usleep(NSW_SLEEP_MS * 1000);
            
            // Skip DS4/DualSense poll processing
            goto after_poll_processing;
            
        } else {
            // DS4/DualSense: original behavior
            int nfds = 1;
            if (ufd >= 0 || uhid_fd >= 0) nfds = 2;
            if (inotify_fd >= 0) nfds = 3;
            
            int poll_timeout = shm_ptr->slots[idx].is_bluetooth ? BT_POLL_TIMEOUT_MS : POLL_TIMEOUT_MS;
            poll_ret = poll(fds, nfds, poll_timeout);
        }
        
        if (poll_ret < 0) {
            if (errno == EINTR) continue;
            syslog(LOG_ERR, "DSTX: poll() failed: %s", strerror(errno));
            break;
        }

        if (poll_ret > 0) {
            if (inotify_fd >= 0 && (fds[2].revents & POLLIN)) {
                char buffer[4096] __attribute__ ((aligned(__alignof__(struct inotify_event))));
                ssize_t len = read(inotify_fd, buffer, sizeof(buffer));
                if (len > 0) {
                    for (char *ptr = buffer; ptr < buffer + len; ) {
                        struct inotify_event *event = (struct inotify_event *)ptr;
                        if (event->mask & IN_MODIFY) {
                            struct timeval now;
                            gettimeofday(&now, NULL);
                            long elapsed_us = (now.tv_sec - last_daemon_write.tv_sec) * 1000000L + 
                                              (now.tv_usec - last_daemon_write.tv_usec);
                            
                            if (!atomic_load(&slot->writing_output) && elapsed_us > 50000) {
                                usleep(5000);
                                
                                safe_shm_lock(&shm_ptr->proc_mutex);
                                
                                if (!atomic_load(&slot->led_reapply)) {
                                    log_ratelimit_time(LOG_CAT_DRIVER, 5000000, LOG_DEBUG,
                                                       "INOTIFY: External intervention IGNORED (reapply=off) on slot %d", idx);
                                    pthread_mutex_unlock(&shm_ptr->proc_mutex);
                                    ptr += sizeof(struct inotify_event) + event->len;
                                    continue;
                                }
                                
                                if (has_led && atomic_load(&slot->led_static)) {
                                    atomic_store(&slot->external_retry_count, 10);
                                    gettimeofday(&slot->last_external_retry, NULL);
                                    atomic_store(&slot->led_dirty, true);
                                    log_ratelimit_time(LOG_CAT_DRIVER, 5000000, LOG_DEBUG,
                                                       "INOTIFY: External intervention on slot %d (static mode) – starting 10 retries", idx);
                                } else if (has_led) {
                                    log_ratelimit_time(LOG_CAT_DRIVER, 5000000, LOG_DEBUG,
                                                       "INOTIFY: External intervention on slot %d ignored (effect mode)", idx);
                                }
                                
                                pthread_mutex_unlock(&shm_ptr->proc_mutex);
                            }
                        }
                        ptr += sizeof(struct inotify_event) + event->len;
                    }
                }
            }

            if (fds[0].revents & (POLLIN | POLLHUP | POLLERR)) {
                if (slot->type == TYPE_NSW_PRO) {
                    // Already handled above
                } else {
                    int n = read(fd, buf, sizeof(buf));
                    if (n > 0) {
                        struct timeval now;
                        gettimeofday(&now, NULL);
                        
                        int target_fd = use_uhid ? uhid_fd : ufd;
                        
                        safe_shm_lock(&shm_ptr->proc_mutex);
                        if (slot->type == TYPE_DS4) translate_ds4(buf, slot, target_fd);
                        else if (slot->type == TYPE_DUALSENSE) translate_dualsense(buf, slot, target_fd);
                        pthread_mutex_unlock(&shm_ptr->proc_mutex);
                        
                        if (use_uhid && uhid_fd >= 0) {
                            uint8_t uhid_report[64];
                            size_t report_size = uhid_build_input_report(slot, uhid_report, sizeof(uhid_report));
                            if (report_size > 0) {
                                uhid_send_input(uhid_fd, uhid_report, report_size);
                            }
                        }
                    } else if (n == 0 || (n < 0 && errno != EAGAIN && errno != EWOULDBLOCK)) {
                        break;
                    }
                }
            }
            
            if (ufd >= 0 && (fds[1].revents & POLLIN)) {
                struct input_event ev;
                if (read(ufd, &ev, sizeof(ev)) > 0) {
                    safe_shm_lock(&shm_ptr->proc_mutex);
                    if (ev.type == EV_UINPUT && ev.code == UI_FF_UPLOAD) {
                        rumble_handle_ff_upload(ufd, &ev, slot);
                        pthread_mutex_unlock(&shm_ptr->proc_mutex);
                    } else {
                        rumble_handle_ff_event(&ev, slot);
                        pthread_mutex_unlock(&shm_ptr->proc_mutex);
                    }
                }
            }
            
            if (uhid_fd >= 0 && (fds[1].revents & POLLIN)) {
                uhid_handle_events(uhid_fd, slot);
            }
        }

after_poll_processing:
        // ===== RUMBLE PIPELINE =====
        bool rumble_wrote = rumble_process_pipeline(fd, slot, &last_rumble_out);
        bool led_wrote = false;
        if (has_led && local_led_dirty) {
            led_wrote = led_process_pipeline(fd, slot, &last_led_out);
        }

        if (rumble_wrote || led_wrote) {
            gettimeofday(&last_daemon_write, NULL);
        }
    }

    // ===== CLEANUP - THREAD WILL BE TERMINATED =====
    syslog(LOG_INFO, "DSTX: Terminating thread for slot %d", idx);
    
    if (slot->type == TYPE_NSW_PRO) {
        nsw_cleanup(slot);
    }
    
    if (inotify_fd >= 0) {
        if (inotify_wd >= 0) inotify_rm_watch(inotify_fd, inotify_wd);
        close(inotify_fd);
    }
    if (ufd >= 0) { 
        ioctl(ufd, UI_DEV_DESTROY); 
        close(ufd); 
    }
    if (uhid_fd >= 0) {
        uhid_destroy(uhid_fd);
    }
    
    close(fd);
    
    safe_shm_lock(&shm_ptr->proc_mutex);
    atomic_store(&slot->connected, false);
    slot->uinput_fd = -1;
    slot->uhid_fd = -1;
    memset(slot->dev_path, 0, sizeof(slot->dev_path));
    mark_slot_free(shm_ptr, idx);
    pthread_mutex_unlock(&shm_ptr->proc_mutex);
    
    syslog(LOG_INFO, "DSTX: Thread for slot %d terminated", idx);
    return NULL;
}

void run_daemon_loop(void) {
    if (!shm_ptr) return;

    ledfx_init();
    syslog(LOG_INFO, "LEDFX: Effect system initialized");

    // The profile system is managed by a singleton thread (settings.c).
    // The active profile has already been loaded and applied to SHM during initialization.
    // No additional call is needed here.

    safe_shm_lock(&shm_ptr->proc_mutex);
    pid_t my_pid = getpid();
    atomic_store(&shm_ptr->daemon_pid, my_pid);
    atomic_store(&shm_ptr->heartbeat, 1);
    syslog(LOG_INFO, "DSTX: Daemon ready - PID=%d, heartbeat=1", my_pid);
    pthread_mutex_unlock(&shm_ptr->proc_mutex);

    // Initialize free slot bitmap (now inside SHM)
    shm_ptr->free_slots_bitmap = 0xFF;
    
    for (int i = 0; i < MAX_SLOTS; i++) {
        atomic_store(&shm_ptr->slots[i].connected, false);
        shm_ptr->slots[i].uinput_fd = -1;
        shm_ptr->slots[i].uhid_fd = -1;
        atomic_store(&shm_ptr->slots[i].battery, 100);
        shm_ptr->slots[i].output_seq = 0;
        atomic_store(&shm_ptr->slots[i].external_retry_count, 0);
        memset(&shm_ptr->slots[i].last_external_retry, 0, sizeof(struct timeval));
        atomic_init(&shm_ptr->slots[i].writing_output, false);
        // Initialize watchdog heartbeat and stop flag
        atomic_init(&shm_ptr->slots[i].worker_heartbeat, 0ULL);
        atomic_init(&shm_ptr->slots[i].worker_stop, false);
        if (shm_ptr->slots[i].type != TYPE_NSW_PRO) {
            atomic_store(&shm_ptr->slots[i].led_dirty, true);
        } else {
            atomic_store(&shm_ptr->slots[i].led_dirty, false);
        }
    }

    pthread_t threads[MAX_SLOTS] = {0};
    int inotify_fd = inotify_init1(IN_NONBLOCK | IN_CLOEXEC);
    if (inotify_fd < 0) {
        syslog(LOG_ERR, "DSTX: inotify error (%s). Aborting.", strerror(errno));
        return;
    }
    
    if (inotify_add_watch(inotify_fd, "/dev", IN_CREATE) < 0) {
        syslog(LOG_WARNING, "DSTX: Hotplug disabled (inotify error on /dev)");
    }

    scan_existing_devices(threads); 

    struct pollfd pfd = { .fd = inotify_fd, .events = POLLIN };
    syslog(LOG_INFO, "DSTX: Loop started.");

    while (keep_running) {
        atomic_fetch_add(&shm_ptr->heartbeat, 1);

        // ===== WATCHDOG: monitor worker threads and restart if necessary =====
        uint64_t now_us = get_monotonic_time_us();
        for (int i = 0; i < MAX_SLOTS; i++) {
            if (threads[i] != 0) {
                uint64_t hb = atomic_load(&shm_ptr->slots[i].worker_heartbeat);
                if (hb != 0 && (now_us - hb) > WORKER_HEARTBEAT_TIMEOUT_US) {
                    syslog(LOG_WARNING, "DSTX: Worker thread for slot %d stuck (heartbeat expired). Restarting...", i);
                    // Signal thread to stop and wait
                    atomic_store(&shm_ptr->slots[i].worker_stop, true);
                    pthread_join(threads[i], NULL);
                    threads[i] = 0;
                    atomic_store(&shm_ptr->slots[i].worker_stop, false);
                    atomic_store(&shm_ptr->slots[i].connected, false);
                    mark_slot_free(shm_ptr, i);
                    
                    // Check if device still exists and try to recreate
                    const char *dev_path = shm_ptr->slots[i].dev_path;
                    if (dev_path[0] != '\0' && access(dev_path, F_OK) == 0) {
                        syslog(LOG_INFO, "DSTX: Trying to recreate thread for slot %d (device %s)", i, dev_path);
                        try_register_control(dev_path, threads);
                    } else {
                        syslog(LOG_WARNING, "DSTX: Device for slot %d no longer present, not recreating", i);
                    }
                }
            }
        }

        // Check slots with lost connection (existing)
        for (int i = 0; i < MAX_SLOTS; i++) {
            if (threads[i] != 0) {
                safe_shm_lock(&shm_ptr->proc_mutex);
                bool still_conn = atomic_load(&shm_ptr->slots[i].connected);
                pthread_mutex_unlock(&shm_ptr->proc_mutex);
                if (!still_conn) {
                    int ret = pthread_join(threads[i], NULL);
                    if (ret != 0 && ret != ESRCH) {
                        syslog(LOG_WARNING, "DSTX: pthread_join failed on slot %d: %s", i, strerror(ret));
                    }
                    threads[i] = 0;
                }
            }
        }

        int ret = poll(&pfd, 1, 200); 
        if (ret > 0 && (pfd.revents & POLLIN)) {
            char buffer[4096] __attribute__ ((aligned(__alignof__(struct inotify_event))));
            ssize_t len = read(inotify_fd, buffer, sizeof(buffer));
            if (len > 0) {
                for (char *ptr = buffer; ptr < buffer + len; ) {
                    struct inotify_event *event = (struct inotify_event *)ptr;
                    if (event->len && strstr(event->name, "hidraw")) {
                        int retry_count = 0;
                        bool registered = false;
                        
                        while (retry_count < HOTPLUG_MAX_RETRIES && !registered) {
                            if (retry_count > 0) {
                                usleep(HOTPLUG_RETRY_DELAY_MS * 1000);
                            }
                            
                            char path[PATH_MAX];
                            snprintf(path, sizeof(path), "/dev/%s", event->name);
                            
                            int test_fd = open(path, O_RDWR | O_NONBLOCK);
                            if (test_fd >= 0) {
                                close(test_fd);
                                try_register_control(path, threads);
                                registered = true;
                                syslog(LOG_DEBUG, "DSTX: Device %s registered", event->name);
                            }
                            retry_count++;
                        }
                    }
                    ptr += sizeof(struct inotify_event) + event->len;
                }
            }
        }
    }

    syslog(LOG_INFO, "DSTX: Shutting down daemon.");

    // Wait for all active threads before exiting
    for (int i = 0; i < MAX_SLOTS; i++) {
        if (threads[i] != 0) {
            pthread_join(threads[i], NULL);
            threads[i] = 0;
        }
    }

    ledfx_cleanup();
    
    safe_shm_lock(&shm_ptr->proc_mutex);
    atomic_store(&shm_ptr->daemon_pid, 0);
    atomic_store(&shm_ptr->heartbeat, 0);
    for (int i = 0; i < MAX_SLOTS; i++) {
        atomic_store(&shm_ptr->slots[i].connected, false);
    }
    pthread_mutex_unlock(&shm_ptr->proc_mutex);
    close(inotify_fd);
}
