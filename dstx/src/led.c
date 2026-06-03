/*
 * led.c - LED effect system implementation for DSTX
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

#include "led.h"
#include <math.h>
#include <assert.h>
#include <errno.h>
#include <time.h>

// ========================================================================
// INTERNAL CONSTANTS
// ========================================================================
#define MAX_SPEED 10
#define MIN_SPEED 1
#define MAX_BRIGHTNESS 100
#define MIN_BRIGHTNESS 1
#define RATE_LIMIT_US 8000  // 8ms minimum between writes (≈125Hz)

// Easing table size (256 points is enough for smooth linear interpolation)
#define EASING_TABLE_SIZE 256

// ========================================================================
// HELPER MACRO FOR TIME CALCULATION
// ========================================================================
#define TIMEVAL_DIFF_US(tv1, tv2) \
    (((tv1).tv_sec - (tv2).tv_sec) * 1000000L + \
     ((tv1).tv_usec - (tv2).tv_usec))

// ========================================================================
// PRECOMPUTED TABLES (SINE AND EASING)
// ========================================================================
#define SIN_TABLE_SIZE 360
static float g_sin_table[SIN_TABLE_SIZE];

// Easing tables
typedef enum {
    EASING_LINEAR,
    EASING_SINE_IN_OUT,
    EASING_SINE_CYCLE,   // Smooth cycle: 0 -> 1 -> 0
    EASING_QUAD_IN_OUT,
    EASING_CUBIC_IN_OUT,
    EASING_COUNT
} easing_type_t;

static float g_easing_tables[EASING_COUNT][EASING_TABLE_SIZE];
static bool g_tables_initialized = false;

// Easing functions (used only to generate the tables)
static float easing_linear(float t) {
    return t;
}

static float easing_sine_in_out(float t) {
    return (1.0f - cosf(t * M_PI)) / 2.0f;
}

static float easing_sine_cycle(float t) {
    // 0 → 1 → 0 as t goes from 0 to 1
    return 0.5f * (1.0f - cosf(2.0f * M_PI * t));
}

static float easing_quad_in_out(float t) {
    if (t < 0.5f) return 2.0f * t * t;
    t = 2.0f * (1.0f - t);
    return 1.0f - (t * t) / 2.0f;
}

static float easing_cubic_in_out(float t) {
    if (t < 0.5f) return 4.0f * t * t * t;
    t = 2.0f * (1.0f - t);
    return 1.0f - (t * t * t) / 2.0f;
}

// Initializes all tables
static void init_tables(void) {
    if (g_tables_initialized) return;
    
    // Sine table (for fast_sinf)
    for (int i = 0; i < SIN_TABLE_SIZE; i++) {
        g_sin_table[i] = sinf(i * M_PI / 180.0f);
    }
    
    // Easing tables
    for (int i = 0; i < EASING_TABLE_SIZE; i++) {
        float t = (float)i / (EASING_TABLE_SIZE - 1);
        g_easing_tables[EASING_LINEAR][i] = easing_linear(t);
        g_easing_tables[EASING_SINE_IN_OUT][i] = easing_sine_in_out(t);
        g_easing_tables[EASING_SINE_CYCLE][i] = easing_sine_cycle(t);
        g_easing_tables[EASING_QUAD_IN_OUT][i] = easing_quad_in_out(t);
        g_easing_tables[EASING_CUBIC_IN_OUT][i] = easing_cubic_in_out(t);
    }
    
    g_tables_initialized = true;
}

static inline float fast_sinf(float degrees) {
    int idx = ((int)degrees) % SIN_TABLE_SIZE;
    if (idx < 0) idx += SIN_TABLE_SIZE;
    return g_sin_table[idx];
}

// Applies easing with linear interpolation
static inline float easing_apply(easing_type_t type, float t) {
    // t in [0,1]
    if (t <= 0.0f) return g_easing_tables[type][0];
    if (t >= 1.0f) return g_easing_tables[type][EASING_TABLE_SIZE - 1];
    
    float pos = t * (EASING_TABLE_SIZE - 1);
    int idx = (int)pos;
    float frac = pos - idx;
    float a = g_easing_tables[type][idx];
    float b = g_easing_tables[type][idx + 1];
    return a + frac * (b - a);
}

// ========================================================================
// SPEED MULTIPLIER TABLE PER EFFECT
// ========================================================================
// Each effect has a multiplier that adjusts the base speed
// The user continues to use speed 1-10, but internally we apply:
// final_speed = base_speed(speed) * multiplier[effect]
//
// Adjust these values to find the "sweet spot" for each effect
// ========================================================================

typedef struct {
    led_effect_t effect;
    float multiplier;
} speed_multiplier_entry_t;

static const speed_multiplier_entry_t g_speed_multipliers[] = {
    { LEDFX_BREATH,        1.0f },   // Smooth breathing
    { LEDFX_RAINBOW,       1.0f },   // Spectrum rotation
    { LEDFX_PULSE,         1.0f },   // Heart pulse
    { LEDFX_STROBE,        8.0f },   // Fast blinking (8x faster)
    { LEDFX_WAVE,          1.2f },   // RGB wave (20% faster)
    { LEDFX_BATTERY,       0.8f },   // Battery indicator (20% slower)
    { LEDFX_TRIGGER,       0.0f },   // Does not use speed
    { LEDFX_BUTTON_PRESS,  0.0f }    // Does not use speed
};

static float get_speed_multiplier_for_effect(led_effect_t effect) {
    size_t count = sizeof(g_speed_multipliers) / sizeof(g_speed_multipliers[0]);
    for (size_t i = 0; i < count; i++) {
        if (g_speed_multipliers[i].effect == effect) {
            return g_speed_multipliers[i].multiplier;
        }
    }
    return 1.0f;  // Default
}

// Base speed
static inline float get_base_speed_multiplier(uint8_t speed) {
    float t = (speed - MIN_SPEED) / (float)(MAX_SPEED - MIN_SPEED);
    return 0.05f + t * (1.2f - 0.05f);
}

// ========================================================================
// EFFECT STRUCTURE (FUNCTION TABLE)
// ========================================================================

// Forward declarations of effect functions
struct led_slot_state_t; // opaque
static void effect_static(struct led_slot_state_t *state, controller_t *slot, double phase, uint8_t *r, uint8_t *g, uint8_t *b);
static void effect_breath(struct led_slot_state_t *state, controller_t *slot, double phase, uint8_t *r, uint8_t *g, uint8_t *b);
static void effect_rainbow(struct led_slot_state_t *state, controller_t *slot, double phase, uint8_t *r, uint8_t *g, uint8_t *b);
static void effect_pulse(struct led_slot_state_t *state, controller_t *slot, double phase, uint8_t *r, uint8_t *g, uint8_t *b);
static void effect_strobe(struct led_slot_state_t *state, controller_t *slot, double phase, uint8_t *r, uint8_t *g, uint8_t *b);
static void effect_wave(struct led_slot_state_t *state, controller_t *slot, double phase, uint8_t *r, uint8_t *g, uint8_t *b);
static void effect_battery(struct led_slot_state_t *state, controller_t *slot, double phase, uint8_t *r, uint8_t *g, uint8_t *b);
static void effect_trigger(struct led_slot_state_t *state, controller_t *slot, double phase, uint8_t *r, uint8_t *g, uint8_t *b);
static void effect_button(struct led_slot_state_t *state, controller_t *slot, double phase, uint8_t *r, uint8_t *g, uint8_t *b);

// Effect table: each entry contains name and update function
typedef struct {
    const char *name;
    void (*update)(struct led_slot_state_t *state, controller_t *slot, double phase, uint8_t *r, uint8_t *g, uint8_t *b);
} led_effect_entry_t;

static led_effect_entry_t g_effects[] = {
    [LEDFX_STATIC]   = { "STATIC",   effect_static },
    [LEDFX_BREATH]   = { "BREATH",   effect_breath },
    [LEDFX_RAINBOW]  = { "RAINBOW",  effect_rainbow },
    [LEDFX_PULSE]    = { "PULSE",    effect_pulse },
    [LEDFX_STROBE]   = { "STROBE",   effect_strobe },
    [LEDFX_WAVE]     = { "WAVE",     effect_wave },
    [LEDFX_BATTERY]  = { "BATTERY",  effect_battery },
    [LEDFX_TRIGGER]  = { "TRIGGER",  effect_trigger },
    [LEDFX_BUTTON_PRESS] = { "BUTTON", effect_button }
};
_Static_assert(sizeof(g_effects)/sizeof(g_effects[0]) == LEDFX_COUNT, "Effect table size mismatch");

// ========================================================================
// INTERNAL STATE (COMPLETELY PRIVATE)
// ========================================================================
typedef struct led_slot_state_t {
    led_effect_t current_effect;     // Active effect
    double start_time;                // Absolute timestamp of effect start (seconds)
    uint8_t speed;                    // Current speed
    uint8_t brightness;               // Current brightness
    bool active;                       // Whether running (false for static)
    
    // Timers for rate limiting
    struct timeval last_write;         // Last time we wrote to SHM
    
    // Last color sent (to avoid unnecessary writes)
    uint8_t last_r, last_g, last_b;
} led_slot_state_t;

// State array (ONE PER SLOT) - COMPLETELY PRIVATE
static led_slot_state_t g_slot_state[MAX_SLOTS];
static bool g_initialized = false;

// ========================================================================
// PRIVATE HELPER FUNCTIONS
// ========================================================================

// Gets current time in seconds (high resolution, monotonic)
static inline double get_current_time_sec(void) {
    struct timespec ts;
    clock_gettime(CLOCK_MONOTONIC, &ts);
    return ts.tv_sec + ts.tv_nsec / 1e9;
}

// ========================================================================
// EFFECT IMPLEMENTATIONS (ALL PRIVATE)
// ========================================================================

static void effect_static(led_slot_state_t *state, controller_t *slot, double phase, uint8_t *r, uint8_t *g, uint8_t *b) {
    (void)state; (void)phase;
    float brightness = state->brightness / 100.0f;
    *r = (uint8_t)(atomic_load(&slot->led_base_r) * brightness);
    *g = (uint8_t)(atomic_load(&slot->led_base_g) * brightness);
    *b = (uint8_t)(atomic_load(&slot->led_base_b) * brightness);
}

static void effect_breath(led_slot_state_t *state, controller_t *slot, double phase, uint8_t *r, uint8_t *g, uint8_t *b) {
    // Convert phase to cycle progress (0 to 1)
    float t = fmod(phase, 360.0f) / 360.0f;
    // Apply cyclic easing: goes up and down smoothly
    float factor = easing_apply(EASING_SINE_CYCLE, t);
    float brightness = state->brightness * factor / 100.0f;
    
    *r = (uint8_t)(atomic_load(&slot->led_base_r) * brightness);
    *g = (uint8_t)(atomic_load(&slot->led_base_g) * brightness);
    *b = (uint8_t)(atomic_load(&slot->led_base_b) * brightness);
}

static void effect_rainbow(led_slot_state_t *state, controller_t *slot, double phase, uint8_t *r, uint8_t *g, uint8_t *b) {
    (void)slot;
    float h = phase;
    float s = 1.0f;
    float v = state->brightness / 100.0f;
    
    float c = v * s;
    float x = c * (1 - fabsf(fmodf(h / 60.0f, 2) - 1));
    float m = v - c;
    
    float rf, gf, bf;
    
    if (h < 60) {
        rf = c; gf = x; bf = 0;
    } else if (h < 120) {
        rf = x; gf = c; bf = 0;
    } else if (h < 180) {
        rf = 0; gf = c; bf = x;
    } else if (h < 240) {
        rf = 0; gf = x; bf = c;
    } else if (h < 300) {
        rf = x; gf = 0; bf = c;
    } else {
        rf = c; gf = 0; bf = x;
    }
    
    *r = (uint8_t)((rf + m) * 255);
    *g = (uint8_t)((gf + m) * 255);
    *b = (uint8_t)((bf + m) * 255);
}

static void effect_pulse(led_slot_state_t *state, controller_t *slot, double phase, uint8_t *r, uint8_t *g, uint8_t *b) {
    float rad = phase * M_PI / 180.0f;
    float factor = (sinf(rad) + 1.0f) / 2.0f;
    factor = 0.2f + factor * 0.8f;  // 20% to 100%
    
    float brightness = state->brightness * factor / 100.0f;
    
    *r = (uint8_t)(atomic_load(&slot->led_base_r) * brightness);
    *g = (uint8_t)(atomic_load(&slot->led_base_g) * brightness);
    *b = (uint8_t)(atomic_load(&slot->led_base_b) * brightness);
}

static void effect_strobe(led_slot_state_t *state, controller_t *slot, double phase, uint8_t *r, uint8_t *g, uint8_t *b) {
    bool on = (fmod(phase, 360.0f) < 180.0f);
    if (on) {
        float brightness = state->brightness / 100.0f;
        *r = (uint8_t)(atomic_load(&slot->led_base_r) * brightness);
        *g = (uint8_t)(atomic_load(&slot->led_base_g) * brightness);
        *b = (uint8_t)(atomic_load(&slot->led_base_b) * brightness);
    } else {
        *r = *g = *b = 0;
    }
}

static void effect_wave(led_slot_state_t *state, controller_t *slot, double phase, uint8_t *r, uint8_t *g, uint8_t *b) {
    (void)slot;
    float rad = phase * M_PI / 180.0f;
    float brightness = state->brightness / 100.0f;
    
    *r = (uint8_t)((128 + 127 * sinf(rad)) * brightness);
    *g = (uint8_t)((128 + 127 * sinf(rad + 2*M_PI/3)) * brightness);
    *b = (uint8_t)((128 + 127 * sinf(rad + 4*M_PI/3)) * brightness);
}

static void effect_battery(led_slot_state_t *state, controller_t *slot, double phase, uint8_t *r, uint8_t *g, uint8_t *b) {
    float brightness = state->brightness / 100.0f;
    int battery = atomic_load(&slot->battery);
    
    if (battery >= 80) {
        *r = 0; *g = (uint8_t)(255 * brightness); *b = 0;
    } else if (battery >= 50) {
        *r = (uint8_t)(255 * brightness);
        *g = (uint8_t)(255 * brightness);
        *b = 0;
    } else if (battery >= 20) {
        *r = (uint8_t)(255 * brightness);
        *g = (uint8_t)(165 * brightness);
        *b = 0;
    } else {
        // Low battery: blink smoothly with cyclic easing
        float t = fmod(phase, 360.0f) / 360.0f;
        float factor = easing_apply(EASING_SINE_CYCLE, t);
        *r = (uint8_t)(255 * brightness * factor);
        *g = 0;
        *b = 0;
    }
}

/**
 * effect_trigger - Effect that lights the LED based on triggers (LT/RT)
 *
 * Behavior:
 * - Initial state: LED off (black - 000000)
 * - If LT == 0 and RT == 0: LED off (black)
 * - If any trigger > 0: LED shows base color (led_base_r/g/b)
 *
 * LED intensity is modulated by the maximum value of the two triggers,
 * creating an "analog response" effect where deeper trigger = brighter LED.
 */
static void effect_trigger(led_slot_state_t *state, controller_t *slot, double phase, 
                           uint8_t *r, uint8_t *g, uint8_t *b) {
    (void)phase;
    
    // ALWAYS start with black as base
    *r = 0;
    *g = 0;
    *b = 0;
    
    // Get trigger values (0 to 255)
    uint16_t lt = (slot->LT > 0) ? (slot->LT) : 0;
    uint16_t rt = (slot->RT > 0) ? (slot->RT) : 0;
    
    // Maximum value between both triggers (0-255)
    uint16_t max_trigger = (lt > rt) ? lt : rt;
    
    if (max_trigger > 0) {
        // Trigger pressed → show base color with modulated intensity
        float brightness = state->brightness / 100.0f;
        float intensity = (max_trigger / 255.0f) * brightness;
        
        *r = (uint8_t)(atomic_load(&slot->led_base_r) * intensity);
        *g = (uint8_t)(atomic_load(&slot->led_base_g) * intensity);
        *b = (uint8_t)(atomic_load(&slot->led_base_b) * intensity);
    }
}

/**
 * effect_button - Effect that lights the LED based on any button press
 *
 * Behavior:
 * - Initial state: LED off (black - 000000)
 * - If no button pressed: LED off (black)
 * - If any button pressed: LED shows base color (led_base_r/g/b)
 */
static void effect_button(led_slot_state_t *state, controller_t *slot, double phase, 
                          uint8_t *r, uint8_t *g, uint8_t *b) {
    (void)phase;
    
    // ALWAYS start with black as base
    *r = 0;
    *g = 0;
    *b = 0;
    
    // Check if any button is pressed
    bool any_button_pressed = 
        slot->cross || slot->circle || slot->square || slot->triangle ||
        slot->L1 || slot->R1 || slot->L2 || slot->R2 ||
        slot->Share || slot->Options || slot->PS || 
        slot->L3 || slot->R3 || slot->touch_btn;
    
    if (any_button_pressed) {
        // Some button pressed → show base color with configured maximum brightness
        float brightness = state->brightness / 100.0f;
        
        *r = (uint8_t)(atomic_load(&slot->led_base_r) * brightness);
        *g = (uint8_t)(atomic_load(&slot->led_base_g) * brightness);
        *b = (uint8_t)(atomic_load(&slot->led_base_b) * brightness);
    }
}

// ========================================================================
// PUBLIC FUNCTIONS
// ========================================================================

void ledfx_init(void) {
    if (g_initialized) return;
    
    init_tables();
    
    for (int i = 0; i < MAX_SLOTS; i++) {
        led_slot_state_t *state = &g_slot_state[i];
        state->current_effect = LEDFX_STATIC;
        state->start_time = 0.0;
        state->speed = 5;
        state->brightness = 80;
        state->active = false;
        state->last_write.tv_sec = 0;
        state->last_write.tv_usec = 0;
        state->last_r = state->last_g = state->last_b = 0;
    }
    
    g_initialized = true;
    syslog(LOG_INFO, "LEDFX: Effect system initialized");
}

void ledfx_cleanup(void) {
    g_initialized = false;
    syslog(LOG_INFO, "LEDFX: Effect system finalized");
}

void ledfx_process_requests(void) {
    if (!shm_ptr || !g_initialized) return;
    
    for (int i = 0; i < MAX_SLOTS; i++) {
        // Atomic read of connected flag
        if (!atomic_load(&shm_ptr->slots[i].connected)) continue;
        
        // Protect SHM field reads with mutex
        safe_shm_lock(&shm_ptr->proc_mutex);
        bool pending = atomic_load(&shm_ptr->slots[i].led_request_pending);
        int effect = atomic_load(&shm_ptr->slots[i].led_request_effect);
        uint8_t speed = atomic_load(&shm_ptr->slots[i].led_request_speed);
        uint8_t brightness = atomic_load(&shm_ptr->slots[i].led_request_brightness);
        
        if (pending) {
            atomic_store(&shm_ptr->slots[i].led_request_pending, false);
        }
        pthread_mutex_unlock(&shm_ptr->proc_mutex);
        
        if (pending) {
            if (speed < MIN_SPEED || speed > MAX_SPEED) speed = 5;
            if (brightness < MIN_BRIGHTNESS || brightness > MAX_BRIGHTNESS) brightness = 80;
            
            led_slot_state_t *state = &g_slot_state[i];
            
            if (effect == 0) {
                // Static mode
                atomic_store(&shm_ptr->slots[i].led_static, true);
                state->active = false;
                
                // Set static color from base (using atomic_store)
                uint8_t base_r = atomic_load(&shm_ptr->slots[i].led_base_r);
                uint8_t base_g = atomic_load(&shm_ptr->slots[i].led_base_g);
                uint8_t base_b = atomic_load(&shm_ptr->slots[i].led_base_b);
                atomic_store(&shm_ptr->slots[i].led_r, base_r);
                atomic_store(&shm_ptr->slots[i].led_g, base_g);
                atomic_store(&shm_ptr->slots[i].led_b, base_b);
                atomic_store(&shm_ptr->slots[i].led_dirty, true);
                
                // Rate-limited log (max 1 per second) for static mode
                log_ratelimit_time(LOG_CAT_LED, 1000000, LOG_DEBUG,
                                   "LEDFX: Slot %d static mode", i);
                
            } else if (effect > 0 && effect < LEDFX_COUNT) {
                // Start new effect
                atomic_store(&shm_ptr->slots[i].led_static, false);
                state->active = true;
                state->current_effect = (led_effect_t)effect;
                state->speed = speed;
                state->brightness = brightness;
                state->start_time = get_current_time_sec();
                gettimeofday(&state->last_write, NULL);
                
                // For effects that should start with LED black (TRIGGER and BUTTON)
                if (effect == LEDFX_TRIGGER || effect == LEDFX_BUTTON_PRESS) {
                    atomic_store(&shm_ptr->slots[i].led_r, 0);
                    atomic_store(&shm_ptr->slots[i].led_g, 0);
                    atomic_store(&shm_ptr->slots[i].led_b, 0);
                }
                
                // Force LED dirty to ensure hardware update
                atomic_store(&shm_ptr->slots[i].led_dirty, true);
                
                // Reset last color cache
                state->last_r = state->last_g = state->last_b = 0;
                
                // INFO log (no rate limiting) for effect start
                syslog(LOG_INFO, "LEDFX: Slot %d starting effect %d (%s) (speed=%d, brightness=%d)", 
                       i, effect, g_effects[effect].name, speed, brightness);
            }
        }
    }
}

bool ledfx_update_slot(int slot_idx, double current_time) {
    if (!shm_ptr || !g_initialized) return false;
    if (slot_idx < 0 || slot_idx >= MAX_SLOTS) return false;
    if (!atomic_load(&shm_ptr->slots[slot_idx].connected)) return false;
    
    controller_t *slot = &shm_ptr->slots[slot_idx];
    
    // Static mode does not need updates
    if (atomic_load(&slot->led_static)) return false;
    
    led_slot_state_t *state = &g_slot_state[slot_idx];
    if (!state->active) return false;
    
    // ===== RATE LIMITING =====
    struct timeval now_tv;
    gettimeofday(&now_tv, NULL);
    long elapsed_us = TIMEVAL_DIFF_US(now_tv, state->last_write);
    
    bool is_first_frame = (state->last_write.tv_sec == 0 && state->last_write.tv_usec == 0);
    bool cache_reset = (state->last_r == 0 && state->last_g == 0 && state->last_b == 0);
    
    if (!is_first_frame && !cache_reset && elapsed_us < RATE_LIMIT_US) {
        return false;
    }
    
    // Calculate base speed
    float base_speed = get_base_speed_multiplier(state->speed);
    
    // Apply effect-specific multiplier
    float effect_multiplier = get_speed_multiplier_for_effect(state->current_effect);
    float final_speed = base_speed * effect_multiplier;
    
    // Calculate phase based on elapsed time
    double elapsed = current_time - state->start_time;
    double phase = fmod(elapsed * final_speed * 360.0, 360.0);
    
    // Calculate new color
    uint8_t r, g, b;
    led_effect_entry_t *effect = &g_effects[state->current_effect];
    effect->update(state, slot, phase, &r, &g, &b);
    
    // Only update if changed
    if (r != state->last_r || g != state->last_g || b != state->last_b) {
        atomic_store(&slot->led_r, r);
        atomic_store(&slot->led_g, g);
        atomic_store(&slot->led_b, b);
        atomic_store(&slot->led_dirty, true);
        
        state->last_r = r;
        state->last_g = g;
        state->last_b = b;
        state->last_write = now_tv;
        
        return true;
    }
    
    return false;
}

const char* ledfx_get_effect_name(led_effect_t effect) {
    if (effect >= 0 && effect < LEDFX_COUNT) {
        return g_effects[effect].name;
    }
    return "UNKNOWN";
}
