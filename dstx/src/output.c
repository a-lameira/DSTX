/*
 * output.c - Unified output report handling for DSTX
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
#include <math.h>

// ========================================================================
// REPORT FORMAT CONSTANTS
// ========================================================================
#define DS4_USB_REPORT_SIZE 32
#define DS4_BT_REPORT_SIZE 78
#define DS_USB_REPORT_SIZE 48
#define DS_BT_REPORT_SIZE 78

// DS4 USB flags
#define DS4_FLAG_RUMBLE  0x01
#define DS4_FLAG_LED     0x02
#define DS4_FLAG_FLASH   0x04

// ========================================================================
// HELPER FUNCTION FOR PLAYER LEDS MAPPING (DUALSENSE)
// ========================================================================
/**
 * Maps player mode (0-5) to Player LEDs configuration byte
 * Based on DualSense documentation:
 * 0: off        (0x00)
 * 1: player 1   (0x04) - -x- -
 * 2: player 2   (0x06) - x-x -
 * 3: player 3   (0x15) x -x- x
 * 4: player 4   (0x1B) x x-x x
 * 5: player 5   (0x1F) x xxx x (not confirmed)
 */
static inline uint8_t player_leds_to_byte(uint8_t mode) {
    static const uint8_t map[] = {
        0x00,  // 0: off
        0x04,  // 1: player 1
        0x06,  // 2: player 2
        0x15,  // 3: player 3
        0x1B,  // 4: player 4
        0x1F   // 5: player 5
    };

    if (mode > 5) return 0x00;
    return map[mode];
}

// ========================================================================
// HELPER FUNCTION TO APPLY GLOBAL BRIGHTNESS
// ========================================================================
static inline uint8_t scale_led(uint8_t value, uint8_t brightness) {
    // brightness already validated (0-100) before use
    return (uint16_t)value * brightness / 100;
}

// ========================================================================
// HELPER FUNCTION TO CLAMP SHM VALUES
// ========================================================================
static inline uint8_t clamp_u8(int val, uint8_t min, uint8_t max, uint8_t def) {
    if (val < min || val > max) return def;
    return (uint8_t)val;
}

// ========================================================================
// HELPER FUNCTION TO COMPUTE PERIODIC WAVE VALUE
// ========================================================================
static uint8_t compute_periodic_wave(periodic_effect_t *p, struct timeval *now) {
    long elapsed_us = (now->tv_sec - p->start_time.tv_sec) * 1000000L +
                      (now->tv_usec - p->start_time.tv_usec);
    long period_us = p->period * 1000L;  // period is in ms in the effect
    if (period_us <= 0) return 0;

    double t = (double)(elapsed_us % period_us) / 1000.0;
    double norm = t / p->period;
    double wave;

    switch (p->waveform) {
        case FF_SINE:
            wave = sin(2 * M_PI * norm);
            break;
        case FF_SQUARE:
            wave = (norm < 0.5) ? 1.0 : -1.0;
            break;
        case FF_TRIANGLE:
            wave = 2.0 * fabs(2.0 * norm - 1.0) - 1.0;
            break;
        default:
            wave = 0.0;
    }

    double value = p->offset + p->magnitude * wave;
    if (value < 0) value = 0;
    if (value > 32767) value = 32767;
    return (uint8_t)(value / 128);
}

// ========================================================================
// HELPER FUNCTION: split wave into two channels
// ========================================================================
static void apply_wave_to_rumble(controller_t *slot, uint8_t wave_value) {
    if (wave_value > 127) {
        atomic_store(&slot->rumble_strong, wave_value);
        atomic_store(&slot->rumble_weak, 0);
    } else {
        atomic_store(&slot->rumble_strong, 0);
        atomic_store(&slot->rumble_weak, wave_value);
    }
}

// ========================================================================
// REPORT BUILDERS - DUALSHOCK 4
// ========================================================================
static void build_ds4_usb_report(uint8_t *report, const controller_t *slot) {
    memset(report, 0, DS4_USB_REPORT_SIZE);

    report[0] = 0x05;
    report[1] = DS4_FLAG_RUMBLE | DS4_FLAG_LED | DS4_FLAG_FLASH;
    report[2] = 0x00;

    // RUMBLE (order: Strong, Weak)
    report[4] = slot->rumble_strong;
    report[5] = slot->rumble_weak;

    report[6] = scale_led(slot->led_r, slot->global_led_brightness);
    report[7] = scale_led(slot->led_g, slot->global_led_brightness);
    report[8] = scale_led(slot->led_b, slot->global_led_brightness);

    report[9] = 0x00;
    report[10] = 0x00;
}

static void build_ds4_bt_report(uint8_t *report, const controller_t *slot) {
    memset(report, 0, DS4_BT_REPORT_SIZE);

    report[0] = 0x11;
    report[1] = 0x80;
    report[3] = 0x03;

    report[6] = slot->rumble_weak;
    report[7] = slot->rumble_strong;

    report[8] = scale_led(slot->led_r, slot->global_led_brightness);
    report[9] = scale_led(slot->led_g, slot->global_led_brightness);
    report[10] = scale_led(slot->led_b, slot->global_led_brightness);

    uint8_t bt_hdr = 0xA2;
    uint32_t crc = crc32(0L, Z_NULL, 0);
    crc = crc32(crc, &bt_hdr, 1);
    crc = crc32(crc, report, 74);
    memcpy(&report[74], &crc, 4);
}

// ========================================================================
// REPORT BUILDERS - DUALSENSE
// ========================================================================
static void build_dualsense_usb_report(uint8_t *report, const controller_t *slot) {
    memset(report, 0, DS_USB_REPORT_SIZE);

    report[0] = 0x02;
    report[1] = 0x01 | 0x02 | 0x10;
    report[2] = 0x01 | 0x02 | 0x04 | 0x10;

    report[3] = slot->rumble_weak;
    report[4] = slot->rumble_strong;

    report[40] = 0x02;
    report[42] = 0x00;
    report[44] = player_leds_to_byte(slot->player_leds);

    report[45] = scale_led(slot->led_r, slot->global_led_brightness);
    report[46] = scale_led(slot->led_g, slot->global_led_brightness);
    report[47] = scale_led(slot->led_b, slot->global_led_brightness);
}

static void build_dualsense_bt_report(uint8_t *report, const controller_t *slot) {
    memset(report, 0, DS_BT_REPORT_SIZE);

    report[0] = 0x31;
    report[1] = 0x02;
    report[2] = 0x01 | 0x02 | 0x10;
    report[3] = 0x01 | 0x02 | 0x04 | 0x10;

    report[4] = slot->rumble_weak;
    report[5] = slot->rumble_strong;

    report[41] = 0x02;
    report[44] = 0x00;
    report[45] = player_leds_to_byte(slot->player_leds);

    report[46] = scale_led(slot->led_r, slot->global_led_brightness);
    report[47] = scale_led(slot->led_g, slot->global_led_brightness);
    report[48] = scale_led(slot->led_b, slot->global_led_brightness);

    uint8_t bt_hdr = 0xA2;
    uint32_t crc = crc32(0L, Z_NULL, 0);
    crc = crc32(crc, &bt_hdr, 1);
    crc = crc32(crc, report, 74);
    memcpy(&report[74], &crc, 4);
}

// ========================================================================
// MAIN OUTPUT FUNCTION
// ========================================================================
void send_output_report(int fd, controller_t *slot) {
    if (fd < 0 || !slot) return;
    if (!atomic_load(&slot->connected)) return;

    uint8_t local_rumble_strong, local_rumble_weak;
    uint8_t local_led_r, local_led_g, local_led_b;
    uint8_t local_global_brightness;
    controller_type_t local_type;
    bool local_is_bt;
    uint8_t local_output_seq;
    uint8_t local_player_leds;
    uint8_t local_gain;

    safe_shm_lock(&shm_ptr->proc_mutex);

    local_rumble_strong = atomic_load(&slot->rumble_strong);
    local_rumble_weak   = atomic_load(&slot->rumble_weak);
    local_player_leds   = atomic_load(&slot->player_leds);
    local_gain          = slot->rumble_gain;

    local_led_r         = slot->led_r;
    local_led_g         = slot->led_g;
    local_led_b         = slot->led_b;
    local_global_brightness = slot->global_led_brightness;
    local_type          = slot->type;
    local_is_bt         = slot->is_bluetooth;
    local_output_seq    = slot->output_seq;

    pthread_mutex_unlock(&shm_ptr->proc_mutex);

    // VALIDATION: ensure values are within allowed ranges
    local_gain = clamp_u8(local_gain, 0, 100, 100);
    local_global_brightness = clamp_u8(local_global_brightness, 0, 100, 80);
    local_player_leds = clamp_u8(local_player_leds, 0, 5, 0);

    uint8_t strong_gained = (uint16_t)local_rumble_strong * local_gain / 100;
    uint8_t weak_gained   = (uint16_t)local_rumble_weak   * local_gain / 100;

    ptrdiff_t diff = slot - shm_ptr->slots;
    int slot_index = (int)diff;
    
    // Rate-limited log (max 1 per second) for output debugging
    log_ratelimit_time(LOG_CAT_OUTPUT, 1000000, LOG_DEBUG,
                       "OUTPUT: Slot %d - Rumble(raw=%d,%d gain=%d -> %d,%d) LED(%d,%d,%d) Bright=%d PlayerLEDs=%d",
                       slot_index, local_rumble_strong, local_rumble_weak, local_gain,
                       strong_gained, weak_gained,
                       local_led_r, local_led_g, local_led_b, local_global_brightness,
                       local_player_leds);

    uint8_t report[DS4_BT_REPORT_SIZE];
    size_t report_size = 0;

    controller_t tmp;
    memset(&tmp, 0, sizeof(tmp));
    tmp.rumble_strong = strong_gained;
    tmp.rumble_weak   = weak_gained;
    tmp.led_r         = local_led_r;
    tmp.led_g         = local_led_g;
    tmp.led_b         = local_led_b;
    tmp.global_led_brightness = local_global_brightness;
    tmp.type          = local_type;
    tmp.is_bluetooth  = local_is_bt;
    tmp.output_seq    = local_output_seq;
    tmp.player_leds   = local_player_leds;

    switch (local_type) {
        case TYPE_DS4:
            if (local_is_bt) {
                build_ds4_bt_report(report, &tmp);
                report_size = DS4_BT_REPORT_SIZE;
            } else {
                build_ds4_usb_report(report, &tmp);
                report_size = DS4_USB_REPORT_SIZE;
            }
            break;

        case TYPE_DUALSENSE:
            if (local_is_bt) {
                build_dualsense_bt_report(report, &tmp);
                report_size = DS_BT_REPORT_SIZE;
            } else {
                build_dualsense_usb_report(report, &tmp);
                report_size = DS_USB_REPORT_SIZE;
            }
            break;

        case TYPE_NSW_PRO:
            syslog(LOG_WARNING, "OUTPUT: send_output_report called for NSW Pro - this should not happen");
            return;

        default:
            syslog(LOG_WARNING, "OUTPUT: Unknown controller type %d", local_type);
            return;
    }

    // safe_write() guarantees full write or error
    ssize_t written = safe_write(fd, report, report_size);
    if (written < 0) {
        syslog(LOG_ERR, "OUTPUT: Failed to write report: %s", strerror(errno));
    } else if ((size_t)written != report_size) {
        // safe_write already guarantees full write or error, but keep check for safety
        syslog(LOG_WARNING, "OUTPUT: Partial write: %zd/%zu bytes", written, report_size);
    }
}

// ========================================================================
// RUMBLE PIPELINE
// ========================================================================

bool rumble_handle_ff_upload(int ufd, struct input_event *ev, controller_t *slot) {
    if (ev->type != EV_UINPUT || ev->code != UI_FF_UPLOAD) return false;

    struct uinput_ff_upload upload;
    memset(&upload, 0, sizeof(upload));
    upload.request_id = ev->value;

    if (ioctl(ufd, UI_BEGIN_FF_UPLOAD, &upload) != 0) return false;

    bool updated = false;
    int effect_id = upload.effect.id;

    if (effect_id >= 0 && effect_id < 16) {
        if (upload.effect.type == FF_RUMBLE) {
            slot->effect_type[effect_id] = 1;
            uint16_t raw_strong = upload.effect.u.rumble.strong_magnitude >> 8;
            uint16_t raw_weak   = upload.effect.u.rumble.weak_magnitude >> 8;
            slot->ff_effects[effect_id].strong = raw_strong;
            slot->ff_effects[effect_id].weak   = raw_weak;
            updated = true;
            syslog(LOG_DEBUG, "RUMBLE: Slot %d effect %d loaded (raw): S=%d W=%d",
                   (int)(slot - shm_ptr->slots), effect_id, raw_strong, raw_weak);
        }
        else if (upload.effect.type == FF_PERIODIC) {
            slot->effect_type[effect_id] = 2;
            periodic_effect_t *p = &slot->periodic_effects[effect_id];

            p->waveform = upload.effect.u.periodic.waveform;
            p->period   = upload.effect.u.periodic.period;
            p->magnitude = upload.effect.u.periodic.magnitude;
            p->offset    = upload.effect.u.periodic.offset;
            p->phase     = upload.effect.u.periodic.phase;
            p->active    = false;
            p->last_value = 0;
            p->left_freq = 0;
            p->right_freq = 0;

            syslog(LOG_DEBUG, "PERIODIC: Slot %d effect %d: wave=%d, period=%d ms, mag=%d",
                   (int)(slot - shm_ptr->slots), effect_id,
                   p->waveform, p->period, p->magnitude);

            updated = true;
        }
    }

    upload.retval = 0;
    ioctl(ufd, UI_END_FF_UPLOAD, &upload);
    return updated;
}

void rumble_handle_ff_event(struct input_event *ev, controller_t *slot) {
    if (!atomic_load(&slot->rumble_active)) {
        if (ev->type == EV_FF && ev->value == 0) {
            // allow stop command
        } else {
            syslog(LOG_DEBUG, "RUMBLE: FF event ignored (rumble inactive) on slot %d",
                   (int)(slot - shm_ptr->slots));
            return;
        }
    }

    if (ev->type == EV_FF) {
        int effect_id = ev->code;
        if (effect_id < 0 || effect_id >= 16) return;

        if (ev->value > 0) { // start
            if (slot->effect_type[effect_id] == 1) { // rumble
                atomic_store(&slot->rumble_strong, slot->ff_effects[effect_id].strong);
                atomic_store(&slot->rumble_weak,   slot->ff_effects[effect_id].weak);
                atomic_store(&slot->rumble_dirty, true);
                slot->active_effect_id = -1;
                slot->active_effect_type = 0;
                syslog(LOG_DEBUG, "RUMBLE: Slot %d started effect %d (raw): S=%d W=%d",
                       (int)(slot - shm_ptr->slots), effect_id,
                       slot->ff_effects[effect_id].strong, slot->ff_effects[effect_id].weak);
            }
            else if (slot->effect_type[effect_id] == 2) { // periodic
                slot->active_effect_id = effect_id;
                slot->active_effect_type = 2;
                periodic_effect_t *p = &slot->periodic_effects[effect_id];
                gettimeofday(&p->start_time, NULL);
                p->active = true;

                uint8_t first_val = compute_periodic_wave(p, &p->start_time);
                apply_wave_to_rumble(slot, first_val);
                p->last_value = first_val;
                atomic_store(&slot->rumble_dirty, true);
                syslog(LOG_DEBUG, "PERIODIC: Slot %d started effect %d, first value=%d",
                       (int)(slot - shm_ptr->slots), effect_id, first_val);
            }
        } else { // stop (value == 0)
            if (slot->active_effect_id == effect_id) {
                slot->active_effect_id = -1;
                slot->active_effect_type = 0;
                atomic_store(&slot->rumble_strong, 0);
                atomic_store(&slot->rumble_weak, 0);
                atomic_store(&slot->rumble_dirty, true);
                syslog(LOG_DEBUG, "EFFECT: Slot %d stopped effect %d",
                       (int)(slot - shm_ptr->slots), effect_id);
            }
        }
    }
}

bool rumble_process_pipeline(int fd, controller_t *slot, struct timeval *last_rumble_time) {
    struct timeval now;
    gettimeofday(&now, NULL);
    long elapsed = (now.tv_sec - last_rumble_time->tv_sec) * 1000000L +
                   (now.tv_usec - last_rumble_time->tv_usec);

    int slot_index = (int)(slot - shm_ptr->slots);
    bool should_send = false;
    uint16_t left_freq = 0, right_freq = 0;

    // Process active periodic effect (only NSW Pro)
    if (slot->type == TYPE_NSW_PRO &&
        slot->active_effect_type == 2 &&
        slot->active_effect_id >= 0) {

        int eid = slot->active_effect_id;
        periodic_effect_t *p = &slot->periodic_effects[eid];

        uint8_t new_val = compute_periodic_wave(p, &now);
        if (new_val != p->last_value) {
            apply_wave_to_rumble(slot, new_val);
            atomic_store(&slot->rumble_dirty, true);
            p->last_value = new_val;
            left_freq = p->left_freq;
            right_freq = p->right_freq;
            // Rate-limited log for periodic values (1 per second)
            log_ratelimit_time(LOG_CAT_RUMBLE, 1000000, LOG_DEBUG,
                               "PERIODIC: Slot %d new value %d (fL=%u, fR=%u) -> S=%d W=%d",
                               slot_index, new_val, left_freq, right_freq,
                               atomic_load(&slot->rumble_strong), atomic_load(&slot->rumble_weak));
        }
    }

    // Sending logic
    safe_shm_lock(&shm_ptr->proc_mutex);
    bool rumble_dirty = atomic_load(&slot->rumble_dirty);
    uint8_t strong = atomic_load(&slot->rumble_strong);
    uint8_t weak   = atomic_load(&slot->rumble_weak);
    pthread_mutex_unlock(&shm_ptr->proc_mutex);

    if (rumble_dirty && elapsed >= RUMBLE_TIMEOUT_US) {
        should_send = true;
    } else if ((strong > 0 || weak > 0) && elapsed >= RUMBLE_KEEPALIVE_US) {
        should_send = true;
    }

    if (should_send && atomic_load(&slot->connected)) {
        atomic_store(&slot->writing_output, true);

        if (slot->type == TYPE_NSW_PRO) {
            nsw_send_rumble(fd, slot, left_freq, right_freq);
        } else {
            send_output_report(fd, slot);
        }

        atomic_store(&slot->writing_output, false);

        safe_shm_lock(&shm_ptr->proc_mutex);
        atomic_store(&slot->rumble_dirty, false);
        pthread_mutex_unlock(&shm_ptr->proc_mutex);

        *last_rumble_time = now;
        return true;
    }

    return false;
}

// ========================================================================
// UNIFIED LED PIPELINE
// ========================================================================

bool led_process_pipeline(int fd, controller_t *slot, struct timeval *last_led_time) {
    safe_shm_lock(&shm_ptr->proc_mutex);
    bool led_dirty = atomic_load(&slot->led_dirty);
    bool is_static = atomic_load(&slot->led_static);
    uint8_t retry_count = slot->external_retry_count;
    struct timeval last_retry = slot->last_external_retry;
    pthread_mutex_unlock(&shm_ptr->proc_mutex);

    if (!led_dirty && retry_count == 0) return false;

    struct timeval now;
    gettimeofday(&now, NULL);

    int timeout_us;
    if (retry_count > 0) {
        timeout_us = 100000; // 100ms
    } else {
        timeout_us = is_static ? LED_TIMEOUT_US : LED_FAST_TIMEOUT_US;
    }

    struct timeval *last = (retry_count > 0) ? &last_retry : last_led_time;
    long elapsed = (now.tv_sec - last->tv_sec) * 1000000L +
                   (now.tv_usec - last->tv_usec);

    if (elapsed >= timeout_us) {
        atomic_store(&slot->writing_output, true);
        send_output_report(fd, slot);
        atomic_store(&slot->writing_output, false);

        safe_shm_lock(&shm_ptr->proc_mutex);
        if (retry_count > 0) {
            slot->last_external_retry = now;
            if (slot->external_retry_count > 0) {
                slot->external_retry_count--;
            }
        } else {
            *last_led_time = now;
            atomic_store(&slot->led_dirty, false);
        }
        pthread_mutex_unlock(&shm_ptr->proc_mutex);

        // Rate-limited log (max 1 per second) for LED pipeline
        log_ratelimit_time(LOG_CAT_LED, 1000000, LOG_DEBUG,
                           "LED_PIPELINE: Slot %d - sent (remaining retries=%d)",
                           (int)(slot - shm_ptr->slots), retry_count > 0 ? slot->external_retry_count : 0);
        return true;
    }

    return false;
}
