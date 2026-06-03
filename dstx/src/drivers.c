/*
 * drivers.c - Input protocol translation for DSTX
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
  * - Uinput setup
 * - Input handling for DualShock4 and DualSense
 * - Translation of raw reports to controller_t structure
 * - Button debounce (physical, before keymap)
 * - Keybind application (button reassignment)
 * - Radial deadzone application (via axis.c)
 * - Stick sensitivity application (via axis.c)
 * - Configurable Y-axis inversion (with overflow handling)
 * - Sending to uinput/UHID
 * - Digital trigger mode support (L2/R2):
 *   * Analog mode (default): sends ABS_Z/ABS_RZ (axes), does not send BTN_TL2/BTN_TR2.
 *   * Digital mode: sends BTN_TL2/BTN_TR2 (buttons), does not send ABS_Z/ABS_RZ.
 */

#include "dstx.h"
#include "axes.h"
#include "keys.h"
#include <math.h>

// ========================================================================
// HELPER FUNCTIONS
// ========================================================================

/**
 * safe_normalize - Converts 8-bit to 16-bit safely
 */
static inline int16_t safe_normalize(uint8_t v) {
    if (v == 128) return 0;
    if (v == 0)   return -32768;
    if (v == 255) return 32767;
    
    if (v < 128) return (int16_t)((v - 128) * 256);
    return (int16_t)((v - 128) * 257 + 128);
}

/**
 * emit - Sends an event to uinput (using safe_write)
 *
 * Failure logs are rate-limited (max 1 every 5 seconds) to avoid flooding
 * in case of persistent virtual device errors.
 */
void emit(int fd, int type, int code, int value) {
    if (fd < 0) return;
    struct input_event ev = {0};
    gettimeofday(&ev.time, NULL);
    ev.type = type;
    ev.code = code;
    ev.value = value;
    if (safe_write(fd, &ev, sizeof(ev)) != sizeof(ev)) {
        log_ratelimit_time(LOG_CAT_DRIVER, 5000000, LOG_WARNING,
                           "emit: failed to write event (fd=%d, type=%d, code=%d, value=%d)",
                           fd, type, code, value);
    }
}

// ========================================================================
// UINPUT SETUP
// ========================================================================

int setup_uinput_indexed(int index, controller_t *slot) {
    (void)slot;
    int fd = open("/dev/uinput", O_RDWR | O_NONBLOCK | O_CLOEXEC);
    if (fd < 0) {
        syslog(LOG_ERR, "DSTX: Failed to open /dev/uinput: %s", strerror(errno));
        return -1;
    }

    if (ioctl(fd, UI_SET_EVBIT, EV_KEY) < 0) {
        syslog(LOG_ERR, "DSTX: Failed to set EVBIT: %s", strerror(errno));
        close(fd);
        return -1;
    }
    ioctl(fd, UI_SET_EVBIT, EV_ABS);
    ioctl(fd, UI_SET_EVBIT, EV_FF);

    ioctl(fd, UI_SET_FFBIT, FF_RUMBLE);
    ioctl(fd, UI_SET_FFBIT, FF_PERIODIC);
    ioctl(fd, UI_SET_FFBIT, FF_SQUARE);
    ioctl(fd, UI_SET_FFBIT, FF_TRIANGLE);
    ioctl(fd, UI_SET_FFBIT, FF_SINE);
    ioctl(fd, UI_SET_FFBIT, FF_GAIN);
    
    int ff_effects = 16;
    if (ioctl(fd, UI_P_SET_FF_EFFECTS, &ff_effects) < 0) {
        syslog(LOG_WARNING, "DSTX: Failed to set FF_EFFECTS: %s", strerror(errno));
    }

    int buttons[] = {BTN_A, BTN_B, BTN_X, BTN_Y, BTN_START, BTN_SELECT, BTN_TL, BTN_TR, 
                     BTN_THUMBL, BTN_THUMBR, BTN_MODE, BTN_TL2, BTN_TR2};
    for (int i = 0; i < 13; i++) {
        if (ioctl(fd, UI_SET_KEYBIT, buttons[i]) < 0) {
            syslog(LOG_WARNING, "DSTX: Failed to set button %d: %s", buttons[i], strerror(errno));
        }
    }

    int axes[] = {ABS_X, ABS_Y, ABS_RX, ABS_RY, ABS_Z, ABS_RZ, ABS_HAT0X, ABS_HAT0Y};
    for (int i = 0; i < 8; i++) {
        if (ioctl(fd, UI_SET_ABSBIT, axes[i]) < 0) {
            syslog(LOG_WARNING, "DSTX: Failed to set axis %d: %s", axes[i], strerror(errno));
        }
    }

    struct uinput_user_dev u = {0};
    snprintf(u.name, UINPUT_MAX_NAME_SIZE, "DSTX Virtual Xpad #%d", index + 1);
    u.id.bustype = BUS_USB;
    u.id.vendor  = 0x045e; 
    u.id.product = 0x028e; 
    u.id.version = 1;

    u.absmin[ABS_X] = -32768; u.absmax[ABS_X] = 32767;
    u.absmin[ABS_Y] = -32768; u.absmax[ABS_Y] = 32767;
    u.absmin[ABS_RX] = -32768; u.absmax[ABS_RX] = 32767;
    u.absmin[ABS_RY] = -32768; u.absmax[ABS_RY] = 32767;
    u.absmin[ABS_Z] = 0;      u.absmax[ABS_Z] = 255;
    u.absmin[ABS_RZ] = 0;     u.absmax[ABS_RZ] = 255;
    u.absmin[ABS_HAT0X] = -1; u.absmax[ABS_HAT0X] = 1;
    u.absmin[ABS_HAT0Y] = -1; u.absmax[ABS_HAT0Y] = 1;
    u.ff_effects_max = ff_effects;

    if (safe_write(fd, &u, sizeof(u)) != sizeof(u)) {
        syslog(LOG_ERR, "DSTX: Failed to write uinput_user_dev: %s", strerror(errno));
        close(fd);
        return -1;
    }
    
    if (ioctl(fd, UI_DEV_CREATE) < 0) {
        syslog(LOG_ERR, "DSTX: Failed to create uinput device: %s", strerror(errno));
        close(fd);
        return -1;
    }

    struct input_event gain_ev;
    memset(&gain_ev, 0, sizeof(gain_ev));
    gain_ev.type = EV_FF;
    gain_ev.code = FF_GAIN;
    gain_ev.value = 0xFFFF;
    if (safe_write(fd, &gain_ev, sizeof(gain_ev)) != sizeof(gain_ev)) {
        syslog(LOG_WARNING, "DSTX: Failed to set maximum gain on uinput: %s", strerror(errno));
    } else {
        syslog(LOG_DEBUG, "DSTX: Maximum gain set on uinput for slot %d", index);
    }
    
    return fd;
}

// ========================================================================
// DEBOUNCE (for physical buttons)
// ========================================================================

static inline uint64_t time_us(void) {
    struct timeval tv;
    gettimeofday(&tv, NULL);
    return tv.tv_sec * 1000000ULL + tv.tv_usec;
}

// Private structure for physical button debounce (before keymap)
typedef struct {
    uint64_t last_change_us;
    uint8_t pending;
    uint8_t stable;
} phy_debounce_t;

// Global physical debounce array (one per slot, one per physical button)
static phy_debounce_t g_phy_debounce[MAX_SLOTS][PHY_BTN_COUNT];

/**
 * debounce_physical - Applies debounce to a physical button
 * @param slot_idx: Slot index (0..MAX_SLOTS-1)
 * @param phy: Physical button (PHY_BTN_*)
 * @param raw: Raw value read from hardware (0 or 1)
 * @return Stable value after debounce (0 or 1)
 */
static uint8_t debounce_physical(int slot_idx, int phy, uint8_t raw) {
    if (slot_idx < 0 || slot_idx >= MAX_SLOTS) return raw;
    if (phy < 0 || phy >= PHY_BTN_COUNT) return raw;
    
    phy_debounce_t *db = &g_phy_debounce[slot_idx][phy];
    uint64_t now = time_us();
    
    if (raw == db->stable) {
        db->pending = raw;
        return db->stable;
    }
    
    if (raw == db->pending) {
        if (now - db->last_change_us >= DEBOUNCE_DELAY_US) {
            db->stable = raw;
            db->pending = raw;
        }
    } else {
        db->pending = raw;
        db->last_change_us = now;
    }
    
    return db->stable;
}

// ========================================================================
// DUALSHOCK 4 TRANSLATION
// ========================================================================

void translate_ds4(unsigned char *buf, controller_t *slot, int ufd) {
    int offset = (buf[0] == 0x11) ? 3 : 1;
    int slot_idx = (int)(slot - shm_ptr->slots);
    
    // ----- Analog sticks -----
    slot->LX = safe_normalize(buf[offset + 0]);
    slot->LY = safe_normalize(buf[offset + 1]);
    slot->RX = safe_normalize(buf[offset + 2]);
    slot->RY = safe_normalize(buf[offset + 3]);
    
    // Sensitivity
    apply_sensitivity_left(slot, &slot->LX, &slot->LY);
    apply_sensitivity_right(slot, &slot->RX, &slot->RY);
    
    // Y-axis inversion - normalizes any non-zero value as true
    if (atomic_load(&slot->invert_ly)) {
        if (slot->LY == -32768) slot->LY = 32767;
        else slot->LY = -slot->LY;
    }
    if (atomic_load(&slot->invert_ry)) {
        if (slot->RY == -32768) slot->RY = 32767;
        else slot->RY = -slot->RY;
    }
    
    // Triggers: raw values 0-255
    slot->LT = buf[offset + 7];
    slot->RT = buf[offset + 8];
    
    // Deadzone (sticks only) - validate range 0-100
    uint8_t dz = atomic_load(&slot->deadzone);
    if (dz > 100) dz = 0;  // Safe fallback
    apply_deadzone(&slot->LX, &slot->LY, dz);
    apply_deadzone(&slot->RX, &slot->RY, dz);
    
    // ----- Raw button reading -----
    uint8_t buttons  = buf[offset + 4];
    uint8_t buttons2 = buf[offset + 5];
    uint8_t buttons3 = buf[offset + 6];
    
    // Raw state of each physical button (0 or 1)
    uint8_t phy_raw[PHY_BTN_COUNT] = {0};
    
    // Face buttons
    phy_raw[PHY_BTN_SQUARE]   = !!(buttons & 0x10);
    phy_raw[PHY_BTN_CROSS]    = !!(buttons & 0x20);
    phy_raw[PHY_BTN_CIRCLE]   = !!(buttons & 0x40);
    phy_raw[PHY_BTN_TRIANGLE] = !!(buttons & 0x80);
    
    // D-Pad
    uint8_t dpad = buttons & 0x0F;
    phy_raw[PHY_BTN_DPAD_UP]    = (dpad == 0 || dpad == 1 || dpad == 7);
    phy_raw[PHY_BTN_DPAD_DOWN]  = (dpad == 3 || dpad == 4 || dpad == 5);
    phy_raw[PHY_BTN_DPAD_LEFT]  = (dpad == 5 || dpad == 6 || dpad == 7);
    phy_raw[PHY_BTN_DPAD_RIGHT] = (dpad == 1 || dpad == 2 || dpad == 3);
    
    // System buttons
    phy_raw[PHY_BTN_L1]     = !!(buttons2 & 0x01);
    phy_raw[PHY_BTN_R1]     = !!(buttons2 & 0x02);
    phy_raw[PHY_BTN_L2]     = !!(buttons2 & 0x04);
    phy_raw[PHY_BTN_R2]     = !!(buttons2 & 0x08);
    phy_raw[PHY_BTN_SHARE]  = !!(buttons2 & 0x10);
    phy_raw[PHY_BTN_OPTIONS] = !!(buttons2 & 0x20);
    phy_raw[PHY_BTN_L3]     = !!(buttons2 & 0x40);
    phy_raw[PHY_BTN_R3]     = !!(buttons2 & 0x80);
    phy_raw[PHY_BTN_PS]     = !!(buttons3 & 0x01);
    phy_raw[PHY_BTN_TOUCH]  = !!(buttons3 & 0x02);
    
    // ----- Apply debounce (if enabled) -----
    uint8_t phy_stable[PHY_BTN_COUNT];
    if (atomic_load(&slot->debounce_enabled)) {
        for (int i = 0; i < PHY_BTN_COUNT; i++) {
            phy_stable[i] = debounce_physical(slot_idx, i, phy_raw[i]);
        }
    } else {
        memcpy(phy_stable, phy_raw, sizeof(phy_stable));
    }
    
    // ----- Apply keybinds (physical → logical mapping) -----
    // Keymap index validation is handled internally by keys_apply_map()
    keys_apply_map(slot, slot->keymap, phy_stable);
    
    // ----- Send events to virtual device -----
    if (ufd >= 0) {
        // Stick axes
        emit(ufd, EV_ABS, ABS_X,  slot->LX);
        emit(ufd, EV_ABS, ABS_Y,  slot->LY);
        emit(ufd, EV_ABS, ABS_RX, slot->RX);
        emit(ufd, EV_ABS, ABS_RY, slot->RY);
        
        // Digital/analog trigger mode - normalize boolean
        bool trig_digital = (atomic_load(&slot->is_trigger_digital) != 0);
        
        if (!trig_digital) {
            int16_t left_val = 0, right_val = 0;

            // Left trigger (L2)
            if (phy_stable[PHY_BTN_L2]) {
                // Physical trigger pressed: respect keymap
                if (slot->keymap[PHY_BTN_L2] == LOGICAL_BTN_L2)
                    left_val = slot->LT;
                else
                    left_val = 0; // remapped → suppress axis
            } else if (slot->L2) {
                // L2 activated by another button (keybind) → force maximum
                left_val = 255;
            }

            // Right trigger (R2)
            if (phy_stable[PHY_BTN_R2]) {
                if (slot->keymap[PHY_BTN_R2] == LOGICAL_BTN_R2)
                    right_val = slot->RT;
                else
                    right_val = 0;
            } else if (slot->R2) {
                right_val = 255;
            }

            emit(ufd, EV_ABS, ABS_Z,  left_val);
            emit(ufd, EV_ABS, ABS_RZ, right_val);
        }
        
        // Face buttons
        emit(ufd, EV_KEY, BTN_WEST,  slot->triangle);
        emit(ufd, EV_KEY, BTN_NORTH, slot->square);
        emit(ufd, EV_KEY, BTN_SOUTH, slot->cross);
        emit(ufd, EV_KEY, BTN_EAST,  slot->circle);
        
        // D-Pad
        emit(ufd, EV_ABS, ABS_HAT0X, slot->HATX);
        emit(ufd, EV_ABS, ABS_HAT0Y, slot->HATY);
        
        // Top and side buttons
        emit(ufd, EV_KEY, BTN_TL,     slot->L1);
        emit(ufd, EV_KEY, BTN_TR,     slot->R1);
        emit(ufd, EV_KEY, BTN_SELECT, slot->Share);
        emit(ufd, EV_KEY, BTN_START,  slot->Options);
        emit(ufd, EV_KEY, BTN_THUMBL, slot->L3);
        emit(ufd, EV_KEY, BTN_THUMBR, slot->R3);
        emit(ufd, EV_KEY, BTN_MODE,   slot->PS);
        
        // Triggers as digital buttons - send only in digital mode
        if (trig_digital) {
            emit(ufd, EV_KEY, BTN_TL2, slot->L2);
            emit(ufd, EV_KEY, BTN_TR2, slot->R2);
        }
        
        emit(ufd, EV_SYN, SYN_REPORT, 0);
    }
    
    // ----- Battery -----
    uint8_t battery_byte = buf[offset + 29];
    uint8_t level = battery_byte & 0x0F;
    uint8_t cable = (battery_byte & 0x10) ? 1 : 0;
    int new_battery;
    
    if (cable) {
        if (level <= 10) {
            new_battery = (level * 10 + 5) > 100 ? 100 : (level * 10 + 5);
        } else if (level == 11) {
            new_battery = 100;
        } else {
            new_battery = 0;
        }
    } else {
        if (level <= 10) {
            new_battery = (level * 10 + 5) > 100 ? 100 : (level * 10 + 5);
        } else {
            new_battery = 0;
        }
    }
    atomic_store(&slot->battery, new_battery);
}

// ========================================================================
// DUALSENSE TRANSLATION
// ========================================================================

void translate_dualsense(unsigned char *buf, controller_t *slot, int ufd) {
    int offset = (buf[0] == 0x31) ? 2 : 1;
    int slot_idx = (int)(slot - shm_ptr->slots);
    
    // ----- Analog sticks -----
    slot->LX = safe_normalize(buf[offset + 0]);
    slot->LY = safe_normalize(buf[offset + 1]);
    slot->RX = safe_normalize(buf[offset + 2]);
    slot->RY = safe_normalize(buf[offset + 3]);
    
    // Sensitivity
    apply_sensitivity_left(slot, &slot->LX, &slot->LY);
    apply_sensitivity_right(slot, &slot->RX, &slot->RY);
    
    // Y-axis inversion - normalizes any non-zero value as true
    if (atomic_load(&slot->invert_ly)) {
        if (slot->LY == -32768) slot->LY = 32767;
        else slot->LY = -slot->LY;
    }
    if (atomic_load(&slot->invert_ry)) {
        if (slot->RY == -32768) slot->RY = 32767;
        else slot->RY = -slot->RY;
    }
    
    // Triggers: raw values 0-255
    slot->LT = buf[offset + 4];
    slot->RT = buf[offset + 5];
    
    // Deadzone (sticks only) - validate range 0-100
    uint8_t dz = atomic_load(&slot->deadzone);
    if (dz > 100) dz = 0;  // Safe fallback
    apply_deadzone(&slot->LX, &slot->LY, dz);
    apply_deadzone(&slot->RX, &slot->RY, dz);
    
    // ----- Raw button reading -----
    uint8_t buttons_main = buf[offset + 7];
    uint8_t buttons_sys1 = buf[offset + 8];
    uint8_t buttons_sys2 = buf[offset + 9];
    
    uint8_t phy_raw[PHY_BTN_COUNT] = {0};
    
    // Face buttons
    phy_raw[PHY_BTN_SQUARE]   = !!(buttons_main & 0x10);
    phy_raw[PHY_BTN_CROSS]    = !!(buttons_main & 0x20);
    phy_raw[PHY_BTN_CIRCLE]   = !!(buttons_main & 0x40);
    phy_raw[PHY_BTN_TRIANGLE] = !!(buttons_main & 0x80);
    
    // D-Pad
    uint8_t dpad = buttons_main & 0x0F;
    phy_raw[PHY_BTN_DPAD_UP]    = (dpad == 0 || dpad == 1 || dpad == 7);
    phy_raw[PHY_BTN_DPAD_DOWN]  = (dpad == 3 || dpad == 4 || dpad == 5);
    phy_raw[PHY_BTN_DPAD_LEFT]  = (dpad == 5 || dpad == 6 || dpad == 7);
    phy_raw[PHY_BTN_DPAD_RIGHT] = (dpad == 1 || dpad == 2 || dpad == 3);
    
    // System buttons
    phy_raw[PHY_BTN_L1]     = !!(buttons_sys1 & 0x01);
    phy_raw[PHY_BTN_R1]     = !!(buttons_sys1 & 0x02);
    phy_raw[PHY_BTN_L2]     = !!(buttons_sys1 & 0x04);
    phy_raw[PHY_BTN_R2]     = !!(buttons_sys1 & 0x08);
    phy_raw[PHY_BTN_SHARE]  = !!(buttons_sys1 & 0x10);
    phy_raw[PHY_BTN_OPTIONS] = !!(buttons_sys1 & 0x20);
    phy_raw[PHY_BTN_L3]     = !!(buttons_sys1 & 0x40);
    phy_raw[PHY_BTN_R3]     = !!(buttons_sys1 & 0x80);
    phy_raw[PHY_BTN_PS]     = !!(buttons_sys2 & 0x01);
    phy_raw[PHY_BTN_TOUCH]  = !!(buttons_sys2 & 0x02);
    
    // ----- Apply debounce (if enabled) -----
    uint8_t phy_stable[PHY_BTN_COUNT];
    if (atomic_load(&slot->debounce_enabled)) {
        for (int i = 0; i < PHY_BTN_COUNT; i++) {
            phy_stable[i] = debounce_physical(slot_idx, i, phy_raw[i]);
        }
    } else {
        memcpy(phy_stable, phy_raw, sizeof(phy_stable));
    }
    
    // ----- Apply keybinds -----
    // Keymap index validation is handled internally by keys_apply_map()
    keys_apply_map(slot, slot->keymap, phy_stable);
    
    // ----- Send events to virtual device -----
    if (ufd >= 0) {
        // Stick axes
        emit(ufd, EV_ABS, ABS_X,  slot->LX);
        emit(ufd, EV_ABS, ABS_Y,  slot->LY);
        emit(ufd, EV_ABS, ABS_RX, slot->RX);
        emit(ufd, EV_ABS, ABS_RY, slot->RY);
        
        // Digital/analog trigger mode - normalize boolean
        bool trig_digital = (atomic_load(&slot->is_trigger_digital) != 0);
        
        if (!trig_digital) {
            int16_t left_val = 0, right_val = 0;

            // Left trigger (L2)
            if (phy_stable[PHY_BTN_L2]) {
                if (slot->keymap[PHY_BTN_L2] == LOGICAL_BTN_L2)
                    left_val = slot->LT;
                else
                    left_val = 0;
            } else if (slot->L2) {
                left_val = 255;
            }

            // Right trigger (R2)
            if (phy_stable[PHY_BTN_R2]) {
                if (slot->keymap[PHY_BTN_R2] == LOGICAL_BTN_R2)
                    right_val = slot->RT;
                else
                    right_val = 0;
            } else if (slot->R2) {
                right_val = 255;
            }

            emit(ufd, EV_ABS, ABS_Z,  left_val);
            emit(ufd, EV_ABS, ABS_RZ, right_val);
        }
        
        // Face buttons
        emit(ufd, EV_KEY, BTN_WEST,  slot->triangle);
        emit(ufd, EV_KEY, BTN_NORTH, slot->square);
        emit(ufd, EV_KEY, BTN_SOUTH, slot->cross);
        emit(ufd, EV_KEY, BTN_EAST,  slot->circle);
        
        // D-Pad
        emit(ufd, EV_ABS, ABS_HAT0X, slot->HATX);
        emit(ufd, EV_ABS, ABS_HAT0Y, slot->HATY);
        
        // Top and side buttons
        emit(ufd, EV_KEY, BTN_TL,     slot->L1);
        emit(ufd, EV_KEY, BTN_TR,     slot->R1);
        emit(ufd, EV_KEY, BTN_SELECT, slot->Share);
        emit(ufd, EV_KEY, BTN_START,  slot->Options);
        emit(ufd, EV_KEY, BTN_THUMBL, slot->L3);
        emit(ufd, EV_KEY, BTN_THUMBR, slot->R3);
        emit(ufd, EV_KEY, BTN_MODE,   slot->PS);
        
        // Triggers as digital buttons - send only in digital mode
        if (trig_digital) {
            emit(ufd, EV_KEY, BTN_TL2, slot->L2);
            emit(ufd, EV_KEY, BTN_TR2, slot->R2);
        }
        
        emit(ufd, EV_SYN, SYN_REPORT, 0);
    }
    
    // ----- Battery -----
    uint8_t battery_byte = buf[offset + 52];
    uint8_t level = battery_byte & 0x0F;
    uint8_t status = (battery_byte >> 4) & 0x0F;
    int new_battery;
    
    switch (status) {
        case 0x0:
        case 0x1:
        {
            int raw = level * 10 + 5;
            new_battery = (raw > 100) ? 100 : raw;
            break;
        }
        case 0x2:
            new_battery = 100;
            break;
        default:
            new_battery = 0;
            break;
    }
    atomic_store(&slot->battery, new_battery);
}
