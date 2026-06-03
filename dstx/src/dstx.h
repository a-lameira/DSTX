/*
 * dstx.h - Main header for DSTX
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
 * Contains all data structures, constants and prototypes shared across system modules.
 */

#ifndef DSTX_H
#define DSTX_H

#include <stdio.h>
#include <stdlib.h>
#include <fcntl.h>
#include <unistd.h>
#include <dirent.h>
#include <string.h>
#include <signal.h>
#include <sys/ioctl.h>
#include <sys/time.h>
#include <sys/select.h>
#include <sys/stat.h>
#include <sys/mman.h>
#include <sys/types.h>
#include <syslog.h>
#include <errno.h>
#include <linux/hidraw.h>
#include <linux/input.h>
#include <linux/uinput.h>
#include <termios.h>
#include <stdbool.h>
#include <stdatomic.h>
#include <libgen.h>
#include <pthread.h>
#include <stdint.h>
#include <zlib.h>
#include <poll.h>
#include <math.h>

// ========================================================================
// GLOBAL CONSTANTS
// ========================================================================
#ifndef UI_P_SET_FF_EFFECTS
#define UI_P_SET_FF_EFFECTS _IOW(UINPUT_IOCTL_BASE, 201, int)
#endif

#define MAX_SLOTS 4
#define MAX_BUF 128
#define MY_MAX_INPUT 256
#define SHM_PATH "/dstx_shared_mem"
#define SHM_MAGIC_VALUE 0x44535458 // "DSTX" in Hexadecimal

// Pipeline timeouts (in microseconds)
#define RUMBLE_TIMEOUT_US 5000    // 5ms for rumble (fast response)
#define RUMBLE_KEEPALIVE_US 20000 // 20ms for rumble keep-alive
#define LED_TIMEOUT_US    20000   // 20ms for LED (static mode)
#define LED_FAST_TIMEOUT_US 5000  // 5ms for LED (effect mode)

// ===== DEBOUNCE CONSTANTS =====
#define DEBOUNCE_DELAY_US 15000   // 15 ms

// ===== WATCHDOG CONSTANTS =====
#define WORKER_HEARTBEAT_TIMEOUT_US 5000000  // 5 seconds

// Button debounce indices
enum {
    BTN_DEBOUNCE_SQUARE,
    BTN_DEBOUNCE_CROSS,
    BTN_DEBOUNCE_CIRCLE,
    BTN_DEBOUNCE_TRIANGLE,
    BTN_DEBOUNCE_L1,
    BTN_DEBOUNCE_R1,
    BTN_DEBOUNCE_L2,
    BTN_DEBOUNCE_R2,
    BTN_DEBOUNCE_SHARE,
    BTN_DEBOUNCE_OPTIONS,
    BTN_DEBOUNCE_L3,
    BTN_DEBOUNCE_R3,
    BTN_DEBOUNCE_PS,
    BTN_DEBOUNCE_TOUCH,
    // D-PAD directions
    BTN_DEBOUNCE_DPAD_UP,
    BTN_DEBOUNCE_DPAD_DOWN,
    BTN_DEBOUNCE_DPAD_LEFT,
    BTN_DEBOUNCE_DPAD_RIGHT,
    BTN_DEBOUNCE_COUNT
};

// ===== MAXIMUM INPUT NODES =====
#ifndef MAX_INPUT_NODES
#define MAX_INPUT_NODES 8
#endif

// ========================================================================
// LOG RATE LIMITING CATEGORIES
// ========================================================================
typedef enum {
    LOG_CAT_RUMBLE,      // Rumble pipeline and periodic effects
    LOG_CAT_LED,         // LED pipeline and effects
    LOG_CAT_UHID,        // UHID input/output reports
    LOG_CAT_DRIVER,      // DS4/DualSense translation
    LOG_CAT_NSW,         // Nintendo Switch Pro (evdev)
    LOG_CAT_OUTPUT,      // Output reports (send_output_report)
    LOG_CAT_WORKER,      // Worker thread (loop status)
    LOG_CAT_COUNT        // Number of categories
} log_category_t;

// ========================================================================
// CONTROLLER TYPES
// ========================================================================
typedef enum {
    TYPE_DS4,           // DualShock 4
    TYPE_DUALSENSE,     // DualSense
    TYPE_NSW_PRO        // Nintendo Switch Pro
} controller_type_t;

// ========================================================================
// SENSITIVITY PRESETS
// ========================================================================
typedef enum {
    SENS_PRESET_DEFAULT = 0,   // 1:1 linear (default)
    SENS_PRESET_PRECISION,      // Precision for sniping
    SENS_PRESET_RAPID,          // Fast response
    SENS_PRESET_SUAVE,          // Smooth curve
    SENS_PRESET_AGGRESSIVE,     // Aggressive response
    SENS_PRESET_SNIPER,         // Sniper style
    SENS_PRESET_RACING,         // For racing games
    SENS_PRESET_FPS,            // For FPS games
    SENS_PRESET_COUNT
} sensitivity_preset_t;

// ========================================================================
// KEYBIND SYSTEM (BUTTON REMAPPING)
// ========================================================================

// Physical buttons – identify each button on the hardware (controller independent)
typedef enum {
    PHY_BTN_CROSS = 0,
    PHY_BTN_CIRCLE,
    PHY_BTN_SQUARE,
    PHY_BTN_TRIANGLE,
    PHY_BTN_L1,
    PHY_BTN_R1,
    PHY_BTN_L2,
    PHY_BTN_R2,
    PHY_BTN_SHARE,
    PHY_BTN_OPTIONS,
    PHY_BTN_L3,
    PHY_BTN_R3,
    PHY_BTN_PS,
    PHY_BTN_TOUCH,
    PHY_BTN_DPAD_UP,
    PHY_BTN_DPAD_DOWN,
    PHY_BTN_DPAD_LEFT,
    PHY_BTN_DPAD_RIGHT,
    PHY_BTN_COUNT
} physical_button_t;

// Logical buttons – same set, plus NONE (disabled)
typedef enum {
    LOGICAL_BTN_NONE = 0,
    LOGICAL_BTN_CROSS,
    LOGICAL_BTN_CIRCLE,
    LOGICAL_BTN_SQUARE,
    LOGICAL_BTN_TRIANGLE,
    LOGICAL_BTN_L1,
    LOGICAL_BTN_R1,
    LOGICAL_BTN_L2,
    LOGICAL_BTN_R2,
    LOGICAL_BTN_SHARE,
    LOGICAL_BTN_OPTIONS,
    LOGICAL_BTN_L3,
    LOGICAL_BTN_R3,
    LOGICAL_BTN_PS,
    LOGICAL_BTN_TOUCH,
    LOGICAL_BTN_DPAD_UP,
    LOGICAL_BTN_DPAD_DOWN,
    LOGICAL_BTN_DPAD_LEFT,
    LOGICAL_BTN_DPAD_RIGHT,
    LOGICAL_BTN_COUNT
} logical_button_t;

// ========================================================================
// STRUCTURE FOR PERIODIC EFFECTS (SINE, SQUARE, TRIANGLE)
// ========================================================================
typedef struct {
    bool active;               // whether currently running
    uint16_t waveform;         // FF_SINE, FF_SQUARE, FF_TRIANGLE
    uint16_t period;           // period in milliseconds
    int16_t magnitude;         // amplitude (0-32767)
    int16_t offset;            // offset (0-32767)
    uint16_t phase;            // phase (not used in current implementation)
    struct timeval start_time; // time when effect was started
    uint8_t last_value;        // last value sent (for both channels)
    
    // VARIABLE FREQUENCY FOR NSW PRO
    uint16_t left_freq;        // left motor frequency in Hz
    uint16_t right_freq;       // right motor frequency in Hz
} periodic_effect_t;

// ========================================================================
// STRUCTURE TO STORE INPUT NODE (evdev) INFORMATION
// ========================================================================
typedef struct {
    char path[PATH_MAX];      // Full path, e.g., /dev/input/event4
    char name[128];           // Device name, e.g., "Wireless Controller"
} input_node_info_t;

// ========================================================================
// DATA STRUCTURE FOR A SINGLE CONTROLLER
// ========================================================================
typedef struct {
    // ----- Input Data (Analog Sticks) -----
    int16_t LX, LY, RX, RY;      // Analog sticks (-32768 to 32767)
    int16_t LT, RT;               // Triggers (0 to 255)
    
    // ----- Digital Buttons (Full Mapping) -----
    uint8_t square, cross, circle, triangle;
    uint8_t L1, R1, L2, R2; 
    uint8_t Share, Options, L3, R3, PS, touch_btn;
    int HATX, HATY;                // D-Pad (-1, 0, 1)
    _Atomic int battery;           // Battery level (0-100)
    
    // ----- Status and Identification -----
    _Atomic bool connected;        // Controller connected?
    bool is_bluetooth;             // Bluetooth connection? (immutable after init)
    int uinput_fd;                  // Virtual device file descriptor (uinput)
    _Atomic bool emulate_active;    // Emulation active?
    controller_type_t type;         // Controller type (immutable after init)
    char dev_path[128];             // Path in /dev
    
    // ===== UHID FIELDS =====
    _Atomic bool is_uhid;           // true = uses UHID, false = uses uinput
    int uhid_fd;                     // UHID device FD (-1 if not created)
    uint8_t uhid_output_buf[64];     // Buffer for UHID output reports
    _Atomic bool uhid_output_pending; // Flag for pending output report
    
    // ----- Feedback (LED and Rumble) -----
    _Atomic uint8_t led_r, led_g, led_b;    // Current LED color (can be changed by effects)
    _Atomic uint8_t led_base_r, led_base_g, led_base_b; // Base reference color (static)
    _Atomic uint8_t rumble_weak, rumble_strong; // Rumble intensities
    _Atomic uint8_t rumble_gain;             // Applied gain (0-100)
    _Atomic uint8_t deadzone;                // Stick deadzone (0-100) - default 10%
    _Atomic bool debounce_enabled;          // true = apply debounce, false = raw values
    
    // ===== STICK SENSITIVITY =====
    _Atomic uint8_t sensitivity_left_preset;   // Left stick preset
    _Atomic uint8_t sensitivity_right_preset;  // Right stick preset
    
    // ===== KEYBINDS (BUTTON REMAPPING) =====
    uint8_t keymap[PHY_BTN_COUNT];

    // ===== LAYOUT REQUESTS (one-shot, processed by daemon) =====
    _Atomic bool request_switch_layout;   // request swapping A↔B and X↔Y
    _Atomic bool request_xbox_layout;     // request restoring identity mapping on face buttons
    _Atomic bool request_reset_all_keybinds;   // restore entire keymap to identity
    
    // ===== WATCHDOG =====
    _Atomic uint64_t worker_heartbeat;   // Timestamp of last worker iteration (us)
    _Atomic bool worker_stop;            // Signal for worker thread to stop

    // Array to store multiple rumble effects (index = effect_id)
    struct {
        uint8_t strong;
        uint8_t weak;
    } ff_effects[16];
    
    // ----- PERIODIC EFFECTS -----
    periodic_effect_t periodic_effects[16];  // up to 16 loaded periodic effects
    uint8_t effect_type[16];                  // 0 = none, 1 = rumble, 2 = periodic
    int active_effect_id;                      // -1 if none active
    int active_effect_type;                    // 0 = none, 1 = rumble, 2 = periodic
    
    _Atomic bool led_dirty;          // LED needs update?
    _Atomic bool rumble_dirty;        // Rumble needs update?
    _Atomic bool writing_output;      // Flag to avoid loop with inotify
    
    // ----- LED Effect Control -----
    _Atomic bool led_static;           // true = static mode, false = effects active
    _Atomic int led_request_effect;     // Effect requested by UI (-1 = none)
    _Atomic uint8_t led_request_speed;  // Requested speed
    _Atomic uint8_t led_request_brightness; // Requested brightness
    _Atomic bool led_request_pending;   // Pending request
    _Atomic uint8_t player_leds;  // 0=off, 1=player1, 2=player2, 3=player3, 4=player4, 5=player5 
    _Atomic float effect_phase;         // Current effect phase (0-360°)
    _Atomic uint8_t global_led_brightness; // Global brightness (0-100)
    _Atomic bool led_reapply;          // true = react to external interventions (default), false = ignore
    
    // ----- Retry control for external intervention (only static mode) -----
    _Atomic uint8_t external_retry_count; // Number of remaining retransmissions (0 = inactive)
    struct timeval last_external_retry;   // Time of last retry in the sequence
    
    // ===== RUMBLE CONTROL =====
    _Atomic bool rumble_active;          // true = rumble enabled, false = disabled
    
    // ===== Y-AXIS INVERSION =====
    _Atomic bool invert_ly;              // Invert left stick Y axis
    _Atomic bool invert_ry;              // Invert right stick Y axis
    
    // ===== TRIGGER (L2/R2) HANDLING =====
    _Atomic bool is_trigger_digital;     // false = analog (default), true = digital (on/off)
    
    // ===== DEBOUNCE FIELDS =====
    // Stable D-PAD directions (after debounce)
    uint8_t dpad_up;
    uint8_t dpad_down;
    uint8_t dpad_left;
    uint8_t dpad_right;
    
    // Button debounce structure (accessed only by worker thread)
    struct {
        uint64_t last_change_us;   // timestamp of last change (us)
        uint8_t pending;            // value being confirmed
    } debounce[BTN_DEBOUNCE_COUNT];

    // ===== NINTENDO SWITCH PRO FIELDS =====
    uint8_t output_seq;             // Sequence number for output reports (0-15)
    
    // ----- Device information (for 'info' screen) -----
    char product_name[128];                     // Product name (HIDIOCGRAWNAME)
    char uniq[64];                               // Serial number (HIDIOCGRAWUNIQ)
    char driver[32];                             // Kernel driver (from uevent)
    input_node_info_t input_nodes[MAX_INPUT_NODES]; // Input nodes with names
    int num_input_nodes;                          // Number of nodes found
} controller_t;

// ========================================================================
// PERSISTENT PER-SLOT CONFIGURATION (for profiles)
// ========================================================================
typedef struct {
    uint8_t led_r, led_g, led_b;               // Current static color
    uint8_t led_base_r, led_base_g, led_base_b; // Base color (for effects)
    uint8_t rumble_gain;                        // 0-100
    uint8_t deadzone;                           // 0-100
    uint8_t global_led_brightness;              // 0-100
    uint8_t player_leds;                        // 0-5 (DualSense)
    bool debounce_enabled;
    bool emulate_active;
    bool is_uhid;
    bool led_reapply;
    bool rumble_active;
    bool invert_ly, invert_ry;
    uint8_t sensitivity_left_preset;            // SENS_PRESET_*
    uint8_t sensitivity_right_preset;
    uint8_t led_effect;                         // 0=static, 1..8
    uint8_t led_effect_speed;                   // 1-10
    uint8_t led_effect_brightness;              // 0-100
    uint8_t keymap[PHY_BTN_COUNT];              // Persistent button mapping
    bool treat_triggers_as_digital;             // false = analog, true = digital
} slot_config_t;

// ========================================================================
// CONSTANT FOR PROFILE NAME LENGTH (used in shared_data_t)
// ========================================================================
#define PROFILE_NAME_LEN 64

// ========================================================================
// GLOBAL SHARED MEMORY
// ========================================================================
typedef struct {
    uint32_t magic;                          // Magic number for validation
    pthread_mutex_t proc_mutex;               // Robust process-shared mutex
    controller_t slots[MAX_SLOTS];             // Controller slots
    _Atomic bool request_reload;               // Request to reload config
    
    // Handshake with daemon
    _Atomic int32_t daemon_pid;                // PID of active daemon
    _Atomic uint32_t heartbeat;                 // Heartbeat for freeze detection
    
    _Atomic bool ledfx_active;          // Effect system active in daemon?

    // Bitmap of free slots (now inside SHM)
    uint8_t free_slots_bitmap;
    
    // ===== PROFILE COMMANDS (UI/D-Bus ↔ settings thread communication) =====
    _Atomic int profile_request;               // 0=none, 1=load, 2=save, 3=delete, 4=list, 5=set_auto_save
    char profile_name[PROFILE_NAME_LEN];       // Target profile name
    _Atomic int profile_response;              // 0=ok, -1=error
    char profile_response_msg[4096];            // Return message (success/error)
    _Atomic int auto_save_enabled;             // 0/1
    _Atomic int auto_save_delay_ms;            // Debounce in ms
    char current_profile_name[PROFILE_NAME_LEN]; // Name of currently applied profile
} shared_data_t;

// ========================================================================
// GLOBAL VARIABLES (defined in main.c)
// ========================================================================
extern shared_data_t *shm_ptr;
extern pthread_mutex_t data_mutex;
extern volatile bool keep_running;
extern bool is_daemon_mode;
extern int shm_fd;

// ========================================================================
// SYNCHRONIZATION UTILITIES
// ========================================================================
static inline void safe_shm_lock(pthread_mutex_t *mutex) {
    int rc = pthread_mutex_lock(mutex);
    if (rc == EOWNERDEAD) {
        pthread_mutex_consistent(mutex);
        syslog(LOG_WARNING, "DSTX: Recovered mutex from abruptly terminated process.");
    }
}

// ========================================================================
// TRIGGER UTILITIES (keybinds and analog mode)
// ========================================================================
static inline int16_t get_trigger_axis_value(controller_t *slot, bool is_left) {
    if (is_left) {
        // Physical trigger pressed? (analog value > 0)
        if (slot->LT > 0) {
            // If physical L2 is mapped to LOGICAL_BTN_L2, send analog value
            if (slot->keymap[PHY_BTN_L2] == LOGICAL_BTN_L2)
                return slot->LT;
            else
                return 0;   // remapped to another button → suppress axis
        }
        // Physical trigger not pressed, but L2 activated by another keybind → force maximum
        if (slot->L2)
            return 255;
        return 0;
    } else {
        if (slot->RT > 0) {
            if (slot->keymap[PHY_BTN_R2] == LOGICAL_BTN_R2)
                return slot->RT;
            else
                return 0;
        }
        if (slot->R2)
            return 255;
        return 0;
    }
}

// ========================================================================
// PROTOTYPES: UTILS (utils.c)
// ========================================================================
void start_service(void);
void stop_service(void);
void disconnect_shm(void);
bool try_connect_shm(void);
void set_nonblocking(int fd);
void enable_raw_mode(void);
void disable_raw_mode(void);
void cleanup(int sig);
bool is_daemon_alive(void);
double get_monotonic_time_sec(void);
uint64_t get_monotonic_time_us(void);          // for watchdog
ssize_t safe_write(int fd, const void *buf, size_t count); // full write
int discover_all_input_nodes(const char *hidraw_path, char paths[][PATH_MAX], int max_nodes);
void controller_to_slot_config(slot_config_t *cfg, const controller_t *ctrl);
void slot_config_to_controller(const slot_config_t *cfg, controller_t *ctrl);

/**
 * profile_request_sync - Send profile request to daemon and wait for response
 * @param shm: Pointer to shared memory
 * @param request: 1=load, 2=save, 3=delete, 4=list, 5=set_auto_save
 * @param name: Profile name (may be NULL)
 * @param auto_enable: -1 = no change, 0=off, 1=on
 * @param auto_delay: -1 = no change, otherwise delay in ms
 * @param out_msg: Buffer for return message (minimum 512 bytes)
 * @param msg_size: Size of out_msg buffer
 * @return true on success, false on error or timeout
 */
bool profile_request_sync(shared_data_t *shm, int request, const char *name,
                          int auto_enable, int auto_delay, char *out_msg, size_t msg_size);

// ========================================================================
// PROTOTYPES: LOG RATE LIMITING (utils.c)
// ========================================================================

/**
 * log_rate_init - Initialize log rate limiting structures
 * Must be called once at program start (daemon main and UI main)
 */
void log_rate_init(void);

/**
 * log_ratelimit_time - Emit log at most once per interval (per category)
 * @param cat: Log category (LOG_CAT_*)
 * @param interval_us: Minimum interval between logs (microseconds)
 * @param level: syslog level (LOG_DEBUG, LOG_INFO, etc.)
 * @param fmt: printf format string
 * @return true if log was emitted, false if suppressed
 */
bool log_ratelimit_time(log_category_t cat, uint64_t interval_us, int level, const char *fmt, ...)
    __attribute__((format(printf, 4, 5)));

/**
 * log_ratelimit_count - Emit log every N calls (per category)
 * @param cat: Log category
 * @param every_n: Emit every N calls (e.g., 100 = 1 every 100)
 * @param level: syslog level
 * @param fmt: printf format string
 * @return true if log was emitted, false otherwise
 */
bool log_ratelimit_count(log_category_t cat, uint32_t every_n, int level, const char *fmt, ...)
    __attribute__((format(printf, 4, 5)));

/**
 * log_reset_category - Reset counters/timestamps for a category
 * Useful to force logs after an important event even if rate limit is active
 */
void log_reset_category(log_category_t cat);

// ========================================================================
// PROTOTYPES: UINPUT (shared)
// ========================================================================
int setup_uinput_indexed(int index, controller_t *slot);

// ========================================================================
// PROTOTYPES: UHID (uhid.c)
// ========================================================================
int uhid_create(controller_t *slot, int index);
void uhid_destroy(int fd);
void uhid_handle_events(int fd, controller_t *slot);
int uhid_send_input(int fd, const uint8_t *data, size_t size);
size_t uhid_build_input_report(controller_t *slot, uint8_t *buf, size_t buf_size);

// ========================================================================
// PROTOTYPES: UI (ui.c) and DISPLAY (display.c)
// ========================================================================
void run_ui_loop(void);
void force_terminal_size(int r, int c);
void get_binary_path(char *out_dir, size_t size);
bool check_window_sanity(void);
int update_and_get_slot_idx(shared_data_t *shm);
void render_full_ui(shared_data_t *shm, int idx, const char *cmd_line, bool alive, bool info_mode);

// ========================================================================
// PROTOTYPES: DAEMON (daemon.c)
// ========================================================================
void run_daemon_loop(void);
void *controller_worker(void *arg);

// ========================================================================
// PROTOTYPES: INPUT TRANSLATION (drivers.c)
// ========================================================================
void emit(int fd, int type, int code, int value);
void translate_ds4(unsigned char *buf, controller_t *slot, int ufd);
void translate_dualsense(unsigned char *buf, controller_t *slot, int ufd);
void translate_nsw_pro(unsigned char *buf, controller_t *slot, int ufd);

// ========================================================================
// PROTOTYPES: UNIFIED OUTPUT (output.c)
// ========================================================================
void send_output_report(int fd, controller_t *slot);
bool rumble_handle_ff_upload(int ufd, struct input_event *ev, controller_t *slot);
void rumble_handle_ff_event(struct input_event *ev, controller_t *slot);
bool rumble_process_pipeline(int fd, controller_t *slot, struct timeval *last_rumble_time);
bool led_process_pipeline(int fd, controller_t *slot, struct timeval *last_led_time);

// ========================================================================
// PROTOTYPES: AXIS (axis.c)
// ========================================================================
void init_axis_system(void);
void axis_apply_preset(controller_t *slot, sensitivity_preset_t preset);
const char* axis_get_preset_name(sensitivity_preset_t preset);
void axis_apply_sensitivity(int16_t *x, int16_t *y, uint8_t preset_index);
void axis_apply_deadzone(int16_t *x, int16_t *y, uint8_t deadzone_pct);

// ========================================================================
// PROTOTYPES: NINTENDO SWITCH PRO SPECIFIC FUNCTIONS (nsw.c)
// ========================================================================
bool nsw_init(int fd, controller_t *slot);
int nsw_read_events(controller_t *slot, int ufd);
void nsw_send_rumble(int fd, controller_t *slot, uint16_t freq_left, uint16_t freq_right);
void nsw_heartbeat_ping(controller_t *slot);
bool nsw_is_connected(controller_t *slot);
bool nsw_monitor(controller_t *slot, int fd);
void nsw_cleanup(controller_t *slot);
void nsw_set_uhid_fd(controller_t *slot, int uhid_fd);

// ========================================================================
// PROTOTYPES: LED (led.h)
// ========================================================================
#include "led.h"

// ========================================================================
// PROTOTYPES: KEYBINDS (keys.c)
// ========================================================================
void keys_get_default_map(controller_type_t type, uint8_t *map_out);
void keys_apply_map(controller_t *slot, const uint8_t *keymap,
                    const uint8_t *raw_buttons_phy_state);

#endif // DSTX_H
