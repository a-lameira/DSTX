/*
 * dbus-utils.c - Utility functions for the D-Bus bridge
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
#include <stdatomic.h>
#include <string.h>
#include <sys/mman.h>
#include <sys/stat.h>
#include <fcntl.h>
#include <errno.h>

uint64_t get_time_us(void) {
    struct timeval tv;
    gettimeofday(&tv, NULL);
    return (uint64_t)tv.tv_sec * 1000000 + tv.tv_usec;
}

bool should_emit_signal(uint64_t last_emit, uint64_t min_interval_us) {
    uint64_t now_us = get_time_us();
    return (now_us - last_emit) >= min_interval_us;
}

uint16_t pack_buttons(controller_t *c) {
    uint16_t buttons = 0;
    if (c->cross)     buttons |= (1 << 0);
    if (c->circle)    buttons |= (1 << 1);
    if (c->square)    buttons |= (1 << 2);
    if (c->triangle)  buttons |= (1 << 3);
    if (c->L1)        buttons |= (1 << 4);
    if (c->R1)        buttons |= (1 << 5);
    if (c->L2)        buttons |= (1 << 6);
    if (c->R2)        buttons |= (1 << 7);
    if (c->Share)     buttons |= (1 << 8);
    if (c->Options)   buttons |= (1 << 9);
    if (c->L3)        buttons |= (1 << 10);
    if (c->R3)        buttons |= (1 << 11);
    if (c->PS)        buttons |= (1 << 12);
    if (c->touch_btn) buttons |= (1 << 13);
    return buttons;
}

/* ================== Safe access functions for atomic types (C11) ================== */
bool atomic_load_bool(_Atomic bool *src) {
    return atomic_load_explicit(src, memory_order_relaxed);
}

void atomic_store_bool(_Atomic bool *dst, bool val) {
    atomic_store_explicit(dst, val, memory_order_relaxed);
}

uint8_t atomic_load_uint8(_Atomic uint8_t *src) {
    return atomic_load_explicit(src, memory_order_relaxed);
}

void atomic_store_uint8(_Atomic uint8_t *dst, uint8_t val) {
    atomic_store_explicit(dst, val, memory_order_relaxed);
}

uint32_t atomic_load_uint32(_Atomic uint32_t *src) {
    return atomic_load_explicit(src, memory_order_relaxed);
}

int32_t atomic_load_int32(_Atomic int32_t *src) {
    return atomic_load_explicit(src, memory_order_relaxed);
}

/* ================== State copy ================== */
void copy_controller_state(controller_t *dst, controller_t *src) {
    // Copy non-atomic fields directly
    dst->LX = src->LX;
    dst->LY = src->LY;
    dst->RX = src->RX;
    dst->RY = src->RY;
    dst->LT = src->LT;
    dst->RT = src->RT;
    dst->HATX = src->HATX;
    dst->HATY = src->HATY;
    
    dst->square = src->square;
    dst->cross = src->cross;
    dst->circle = src->circle;
    dst->triangle = src->triangle;
    dst->L1 = src->L1;
    dst->R1 = src->R1;
    dst->L2 = src->L2;
    dst->R2 = src->R2;
    dst->Share = src->Share;
    dst->Options = src->Options;
    dst->L3 = src->L3;
    dst->R3 = src->R3;
    dst->PS = src->PS;
    dst->touch_btn = src->touch_btn;
    dst->battery = src->battery;
    
    dst->dpad_up = src->dpad_up;
    dst->dpad_down = src->dpad_down;
    dst->dpad_left = src->dpad_left;
    dst->dpad_right = src->dpad_right;
    
    dst->is_bluetooth = src->is_bluetooth;
    dst->type = src->type;
    dst->uinput_fd = src->uinput_fd;
    dst->uhid_fd = src->uhid_fd;
    memcpy(dst->uhid_output_buf, src->uhid_output_buf, sizeof(dst->uhid_output_buf));
    
    dst->led_r = src->led_r;
    dst->led_g = src->led_g;
    dst->led_b = src->led_b;
    dst->led_base_r = src->led_base_r;
    dst->led_base_g = src->led_base_g;
    dst->led_base_b = src->led_base_b;
    dst->rumble_weak = src->rumble_weak;
    dst->rumble_strong = src->rumble_strong;
    dst->rumble_gain = src->rumble_gain;
    dst->deadzone = src->deadzone;
    dst->debounce_enabled = src->debounce_enabled;
    dst->global_led_brightness = src->global_led_brightness;
    dst->output_seq = src->output_seq;
    dst->external_retry_count = src->external_retry_count;
    dst->last_external_retry = src->last_external_retry;
    
    dst->active_effect_id = src->active_effect_id;
    dst->active_effect_type = src->active_effect_type;
    memcpy(dst->ff_effects, src->ff_effects, sizeof(dst->ff_effects));
    memcpy(dst->periodic_effects, src->periodic_effects, sizeof(dst->periodic_effects));
    memcpy(dst->effect_type, src->effect_type, sizeof(dst->effect_type));
    memcpy(dst->debounce, src->debounce, sizeof(dst->debounce));
    
    // Copy keymap
    memcpy(dst->keymap, src->keymap, sizeof(dst->keymap));
    
    // Copy atomic fields using helper functions
    atomic_store_bool(&dst->connected, atomic_load_bool(&src->connected));
    atomic_store_bool(&dst->emulate_active, atomic_load_bool(&src->emulate_active));
    atomic_store_bool(&dst->is_uhid, atomic_load_bool(&src->is_uhid));
    atomic_store_bool(&dst->uhid_output_pending, atomic_load_bool(&src->uhid_output_pending));
    atomic_store_bool(&dst->led_dirty, atomic_load_bool(&src->led_dirty));
    atomic_store_bool(&dst->rumble_dirty, atomic_load_bool(&src->rumble_dirty));
    atomic_store_bool(&dst->writing_output, atomic_load_bool(&src->writing_output));
    atomic_store_bool(&dst->led_static, atomic_load_bool(&src->led_static));
    atomic_store_bool(&dst->led_request_pending, atomic_load_bool(&src->led_request_pending));
    atomic_store_bool(&dst->led_reapply, atomic_load_bool(&src->led_reapply));
    atomic_store_bool(&dst->rumble_active, atomic_load_bool(&src->rumble_active));
    atomic_store_bool(&dst->invert_ly, atomic_load_bool(&src->invert_ly));
    atomic_store_bool(&dst->invert_ry, atomic_load_bool(&src->invert_ry));
    atomic_store_bool(&dst->is_trigger_digital, atomic_load_bool(&src->is_trigger_digital));
    
    atomic_store_uint8(&dst->sensitivity_left_preset, atomic_load_uint8(&src->sensitivity_left_preset));
    atomic_store_uint8(&dst->sensitivity_right_preset, atomic_load_uint8(&src->sensitivity_right_preset));
    atomic_store_uint8(&dst->player_leds, atomic_load_uint8(&src->player_leds));
    atomic_store_uint8(&dst->led_request_speed, atomic_load_uint8(&src->led_request_speed));
    atomic_store_uint8(&dst->led_request_brightness, atomic_load_uint8(&src->led_request_brightness));
    
    atomic_store(&dst->led_request_effect, atomic_load(&src->led_request_effect));
    atomic_store(&dst->effect_phase, atomic_load(&src->effect_phase));
    
    // Strings
    strncpy(dst->dev_path, src->dev_path, sizeof(dst->dev_path)-1);
    dst->dev_path[sizeof(dst->dev_path)-1] = '\0';
    strncpy(dst->product_name, src->product_name, sizeof(dst->product_name)-1);
    dst->product_name[sizeof(dst->product_name)-1] = '\0';
    strncpy(dst->uniq, src->uniq, sizeof(dst->uniq)-1);
    dst->uniq[sizeof(dst->uniq)-1] = '\0';
    strncpy(dst->driver, src->driver, sizeof(dst->driver)-1);
    dst->driver[sizeof(dst->driver)-1] = '\0';
    
    dst->num_input_nodes = src->num_input_nodes;
    memcpy(dst->input_nodes, src->input_nodes, sizeof(input_node_info_t) * src->num_input_nodes);
}

/* ================== Comparisons ================== */
bool telemetry_changed(controller_t *a, controller_t *b) {
    return (a->LX != b->LX || a->LY != b->LY ||
            a->RX != b->RX || a->RY != b->RY ||
            a->LT != b->LT || a->RT != b->RT ||
            a->HATX != b->HATX || a->HATY != b->HATY ||
            a->square != b->square || a->cross != b->cross ||
            a->circle != b->circle || a->triangle != b->triangle ||
            a->L1 != b->L1 || a->R1 != b->R1 ||
            a->L2 != b->L2 || a->R2 != b->R2 ||
            a->Share != b->Share || a->Options != b->Options ||
            a->L3 != b->L3 || a->R3 != b->R3 ||
            a->PS != b->PS || a->touch_btn != b->touch_btn ||
            a->dpad_up != b->dpad_up || a->dpad_down != b->dpad_down ||
            a->dpad_left != b->dpad_left || a->dpad_right != b->dpad_right);
}

bool config_changed(controller_t *a, controller_t *b) {
    if (a->led_r != b->led_r || a->led_g != b->led_g || a->led_b != b->led_b ||
        a->rumble_gain != b->rumble_gain || a->deadzone != b->deadzone ||
        a->global_led_brightness != b->global_led_brightness ||
        a->player_leds != b->player_leds ||
        a->debounce_enabled != b->debounce_enabled ||
        atomic_load_bool(&a->emulate_active) != atomic_load_bool(&b->emulate_active) ||
        atomic_load_bool(&a->is_uhid) != atomic_load_bool(&b->is_uhid) ||
        atomic_load_bool(&a->led_reapply) != atomic_load_bool(&b->led_reapply) ||
        atomic_load_bool(&a->rumble_active) != atomic_load_bool(&b->rumble_active) ||
        atomic_load_bool(&a->invert_ly) != atomic_load_bool(&b->invert_ly) ||
        atomic_load_bool(&a->invert_ry) != atomic_load_bool(&b->invert_ry) ||
        atomic_load_bool(&a->is_trigger_digital) != atomic_load_bool(&b->is_trigger_digital) ||
        atomic_load_uint8(&a->sensitivity_left_preset) != atomic_load_uint8(&b->sensitivity_left_preset) ||
        atomic_load_uint8(&a->sensitivity_right_preset) != atomic_load_uint8(&b->sensitivity_right_preset))
        return true;
    
    if (memcmp(a->keymap, b->keymap, sizeof(a->keymap)) != 0)
        return true;
    
    return false;
}

/* ================== SHM Helpers ================== */
shm_handle_t open_shm_handle(DBusConnection *conn, DBusMessage *msg, unsigned char slot) {
    (void)conn; (void)msg;
    shm_handle_t h = {NULL, -1};

    pthread_mutex_lock(&g_state.lock);
    bool alive = g_state.daemon_alive;
    pthread_mutex_unlock(&g_state.lock);
    
    if (!alive) {
        return h;
    }
    
    if (slot >= MAX_SLOTS) {
        return h;
    }

    h.fd = shm_open(SHM_PATH, O_RDWR, 0660);
    if (h.fd == -1) return h;

    struct stat st;
    if (fstat(h.fd, &st) == -1 || (size_t)st.st_size < sizeof(shared_data_t)) {
        close(h.fd);
        h.fd = -1;
        return h;
    }

    h.shm = mmap(NULL, sizeof(shared_data_t), PROT_READ | PROT_WRITE,
                 MAP_SHARED, h.fd, 0);
    if (h.shm == MAP_FAILED) {
        close(h.fd);
        h.fd = -1;
        h.shm = NULL;
        return h;
    }

    if (h.shm->magic != SHM_MAGIC_VALUE) {
        munmap(h.shm, sizeof(shared_data_t));
        close(h.fd);
        h.shm = NULL;
        h.fd = -1;
        return h;
    }

    pthread_mutex_lock(&h.shm->proc_mutex);
    
    bool slot_connected = atomic_load_bool(&h.shm->slots[slot].connected);
    if (!slot_connected) {
        pthread_mutex_unlock(&h.shm->proc_mutex);
        munmap(h.shm, sizeof(shared_data_t));
        close(h.fd);
        h.shm = NULL;
        h.fd = -1;
        return h;
    }
    return h;
}

void close_shm_handle(shm_handle_t *h) {
    if (h->shm) {
        pthread_mutex_unlock(&h->shm->proc_mutex);
        munmap(h->shm, sizeof(shared_data_t));
    }
    if (h->fd != -1) close(h->fd);
    h->shm = NULL;
    h->fd = -1;
}

shared_data_t* open_shm_handle_any(DBusConnection *conn, DBusMessage *msg) {
    (void)conn; (void)msg;
    pthread_mutex_lock(&g_state.lock);
    bool alive = g_state.daemon_alive;
    pthread_mutex_unlock(&g_state.lock);
    if (!alive) return NULL;

    int fd = shm_open(SHM_PATH, O_RDWR, 0660);
    if (fd == -1) return NULL;

    struct stat st;
    if (fstat(fd, &st) == -1 || (size_t)st.st_size < sizeof(shared_data_t)) {
        close(fd);
        return NULL;
    }

    shared_data_t *shm = mmap(NULL, sizeof(shared_data_t), PROT_READ | PROT_WRITE, MAP_SHARED, fd, 0);
    if (shm == MAP_FAILED) {
        close(fd);
        return NULL;
    }

    if (shm->magic != SHM_MAGIC_VALUE) {
        munmap(shm, sizeof(shared_data_t));
        close(fd);
        return NULL;
    }

    return shm;
}

void close_shm_handle_any(shared_data_t *shm) {
    if (shm) munmap(shm, sizeof(shared_data_t));
}

/* ================== Synchronous communication with daemon via SHM ================== */
#define PROFILE_REQUEST_TIMEOUT_MS 1000

bool shm_request_sync(shared_data_t *shm, int request, const char *name,
                      int auto_enable, int auto_delay, char *out_msg, size_t msg_size) {
    if (!shm || !out_msg || msg_size == 0) return false;

    pthread_mutex_lock(&shm->proc_mutex);
    atomic_store(&shm->profile_request, request);
    if (name) {
        strncpy(shm->profile_name, name, PROFILE_NAME_LEN - 1);
        shm->profile_name[PROFILE_NAME_LEN - 1] = '\0';
    } else {
        shm->profile_name[0] = '\0';
    }
    if (auto_enable >= 0) atomic_store(&shm->auto_save_enabled, auto_enable);
    if (auto_delay >= 0) atomic_store(&shm->auto_save_delay_ms, auto_delay);
    atomic_store(&shm->profile_response, 0);
    shm->profile_response_msg[0] = '\0';
    pthread_mutex_unlock(&shm->proc_mutex);

    const int timeout_ms = PROFILE_REQUEST_TIMEOUT_MS;
    const int step_ms = 20;
    int waited = 0;
    while (waited < timeout_ms) {
        usleep(step_ms * 1000);
        waited += step_ms;
        int resp = atomic_load(&shm->profile_response);
        if (resp != 0) {
            pthread_mutex_lock(&shm->proc_mutex);
            snprintf(out_msg, msg_size, "%s", shm->profile_response_msg);
            atomic_store(&shm->profile_response, 0);
            pthread_mutex_unlock(&shm->proc_mutex);
            return (resp == 1);
        }
    }
    snprintf(out_msg, msg_size, "Timeout waiting for daemon response");
    return false;
}
