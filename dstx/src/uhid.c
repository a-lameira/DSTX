/*
 * uhid.c - UHID device support for DSTX
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
 * Implements UHID device creation/destruction analogously to uinput.
 * When emulate_active = true and is_uhid = true, a virtual HID device is created.
 *
 * Adds specific identifiers:
 * - Vendor ID: 0x045e (Microsoft, for game compatibility)
 * - Product ID: 0x0300 + slot_index (to identify each slot)
 * - Version: Encodes the original controller type (0x0101=DS4, 0x0102=DS, 0x0103=NSW)
 *
 * Custom HID descriptor exposes:
 * - 13 buttons (BTN_SOUTH, EAST, NORTH, WEST, TL, TR, TL2, TR2, SELECT, START, MODE, THUMBL, THUMBR)
 * - 6 analog axes (X, Y, Z, Rx, Ry, Rz) with range 0-255
 * - D-Pad as HAT (-1 to 1)
 *
 * Respects digital/analog trigger mode:
 * - Digital mode: sends button bits (L2/R2), axes zeroed.
 * - Analog mode: sends axes (ABS_Z/ABS_RZ), button bits zeroed.
 */

#include "dstx.h"
#include <linux/uhid.h>
#include <poll.h>
#include <sys/ioctl.h>
#include <stddef.h>

// ========================================================================
// UHID-SPECIFIC CONSTANTS
// ========================================================================
#define UHID_MAX_EVENTS 16
#define UHID_REPORT_SIZE 64

// ========================================================================
// INTERNAL FUNCTION PROTOTYPES (ALL STATIC)
// ========================================================================
static int uhid_write_event(int fd, struct uhid_event *ev);
static int uhid_read_event(int fd, struct uhid_event *ev);
static void uhid_handle_output(struct uhid_event *ev, controller_t *slot);
static void uhid_handle_get_report(struct uhid_event *ev, controller_t *slot, int fd);
static void uhid_handle_set_report(struct uhid_event *ev, controller_t *slot, int fd);
static size_t uhid_build_report_descriptor(uint8_t *buf, size_t buf_size);

// ========================================================================
// I/O HELPER FUNCTIONS
// ========================================================================

/*
 * uhid_write_event - Writes a complete UHID event using safe_write()
 */
static int uhid_write_event(int fd, struct uhid_event *ev) {
    ssize_t ret = safe_write(fd, ev, sizeof(*ev));
    if (ret != sizeof(*ev)) {
        syslog(LOG_ERR, "UHID: Failed to write event: %s", strerror(errno));
        return -1;
    }
    return 0;
}

/**
 * uhid_read_event - Reads a complete UHID event (non-blocking)
 */
static int uhid_read_event(int fd, struct uhid_event *ev) {
    ssize_t ret = read(fd, ev, sizeof(*ev));
    if (ret < 0) {
        if (errno != EAGAIN && errno != EWOULDBLOCK) {
            syslog(LOG_ERR, "UHID: Read error: %s", strerror(errno));
        }
        return -1;
    }
    if (ret != sizeof(*ev)) {
        syslog(LOG_WARNING, "UHID: Partial read: %zd/%zu bytes", ret, sizeof(*ev));
        return -1;
    }
    return 0;
}

// ========================================================================
// HID REPORT DESCRIPTOR CONSTRUCTION
// ========================================================================

/**
 * uhid_build_report_descriptor - Builds the HID descriptor with specified capabilities
 *
 * Returns descriptor size or 0 on error
 */
static size_t uhid_build_report_descriptor(uint8_t *buf, size_t buf_size) {
    static const uint8_t custom_descriptor[] = {
        // ===== Application Collection =====
        0x05, 0x01,        // Usage Page (Generic Desktop)
        0x09, 0x05,        // Usage (Game Pad)
        0xA1, 0x01,        // Collection (Application)
        
        // ===== REPORT ID 1 =====
        0x85, 0x01,        // Report ID (1)
        
        // ===== Bytes 0-1: Buttons =====
        0x05, 0x09,        // Usage Page (Button)
        0x19, 0x01,        // Usage Minimum (1)
        0x29, 0x0F,        // Usage Maximum (15)
        0x15, 0x00,        // Logical Minimum (0)
        0x25, 0x01,        // Logical Maximum (1)
        0x75, 0x01,        // Report Size (1 bit)
        0x95, 0x0F,        // Report Count (15 bits)
        0x81, 0x02,        // Input (Data,Var,Abs)
        
        // Padding to complete 2 bytes
        0x75, 0x01,        // Report Size (1 bit)
        0x95, 0x01,        // Report Count (1 bit)
        0x81, 0x03,        // Input (Const,Var,Abs)
        
        // ===== Byte 2: D-Pad =====
        0x05, 0x01,        // Usage Page (Generic Desktop)
        0x09, 0x39,        // Usage (Hat Switch)
        0x15, 0x00,        // Logical Minimum (0)
        0x25, 0x07,        // Logical Maximum (7)
        0x35, 0x00,        // Physical Minimum (0)
        0x46, 0x3B, 0x01,  // Physical Maximum (315)
        0x65, 0x14,        // Unit (Degrees)
        0x75, 0x08,        // Report Size (8 bits)
        0x95, 0x01,        // Report Count (1)
        0x81, 0x42,        // Input (Data,Var,Abs,Null)
        
        // ===== Byte 3: Axis X (Left Stick X) =====
        0x05, 0x01,        // Usage Page (Generic Desktop)
        0x09, 0x30,        // Usage (X)
        0x15, 0x00,        // Logical Minimum (0)
        0x26, 0xFF, 0x00,  // Logical Maximum (255)
        0x75, 0x08,        // Report Size (8 bits)
        0x95, 0x01,        // Report Count (1)
        0x81, 0x02,        // Input (Data,Var,Abs)
        
        // ===== Byte 4: Axis Y (Left Stick Y) =====
        0x09, 0x31,        // Usage (Y)
        0x15, 0x00,        // Logical Minimum (0)
        0x26, 0xFF, 0x00,  // Logical Maximum (255)
        0x75, 0x08,        // Report Size (8 bits)
        0x95, 0x01,        // Report Count (1)
        0x81, 0x02,        // Input (Data,Var,Abs)
        
        // ===== Byte 5: PADDING 1 =====
        0x05, 0x01,        // Usage Page (Generic Desktop)
        0x09, 0x00,        // Usage (Undefined)
        0x15, 0x00,        // Logical Minimum (0)
        0x26, 0xFF, 0x00,  // Logical Maximum (255)
        0x75, 0x08,        // Report Size (8 bits)
        0x95, 0x01,        // Report Count (1)
        0x81, 0x03,        // Input (Const,Var,Abs)
        
        // ===== Byte 6: PADDING 2 =====
        0x05, 0x01,        // Usage Page (Generic Desktop)
        0x09, 0x00,        // Usage (Undefined)
        0x15, 0x00,        // Logical Minimum (0)
        0x26, 0xFF, 0x00,  // Logical Maximum (255)
        0x75, 0x08,        // Report Size (8 bits)
        0x95, 0x01,        // Report Count (1)
        0x81, 0x03,        // Input (Const,Var,Abs)
        
        // ===== Byte 7: Axis Rx (Right Stick X) =====
        0x09, 0x33,        // Usage (Rx)
        0x15, 0x00,        // Logical Minimum (0)
        0x26, 0xFF, 0x00,  // Logical Maximum (255)
        0x75, 0x08,        // Report Size (8 bits)
        0x95, 0x01,        // Report Count (1)
        0x81, 0x02,        // Input (Data,Var,Abs)
        
        // ===== Byte 8: Axis Ry (Right Stick Y) =====
        0x09, 0x34,        // Usage (Ry)
        0x15, 0x00,        // Logical Minimum (0)
        0x26, 0xFF, 0x00,  // Logical Maximum (255)
        0x75, 0x08,        // Report Size (8 bits)
        0x95, 0x01,        // Report Count (1)
        0x81, 0x02,        // Input (Data,Var,Abs)
        
        // ===== Byte 9: PADDING 3 =====
        0x05, 0x01,        // Usage Page (Generic Desktop)
        0x09, 0x00,        // Usage (Undefined)
        0x15, 0x00,        // Logical Minimum (0)
        0x26, 0xFF, 0x00,  // Logical Maximum (255)
        0x75, 0x08,        // Report Size (8 bits)
        0x95, 0x01,        // Report Count (1)
        0x81, 0x03,        // Input (Const,Var,Abs)
        
        // ===== Byte 10: Axis Z (Left Trigger/L2) =====
        0x05, 0x01,        // Usage Page (Generic Desktop)
        0x09, 0x32,        // Usage (Z)
        0x15, 0x00,        // Logical Minimum (0)
        0x26, 0xFF, 0x00,  // Logical Maximum (255)
        0x75, 0x08,        // Report Size (8 bits)
        0x95, 0x01,        // Report Count (1)
        0x81, 0x02,        // Input (Data,Var,Abs)
        
        // ===== Byte 11: Axis Rz (Right Trigger/R2) =====
        0x09, 0x35,        // Usage (Rz)
        0x15, 0x00,        // Logical Minimum (0)
        0x26, 0xFF, 0x00,  // Logical Maximum (255)
        0x75, 0x08,        // Report Size (8 bits)
        0x95, 0x01,        // Report Count (1)
        0x81, 0x02,        // Input (Data,Var,Abs)
        
        // ===== Output Reports (Rumble) =====
        0x05, 0x0F,        // Usage Page (Physical Interface)
        0x09, 0x21,        // Usage (Rumble)
        0xA1, 0x02,        // Collection (Logical)
        0x75, 0x08,        // Report Size (8 bits)
        0x95, 0x04,        // Report Count (4)
        0x46, 0xFF, 0x00,  // Physical Maximum (255)
        0x26, 0xFF, 0x00,  // Logical Maximum (255)
        0x09, 0x26,        // Usage (Rumble)
        0x91, 0x02,        // Output (Data,Var,Abs)
        0xC0,              // End Collection
        
        0xC0                // End Collection (Application)
    };
    
    if (sizeof(custom_descriptor) <= buf_size) {
        memcpy(buf, custom_descriptor, sizeof(custom_descriptor));
        return sizeof(custom_descriptor);
    }
    return 0;
}

// ========================================================================
// UHID EVENT HANDLERS
// ========================================================================

static void uhid_handle_output(struct uhid_event *ev, controller_t *slot) {
    if (ev->type != UHID_OUTPUT) return;
    if (ev->u.output.size >= 3) {
        uint8_t strong = ev->u.output.data[1];
        uint8_t weak = ev->u.output.data[2];
        uint8_t gain = atomic_load(&slot->rumble_gain);
        strong = (uint16_t)strong * gain / 100;
        weak = (uint16_t)weak * gain / 100;
        atomic_store(&slot->rumble_strong, strong);
        atomic_store(&slot->rumble_weak, weak);
        atomic_store(&slot->rumble_dirty, true);
        // Rate-limited log (max 1 per second) for output reports
        log_ratelimit_time(LOG_CAT_UHID, 1000000, LOG_DEBUG,
                           "UHID: Output report - strong=%d, weak=%d", strong, weak);
    }
}

static void uhid_handle_get_report(struct uhid_event *ev, controller_t *slot, int fd) {
    (void)slot;
    struct uhid_event reply;
    memset(&reply, 0, sizeof(reply));
    reply.type = UHID_GET_REPORT_REPLY;
    reply.u.get_report_reply.id = ev->u.get_report.id;
    reply.u.get_report_reply.err = 0;
    reply.u.get_report_reply.size = 0;
    if (uhid_write_event(fd, &reply) < 0) {
        syslog(LOG_ERR, "UHID: Failed to reply to GET_REPORT");
    }
}

static void uhid_handle_set_report(struct uhid_event *ev, controller_t *slot, int fd) {
    struct uhid_event reply;
    memset(&reply, 0, sizeof(reply));
    reply.type = UHID_SET_REPORT_REPLY;
    reply.u.set_report_reply.id = ev->u.set_report.id;
    reply.u.set_report_reply.err = 0;
    if (ev->u.set_report.size >= 3 && ev->u.set_report.rtype == 2) {
        uint8_t strong = ev->u.set_report.data[1];
        uint8_t weak = ev->u.set_report.data[2];
        uint8_t gain = atomic_load(&slot->rumble_gain);
        strong = (uint16_t)strong * gain / 100;
        weak = (uint16_t)weak * gain / 100;
        atomic_store(&slot->rumble_strong, strong);
        atomic_store(&slot->rumble_weak, weak);
        atomic_store(&slot->rumble_dirty, true);
    }
    if (uhid_write_event(fd, &reply) < 0) {
        syslog(LOG_ERR, "UHID: Failed to reply to SET_REPORT");
    }
}

// ========================================================================
// PUBLIC FUNCTIONS
// ========================================================================

int uhid_create(controller_t *slot, int index) {
    int fd = open("/dev/uhid", O_RDWR | O_NONBLOCK | O_CLOEXEC);
    if (fd < 0) {
        syslog(LOG_ERR, "UHID: Failed to open /dev/uhid: %s", strerror(errno));
        return -1;
    }
    
    struct uhid_event ev;
    memset(&ev, 0, sizeof(ev));
    ev.type = UHID_CREATE2;
    snprintf((char *)ev.u.create2.name, sizeof(ev.u.create2.name), 
             "Xbox 360 Controller #%d", index + 1);
    snprintf((char *)ev.u.create2.phys, sizeof(ev.u.create2.phys), 
             "dsti/%d/input0", index);
    snprintf((char *)ev.u.create2.uniq, sizeof(ev.u.create2.uniq), 
             "DSTX-%d-%08x", index, (unsigned int)time(NULL));
    ev.u.create2.vendor = 0x045e;
    ev.u.create2.product = 0x0300 + index;
    ev.u.create2.version = 0x0100;
    if (slot) {
        switch (slot->type) {
            case TYPE_DS4: ev.u.create2.version = 0x0101; break;
            case TYPE_DUALSENSE: ev.u.create2.version = 0x0102; break;
            case TYPE_NSW_PRO: ev.u.create2.version = 0x0103; break;
            default: ev.u.create2.version = 0x0100; break;
        }
    }
    ev.u.create2.country = 0;
    ev.u.create2.rd_size = uhid_build_report_descriptor(ev.u.create2.rd_data, sizeof(ev.u.create2.rd_data));
    if (ev.u.create2.rd_size == 0) {
        syslog(LOG_ERR, "UHID: Failed to build report descriptor");
        close(fd);
        return -1;
    }
    if (uhid_write_event(fd, &ev) < 0) {
        syslog(LOG_ERR, "UHID: Failed to send UHID_CREATE2");
        close(fd);
        return -1;
    }
    struct pollfd pfd = { .fd = fd, .events = POLLIN };
    int ret = poll(&pfd, 1, 3000);
    if (ret > 0) {
        struct uhid_event start_ev;
        if (uhid_read_event(fd, &start_ev) == 0 && start_ev.type == UHID_START) {
            syslog(LOG_INFO, "UHID: Device created for slot %d", index);
            return fd;
        }
    }
    syslog(LOG_ERR, "UHID: Timeout waiting for UHID_START for slot %d", index);
    close(fd);
    return -1;
}

void uhid_destroy(int fd) {
    if (fd < 0) return;
    struct uhid_event ev;
    memset(&ev, 0, sizeof(ev));
    ev.type = UHID_DESTROY;
    if (uhid_write_event(fd, &ev) < 0) {
        syslog(LOG_WARNING, "UHID: Failed to send UHID_DESTROY: %s", strerror(errno));
    }
    close(fd);
    // Rate-limited log (optional, low frequency)
    log_ratelimit_time(LOG_CAT_UHID, 1000000, LOG_DEBUG, "UHID: Device destroyed");
}

void uhid_handle_events(int fd, controller_t *slot) {
    struct uhid_event ev;
    while (uhid_read_event(fd, &ev) == 0) {
        switch (ev.type) {
            case UHID_START:
                log_ratelimit_time(LOG_CAT_UHID, 1000000, LOG_DEBUG, "UHID: START event");
                break;
            case UHID_STOP:
                log_ratelimit_time(LOG_CAT_UHID, 1000000, LOG_DEBUG, "UHID: STOP event");
                break;
            case UHID_OPEN:
                log_ratelimit_time(LOG_CAT_UHID, 1000000, LOG_DEBUG, "UHID: Device opened");
                break;
            case UHID_CLOSE:
                log_ratelimit_time(LOG_CAT_UHID, 1000000, LOG_DEBUG, "UHID: Device closed");
                break;
            case UHID_OUTPUT:
                uhid_handle_output(&ev, slot);
                break;
            case UHID_GET_REPORT:
                uhid_handle_get_report(&ev, slot, fd);
                break;
            case UHID_SET_REPORT:
                uhid_handle_set_report(&ev, slot, fd);
                break;
            default:
                log_ratelimit_time(LOG_CAT_UHID, 1000000, LOG_DEBUG, "UHID: Unhandled event: %d", ev.type);
                break;
        }
    }
}

int uhid_send_input(int fd, const uint8_t *data, size_t size) {
    if (fd < 0 || !data || size == 0 || size > UHID_REPORT_SIZE) return -1;
    struct uhid_event ev;
    memset(&ev, 0, sizeof(ev));
    ev.type = UHID_INPUT2;
    ev.u.input2.size = size;
    memcpy(ev.u.input2.data, data, size);
    if (uhid_write_event(fd, &ev) < 0) {
        syslog(LOG_ERR, "UHID: Failed to send INPUT2");
        return -1;
    }
    return 0;
}

size_t uhid_build_input_report(controller_t *slot, uint8_t *buf, size_t buf_size) {
    if (buf_size < 12) return 0;
    memset(buf, 0, 12);
    buf[0] = 0x01;
    
    uint16_t buttons = 0;
    // Buttons always present
    if (slot->cross) buttons |= (1 << 0);
    if (slot->circle) buttons |= (1 << 1);
    if (slot->triangle) buttons |= (1 << 4);
    if (slot->square) buttons |= (1 << 3);
    if (slot->L1) buttons |= (1 << 6);
    if (slot->R1) buttons |= (1 << 7);
    if (slot->Share) buttons |= (1 << 10);
    if (slot->Options) buttons |= (1 << 11);
    if (slot->PS) buttons |= (1 << 12);
    if (slot->L3) buttons |= (1 << 13);
    if (slot->R3) buttons |= (1 << 14);
    
    bool trig_digital = atomic_load(&slot->is_trigger_digital);
    if (trig_digital) {
        if (slot->L2) buttons |= (1 << 8);
        if (slot->R2) buttons |= (1 << 9);
    }
    
    buf[1] = buttons & 0xFF;
    buf[2] = (buttons >> 8) & 0xFF;
    
    // D-Pad
    uint8_t dpad_value;
    if (slot->HATY == -1 && slot->HATX == 0) dpad_value = 0;
    else if (slot->HATY == -1 && slot->HATX == 1) dpad_value = 1;
    else if (slot->HATY == 0 && slot->HATX == 1) dpad_value = 2;
    else if (slot->HATY == 1 && slot->HATX == 1) dpad_value = 3;
    else if (slot->HATY == 1 && slot->HATX == 0) dpad_value = 4;
    else if (slot->HATY == 1 && slot->HATX == -1) dpad_value = 5;
    else if (slot->HATY == 0 && slot->HATX == -1) dpad_value = 6;
    else if (slot->HATY == -1 && slot->HATX == -1) dpad_value = 7;
    else dpad_value = 8;
    buf[3] = dpad_value;
    
    // Sticks
    buf[4] = (slot->LX + 32768) >> 8;
    buf[5] = (slot->LY + 32768) >> 8;
    buf[8] = (slot->RX + 32768) >> 8;
    buf[9] = (slot->RY + 32768) >> 8;
    
    // Trigger axes - only in analog mode
    if (!trig_digital) {
        int16_t left_val = get_trigger_axis_value(slot, true);
        int16_t right_val = get_trigger_axis_value(slot, false);
        buf[11] = left_val;   // Now 0-255
        buf[12] = right_val;
    }
    
#ifdef DSTX_DEBUG_VERBOSE
    syslog(LOG_DEBUG, "UHID Report[%d]: ID=1 BTN=0x%04x D=%d LX=%d LY=%d RX=%d RY=%d LT=%d RT=%d (digital=%d)",
           (int)(slot - shm_ptr->slots),
           buttons, buf[3], buf[4], buf[5], buf[8], buf[9], buf[11], buf[12], trig_digital);
#endif
    
    return 13;
}
