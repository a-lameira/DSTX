/*
 * nsw.c - Nintendo Switch Pro Controller support via evdev
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
 * - Uses the kernel hid-nintendo driver for communication
 * - Reads events from /dev/input/eventX
 * - Writes rumble via ioctl EVIOCSFF on the same fd
 * - Inotify for immediate disconnection detection
 * - Rate limiting to avoid duplicate commands
 * - Keybind support (button remapping) via keymap system
 * - Per-slot context cache for stability
 * - Rate limiting when forwarding to uinput
 * - PREVENTION AGAINST DOUBLE INITIALIZATION
 * - ROBUST UINPUT ERROR HANDLING
 * - UHID SUPPORT (Nintendo Switch Pro)
 * - BLUETOOTH OFFSET CORRECTION (kernel bug)
 * - Digital trigger mode support (L2/R2) via is_trigger_digital flag
 * - Capture button (BTN_Z) mapped to PHY_BTN_TOUCH
 */

#include "dstx.h"
#include "axes.h"
#include "keys.h"
#include <linux/input.h>
#include <sys/ioctl.h>
#include <poll.h>
#include <errno.h>
#include <fcntl.h>
#include <dirent.h>
#include <sys/inotify.h>
#include <limits.h>
#include <math.h>
#include <string.h>

// Macro to test bits
#define test_bit(nr, addr) \
    (((1UL << ((nr) % (sizeof(unsigned long) * 8))) & \
      ((addr)[(nr) / (sizeof(unsigned long) * 8)])) != 0)

// ========================================================================
// CONSTANTS
// ========================================================================
#define NSW_INOTIFY_BUFFER_SIZE     4096
#define NSW_MAX_EFFECTS              16
#define NSW_FF_GAIN               0xFFFF
#define NSW_RUMBLE_RATE_LIMIT_US   50000  // 50ms minimum between rumble commands
#define NSW_UINPUT_RATE_LIMIT_US   4000   // 4ms minimum between uinput events
#define NSW_MAX_RUMBLE_LOGS          5    // Maximum rumble logs per second

// Fixed offsets for Bluetooth connection (empirical average values)
// X: add; Y: subtract
#define NSW_BT_OFFSET_LX 2545
#define NSW_BT_OFFSET_LY 2978
#define NSW_BT_OFFSET_RX 2438
#define NSW_BT_OFFSET_RY 2873

// ========================================================================
// INTERNAL STRUCTURES (COMPLETELY PRIVATE)
// ========================================================================

typedef struct {
    int event_fd;                    // /dev/input/eventX file descriptor
    int inotify_fd;                  // inotify file descriptor
    int inotify_wd;                  // inotify watch descriptor
    int effect_id;                   // ID of active rumble effect
    bool connected;                  // Connection state
    bool initialized;                // Whether initialized
    char event_path[PATH_MAX];       // Event device path
    int slot_index;                  // Slot index (for logging)
    
    // Cache of last rumble sent
    uint8_t last_strong;             // Last strong value sent
    uint8_t last_weak;               // Last weak value sent
    struct timeval last_rumble_time; // Time of last rumble command
    int rumble_log_count;            // Counter for log rate limiting
    struct timeval last_rumble_log_time; // Last time rumble was logged
    
    // Cache of last state sent to uinput
    uint8_t last_cross, last_circle, last_square, last_triangle;
    uint8_t last_l1, last_r1, last_l2, last_r2;
    uint8_t last_share, last_options, last_ps, last_l3, last_r3;
    int16_t last_lx, last_ly, last_rx, last_ry;
    int16_t last_lt, last_rt;
    int last_hatx, last_haty;
    
    // Rate limiting for uinput
    struct timeval last_uinput_time;
    
    // Prevention against double initialization
    bool is_active;                  // Whether thread is active
    pid_t thread_pid;                // Thread PID (for debugging)
    
    // ===== UHID SUPPORT =====
    int uhid_fd;                     // UHID fd (-1 if not used)
    
    // ===== STICK VALUES (already normalized by kernel) =====
    int16_t lx, ly, rx, ry;
    
    // ===== RAW PHYSICAL BUTTON STATE (persistent across calls) =====
    uint8_t phy_raw[PHY_BTN_COUNT];
} nsw_context_t;

// Global context (one per slot) - COMPLETELY PRIVATE TO THIS FILE
static nsw_context_t g_nsw_contexts[MAX_SLOTS] = {0};

// Counters for diagnostic logs (not reentrant, but sufficient for debugging)
static int rumble_log_counter = 0;
static int read_events_counter = 0;
static int keymap_counter = 0;
#define RUMBLE_LOG_RATE 10
#define READ_LOG_RATE 100
#define KEYMAP_LOG_RATE 100

// ========================================================================
// STATIC HELPER FUNCTIONS
// ========================================================================

static inline int get_slot_index(controller_t *slot)
{
    return (int)(slot - shm_ptr->slots);
}

static inline nsw_context_t *get_context(controller_t *slot)
{
    int idx = get_slot_index(slot);
    if (idx < 0 || idx >= MAX_SLOTS) return NULL;
    return &g_nsw_contexts[idx];
}

/**
 * clamp_u8 - Ensures an integer value is within uint8_t range
 */
static inline uint8_t clamp_u8(int val, uint8_t min, uint8_t max, uint8_t def)
{
    if (val < min || val > max) return def;
    return (uint8_t)val;
}

/**
 * should_log_rumble - Rate limiting for rumble logs
 */
static inline bool should_log_rumble(nsw_context_t *ctx)
{
    struct timeval now;
    gettimeofday(&now, NULL);
    
    long elapsed_us = (now.tv_sec - ctx->last_rumble_log_time.tv_sec) * 1000000L +
                      (now.tv_usec - ctx->last_rumble_log_time.tv_usec);
    
    if (elapsed_us > 1000000) { // 1 second
        ctx->rumble_log_count = 0;
        ctx->last_rumble_log_time = now;
    }
    
    if (ctx->rumble_log_count < NSW_MAX_RUMBLE_LOGS) {
        ctx->rumble_log_count++;
        return true;
    }
    
    return false;
}

/**
 * nsw_find_evdev_device - Finds the NSW Pro evdev device
 * @param slot: Pointer to slot (to fill input_nodes)
 * @return file descriptor of the device, or -1 if not found
 */
static int nsw_find_evdev_device(controller_t *slot)
{
    DIR *dir = opendir("/dev/input");
    if (!dir) {
        syslog(LOG_ERR, "NSW: Could not open /dev/input");
        return -1;
    }

    struct dirent *entry;
    int found_fd = -1;
    int event_index = 0;

    syslog(LOG_INFO, "NSW: Looking for Pro Controller device...");

    while ((entry = readdir(dir)) != NULL) {
        if (strncmp(entry->d_name, "event", 5) != 0)
            continue;

        char path[PATH_MAX];
        snprintf(path, sizeof(path), "/dev/input/%s", entry->d_name);

        int fd = open(path, O_RDWR | O_NONBLOCK);
        if (fd < 0) continue;

        // Get device name
        char name[256];
        if (ioctl(fd, EVIOCGNAME(sizeof(name)), name) < 0) {
            close(fd);
            continue;
        }

        // Check if it's a Pro Controller (ignore IMU devices)
        bool is_pro_controller = false;
        
        if (strstr(name, "Pro Controller") != NULL && strstr(name, "IMU") == NULL) {
            is_pro_controller = true;
        } else if (strstr(name, "Nintendo") != NULL && 
                   strstr(name, "Controller") != NULL &&
                   strstr(name, "IMU") == NULL) {
            is_pro_controller = true;
        }

        if (is_pro_controller) {
            syslog(LOG_INFO, "NSW: Found: %s - %s", path, name);
            
            // Store in SHM for future reference
            if (slot && event_index < MAX_INPUT_NODES) {
                snprintf(slot->input_nodes[event_index].path, PATH_MAX, "%s", path);
                
                int len = snprintf(slot->input_nodes[event_index].name, 
                                   sizeof(slot->input_nodes[event_index].name), 
                                   "%s", name);
                if (len >= (int)sizeof(slot->input_nodes[event_index].name)) {
                    syslog(LOG_DEBUG, "NSW: Device name truncated");
                }
                
                slot->num_input_nodes = event_index + 1;
            }
            
            found_fd = fd;
            event_index++;
            break; // Take only the first non-IMU device
        } else {
            close(fd);
        }
    }

    closedir(dir);
    
    if (found_fd >= 0) {
        syslog(LOG_INFO, "NSW: Event device found (fd=%d)", found_fd);
    } else {
        syslog(LOG_ERR, "NSW: No Pro Controller device found");
    }
    
    return found_fd;
}

/**
 * nsw_setup_inotify - Configures inotify monitoring for the device
 * @param ctx: NSW context
 * @return true if configured successfully
 */
static bool nsw_setup_inotify(nsw_context_t *ctx)
{
    ctx->inotify_fd = inotify_init1(IN_NONBLOCK | IN_CLOEXEC);
    if (ctx->inotify_fd < 0) {
        syslog(LOG_WARNING, "NSW: Failed to create inotify: %s", strerror(errno));
        return false;
    }

    // Monitor the directory containing the device
    char dir_path[PATH_MAX];
    strncpy(dir_path, ctx->event_path, sizeof(dir_path)-1);
    dir_path[sizeof(dir_path)-1] = '\0';
    char *last_slash = strrchr(dir_path, '/');
    if (last_slash) {
        *last_slash = '\0';
    } else {
        strcpy(dir_path, "/dev/input");
    }

    ctx->inotify_wd = inotify_add_watch(ctx->inotify_fd, dir_path, IN_DELETE);
    if (ctx->inotify_wd < 0) {
        syslog(LOG_WARNING, "NSW: Failed to add inotify watch: %s", strerror(errno));
        close(ctx->inotify_fd);
        ctx->inotify_fd = -1;
        return false;
    }

    syslog(LOG_INFO, "NSW: Inotify configured for %s", dir_path);
    return true;
}

/**
 * nsw_check_inotify - Checks if the device has been removed
 * @param ctx: NSW context
 * @return true if the device was removed
 */
static bool nsw_check_inotify(nsw_context_t *ctx)
{
    if (ctx->inotify_fd < 0) return false;

    char buffer[NSW_INOTIFY_BUFFER_SIZE] __attribute__ ((aligned(__alignof__(struct inotify_event))));
    ssize_t len = read(ctx->inotify_fd, buffer, sizeof(buffer));
    
    if (len <= 0) return false;

    for (char *ptr = buffer; ptr < buffer + len; ) {
        struct inotify_event *event = (struct inotify_event *)ptr;
        
        if (event->wd == ctx->inotify_wd && (event->mask & IN_DELETE)) {
            if (strstr(ctx->event_path, event->name) != NULL) {
                syslog(LOG_INFO, "NSW: Device %s was removed", event->name);
                return true;
            }
        }
        
        ptr += sizeof(struct inotify_event) + event->len;
    }
    
    return false;
}

/**
 * clamp_axis - Keeps values within allowed range (-32768..32767)
 */
static inline int16_t clamp_axis(int32_t val) {
    if (val > 32767) return 32767;
    if (val < -32768) return -32768;
    return (int16_t)val;
}

/**
 * nsw_apply_transforms - Applies transforms to axes, including BT correction
 * @param slot: Pointer to slot
 * @param ctx: NSW context
 *
 * The kernel already provides values in the correct standard (Y positive = down).
 * For Bluetooth, fixed offsets are applied to correct a kernel bug.
 * For USB, no correction is applied.
 */
static void nsw_apply_transforms(controller_t *slot, nsw_context_t *ctx)
{
    if (!slot || !ctx) return;
    
    // Raw stick values (read from evdev and kept in context)
    int16_t lx = ctx->lx;
    int16_t ly = ctx->ly;
    int16_t rx = ctx->rx;
    int16_t ry = ctx->ry;
    
    // === BLUETOOTH CORRECTION (fixed offset) ===
    if (slot->is_bluetooth) {
        lx = clamp_axis(lx + NSW_BT_OFFSET_LX);
        ly = clamp_axis(ly - NSW_BT_OFFSET_LY);
        rx = clamp_axis(rx + NSW_BT_OFFSET_RX);
        ry = clamp_axis(ry - NSW_BT_OFFSET_RY);
    }
    
    // Store normalized values
    slot->LX = lx;
    slot->LY = ly;
    slot->RX = rx;
    slot->RY = ry;
    
    // === APPLY SENSITIVITY ===
    apply_sensitivity_left(slot, &slot->LX, &slot->LY);
    apply_sensitivity_right(slot, &slot->RX, &slot->RY);
    
    // === USER-CONFIGURABLE Y-AXIS INVERSION (already normalized as boolean) ===
    bool invert_ly = (atomic_load(&slot->invert_ly) != 0);
    bool invert_ry = (atomic_load(&slot->invert_ry) != 0);
    
    if (invert_ly) {
        if (slot->LY == -32768)
            slot->LY = 32767;
        else
            slot->LY = -slot->LY;
    }
    
    if (invert_ry) {
        if (slot->RY == -32768)
            slot->RY = 32767;
        else
            slot->RY = -slot->RY;
    }
    
    // === APPLY RADIAL DEADZONE (validate range 0-100) ===
    uint8_t dz = atomic_load(&slot->deadzone);
    if (dz > 100) {
        syslog(LOG_WARNING, "NSW: Invalid deadzone (%d), using 0", dz);
        dz = 0;
    }
    if (dz > 0) {
        apply_deadzone(&slot->LX, &slot->LY, dz);
        apply_deadzone(&slot->RX, &slot->RY, dz);
    }
}

// ========================================================================
// PUBLIC FUNCTIONS
// ========================================================================

bool nsw_init(int fd, controller_t *slot)
{
    (void)fd;
    
    int idx = get_slot_index(slot);
    nsw_context_t *ctx = &g_nsw_contexts[idx];
    
    // Check if already initialized
    if (ctx->initialized) {
        syslog(LOG_WARNING, "NSW: Slot %d already initialized, ignoring duplicate init", idx);
        return true;
    }
    
    memset(ctx, 0, sizeof(nsw_context_t));
    ctx->slot_index = idx;
    ctx->effect_id = -1;
    ctx->last_strong = 0;
    ctx->last_weak = 0;
    ctx->is_active = true;
    ctx->thread_pid = getpid();
    ctx->uhid_fd = -1;
    ctx->lx = 0;
    ctx->ly = 0;
    ctx->rx = 0;
    ctx->ry = 0;
    memset(ctx->phy_raw, 0, sizeof(ctx->phy_raw));
    gettimeofday(&ctx->last_rumble_time, NULL);
    gettimeofday(&ctx->last_rumble_log_time, NULL);
    
    // Initialize uinput caches
    ctx->last_cross = 0;
    ctx->last_circle = 0;
    ctx->last_square = 0;
    ctx->last_triangle = 0;
    ctx->last_l1 = 0;
    ctx->last_r1 = 0;
    ctx->last_l2 = 0;
    ctx->last_r2 = 0;
    ctx->last_share = 0;
    ctx->last_options = 0;
    ctx->last_ps = 0;
    ctx->last_l3 = 0;
    ctx->last_r3 = 0;
    ctx->last_lx = 0;
    ctx->last_ly = 0;
    ctx->last_rx = 0;
    ctx->last_ry = 0;
    ctx->last_lt = -1;
    ctx->last_rt = -1;
    ctx->last_hatx = 0;
    ctx->last_haty = 0;
    gettimeofday(&ctx->last_uinput_time, NULL);
    
    syslog(LOG_INFO, "========== STARTING NSW PRO INITIALIZATION (Slot %d) ==========", idx);
    
    int event_fd = nsw_find_evdev_device(slot);
    if (event_fd < 0) {
        syslog(LOG_ERR, "NSW: ✗ Failed to find event device");
        ctx->is_active = false;
        return false;
    }
    
    ctx->event_fd = event_fd;
    
    char proc_path[PATH_MAX];
    snprintf(proc_path, sizeof(proc_path), "/proc/self/fd/%d", event_fd);
    ssize_t len = readlink(proc_path, ctx->event_path, sizeof(ctx->event_path)-1);
    if (len > 0) {
        ctx->event_path[len] = '\0';
        syslog(LOG_INFO, "NSW: Event device: %s", ctx->event_path);
    }
    
    nsw_setup_inotify(ctx);
    
    unsigned long ff_bits[256 / sizeof(unsigned long)];
    if (ioctl(event_fd, EVIOCGBIT(EV_FF, sizeof(ff_bits)), ff_bits) >= 0) {
        if (test_bit(FF_RUMBLE, ff_bits)) {
            syslog(LOG_INFO, "NSW: ✓ Rumble support detected");
            
            struct input_event gain_ev;
            memset(&gain_ev, 0, sizeof(gain_ev));
            gain_ev.type = EV_FF;
            gain_ev.code = FF_GAIN;
            gain_ev.value = NSW_FF_GAIN;
            if (safe_write(event_fd, &gain_ev, sizeof(gain_ev)) != sizeof(gain_ev)) {
                syslog(LOG_WARNING, "NSW: Failed to set FF_GAIN");
            }
        } else {
            syslog(LOG_WARNING, "NSW: ⚠ Device does not support rumble");
        }
    }
    
    int flags = fcntl(event_fd, F_GETFL, 0);
    fcntl(event_fd, F_SETFL, flags | O_NONBLOCK);
    
    ctx->connected = true;
    ctx->initialized = true;
    
    syslog(LOG_INFO, "========== NSW PRO INITIALIZATION COMPLETE (Slot %d) ==========", idx);
    return true;
}

/**
 * nsw_set_uhid_fd - Updates the UHID file descriptor in the NSW context
 * @param slot: Pointer to controller slot
 * @param uhid_fd: UHID file descriptor (-1 to disable)
 */
void nsw_set_uhid_fd(controller_t *slot, int uhid_fd)
{
    nsw_context_t *ctx = get_context(slot);
    if (!ctx || !ctx->initialized) return;
    
    ctx->uhid_fd = uhid_fd;
    // Rate-limited log (1 per second) for this category
    log_ratelimit_time(LOG_CAT_NSW, 1000000, LOG_DEBUG,
                       "NSW: Slot %d UHID fd updated to %d", ctx->slot_index, uhid_fd);
}

/**
 * nsw_read_events - Reads events from evdev device and updates SHM
 * @param slot: Pointer to controller slot
 * @param ufd: uinput file descriptor (for forwarding)
 * @return Number of events processed
 */
int nsw_read_events(controller_t *slot, int ufd)
{
    nsw_context_t *ctx = get_context(slot);
    if (!ctx || !ctx->initialized || !ctx->is_active || ctx->event_fd < 0) return 0;
    
    // Periodic log with time-based rate limit (1 per second) instead of pure counter
    if (log_ratelimit_time(LOG_CAT_NSW, 1000000, LOG_DEBUG,
                           "NSW_READ: slot %d, event_fd=%d", ctx->slot_index, ctx->event_fd)) {
        read_events_counter = 0; // reset for consistency, not strictly needed
    }
    
    // Get UHID fd from context
    int uhid_fd = ctx->uhid_fd;
    bool use_uhid = (uhid_fd >= 0);
    
    struct input_event ev;
    int count = 0;
    bool state_changed = false;
    
    // Process all available events (non-blocking)
    while (1) {
        ssize_t r = read(ctx->event_fd, &ev, sizeof(ev));
        if (r != sizeof(ev)) {
            if (r < 0 && (errno == EAGAIN || errno == EWOULDBLOCK)) {
                break;
            }
            if (r == 0 || (r < 0 && errno != EINTR)) {
                syslog(LOG_WARNING, "NSW: Event read error: %s", strerror(errno));
                ctx->connected = false;
                return count;
            }
            continue;
        }
        
        count++;
        state_changed = true;
        
        switch (ev.type) {
            case EV_KEY:
#ifdef DSTX_DEBUG_VERBOSE
                syslog(LOG_DEBUG, "NSW_EVENT: EV_KEY code=%d value=%d", ev.code, ev.value);
#endif
                switch (ev.code) {
                    // Face buttons (physical mapping)
                    case BTN_SOUTH: ctx->phy_raw[PHY_BTN_CROSS] = ev.value; break;
                    case BTN_EAST:  ctx->phy_raw[PHY_BTN_CIRCLE] = ev.value; break;
                    case BTN_NORTH: ctx->phy_raw[PHY_BTN_TRIANGLE] = ev.value; break;
                    case BTN_WEST:  ctx->phy_raw[PHY_BTN_SQUARE] = ev.value; break;
                    
                    // L1/R1 buttons
                    case BTN_TL:    ctx->phy_raw[PHY_BTN_L1] = ev.value; break;
                    case BTN_TR:    ctx->phy_raw[PHY_BTN_R1] = ev.value; break;
                    
                    // L2/R2 triggers
                    case BTN_TL2:
                        slot->LT = ev.value ? 255 : 0;   // analog value (for axes and LED)
                        ctx->phy_raw[PHY_BTN_L2] = ev.value; // raw state for keymap
                        break;
                    case BTN_TR2:
                        slot->RT = ev.value ? 255 : 0;
                        ctx->phy_raw[PHY_BTN_R2] = ev.value;
                        break;
                    
                    // System buttons
                    case BTN_SELECT: ctx->phy_raw[PHY_BTN_SHARE] = ev.value; break;
                    case BTN_START:  ctx->phy_raw[PHY_BTN_OPTIONS] = ev.value; break;
                    case BTN_MODE:   ctx->phy_raw[PHY_BTN_PS] = ev.value; break;
                    
                    // Stick buttons
                    case BTN_THUMBL: ctx->phy_raw[PHY_BTN_L3] = ev.value; break;
                    case BTN_THUMBR: ctx->phy_raw[PHY_BTN_R3] = ev.value; break;
                    
                    // Capture button (mapped to TOUCH)
                    case BTN_Z:
                        ctx->phy_raw[PHY_BTN_TOUCH] = ev.value;
                        break;
                }
                break;
                
            case EV_ABS:
#ifdef DSTX_DEBUG_VERBOSE
                syslog(LOG_DEBUG, "NSW_EVENT: EV_ABS code=%d value=%d", ev.code, ev.value);
#endif
                switch (ev.code) {
                    case ABS_X:   ctx->lx = ev.value; break;
                    case ABS_Y:   ctx->ly = ev.value; break;
                    case ABS_RX:  ctx->rx = ev.value; break;
                    case ABS_RY:  ctx->ry = ev.value; break;
                    case ABS_HAT0X:
                        ctx->phy_raw[PHY_BTN_DPAD_LEFT]  = (ev.value == -1);
                        ctx->phy_raw[PHY_BTN_DPAD_RIGHT] = (ev.value == 1);
                        break;
                    case ABS_HAT0Y:
                        ctx->phy_raw[PHY_BTN_DPAD_UP]    = (ev.value == -1);
                        ctx->phy_raw[PHY_BTN_DPAD_DOWN]  = (ev.value == 1);
                        break;
                }
                break;
        }
    }
    
    // Log number of processed events (time-based rate limit)
    if (log_ratelimit_time(LOG_CAT_NSW, 1000000, LOG_DEBUG,
                           "NSW_READ: processed %d events, state_changed=%d", count, state_changed)) {
        read_events_counter = 0;
    }
    
    // ===== APPLY AXIS TRANSFORMS (sticks) =====
    nsw_apply_transforms(slot, ctx);
    
    // ===== APPLY KEYBIND (physical → logical mapping) =====
    // Rate-limited log for keymap application (1 per second)
    if (log_ratelimit_time(LOG_CAT_NSW, 1000000, LOG_DEBUG,
                           "NSW_KEYMAP: applying map, phy_raw[0-3]=%d,%d,%d,%d, phy_raw[L2,R2]=%d,%d, phy_raw[TOUCH]=%d",
                           ctx->phy_raw[0], ctx->phy_raw[1], ctx->phy_raw[2], ctx->phy_raw[3],
                           ctx->phy_raw[PHY_BTN_L2], ctx->phy_raw[PHY_BTN_R2],
                           ctx->phy_raw[PHY_BTN_TOUCH])) {
        keymap_counter = 0;
    }
    keys_apply_map(slot, slot->keymap, ctx->phy_raw);
    
    // ===== FORWARD TO UINPUT OR UHID =====
    if (state_changed) {
        struct timeval now;
        gettimeofday(&now, NULL);
        long elapsed_us = (now.tv_sec - ctx->last_uinput_time.tv_sec) * 1000000L +
                          (now.tv_usec - ctx->last_uinput_time.tv_usec);
        
        if (elapsed_us >= NSW_UINPUT_RATE_LIMIT_US) {
            
            // ===== UINPUT =====
            if (ufd >= 0 && !use_uhid) {
                struct input_event new_ev;
                memset(&new_ev, 0, sizeof(new_ev));
                gettimeofday(&new_ev.time, NULL);
                bool sent = false;
                
                // Logical buttons (result of keymap)
                if (slot->cross != ctx->last_cross) {
                    new_ev.type = EV_KEY; new_ev.code = BTN_SOUTH; new_ev.value = slot->cross;
                    if (safe_write(ufd, &new_ev, sizeof(new_ev)) != sizeof(new_ev))
                        syslog(LOG_WARNING, "NSW: Failed to send cross event");
                    sent = true;
                    ctx->last_cross = slot->cross;
                }
                if (slot->circle != ctx->last_circle) {
                    new_ev.type = EV_KEY; new_ev.code = BTN_EAST; new_ev.value = slot->circle;
                    if (safe_write(ufd, &new_ev, sizeof(new_ev)) != sizeof(new_ev))
                        syslog(LOG_WARNING, "NSW: Failed to send circle event");
                    sent = true;
                    ctx->last_circle = slot->circle;
                }
                if (slot->square != ctx->last_square) {
                    new_ev.type = EV_KEY; new_ev.code = BTN_NORTH; new_ev.value = slot->square;
                    if (safe_write(ufd, &new_ev, sizeof(new_ev)) != sizeof(new_ev))
                        syslog(LOG_WARNING, "NSW: Failed to send square event");
                    sent = true;
                    ctx->last_square = slot->square;
                }
                if (slot->triangle != ctx->last_triangle) {
                    new_ev.type = EV_KEY; new_ev.code = BTN_WEST; new_ev.value = slot->triangle;
                    if (safe_write(ufd, &new_ev, sizeof(new_ev)) != sizeof(new_ev))
                        syslog(LOG_WARNING, "NSW: Failed to send triangle event");
                    sent = true;
                    ctx->last_triangle = slot->triangle;
                }
                if (slot->L1 != ctx->last_l1) {
                    new_ev.type = EV_KEY; new_ev.code = BTN_TL; new_ev.value = slot->L1;
                    if (safe_write(ufd, &new_ev, sizeof(new_ev)) != sizeof(new_ev))
                        syslog(LOG_WARNING, "NSW: Failed to send L1 event");
                    sent = true;
                    ctx->last_l1 = slot->L1;
                }
                if (slot->R1 != ctx->last_r1) {
                    new_ev.type = EV_KEY; new_ev.code = BTN_TR; new_ev.value = slot->R1;
                    if (safe_write(ufd, &new_ev, sizeof(new_ev)) != sizeof(new_ev))
                        syslog(LOG_WARNING, "NSW: Failed to send R1 event");
                    sent = true;
                    ctx->last_r1 = slot->R1;
                }
                if (slot->Share != ctx->last_share) {
                    new_ev.type = EV_KEY; new_ev.code = BTN_SELECT; new_ev.value = slot->Share;
                    if (safe_write(ufd, &new_ev, sizeof(new_ev)) != sizeof(new_ev))
                        syslog(LOG_WARNING, "NSW: Failed to send Share event");
                    sent = true;
                    ctx->last_share = slot->Share;
                }
                if (slot->Options != ctx->last_options) {
                    new_ev.type = EV_KEY; new_ev.code = BTN_START; new_ev.value = slot->Options;
                    if (safe_write(ufd, &new_ev, sizeof(new_ev)) != sizeof(new_ev))
                        syslog(LOG_WARNING, "NSW: Failed to send Options event");
                    sent = true;
                    ctx->last_options = slot->Options;
                }
                if (slot->PS != ctx->last_ps) {
                    new_ev.type = EV_KEY; new_ev.code = BTN_MODE; new_ev.value = slot->PS;
                    if (safe_write(ufd, &new_ev, sizeof(new_ev)) != sizeof(new_ev))
                        syslog(LOG_WARNING, "NSW: Failed to send PS event");
                    sent = true;
                    ctx->last_ps = slot->PS;
                }
                if (slot->L3 != ctx->last_l3) {
                    new_ev.type = EV_KEY; new_ev.code = BTN_THUMBL; new_ev.value = slot->L3;
                    if (safe_write(ufd, &new_ev, sizeof(new_ev)) != sizeof(new_ev))
                        syslog(LOG_WARNING, "NSW: Failed to send L3 event");
                    sent = true;
                    ctx->last_l3 = slot->L3;
                }
                if (slot->R3 != ctx->last_r3) {
                    new_ev.type = EV_KEY; new_ev.code = BTN_THUMBR; new_ev.value = slot->R3;
                    if (safe_write(ufd, &new_ev, sizeof(new_ev)) != sizeof(new_ev))
                        syslog(LOG_WARNING, "NSW: Failed to send R3 event");
                    sent = true;
                    ctx->last_r3 = slot->R3;
                }
                
                // Stick axes
                if (slot->LX != ctx->last_lx) {
                    new_ev.type = EV_ABS; new_ev.code = ABS_X; new_ev.value = slot->LX;
                    if (safe_write(ufd, &new_ev, sizeof(new_ev)) != sizeof(new_ev))
                        syslog(LOG_WARNING, "NSW: Failed to send LX axis");
                    sent = true;
                    ctx->last_lx = slot->LX;
                }
                if (slot->LY != ctx->last_ly) {
                    new_ev.type = EV_ABS; new_ev.code = ABS_Y; new_ev.value = slot->LY;
                    if (safe_write(ufd, &new_ev, sizeof(new_ev)) != sizeof(new_ev))
                        syslog(LOG_WARNING, "NSW: Failed to send LY axis");
                    sent = true;
                    ctx->last_ly = slot->LY;
                }
                if (slot->RX != ctx->last_rx) {
                    new_ev.type = EV_ABS; new_ev.code = ABS_RX; new_ev.value = slot->RX;
                    if (safe_write(ufd, &new_ev, sizeof(new_ev)) != sizeof(new_ev))
                        syslog(LOG_WARNING, "NSW: Failed to send RX axis");
                    sent = true;
                    ctx->last_rx = slot->RX;
                }
                if (slot->RY != ctx->last_ry) {
                    new_ev.type = EV_ABS; new_ev.code = ABS_RY; new_ev.value = slot->RY;
                    if (safe_write(ufd, &new_ev, sizeof(new_ev)) != sizeof(new_ev))
                        syslog(LOG_WARNING, "NSW: Failed to send RY axis");
                    sent = true;
                    ctx->last_ry = slot->RY;
                }
                
                bool trig_digital = (atomic_load(&slot->is_trigger_digital) != 0);
                
                if (!trig_digital) {
                    int16_t left_trigger_val = get_trigger_axis_value(slot, true);
                    int16_t right_trigger_val = get_trigger_axis_value(slot, false);

                    if (left_trigger_val != ctx->last_lt) {
                        new_ev.type = EV_ABS;
                        new_ev.code = ABS_Z;
                        new_ev.value = left_trigger_val;
                        if (safe_write(ufd, &new_ev, sizeof(new_ev)) != sizeof(new_ev))
                            syslog(LOG_WARNING, "NSW: Failed to send L2 axis");
                        sent = true;
                        ctx->last_lt = left_trigger_val;
                    }
                    if (right_trigger_val != ctx->last_rt) {
                        new_ev.type = EV_ABS;
                        new_ev.code = ABS_RZ;
                        new_ev.value = right_trigger_val;
                        if (safe_write(ufd, &new_ev, sizeof(new_ev)) != sizeof(new_ev))
                            syslog(LOG_WARNING, "NSW: Failed to send R2 axis");
                        sent = true;
                        ctx->last_rt = right_trigger_val;
                    }
                } else {
                    // Digital mode: send BTN_TL2/BTN_TR2 buttons, do not send axes
                    // slot->L2 and slot->R2 are already set by keys_apply_map
                    if (slot->L2 != ctx->last_l2) {
                        new_ev.type = EV_KEY;
                        new_ev.code = BTN_TL2;
                        new_ev.value = slot->L2;
                        if (safe_write(ufd, &new_ev, sizeof(new_ev)) != sizeof(new_ev))
                            syslog(LOG_WARNING, "NSW: Failed to send digital L2 button");
                        sent = true;
                        ctx->last_l2 = slot->L2;
                        // Digital log rate-limited (1 per second)
                        log_ratelimit_time(LOG_CAT_NSW, 1000000, LOG_DEBUG, "NSW: Digital L2=%d", slot->L2);
                    }
                    if (slot->R2 != ctx->last_r2) {
                        new_ev.type = EV_KEY;
                        new_ev.code = BTN_TR2;
                        new_ev.value = slot->R2;
                        if (safe_write(ufd, &new_ev, sizeof(new_ev)) != sizeof(new_ev))
                            syslog(LOG_WARNING, "NSW: Failed to send digital R2 button");
                        sent = true;
                        ctx->last_r2 = slot->R2;
                        log_ratelimit_time(LOG_CAT_NSW, 1000000, LOG_DEBUG, "NSW: Digital R2=%d", slot->R2);
                    }
                }
                
                // D-Pad
                if (slot->HATX != ctx->last_hatx) {
                    new_ev.type = EV_ABS; new_ev.code = ABS_HAT0X; new_ev.value = slot->HATX;
                    if (safe_write(ufd, &new_ev, sizeof(new_ev)) != sizeof(new_ev))
                        syslog(LOG_WARNING, "NSW: Failed to send HATX");
                    sent = true;
                    ctx->last_hatx = slot->HATX;
                }
                if (slot->HATY != ctx->last_haty) {
                    new_ev.type = EV_ABS; new_ev.code = ABS_HAT0Y; new_ev.value = slot->HATY;
                    if (safe_write(ufd, &new_ev, sizeof(new_ev)) != sizeof(new_ev))
                        syslog(LOG_WARNING, "NSW: Failed to send HATY");
                    sent = true;
                    ctx->last_haty = slot->HATY;
                }
                
                if (sent) {
                    new_ev.type = EV_SYN; new_ev.code = SYN_REPORT; new_ev.value = 0;
                    if (safe_write(ufd, &new_ev, sizeof(new_ev)) != sizeof(new_ev))
                        syslog(LOG_WARNING, "NSW: Failed to send SYN_REPORT");
                }
            }
            
            // ===== UHID =====
            if (use_uhid && uhid_fd >= 0) {
                uint8_t uhid_report[64];
                size_t report_size = uhid_build_input_report(slot, uhid_report, sizeof(uhid_report));
                if (report_size > 0) {
                    uhid_send_input(uhid_fd, uhid_report, report_size);
                }
            }
            
            ctx->last_uinput_time = now;
        }
    }
    
    return count;
}

/**
 * nsw_send_rumble - Sends rumble command via Force Feedback
 *
 * SHM VALIDATION: rumble_gain is clamped to 0-100.
 */
void nsw_send_rumble(int fd, controller_t *slot, uint16_t freq_left, uint16_t freq_right)
{
    (void)fd;
    (void)freq_left;
    (void)freq_right;
    
    nsw_context_t *ctx = get_context(slot);
    if (!ctx || !ctx->initialized || !ctx->is_active || ctx->event_fd < 0) return;
    if (!ctx->connected) return;
    
    if (!atomic_load(&slot->rumble_active)) {
        if (ctx->effect_id >= 0) {
            struct input_event stop_ev;
            memset(&stop_ev, 0, sizeof(stop_ev));
            stop_ev.type = EV_FF;
            stop_ev.code = ctx->effect_id;
            stop_ev.value = 0;
            if (safe_write(ctx->event_fd, &stop_ev, sizeof(stop_ev)) != sizeof(stop_ev))
                syslog(LOG_WARNING, "NSW: Failed to stop rumble");
            ioctl(ctx->event_fd, EVIOCRMFF, ctx->effect_id);
            ctx->effect_id = -1;
            ctx->last_strong = 0;
            ctx->last_weak = 0;
            if (should_log_rumble(ctx)) {
                syslog(LOG_DEBUG, "NSW: Rumble disabled - forcing stop on slot %d", 
                       ctx->slot_index);
            }
        }
        return;
    }
    
    struct pollfd pfd = { .fd = ctx->event_fd, .events = POLLOUT };
    int poll_ret = poll(&pfd, 1, 0);
    if (poll_ret < 0 || (pfd.revents & (POLLHUP | POLLERR))) {
        ctx->connected = false;
        return;
    }
    
    uint8_t rumble_strong, rumble_weak;
    uint8_t gain;
    
    // Atomic read of rumble fields (shared with UI and effects)
    rumble_strong = atomic_load(&slot->rumble_strong);
    rumble_weak = atomic_load(&slot->rumble_weak);
    gain = atomic_load(&slot->rumble_gain);
    
    // VALIDATION: ensure gain is within 0-100
    gain = clamp_u8(gain, 0, 100, 100);
    
    uint8_t target_strong = (uint16_t)rumble_strong * gain / 100;
    uint8_t target_weak   = (uint16_t)rumble_weak * gain / 100;
    
    // Periodic log of rumble state (already rate-limited by RUMBLE_LOG_RATE counter)
    if (++rumble_log_counter % RUMBLE_LOG_RATE == 0) {
        log_ratelimit_time(LOG_CAT_RUMBLE, 1000000, LOG_DEBUG,
                           "NSW_RUMBLE: raw(S=%d,W=%d) gain=%d -> target(S=%d,W=%d) effect_id=%d",
                           rumble_strong, rumble_weak, gain, target_strong, target_weak, ctx->effect_id);
    }
    
    struct timeval now;
    gettimeofday(&now, NULL);
    
    if (target_strong == ctx->last_strong && target_weak == ctx->last_weak) {
        ctx->last_rumble_time = now;
        return;
    }
    
    if (target_strong == 0 && target_weak == 0) {
        if (ctx->effect_id == -1) {
            ctx->last_strong = 0;
            ctx->last_weak = 0;
            ctx->last_rumble_time = now;
            return;
        }
        struct input_event stop_ev;
        memset(&stop_ev, 0, sizeof(stop_ev));
        stop_ev.type = EV_FF;
        stop_ev.code = ctx->effect_id;
        stop_ev.value = 0;
        if (safe_write(ctx->event_fd, &stop_ev, sizeof(stop_ev)) == sizeof(stop_ev)) {
            ioctl(ctx->event_fd, EVIOCRMFF, ctx->effect_id);
            ctx->effect_id = -1;
            ctx->last_strong = 0;
            ctx->last_weak = 0;
            ctx->last_rumble_time = now;
            if (should_log_rumble(ctx)) {
                syslog(LOG_DEBUG, "NSW: Rumble STOPPED on slot %d", ctx->slot_index);
            }
        }
        return;
    }
    
    long elapsed_us = (now.tv_sec - ctx->last_rumble_time.tv_sec) * 1000000L +
                      (now.tv_usec - ctx->last_rumble_time.tv_usec);
    if (elapsed_us < NSW_RUMBLE_RATE_LIMIT_US) {
        ctx->last_strong = target_strong;
        ctx->last_weak = target_weak;
        return;
    }
    
    uint16_t strong_mag = (uint16_t)target_strong * 257;
    uint16_t weak_mag = (uint16_t)target_weak * 257;
    
    if (ctx->effect_id >= 0) {
        struct input_event stop_ev;
        memset(&stop_ev, 0, sizeof(stop_ev));
        stop_ev.type = EV_FF;
        stop_ev.code = ctx->effect_id;
        stop_ev.value = 0;
        if (safe_write(ctx->event_fd, &stop_ev, sizeof(stop_ev)) != sizeof(stop_ev))
            syslog(LOG_WARNING, "NSW: Failed to stop effect before recreating");
        ioctl(ctx->event_fd, EVIOCRMFF, ctx->effect_id);
        ctx->effect_id = -1;
        usleep(1000);
    }
    
    struct ff_effect effect;
    memset(&effect, 0, sizeof(effect));
    effect.type = FF_RUMBLE;
    effect.id = -1;
    effect.u.rumble.strong_magnitude = strong_mag;
    effect.u.rumble.weak_magnitude = weak_mag;
    effect.replay.length = 0;
    effect.replay.delay = 0;
    
    if (ioctl(ctx->event_fd, EVIOCSFF, &effect) < 0) {
        if (errno != EAGAIN && errno != EBUSY) {
            syslog(LOG_ERR, "NSW: Rumble upload failed: %s", strerror(errno));
        }
        return;
    }
    
    if (effect.id >= 0) {
        ctx->effect_id = effect.id;
        struct input_event play_ev;
        memset(&play_ev, 0, sizeof(play_ev));
        play_ev.type = EV_FF;
        play_ev.code = effect.id;
        play_ev.value = 1;
        if (safe_write(ctx->event_fd, &play_ev, sizeof(play_ev)) == sizeof(play_ev)) {
            ctx->last_strong = target_strong;
            ctx->last_weak = target_weak;
            ctx->last_rumble_time = now;
            if (should_log_rumble(ctx)) {
                syslog(LOG_DEBUG, "NSW: NEW rumble (S=%d, W=%d, id=%d)", 
                       target_strong, target_weak, effect.id);
            }
        } else {
            syslog(LOG_WARNING, "NSW: Failed to start new rumble effect");
        }
    }
}

bool nsw_monitor(controller_t *slot, int fd)
{
    (void)fd;
    nsw_context_t *ctx = get_context(slot);
    if (!ctx || !ctx->initialized || !ctx->is_active) return true;
    if (nsw_check_inotify(ctx)) {
        if (ctx->connected) {
            syslog(LOG_WARNING, "NSW: Slot %d - Device removed (inotify)", ctx->slot_index);
            ctx->connected = false;
        }
        return false;
    }
    return ctx->connected;
}

void nsw_cleanup(controller_t *slot)
{
    nsw_context_t *ctx = get_context(slot);
    if (!ctx || !ctx->initialized) return;
    syslog(LOG_INFO, "NSW: Slot %d finalizing", ctx->slot_index);
    ctx->is_active = false;
    if (ctx->effect_id >= 0) {
        struct input_event stop_ev;
        memset(&stop_ev, 0, sizeof(stop_ev));
        stop_ev.type = EV_FF;
        stop_ev.code = ctx->effect_id;
        stop_ev.value = 0;
        if (safe_write(ctx->event_fd, &stop_ev, sizeof(stop_ev)) != sizeof(stop_ev))
            syslog(LOG_WARNING, "NSW: Failed to stop rumble during cleanup");
        ioctl(ctx->event_fd, EVIOCRMFF, ctx->effect_id);
        ctx->effect_id = -1;
    }
    if (ctx->inotify_fd >= 0) {
        if (ctx->inotify_wd >= 0) inotify_rm_watch(ctx->inotify_fd, ctx->inotify_wd);
        close(ctx->inotify_fd);
        ctx->inotify_fd = -1;
    }
    if (ctx->event_fd >= 0) {
        close(ctx->event_fd);
        ctx->event_fd = -1;
    }
    ctx->initialized = false;
    ctx->connected = false;
    syslog(LOG_INFO, "NSW: Slot %d cleaned up", ctx->slot_index);
}
