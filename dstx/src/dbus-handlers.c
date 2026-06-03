/*
 * dbus-handlers.c - D-Bus method handlers
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
#include "dbus-systemd.h"
#include "keys.h"
#include <string.h>
#include <stdlib.h>

/* Helper to send an error reply */
static void send_error(DBusConnection *conn, DBusMessage *msg,
                       const char *error_name, const char *error_msg) {
    atomic_fetch_add(&g_errors_occurred, 1);
    DBusMessage *reply = dbus_message_new_error(msg, error_name, error_msg);
    if (reply) {
        dbus_connection_send(conn, reply, NULL);
        dbus_message_unref(reply);
    }
}

static bool send_basic_reply(DBusConnection *conn, DBusMessage *msg) {
    DBusMessage *reply = dbus_message_new_method_return(msg);
    if (!reply) {
        send_error(conn, msg, DBUS_ERROR_FAILED, "Failed to create reply");
        return false;
    }
    if (!dbus_connection_send(conn, reply, NULL)) {
        send_error(conn, msg, DBUS_ERROR_FAILED, "Failed to send reply");
        dbus_message_unref(reply);
        return false;
    }
    dbus_message_unref(reply);
    atomic_fetch_add(&g_methods_called, 1);
    return true;
}

/* ================== Read handlers (getters) ================== */

static void handle_get_core_version(DBusConnection *conn, DBusMessage *msg) {
    DBusMessage *reply = dbus_message_new_method_return(msg);
    if (!reply) {
        send_error(conn, msg, DBUS_ERROR_FAILED, "Failed to create reply");
        return;
    }
    const char *version = DSTX_CORE_VERSION;
    if (!dbus_message_append_args(reply, DBUS_TYPE_STRING, &version, DBUS_TYPE_INVALID)) {
        send_error(conn, msg, DBUS_ERROR_FAILED, "Failed to append version");
        dbus_message_unref(reply);
        return;
    }
    dbus_connection_send(conn, reply, NULL);
    dbus_message_unref(reply);
    atomic_fetch_add(&g_methods_called, 1);
}

static void handle_get_controllers(DBusConnection *conn, DBusMessage *msg) {
    DBusMessage *reply = dbus_message_new_method_return(msg);
    if (!reply) {
        send_error(conn, msg, DBUS_ERROR_FAILED, "Failed to create reply");
        return;
    }

    DBusMessageIter iter, array_iter;
    dbus_message_iter_init_append(reply, &iter);
    
    if (!dbus_message_iter_open_container(&iter, DBUS_TYPE_ARRAY, DBUS_TYPE_BYTE_AS_STRING, &array_iter)) {
        send_error(conn, msg, DBUS_ERROR_FAILED, "Failed to open array container");
        dbus_message_unref(reply);
        return;
    }

    pthread_mutex_lock(&g_state.lock);
    if (g_state.daemon_alive) {
        for (int i = 0; i < MAX_SLOTS; i++) {
            if (atomic_load_bool(&g_state.slots[i].connected)) {
                unsigned char slot = i;
                dbus_message_iter_append_basic(&array_iter, DBUS_TYPE_BYTE, &slot);
            }
        }
    }
    pthread_mutex_unlock(&g_state.lock);

    dbus_message_iter_close_container(&iter, &array_iter);
    dbus_connection_send(conn, reply, NULL);
    dbus_message_unref(reply);
    atomic_fetch_add(&g_methods_called, 1);
}

static void handle_get_controller_info(DBusConnection *conn, DBusMessage *msg) {
    unsigned char slot;
    if (!dbus_message_get_args(msg, NULL, DBUS_TYPE_BYTE, &slot, DBUS_TYPE_INVALID)) {
        send_error(conn, msg, DBUS_ERROR_INVALID_ARGS, "Expected slot number");
        return;
    }
    if (slot >= MAX_SLOTS) {
        send_error(conn, msg, DBUS_ERROR_INVALID_ARGS, "Slot out of range");
        return;
    }

    pthread_mutex_lock(&g_state.lock);
    if (!g_state.daemon_alive) {
        pthread_mutex_unlock(&g_state.lock);
        send_error(conn, msg, DBUS_ERROR_FAILED, "Daemon not connected");
        return;
    }
    
    bool connected = atomic_load_bool(&g_state.slots[slot].connected);
    if (!connected) {
        pthread_mutex_unlock(&g_state.lock);
        send_error(conn, msg, DBUS_ERROR_FAILED, "Controller not connected");
        return;
    }

    controller_t *c = &g_state.slots[slot];
    DBusMessage *reply = dbus_message_new_method_return(msg);
    if (!reply) {
        pthread_mutex_unlock(&g_state.lock);
        send_error(conn, msg, DBUS_ERROR_FAILED, "Failed to create reply");
        return;
    }

    uint32_t type = c->type;
    uint32_t bt = c->is_bluetooth ? 1 : 0;
    uint32_t led_r = c->led_r;
    uint32_t led_g = c->led_g;
    uint32_t led_b = c->led_b;
    uint32_t led_base_r = c->led_base_r;
    uint32_t led_base_g = c->led_base_g;
    uint32_t led_base_b = c->led_base_b;
    uint32_t battery = c->battery;
    uint32_t gain = c->rumble_gain;
    uint32_t deadzone = c->deadzone;
    uint32_t global_brightness = c->global_led_brightness;
    uint32_t player_leds = atomic_load_uint8(&c->player_leds);
    uint32_t emulate = atomic_load_bool(&c->emulate_active) ? 1 : 0;
    uint32_t is_uhid = atomic_load_bool(&c->is_uhid) ? 1 : 0;
    uint32_t triggers_digital = atomic_load_bool(&c->is_trigger_digital) ? 1 : 0;
    uint32_t debounce_enabled = c->debounce_enabled ? 1 : 0;
    uint32_t led_reapply = atomic_load_bool(&c->led_reapply) ? 1 : 0;
    uint32_t rumble_active = atomic_load_bool(&c->rumble_active) ? 1 : 0;
    uint32_t invert_ly = atomic_load_bool(&c->invert_ly) ? 1 : 0;
    uint32_t invert_ry = atomic_load_bool(&c->invert_ry) ? 1 : 0;
    uint32_t sensitivity_left = atomic_load_uint8(&c->sensitivity_left_preset);
    uint32_t sensitivity_right = atomic_load_uint8(&c->sensitivity_right_preset);
    uint32_t led_static_val = atomic_load_bool(&c->led_static) ? 1 : 0;
    uint32_t current_effect = (uint32_t)atomic_load(&c->led_request_effect);
    if (current_effect > 8) current_effect = 0;
    uint32_t effect_speed = atomic_load_uint8(&c->led_request_speed);
    if (effect_speed < 1) effect_speed = 5;

    int32_t lx = c->LX, ly = c->LY;
    int32_t rx = c->RX, ry = c->RY;
    int32_t lt = c->LT, rt = c->RT;
    int32_t hatx = c->HATX, haty = c->HATY;

    uint32_t square = c->square, cross = c->cross;
    uint32_t circle = c->circle, triangle = c->triangle;
    uint32_t l1 = c->L1, r1 = c->R1;
    uint32_t l2 = c->L2, r2 = c->R2;
    uint32_t share = c->Share, options = c->Options;
    uint32_t ps = c->PS;
    uint32_t l3 = c->L3, r3 = c->R3;
    uint32_t touch_btn = c->touch_btn;
    uint32_t dpad_up = c->dpad_up, dpad_down = c->dpad_down;
    uint32_t dpad_left = c->dpad_left, dpad_right = c->dpad_right;

    pthread_mutex_unlock(&g_state.lock);

    dbus_message_append_args(reply,
        DBUS_TYPE_UINT32, &type,
        DBUS_TYPE_UINT32, &bt,
        DBUS_TYPE_UINT32, &led_r,
        DBUS_TYPE_UINT32, &led_g,
        DBUS_TYPE_UINT32, &led_b,
        DBUS_TYPE_UINT32, &led_base_r,
        DBUS_TYPE_UINT32, &led_base_g,
        DBUS_TYPE_UINT32, &led_base_b,
        DBUS_TYPE_UINT32, &battery,
        DBUS_TYPE_UINT32, &gain,
        DBUS_TYPE_UINT32, &deadzone,
        DBUS_TYPE_UINT32, &global_brightness,
        DBUS_TYPE_UINT32, &player_leds,
        DBUS_TYPE_UINT32, &emulate,
        DBUS_TYPE_UINT32, &is_uhid,
        DBUS_TYPE_UINT32, &triggers_digital,
        DBUS_TYPE_UINT32, &debounce_enabled,
        DBUS_TYPE_UINT32, &led_reapply,
        DBUS_TYPE_UINT32, &rumble_active,
        DBUS_TYPE_UINT32, &invert_ly,
        DBUS_TYPE_UINT32, &invert_ry,
        DBUS_TYPE_UINT32, &sensitivity_left,
        DBUS_TYPE_UINT32, &sensitivity_right,
        DBUS_TYPE_UINT32, &led_static_val,
        DBUS_TYPE_UINT32, &current_effect,
        DBUS_TYPE_UINT32, &effect_speed,
        DBUS_TYPE_INT32, &lx,
        DBUS_TYPE_INT32, &ly,
        DBUS_TYPE_INT32, &rx,
        DBUS_TYPE_INT32, &ry,
        DBUS_TYPE_INT32, &lt,
        DBUS_TYPE_INT32, &rt,
        DBUS_TYPE_INT32, &hatx,
        DBUS_TYPE_INT32, &haty,
        DBUS_TYPE_UINT32, &square,
        DBUS_TYPE_UINT32, &cross,
        DBUS_TYPE_UINT32, &circle,
        DBUS_TYPE_UINT32, &triangle,
        DBUS_TYPE_UINT32, &l1,
        DBUS_TYPE_UINT32, &r1,
        DBUS_TYPE_UINT32, &l2,
        DBUS_TYPE_UINT32, &r2,
        DBUS_TYPE_UINT32, &share,
        DBUS_TYPE_UINT32, &options,
        DBUS_TYPE_UINT32, &ps,
        DBUS_TYPE_UINT32, &l3,
        DBUS_TYPE_UINT32, &r3,
        DBUS_TYPE_UINT32, &touch_btn,
        DBUS_TYPE_UINT32, &dpad_up,
        DBUS_TYPE_UINT32, &dpad_down,
        DBUS_TYPE_UINT32, &dpad_left,
        DBUS_TYPE_UINT32, &dpad_right,
        DBUS_TYPE_INVALID);

    dbus_connection_send(conn, reply, NULL);
    dbus_message_unref(reply);
    atomic_fetch_add(&g_methods_called, 1);
}

static void handle_get_telemetry(DBusConnection *conn, DBusMessage *msg) {
    unsigned char slot;
    if (!dbus_message_get_args(msg, NULL, DBUS_TYPE_BYTE, &slot, DBUS_TYPE_INVALID)) {
        send_error(conn, msg, DBUS_ERROR_INVALID_ARGS, "Expected slot number");
        return;
    }
    if (slot >= MAX_SLOTS) {
        send_error(conn, msg, DBUS_ERROR_INVALID_ARGS, "Slot out of range");
        return;
    }
    
    pthread_mutex_lock(&g_state.lock);
    if (!g_state.daemon_alive) {
        pthread_mutex_unlock(&g_state.lock);
        send_error(conn, msg, DBUS_ERROR_FAILED, "Daemon not connected");
        return;
    }
    
    bool connected = atomic_load_bool(&g_state.slots[slot].connected);
    if (!connected) {
        pthread_mutex_unlock(&g_state.lock);
        send_error(conn, msg, DBUS_ERROR_FAILED, "Controller not connected");
        return;
    }
    
    controller_t *c = &g_state.slots[slot];
    int16_t lx = c->LX, ly = c->LY;
    int16_t rx = c->RX, ry = c->RY;
    int16_t lt = c->LT, rt = c->RT;
    int16_t hatx = c->HATX, haty = c->HATY;
    uint16_t buttons = pack_buttons(c);
    
    uint8_t dpad = 0;
    if (c->dpad_up) dpad = 1;
    else if (c->dpad_down) dpad = 2;
    else if (c->dpad_left) dpad = 3;
    else if (c->dpad_right) dpad = 4;
    
    pthread_mutex_unlock(&g_state.lock);
    
    DBusMessage *reply = dbus_message_new_method_return(msg);
    if (!reply) {
        send_error(conn, msg, DBUS_ERROR_FAILED, "Failed to create reply");
        return;
    }
    
    dbus_message_append_args(reply,
        DBUS_TYPE_INT16, &lx,
        DBUS_TYPE_INT16, &ly,
        DBUS_TYPE_INT16, &rx,
        DBUS_TYPE_INT16, &ry,
        DBUS_TYPE_INT16, &lt,
        DBUS_TYPE_INT16, &rt,
        DBUS_TYPE_INT16, &hatx,
        DBUS_TYPE_INT16, &haty,
        DBUS_TYPE_UINT16, &buttons,
        DBUS_TYPE_BYTE, &dpad,
        DBUS_TYPE_INVALID);
    
    dbus_connection_send(conn, reply, NULL);
    dbus_message_unref(reply);
    atomic_fetch_add(&g_methods_called, 1);
}

static void handle_get_detailed_info(DBusConnection *conn, DBusMessage *msg) {
    unsigned char slot;
    if (!dbus_message_get_args(msg, NULL, DBUS_TYPE_BYTE, &slot, DBUS_TYPE_INVALID)) {
        send_error(conn, msg, DBUS_ERROR_INVALID_ARGS, "Expected slot number");
        return;
    }
    if (slot >= MAX_SLOTS) {
        send_error(conn, msg, DBUS_ERROR_INVALID_ARGS, "Slot out of range");
        return;
    }

    pthread_mutex_lock(&g_state.lock);
    if (!g_state.daemon_alive) {
        pthread_mutex_unlock(&g_state.lock);
        send_error(conn, msg, DBUS_ERROR_FAILED, "Daemon not connected");
        return;
    }
    
    bool connected = atomic_load_bool(&g_state.slots[slot].connected);
    if (!connected) {
        pthread_mutex_unlock(&g_state.lock);
        send_error(conn, msg, DBUS_ERROR_FAILED, "Controller not connected");
        return;
    }

    controller_t *c = &g_state.slots[slot];
    DBusMessage *reply = dbus_message_new_method_return(msg);
    if (!reply) {
        pthread_mutex_unlock(&g_state.lock);
        send_error(conn, msg, DBUS_ERROR_FAILED, "Failed to create reply");
        return;
    }

    DBusMessageIter iter, array_iter, struct_iter;
    dbus_message_iter_init_append(reply, &iter);

    const char *product_name = c->product_name[0] ? c->product_name : "";
    const char *uniq = c->uniq[0] ? c->uniq : "";
    const char *driver = c->driver[0] ? c->driver : "";
    
    dbus_message_iter_append_basic(&iter, DBUS_TYPE_STRING, &product_name);
    dbus_message_iter_append_basic(&iter, DBUS_TYPE_STRING, &uniq);
    dbus_message_iter_append_basic(&iter, DBUS_TYPE_STRING, &driver);

    dbus_message_iter_open_container(&iter, DBUS_TYPE_ARRAY, "(ss)", &array_iter);

    for (int i = 0; i < c->num_input_nodes && i < MAX_INPUT_NODES; i++) {
        dbus_message_iter_open_container(&array_iter, DBUS_TYPE_STRUCT, NULL, &struct_iter);
        
        const char *path = c->input_nodes[i].path;
        const char *name = c->input_nodes[i].name;
        
        dbus_message_iter_append_basic(&struct_iter, DBUS_TYPE_STRING, &path);
        dbus_message_iter_append_basic(&struct_iter, DBUS_TYPE_STRING, &name);
        
        dbus_message_iter_close_container(&array_iter, &struct_iter);
    }

    dbus_message_iter_close_container(&iter, &array_iter);
    pthread_mutex_unlock(&g_state.lock);

    dbus_connection_send(conn, reply, NULL);
    dbus_message_unref(reply);
    atomic_fetch_add(&g_methods_called, 1);
}

static void handle_get_invert_status(DBusConnection *conn, DBusMessage *msg) {
    unsigned char slot;
    if (!dbus_message_get_args(msg, NULL, DBUS_TYPE_BYTE, &slot, DBUS_TYPE_INVALID)) {
        send_error(conn, msg, DBUS_ERROR_INVALID_ARGS, "Expected slot number");
        return;
    }
    if (slot >= MAX_SLOTS) {
        send_error(conn, msg, DBUS_ERROR_INVALID_ARGS, "Slot out of range");
        return;
    }

    pthread_mutex_lock(&g_state.lock);
    if (!g_state.daemon_alive) {
        pthread_mutex_unlock(&g_state.lock);
        send_error(conn, msg, DBUS_ERROR_FAILED, "Daemon not connected");
        return;
    }
    
    bool connected = atomic_load_bool(&g_state.slots[slot].connected);
    if (!connected) {
        pthread_mutex_unlock(&g_state.lock);
        send_error(conn, msg, DBUS_ERROR_FAILED, "Controller not connected");
        return;
    }

    dbus_bool_t invert_ly = atomic_load_bool(&g_state.slots[slot].invert_ly) ? TRUE : FALSE;
    dbus_bool_t invert_ry = atomic_load_bool(&g_state.slots[slot].invert_ry) ? TRUE : FALSE;
    pthread_mutex_unlock(&g_state.lock);

    DBusMessage *reply = dbus_message_new_method_return(msg);
    if (!reply) {
        send_error(conn, msg, DBUS_ERROR_FAILED, "Failed to create reply");
        return;
    }
    
    dbus_message_append_args(reply, DBUS_TYPE_BOOLEAN, &invert_ly,
                             DBUS_TYPE_BOOLEAN, &invert_ry,
                             DBUS_TYPE_INVALID);
    
    dbus_connection_send(conn, reply, NULL);
    dbus_message_unref(reply);
    atomic_fetch_add(&g_methods_called, 1);
}

static void handle_get_sensitivity_preset(DBusConnection *conn, DBusMessage *msg) {
    unsigned char slot;
    if (!dbus_message_get_args(msg, NULL, DBUS_TYPE_BYTE, &slot, DBUS_TYPE_INVALID)) {
        send_error(conn, msg, DBUS_ERROR_INVALID_ARGS, "Expected slot number");
        return;
    }
    if (slot >= MAX_SLOTS) {
        send_error(conn, msg, DBUS_ERROR_INVALID_ARGS, "Slot out of range");
        return;
    }

    pthread_mutex_lock(&g_state.lock);
    if (!g_state.daemon_alive) {
        pthread_mutex_unlock(&g_state.lock);
        send_error(conn, msg, DBUS_ERROR_FAILED, "Daemon not connected");
        return;
    }
    
    bool connected = atomic_load_bool(&g_state.slots[slot].connected);
    if (!connected) {
        pthread_mutex_unlock(&g_state.lock);
        send_error(conn, msg, DBUS_ERROR_FAILED, "Controller not connected");
        return;
    }

    unsigned char left = atomic_load_uint8(&g_state.slots[slot].sensitivity_left_preset);
    unsigned char right = atomic_load_uint8(&g_state.slots[slot].sensitivity_right_preset);
    pthread_mutex_unlock(&g_state.lock);

    DBusMessage *reply = dbus_message_new_method_return(msg);
    if (!reply) {
        send_error(conn, msg, DBUS_ERROR_FAILED, "Failed to create reply");
        return;
    }
    
    dbus_message_append_args(reply, DBUS_TYPE_BYTE, &left,
                             DBUS_TYPE_BYTE, &right,
                             DBUS_TYPE_INVALID);
    
    dbus_connection_send(conn, reply, NULL);
    dbus_message_unref(reply);
    atomic_fetch_add(&g_methods_called, 1);
}

static void handle_get_keymap(DBusConnection *conn, DBusMessage *msg) {
    unsigned char slot;
    if (!dbus_message_get_args(msg, NULL, DBUS_TYPE_BYTE, &slot, DBUS_TYPE_INVALID)) {
        send_error(conn, msg, DBUS_ERROR_INVALID_ARGS, "Expected slot number");
        return;
    }
    if (slot >= MAX_SLOTS) {
        send_error(conn, msg, DBUS_ERROR_INVALID_ARGS, "Slot out of range");
        return;
    }

    shm_handle_t h = open_shm_handle(conn, msg, slot);
    if (!h.shm) {
        send_error(conn, msg, DBUS_ERROR_FAILED, "Controller not connected");
        return;
    }

    DBusMessage *reply = dbus_message_new_method_return(msg);
    if (!reply) {
        send_error(conn, msg, DBUS_ERROR_FAILED, "Failed to create reply");
        close_shm_handle(&h);
        return;
    }

    DBusMessageIter iter, array_iter;
    dbus_message_iter_init_append(reply, &iter);
    dbus_message_iter_open_container(&iter, DBUS_TYPE_ARRAY, DBUS_TYPE_BYTE_AS_STRING, &array_iter);

    for (int i = 0; i < PHY_BTN_COUNT; i++) {
        uint8_t val = h.shm->slots[slot].keymap[i];
        dbus_message_iter_append_basic(&array_iter, DBUS_TYPE_BYTE, &val);
    }

    dbus_message_iter_close_container(&iter, &array_iter);
    dbus_connection_send(conn, reply, NULL);
    dbus_message_unref(reply);
    close_shm_handle(&h);
    atomic_fetch_add(&g_methods_called, 1);
}

/* ================== Configuration handlers (setters) ================== */

static void handle_set_led(DBusConnection *conn, DBusMessage *msg) {
    unsigned char slot, r, g, b;
    if (!dbus_message_get_args(msg, NULL, DBUS_TYPE_BYTE, &slot, 
            DBUS_TYPE_BYTE, &r, DBUS_TYPE_BYTE, &g, DBUS_TYPE_BYTE, &b, 
            DBUS_TYPE_INVALID)) {
        send_error(conn, msg, DBUS_ERROR_INVALID_ARGS, "Expected slot,r,g,b");
        return;
    }
    if (slot >= MAX_SLOTS) {
        send_error(conn, msg, DBUS_ERROR_INVALID_ARGS, "Slot out of range");
        return;
    }

    shm_handle_t h = open_shm_handle(conn, msg, slot);
    if (!h.shm) return;

    atomic_store_bool(&h.shm->slots[slot].led_static, true);
    atomic_store_bool(&h.shm->slots[slot].led_request_pending, false);
    h.shm->slots[slot].led_base_r = r;
    h.shm->slots[slot].led_base_g = g;
    h.shm->slots[slot].led_base_b = b;
    h.shm->slots[slot].led_r = r;
    h.shm->slots[slot].led_g = g;
    h.shm->slots[slot].led_b = b;
    atomic_store_bool(&h.shm->slots[slot].led_dirty, true);

    close_shm_handle(&h);
    send_basic_reply(conn, msg);
}

static void handle_set_effect(DBusConnection *conn, DBusMessage *msg) {
    unsigned char slot, effect, speed, brightness;
    if (!dbus_message_get_args(msg, NULL, DBUS_TYPE_BYTE, &slot, 
            DBUS_TYPE_BYTE, &effect, DBUS_TYPE_BYTE, &speed, 
            DBUS_TYPE_BYTE, &brightness, DBUS_TYPE_INVALID)) {
        send_error(conn, msg, DBUS_ERROR_INVALID_ARGS, "Expected slot,effect,speed,brightness");
        return;
    }
    if (slot >= MAX_SLOTS) {
        send_error(conn, msg, DBUS_ERROR_INVALID_ARGS, "Slot out of range");
        return;
    }

    shm_handle_t h = open_shm_handle(conn, msg, slot);
    if (!h.shm) return;

    atomic_store_bool(&h.shm->slots[slot].led_static, false);
    atomic_store(&h.shm->slots[slot].led_request_effect, effect);
    atomic_store_uint8(&h.shm->slots[slot].led_request_speed, speed);
    atomic_store_uint8(&h.shm->slots[slot].led_request_brightness, brightness);
    atomic_store_bool(&h.shm->slots[slot].led_request_pending, true);

    close_shm_handle(&h);
    send_basic_reply(conn, msg);
}

static void handle_set_gain(DBusConnection *conn, DBusMessage *msg) {
    unsigned char slot, gain;
    if (!dbus_message_get_args(msg, NULL, DBUS_TYPE_BYTE, &slot, 
                                DBUS_TYPE_BYTE, &gain, DBUS_TYPE_INVALID)) {
        send_error(conn, msg, DBUS_ERROR_INVALID_ARGS, "Expected slot,gain");
        return;
    }
    if (slot >= MAX_SLOTS) {
        send_error(conn, msg, DBUS_ERROR_INVALID_ARGS, "Slot out of range");
        return;
    }
    if (gain > 100) gain = 100;

    shm_handle_t h = open_shm_handle(conn, msg, slot);
    if (!h.shm) return;

    h.shm->slots[slot].rumble_gain = gain;
    close_shm_handle(&h);
    send_basic_reply(conn, msg);
}

static void handle_set_deadzone(DBusConnection *conn, DBusMessage *msg) {
    unsigned char slot, deadzone;
    if (!dbus_message_get_args(msg, NULL, DBUS_TYPE_BYTE, &slot, 
                                DBUS_TYPE_BYTE, &deadzone, DBUS_TYPE_INVALID)) {
        send_error(conn, msg, DBUS_ERROR_INVALID_ARGS, "Expected slot,deadzone");
        return;
    }
    if (slot >= MAX_SLOTS) {
        send_error(conn, msg, DBUS_ERROR_INVALID_ARGS, "Slot out of range");
        return;
    }
    if (deadzone > 100) deadzone = 100;

    shm_handle_t h = open_shm_handle(conn, msg, slot);
    if (!h.shm) return;

    h.shm->slots[slot].deadzone = deadzone;
    close_shm_handle(&h);
    send_basic_reply(conn, msg);
}

static void handle_set_global_brightness(DBusConnection *conn, DBusMessage *msg) {
    unsigned char slot, brightness;
    if (!dbus_message_get_args(msg, NULL, DBUS_TYPE_BYTE, &slot, 
                                DBUS_TYPE_BYTE, &brightness, DBUS_TYPE_INVALID)) {
        send_error(conn, msg, DBUS_ERROR_INVALID_ARGS, "Expected slot,brightness");
        return;
    }
    if (slot >= MAX_SLOTS) {
        send_error(conn, msg, DBUS_ERROR_INVALID_ARGS, "Slot out of range");
        return;
    }
    if (brightness > 100) brightness = 100;

    shm_handle_t h = open_shm_handle(conn, msg, slot);
    if (!h.shm) return;

    h.shm->slots[slot].global_led_brightness = brightness;
    atomic_store_bool(&h.shm->slots[slot].led_dirty, true);
    close_shm_handle(&h);
    send_basic_reply(conn, msg);
}

static void handle_set_player_leds(DBusConnection *conn, DBusMessage *msg) {
    unsigned char slot, mode;
    if (!dbus_message_get_args(msg, NULL, DBUS_TYPE_BYTE, &slot, 
                                DBUS_TYPE_BYTE, &mode, DBUS_TYPE_INVALID)) {
        send_error(conn, msg, DBUS_ERROR_INVALID_ARGS, "Expected slot,mode");
        return;
    }
    if (slot >= MAX_SLOTS) {
        send_error(conn, msg, DBUS_ERROR_INVALID_ARGS, "Slot out of range");
        return;
    }
    if (mode > 5) mode = 5;

    shm_handle_t h = open_shm_handle(conn, msg, slot);
    if (!h.shm) return;

    atomic_store_uint8(&h.shm->slots[slot].player_leds, mode);
    atomic_store_bool(&h.shm->slots[slot].led_dirty, true);
    close_shm_handle(&h);
    send_basic_reply(conn, msg);
}

static void handle_set_emulate(DBusConnection *conn, DBusMessage *msg) {
    unsigned char slot;
    dbus_bool_t enable;
    if (!dbus_message_get_args(msg, NULL, DBUS_TYPE_BYTE, &slot, 
                                DBUS_TYPE_BOOLEAN, &enable, DBUS_TYPE_INVALID)) {
        send_error(conn, msg, DBUS_ERROR_INVALID_ARGS, "Expected slot,enable");
        return;
    }
    if (slot >= MAX_SLOTS) {
        send_error(conn, msg, DBUS_ERROR_INVALID_ARGS, "Slot out of range");
        return;
    }

    shm_handle_t h = open_shm_handle(conn, msg, slot);
    if (!h.shm) return;

    atomic_store_bool(&h.shm->slots[slot].emulate_active, enable ? true : false);
    close_shm_handle(&h);
    send_basic_reply(conn, msg);
}

static void handle_set_uhid(DBusConnection *conn, DBusMessage *msg) {
    unsigned char slot;
    dbus_bool_t enable;
    if (!dbus_message_get_args(msg, NULL, DBUS_TYPE_BYTE, &slot, 
                                DBUS_TYPE_BOOLEAN, &enable, DBUS_TYPE_INVALID)) {
        send_error(conn, msg, DBUS_ERROR_INVALID_ARGS, "Expected slot,enable");
        return;
    }
    if (slot >= MAX_SLOTS) {
        send_error(conn, msg, DBUS_ERROR_INVALID_ARGS, "Slot out of range");
        return;
    }

    shm_handle_t h = open_shm_handle(conn, msg, slot);
    if (!h.shm) return;

    bool old = atomic_load_bool(&h.shm->slots[slot].is_uhid);
    bool new_val = enable ? true : false;
    
    if (old != new_val) {
        atomic_store_bool(&h.shm->slots[slot].is_uhid, new_val);
        atomic_store_bool(&h.shm->slots[slot].emulate_active, false);
        atomic_store_bool(&h.shm->slots[slot].emulate_active, true);
    }

    close_shm_handle(&h);
    send_basic_reply(conn, msg);
}

static void handle_set_debounce(DBusConnection *conn, DBusMessage *msg) {
    unsigned char slot;
    dbus_bool_t enable;
    if (!dbus_message_get_args(msg, NULL, DBUS_TYPE_BYTE, &slot, 
                                DBUS_TYPE_BOOLEAN, &enable, DBUS_TYPE_INVALID)) {
        send_error(conn, msg, DBUS_ERROR_INVALID_ARGS, "Expected slot,enable");
        return;
    }
    if (slot >= MAX_SLOTS) {
        send_error(conn, msg, DBUS_ERROR_INVALID_ARGS, "Slot out of range");
        return;
    }

    shm_handle_t h = open_shm_handle(conn, msg, slot);
    if (!h.shm) return;

    h.shm->slots[slot].debounce_enabled = enable ? true : false;
    close_shm_handle(&h);
    send_basic_reply(conn, msg);
}

static void handle_set_invert_ly(DBusConnection *conn, DBusMessage *msg) {
    unsigned char slot;
    dbus_bool_t enable;
    if (!dbus_message_get_args(msg, NULL, DBUS_TYPE_BYTE, &slot, 
                                DBUS_TYPE_BOOLEAN, &enable, DBUS_TYPE_INVALID)) {
        send_error(conn, msg, DBUS_ERROR_INVALID_ARGS, "Expected slot,enable");
        return;
    }
    if (slot >= MAX_SLOTS) {
        send_error(conn, msg, DBUS_ERROR_INVALID_ARGS, "Slot out of range");
        return;
    }

    shm_handle_t h = open_shm_handle(conn, msg, slot);
    if (!h.shm) return;

    atomic_store_bool(&h.shm->slots[slot].invert_ly, enable ? true : false);
    close_shm_handle(&h);
    send_basic_reply(conn, msg);
}

static void handle_set_invert_ry(DBusConnection *conn, DBusMessage *msg) {
    unsigned char slot;
    dbus_bool_t enable;
    if (!dbus_message_get_args(msg, NULL, DBUS_TYPE_BYTE, &slot, 
                                DBUS_TYPE_BOOLEAN, &enable, DBUS_TYPE_INVALID)) {
        send_error(conn, msg, DBUS_ERROR_INVALID_ARGS, "Expected slot,enable");
        return;
    }
    if (slot >= MAX_SLOTS) {
        send_error(conn, msg, DBUS_ERROR_INVALID_ARGS, "Slot out of range");
        return;
    }

    shm_handle_t h = open_shm_handle(conn, msg, slot);
    if (!h.shm) return;

    atomic_store_bool(&h.shm->slots[slot].invert_ry, enable ? true : false);
    close_shm_handle(&h);
    send_basic_reply(conn, msg);
}

static void handle_set_led_reapply(DBusConnection *conn, DBusMessage *msg) {
    unsigned char slot;
    dbus_bool_t enable;
    if (!dbus_message_get_args(msg, NULL, DBUS_TYPE_BYTE, &slot, 
                                DBUS_TYPE_BOOLEAN, &enable, DBUS_TYPE_INVALID)) {
        send_error(conn, msg, DBUS_ERROR_INVALID_ARGS, "Expected slot,enable");
        return;
    }
    if (slot >= MAX_SLOTS) {
        send_error(conn, msg, DBUS_ERROR_INVALID_ARGS, "Slot out of range");
        return;
    }

    shm_handle_t h = open_shm_handle(conn, msg, slot);
    if (!h.shm) return;

    atomic_store_bool(&h.shm->slots[slot].led_reapply, enable ? true : false);
    close_shm_handle(&h);
    send_basic_reply(conn, msg);
}

static void handle_set_rumble_active(DBusConnection *conn, DBusMessage *msg) {
    unsigned char slot;
    dbus_bool_t enable;
    if (!dbus_message_get_args(msg, NULL, DBUS_TYPE_BYTE, &slot, 
                                DBUS_TYPE_BOOLEAN, &enable, DBUS_TYPE_INVALID)) {
        send_error(conn, msg, DBUS_ERROR_INVALID_ARGS, "Expected slot,enable");
        return;
    }
    if (slot >= MAX_SLOTS) {
        send_error(conn, msg, DBUS_ERROR_INVALID_ARGS, "Slot out of range");
        return;
    }

    shm_handle_t h = open_shm_handle(conn, msg, slot);
    if (!h.shm) return;

    bool old = atomic_load_bool(&h.shm->slots[slot].rumble_active);
    bool new_val = enable ? true : false;
    
    if (old != new_val) {
        atomic_store_bool(&h.shm->slots[slot].rumble_active, new_val);
        if (!new_val) {
            h.shm->slots[slot].rumble_strong = 0;
            h.shm->slots[slot].rumble_weak = 0;
            atomic_store_bool(&h.shm->slots[slot].rumble_dirty, true);
        }
    }

    close_shm_handle(&h);
    send_basic_reply(conn, msg);
}

static void handle_set_sensitivity_preset_left(DBusConnection *conn, DBusMessage *msg) {
    unsigned char slot, preset;
    if (!dbus_message_get_args(msg, NULL, DBUS_TYPE_BYTE, &slot, 
                                DBUS_TYPE_BYTE, &preset, DBUS_TYPE_INVALID)) {
        send_error(conn, msg, DBUS_ERROR_INVALID_ARGS, "Expected slot,preset");
        return;
    }
    if (slot >= MAX_SLOTS) {
        send_error(conn, msg, DBUS_ERROR_INVALID_ARGS, "Slot out of range");
        return;
    }
    if (preset >= SENS_PRESET_COUNT) {
        send_error(conn, msg, DBUS_ERROR_INVALID_ARGS, "Preset out of range");
        return;
    }

    shm_handle_t h = open_shm_handle(conn, msg, slot);
    if (!h.shm) return;

    atomic_store_uint8(&h.shm->slots[slot].sensitivity_left_preset, preset);
    close_shm_handle(&h);
    send_basic_reply(conn, msg);
}

static void handle_set_sensitivity_preset_right(DBusConnection *conn, DBusMessage *msg) {
    unsigned char slot, preset;
    if (!dbus_message_get_args(msg, NULL, DBUS_TYPE_BYTE, &slot, 
                                DBUS_TYPE_BYTE, &preset, DBUS_TYPE_INVALID)) {
        send_error(conn, msg, DBUS_ERROR_INVALID_ARGS, "Expected slot,preset");
        return;
    }
    if (slot >= MAX_SLOTS) {
        send_error(conn, msg, DBUS_ERROR_INVALID_ARGS, "Slot out of range");
        return;
    }
    if (preset >= SENS_PRESET_COUNT) {
        send_error(conn, msg, DBUS_ERROR_INVALID_ARGS, "Preset out of range");
        return;
    }

    shm_handle_t h = open_shm_handle(conn, msg, slot);
    if (!h.shm) return;

    atomic_store_uint8(&h.shm->slots[slot].sensitivity_right_preset, preset);
    close_shm_handle(&h);
    send_basic_reply(conn, msg);
}

static void handle_set_keybind(DBusConnection *conn, DBusMessage *msg) {
    unsigned char slot, physical, logical;
    if (!dbus_message_get_args(msg, NULL,
                               DBUS_TYPE_BYTE, &slot,
                               DBUS_TYPE_BYTE, &physical,
                               DBUS_TYPE_BYTE, &logical,
                               DBUS_TYPE_INVALID)) {
        send_error(conn, msg, DBUS_ERROR_INVALID_ARGS, "Expected slot, physical, logical");
        return;
    }
    if (slot >= MAX_SLOTS) {
        send_error(conn, msg, DBUS_ERROR_INVALID_ARGS, "Slot out of range");
        return;
    }
    if (physical >= PHY_BTN_COUNT) {
        send_error(conn, msg, DBUS_ERROR_INVALID_ARGS, "Physical button out of range");
        return;
    }
    if (logical >= LOGICAL_BTN_COUNT) {
        send_error(conn, msg, DBUS_ERROR_INVALID_ARGS, "Logical button out of range");
        return;
    }

    shm_handle_t h = open_shm_handle(conn, msg, slot);
    if (!h.shm) return;

    h.shm->slots[slot].keymap[physical] = logical;
    atomic_store_bool(&h.shm->slots[slot].led_dirty, true);
    close_shm_handle(&h);
    send_basic_reply(conn, msg);
}

static void handle_reset_keybinds(DBusConnection *conn, DBusMessage *msg) {
    unsigned char slot;
    if (!dbus_message_get_args(msg, NULL, DBUS_TYPE_BYTE, &slot, DBUS_TYPE_INVALID)) {
        send_error(conn, msg, DBUS_ERROR_INVALID_ARGS, "Expected slot number");
        return;
    }
    if (slot >= MAX_SLOTS) {
        send_error(conn, msg, DBUS_ERROR_INVALID_ARGS, "Slot out of range");
        return;
    }

    shm_handle_t h = open_shm_handle(conn, msg, slot);
    if (!h.shm) return;

    keys_get_default_map(h.shm->slots[slot].type, h.shm->slots[slot].keymap);
    atomic_store_bool(&h.shm->slots[slot].led_dirty, true);
    close_shm_handle(&h);
    send_basic_reply(conn, msg);
}

static void handle_reset_all_keybinds(DBusConnection *conn, DBusMessage *msg) {
    unsigned char slot;
    if (!dbus_message_get_args(msg, NULL, DBUS_TYPE_BYTE, &slot, DBUS_TYPE_INVALID)) {
        send_error(conn, msg, DBUS_ERROR_INVALID_ARGS, "Expected slot number");
        return;
    }
    if (slot >= MAX_SLOTS) {
        send_error(conn, msg, DBUS_ERROR_INVALID_ARGS, "Slot out of range");
        return;
    }

    shm_handle_t h = open_shm_handle(conn, msg, slot);
    if (!h.shm) return;

    atomic_store_bool(&h.shm->slots[slot].request_reset_all_keybinds, true);
    close_shm_handle(&h);
    send_basic_reply(conn, msg);
}

static void handle_set_triggers_digital(DBusConnection *conn, DBusMessage *msg) {
    unsigned char slot;
    dbus_bool_t enable;
    if (!dbus_message_get_args(msg, NULL, DBUS_TYPE_BYTE, &slot,
                                DBUS_TYPE_BOOLEAN, &enable, DBUS_TYPE_INVALID)) {
        send_error(conn, msg, DBUS_ERROR_INVALID_ARGS, "Expected slot, enable");
        return;
    }
    if (slot >= MAX_SLOTS) {
        send_error(conn, msg, DBUS_ERROR_INVALID_ARGS, "Slot out of range");
        return;
    }

    shm_handle_t h = open_shm_handle(conn, msg, slot);
    if (!h.shm) return;

    atomic_store_bool(&h.shm->slots[slot].is_trigger_digital, enable ? true : false);
    close_shm_handle(&h);
    send_basic_reply(conn, msg);
}

static void handle_get_triggers_digital(DBusConnection *conn, DBusMessage *msg) {
    unsigned char slot;
    if (!dbus_message_get_args(msg, NULL, DBUS_TYPE_BYTE, &slot, DBUS_TYPE_INVALID)) {
        send_error(conn, msg, DBUS_ERROR_INVALID_ARGS, "Expected slot number");
        return;
    }
    if (slot >= MAX_SLOTS) {
        send_error(conn, msg, DBUS_ERROR_INVALID_ARGS, "Slot out of range");
        return;
    }

    shm_handle_t h = open_shm_handle(conn, msg, slot);
    if (!h.shm) {
        send_error(conn, msg, DBUS_ERROR_FAILED, "Controller not connected");
        return;
    }

    dbus_bool_t enabled = atomic_load_bool(&h.shm->slots[slot].is_trigger_digital) ? TRUE : FALSE;
    close_shm_handle(&h);

    DBusMessage *reply = dbus_message_new_method_return(msg);
    if (!reply) {
        send_error(conn, msg, DBUS_ERROR_FAILED, "Failed to create reply");
        return;
    }
    if (!dbus_message_append_args(reply, DBUS_TYPE_BOOLEAN, &enabled, DBUS_TYPE_INVALID)) {
        send_error(conn, msg, DBUS_ERROR_FAILED, "Failed to append arguments");
        dbus_message_unref(reply);
        return;
    }
    dbus_connection_send(conn, reply, NULL);
    dbus_message_unref(reply);
    atomic_fetch_add(&g_methods_called, 1);
}

static void handle_apply_switch_layout(DBusConnection *conn, DBusMessage *msg) {
    unsigned char slot;
    if (!dbus_message_get_args(msg, NULL, DBUS_TYPE_BYTE, &slot, DBUS_TYPE_INVALID)) {
        send_error(conn, msg, DBUS_ERROR_INVALID_ARGS, "Expected slot number");
        return;
    }
    if (slot >= MAX_SLOTS) {
        send_error(conn, msg, DBUS_ERROR_INVALID_ARGS, "Slot out of range");
        return;
    }

    shm_handle_t h = open_shm_handle(conn, msg, slot);
    if (!h.shm) return;

    atomic_store_bool(&h.shm->slots[slot].request_switch_layout, true);
    close_shm_handle(&h);
    send_basic_reply(conn, msg);
}

static void handle_apply_xbox_layout(DBusConnection *conn, DBusMessage *msg) {
    unsigned char slot;
    if (!dbus_message_get_args(msg, NULL, DBUS_TYPE_BYTE, &slot, DBUS_TYPE_INVALID)) {
        send_error(conn, msg, DBUS_ERROR_INVALID_ARGS, "Expected slot number");
        return;
    }
    if (slot >= MAX_SLOTS) {
        send_error(conn, msg, DBUS_ERROR_INVALID_ARGS, "Slot out of range");
        return;
    }

    shm_handle_t h = open_shm_handle(conn, msg, slot);
    if (!h.shm) return;

    atomic_store_bool(&h.shm->slots[slot].request_xbox_layout, true);
    close_shm_handle(&h);
    send_basic_reply(conn, msg);
}

static void handle_set_switch_layout_legacy(DBusConnection *conn, DBusMessage *msg) {
    unsigned char slot;
    dbus_bool_t enable;
    if (!dbus_message_get_args(msg, NULL, DBUS_TYPE_BYTE, &slot,
                                DBUS_TYPE_BOOLEAN, &enable, DBUS_TYPE_INVALID)) {
        send_error(conn, msg, DBUS_ERROR_INVALID_ARGS, "Expected slot, enable");
        return;
    }
    if (slot >= MAX_SLOTS) {
        send_error(conn, msg, DBUS_ERROR_INVALID_ARGS, "Slot out of range");
        return;
    }

    shm_handle_t h = open_shm_handle(conn, msg, slot);
    if (!h.shm) return;

    if (enable) {
        atomic_store_bool(&h.shm->slots[slot].request_switch_layout, true);
    } else {
        atomic_store_bool(&h.shm->slots[slot].request_xbox_layout, true);
    }
    close_shm_handle(&h);
    send_basic_reply(conn, msg);
}

/* ================== Core service control handlers ================== */

static void handle_start_core_service(DBusConnection *conn, DBusMessage *msg) {
    int ret = systemd_start_unit(conn, DSTX_UNIT, "replace");
    DBusMessage *reply = dbus_message_new_method_return(msg);
    if (!reply) {
        send_error(conn, msg, DBUS_ERROR_FAILED, "Failed to create reply");
        return;
    }
    dbus_int32_t status = (ret == 0) ? 0 : -1;
    dbus_message_append_args(reply, DBUS_TYPE_INT32, &status, DBUS_TYPE_INVALID);
    dbus_connection_send(conn, reply, NULL);
    dbus_message_unref(reply);
    atomic_fetch_add(&g_methods_called, 1);
}

static void handle_stop_core_service(DBusConnection *conn, DBusMessage *msg) {
    int ret = systemd_stop_unit(conn, DSTX_UNIT, "replace");
    DBusMessage *reply = dbus_message_new_method_return(msg);
    if (!reply) {
        send_error(conn, msg, DBUS_ERROR_FAILED, "Failed to create reply");
        return;
    }
    dbus_int32_t status = (ret == 0) ? 0 : -1;
    dbus_message_append_args(reply, DBUS_TYPE_INT32, &status, DBUS_TYPE_INVALID);
    dbus_connection_send(conn, reply, NULL);
    dbus_message_unref(reply);
    atomic_fetch_add(&g_methods_called, 1);
}

static void handle_restart_core_service(DBusConnection *conn, DBusMessage *msg) {
    int ret = systemd_restart_unit(conn, DSTX_UNIT, "replace");
    DBusMessage *reply = dbus_message_new_method_return(msg);
    if (!reply) {
        send_error(conn, msg, DBUS_ERROR_FAILED, "Failed to create reply");
        return;
    }
    dbus_int32_t status = (ret == 0) ? 0 : -1;
    dbus_message_append_args(reply, DBUS_TYPE_INT32, &status, DBUS_TYPE_INVALID);
    dbus_connection_send(conn, reply, NULL);
    dbus_message_unref(reply);
    atomic_fetch_add(&g_methods_called, 1);
}

static void handle_is_core_service_active(DBusConnection *conn, DBusMessage *msg) {
    dbus_bool_t active = systemd_unit_is_active(conn, DSTX_UNIT) ? TRUE : FALSE;
    DBusMessage *reply = dbus_message_new_method_return(msg);
    if (!reply) {
        send_error(conn, msg, DBUS_ERROR_FAILED, "Failed to create reply");
        return;
    }
    dbus_message_append_args(reply, DBUS_TYPE_BOOLEAN, &active, DBUS_TYPE_INVALID);
    dbus_connection_send(conn, reply, NULL);
    dbus_message_unref(reply);
    atomic_fetch_add(&g_methods_called, 1);
}

static void handle_is_core_service_enabled(DBusConnection *conn, DBusMessage *msg) {
    dbus_bool_t enabled = systemd_unit_is_enabled(conn, DSTX_UNIT) ? TRUE : FALSE;
    DBusMessage *reply = dbus_message_new_method_return(msg);
    if (!reply) {
        send_error(conn, msg, DBUS_ERROR_FAILED, "Failed to create reply");
        return;
    }
    dbus_message_append_args(reply, DBUS_TYPE_BOOLEAN, &enabled, DBUS_TYPE_INVALID);
    dbus_connection_send(conn, reply, NULL);
    dbus_message_unref(reply);
    atomic_fetch_add(&g_methods_called, 1);
}

/* For enable/disable we use system() + sudoers (more reliable) */
static void handle_enable_core_service(DBusConnection *conn, DBusMessage *msg) {
    int status = system("systemctl enable dstx-daemon.service");
    DBusMessage *reply = dbus_message_new_method_return(msg);
    if (!reply) {
        send_error(conn, msg, DBUS_ERROR_FAILED, "Failed to create reply");
        return;
    }
    dbus_int32_t ret = WIFEXITED(status) ? WEXITSTATUS(status) : -1;
    dbus_message_append_args(reply, DBUS_TYPE_INT32, &ret, DBUS_TYPE_INVALID);
    dbus_connection_send(conn, reply, NULL);
    dbus_message_unref(reply);
    atomic_fetch_add(&g_methods_called, 1);
}

static void handle_disable_core_service(DBusConnection *conn, DBusMessage *msg) {
    int status = system("systemctl disable dstx-daemon.service");
    DBusMessage *reply = dbus_message_new_method_return(msg);
    if (!reply) {
        send_error(conn, msg, DBUS_ERROR_FAILED, "Failed to create reply");
        return;
    }
    dbus_int32_t ret = WIFEXITED(status) ? WEXITSTATUS(status) : -1;
    dbus_message_append_args(reply, DBUS_TYPE_INT32, &ret, DBUS_TYPE_INVALID);
    dbus_connection_send(conn, reply, NULL);
    dbus_message_unref(reply);
    atomic_fetch_add(&g_methods_called, 1);
}

/* ================== Profile handlers ================== */

static void handle_get_auto_save_status(DBusConnection *conn, DBusMessage *msg) {
    shared_data_t *shm = open_shm_handle_any(conn, msg);
    if (!shm) {
        send_error(conn, msg, DBUS_ERROR_FAILED, "Daemon not connected");
        return;
    }

    dbus_bool_t enabled = (atomic_load(&shm->auto_save_enabled) != 0);
    int32_t delay_ms = atomic_load(&shm->auto_save_delay_ms);

    DBusMessage *reply = dbus_message_new_method_return(msg);
    if (!reply) {
        send_error(conn, msg, DBUS_ERROR_FAILED, "Failed to create reply");
        close_shm_handle_any(shm);
        return;
    }

    dbus_message_append_args(reply,
        DBUS_TYPE_BOOLEAN, &enabled,
        DBUS_TYPE_INT32, &delay_ms,
        DBUS_TYPE_INVALID);

    dbus_connection_send(conn, reply, NULL);
    dbus_message_unref(reply);
    close_shm_handle_any(shm);
    atomic_fetch_add(&g_methods_called, 1);
}

static void handle_get_current_profile(DBusConnection *conn, DBusMessage *msg) {
    shared_data_t *shm = open_shm_handle_any(conn, msg);
    if (!shm) {
        send_error(conn, msg, DBUS_ERROR_FAILED, "Daemon not connected");
        return;
    }

    const char *profile_name = shm->current_profile_name;
    if (profile_name[0] == '\0') profile_name = "default";

    DBusMessage *reply = dbus_message_new_method_return(msg);
    if (!reply) {
        send_error(conn, msg, DBUS_ERROR_FAILED, "Failed to create reply");
        close_shm_handle_any(shm);
        return;
    }

    dbus_message_append_args(reply,
        DBUS_TYPE_STRING, &profile_name,
        DBUS_TYPE_INVALID);

    dbus_connection_send(conn, reply, NULL);
    dbus_message_unref(reply);
    close_shm_handle_any(shm);
    atomic_fetch_add(&g_methods_called, 1);
}

static void handle_list_profiles(DBusConnection *conn, DBusMessage *msg) {
    shared_data_t *shm = open_shm_handle_any(conn, msg);
    if (!shm) {
        send_error(conn, msg, DBUS_ERROR_FAILED, "Daemon not connected");
        return;
    }
    char resp_msg[4096];
    bool ok = shm_request_sync(shm, 4, NULL, -1, -1, resp_msg, sizeof(resp_msg));
    close_shm_handle_any(shm);
    if (ok) {
        DBusMessage *reply = dbus_message_new_method_return(msg);
        if (!reply) {
            send_error(conn, msg, DBUS_ERROR_FAILED, "Failed to create reply");
            return;
        }
        const char *list = resp_msg;
        if (!dbus_message_append_args(reply, DBUS_TYPE_STRING, &list, DBUS_TYPE_INVALID)) {
            send_error(conn, msg, DBUS_ERROR_FAILED, "Failed to append list");
            dbus_message_unref(reply);
            return;
        }
        dbus_connection_send(conn, reply, NULL);
        dbus_message_unref(reply);
    } else {
        send_error(conn, msg, DBUS_ERROR_FAILED, resp_msg);
    }
    atomic_fetch_add(&g_methods_called, 1);
}

static void handle_load_profile(DBusConnection *conn, DBusMessage *msg) {
    const char *name;
    if (!dbus_message_get_args(msg, NULL, DBUS_TYPE_STRING, &name, DBUS_TYPE_INVALID)) {
        send_error(conn, msg, DBUS_ERROR_INVALID_ARGS, "Expected profile name");
        return;
    }
    shared_data_t *shm = open_shm_handle_any(conn, msg);
    if (!shm) {
        send_error(conn, msg, DBUS_ERROR_FAILED, "Daemon not connected");
        return;
    }
    char resp_msg[512];
    bool ok = shm_request_sync(shm, 1, name, -1, -1, resp_msg, sizeof(resp_msg));
    close_shm_handle_any(shm);
    if (ok) send_basic_reply(conn, msg);
    else send_error(conn, msg, DBUS_ERROR_FAILED, resp_msg);
}

static void handle_save_profile(DBusConnection *conn, DBusMessage *msg) {
    const char *name;
    if (!dbus_message_get_args(msg, NULL, DBUS_TYPE_STRING, &name, DBUS_TYPE_INVALID)) {
        send_error(conn, msg, DBUS_ERROR_INVALID_ARGS, "Expected profile name");
        return;
    }
    shared_data_t *shm = open_shm_handle_any(conn, msg);
    if (!shm) {
        send_error(conn, msg, DBUS_ERROR_FAILED, "Daemon not connected");
        return;
    }
    char resp_msg[512];
    bool ok = shm_request_sync(shm, 2, name, -1, -1, resp_msg, sizeof(resp_msg));
    close_shm_handle_any(shm);
    if (ok) send_basic_reply(conn, msg);
    else send_error(conn, msg, DBUS_ERROR_FAILED, resp_msg);
}

static void handle_delete_profile(DBusConnection *conn, DBusMessage *msg) {
    const char *name;
    if (!dbus_message_get_args(msg, NULL, DBUS_TYPE_STRING, &name, DBUS_TYPE_INVALID)) {
        send_error(conn, msg, DBUS_ERROR_INVALID_ARGS, "Expected profile name");
        return;
    }
    shared_data_t *shm = open_shm_handle_any(conn, msg);
    if (!shm) {
        send_error(conn, msg, DBUS_ERROR_FAILED, "Daemon not connected");
        return;
    }
    char resp_msg[512];
    bool ok = shm_request_sync(shm, 3, name, -1, -1, resp_msg, sizeof(resp_msg));
    close_shm_handle_any(shm);
    if (ok) send_basic_reply(conn, msg);
    else send_error(conn, msg, DBUS_ERROR_FAILED, resp_msg);
}

static void handle_set_auto_save(DBusConnection *conn, DBusMessage *msg) {
    dbus_bool_t enable;
    int delay_ms;
    if (!dbus_message_get_args(msg, NULL, DBUS_TYPE_BOOLEAN, &enable, DBUS_TYPE_INT32, &delay_ms, DBUS_TYPE_INVALID)) {
        send_error(conn, msg, DBUS_ERROR_INVALID_ARGS, "Expected enable (bool) and delay_ms (int32)");
        return;
    }
    if (delay_ms < 100) delay_ms = 100;
    if (delay_ms > 10000) delay_ms = 10000;

    shared_data_t *shm = open_shm_handle_any(conn, msg);
    if (!shm) {
        send_error(conn, msg, DBUS_ERROR_FAILED, "Daemon not connected");
        return;
    }

    char resp_msg[512];
    bool ok = shm_request_sync(shm, 5, NULL, enable ? 1 : 0, delay_ms, resp_msg, sizeof(resp_msg));
    close_shm_handle_any(shm);

    if (ok) {
        DBusMessage *reply = dbus_message_new_method_return(msg);
        if (reply) {
            const char *msg_str = resp_msg;
            dbus_message_append_args(reply, DBUS_TYPE_STRING, &msg_str, DBUS_TYPE_INVALID);
            dbus_connection_send(conn, reply, NULL);
            dbus_message_unref(reply);
        } else {
            send_error(conn, msg, DBUS_ERROR_FAILED, "Failed to create reply");
        }
    } else {
        send_error(conn, msg, DBUS_ERROR_FAILED, resp_msg);
    }
    atomic_fetch_add(&g_methods_called, 1);
}

/* ================== Handler registration ================== */

static DBusHandlerResult message_handler(DBusConnection *conn,
                                         DBusMessage *msg,
                                         void *user_data) {
    (void)user_data;

    const char *interface = dbus_message_get_interface(msg);
    const char *member = dbus_message_get_member(msg);
    
    if (!interface || !member) {
        return DBUS_HANDLER_RESULT_NOT_YET_HANDLED;
    }
    
    if (strcmp(interface, BRIDGE_INTERFACE) != 0) {
        return DBUS_HANDLER_RESULT_NOT_YET_HANDLED;
    }
    
    // Method mapping
    #define HANDLE(method_name, handler) \
        if (strcmp(member, method_name) == 0) { \
            handler(conn, msg); \
            return DBUS_HANDLER_RESULT_HANDLED; \
        }
    
    HANDLE("GetCoreVersion", handle_get_core_version)
    HANDLE("GetControllers", handle_get_controllers)
    HANDLE("GetControllerInfo", handle_get_controller_info)
    HANDLE("GetTelemetry", handle_get_telemetry)
    HANDLE("GetDetailedInfo", handle_get_detailed_info)
    HANDLE("GetInvertStatus", handle_get_invert_status)
    HANDLE("GetSensitivityPreset", handle_get_sensitivity_preset)
    HANDLE("GetKeymap", handle_get_keymap)
    HANDLE("SetLED", handle_set_led)
    HANDLE("SetEffect", handle_set_effect)
    HANDLE("SetGain", handle_set_gain)
    HANDLE("SetDeadzone", handle_set_deadzone)
    HANDLE("SetGlobalBrightness", handle_set_global_brightness)
    HANDLE("SetPlayerLEDs", handle_set_player_leds)
    HANDLE("SetEmulate", handle_set_emulate)
    HANDLE("SetUHID", handle_set_uhid)
    HANDLE("SetDebounce", handle_set_debounce)
    HANDLE("SetLEDReapply", handle_set_led_reapply)
    HANDLE("SetRumbleActive", handle_set_rumble_active)
    HANDLE("SetInvertLY", handle_set_invert_ly)
    HANDLE("SetInvertRY", handle_set_invert_ry)
    HANDLE("SetSensitivityPresetLeft", handle_set_sensitivity_preset_left)
    HANDLE("SetSensitivityPresetRight", handle_set_sensitivity_preset_right)
    HANDLE("SetKeybind", handle_set_keybind)
    HANDLE("ResetKeybinds", handle_reset_keybinds)
    HANDLE("ResetAllKeybinds", handle_reset_all_keybinds)
    HANDLE("SetTriggersDigital", handle_set_triggers_digital)
    HANDLE("GetTriggersDigital", handle_get_triggers_digital)
    HANDLE("ApplySwitchLayout", handle_apply_switch_layout)
    HANDLE("ApplyXboxLayout", handle_apply_xbox_layout)
    HANDLE("SetSwitchLayout", handle_set_switch_layout_legacy)
    HANDLE("StartCoreService", handle_start_core_service)
    HANDLE("StopCoreService", handle_stop_core_service)
    HANDLE("RestartCoreService", handle_restart_core_service)
    HANDLE("IsCoreServiceActive", handle_is_core_service_active)
    HANDLE("IsCoreServiceEnabled", handle_is_core_service_enabled)
    HANDLE("EnableCoreService", handle_enable_core_service)
    HANDLE("DisableCoreService", handle_disable_core_service)
    HANDLE("GetAutoSaveStatus", handle_get_auto_save_status)
    HANDLE("GetCurrentProfile", handle_get_current_profile)
    HANDLE("ListProfiles", handle_list_profiles)
    HANDLE("LoadProfile", handle_load_profile)
    HANDLE("SaveProfile", handle_save_profile)
    HANDLE("DeleteProfile", handle_delete_profile)
    HANDLE("SetAutoSave", handle_set_auto_save)
    
    #undef HANDLE
    
    return DBUS_HANDLER_RESULT_NOT_YET_HANDLED;
}

void register_method_handlers(DBusConnection *conn) {
    DBusObjectPathVTable vtable = {
        .message_function = message_handler,
        .unregister_function = NULL
    };
    dbus_connection_register_object_path(conn, BRIDGE_PATH, &vtable, NULL);
}
