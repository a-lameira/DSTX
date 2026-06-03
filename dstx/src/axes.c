/*
 * axes.c - Analog stick processing for DSTX
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
 * - Logic for sensitivity and deadzone configuration
 */

#include "axes.h"
#include <math.h>

#define NORMALIZED_MAX 65535.0f
#define LUT_SIZE 257
#define STICK_MIN -32768
#define STICK_MAX 32767

static float g_preset_luts[SENS_PRESET_COUNT][LUT_SIZE];
static bool g_initialized = false;

typedef struct {
    const char* name;
    float exponent;
} preset_config_t;

static const preset_config_t g_presets[SENS_PRESET_COUNT] = {
    [SENS_PRESET_DEFAULT]    = { "Default",    1.00f },
    [SENS_PRESET_PRECISION]  = { "Precision",  0.65f },
    [SENS_PRESET_RAPID]      = { "Rapid",      1.80f },
    [SENS_PRESET_SUAVE]      = { "Smooth",     0.75f },
    [SENS_PRESET_AGGRESSIVE] = { "Aggressive", 2.50f },
    [SENS_PRESET_SNIPER]     = { "Sniper",     0.50f },
    [SENS_PRESET_RACING]     = { "Racing",     1.00f },
    [SENS_PRESET_FPS]        = { "FPS",        1.50f }
};

static inline int16_t clamp(int32_t value) {
    if (value > STICK_MAX) return STICK_MAX;
    if (value < STICK_MIN) return STICK_MIN;
    return (int16_t)value;
}

void init_axis_system(void) {
    if (g_initialized) return;
    
    for (int p = 0; p < SENS_PRESET_COUNT; p++) {
        const preset_config_t *cfg = &g_presets[p];
        
        for (int i = 0; i < LUT_SIZE; i++) {
            float input_mag = i / (float)(LUT_SIZE - 1);
            float output_mag = powf(input_mag, cfg->exponent);
            if (output_mag > 1.0f) output_mag = 1.0f;
            
            float normalized = output_mag * NORMALIZED_MAX;
            if (normalized < 0.0f) normalized = 0.0f;
            if (normalized > NORMALIZED_MAX) normalized = NORMALIZED_MAX;
            
            g_preset_luts[p][i] = normalized;
        }
    }
    
    g_initialized = true;
    syslog(LOG_INFO, "AXIS: System initialized with %d presets (float + interpolation)", SENS_PRESET_COUNT);
}

const char* get_sensitivity_preset_name(sensitivity_preset_t preset) {
    if (preset >= 0 && preset < SENS_PRESET_COUNT) {
        return g_presets[preset].name;
    }
    return "Unknown";
}

void apply_sensitivity_preset_left(controller_t *slot, sensitivity_preset_t preset) {
    if (!slot) return;
    if (preset < 0 || preset >= SENS_PRESET_COUNT) return;
    
    uint8_t old = atomic_load(&slot->sensitivity_left_preset);
    if (old != preset) {
        atomic_store(&slot->sensitivity_left_preset, preset);
        syslog(LOG_INFO, "AXIS: Slot %d - LEFT stick -> %s", 
               (int)(slot - shm_ptr->slots), g_presets[preset].name);
    }
}

void apply_sensitivity_preset_right(controller_t *slot, sensitivity_preset_t preset) {
    if (!slot) return;
    if (preset < 0 || preset >= SENS_PRESET_COUNT) return;
    
    uint8_t old = atomic_load(&slot->sensitivity_right_preset);
    if (old != preset) {
        atomic_store(&slot->sensitivity_right_preset, preset);
        syslog(LOG_INFO, "AXIS: Slot %d - RIGHT stick -> %s", 
               (int)(slot - shm_ptr->slots), g_presets[preset].name);
    }
}

/**
 * Core sensitivity application with:
 * - Early exit for null vector
 * - Linear interpolation on LUT
 * - Float usage for performance
 */
static void apply_sensitivity_core(uint8_t preset, int16_t *x, int16_t *y) {
    if (!x || !y) return;
    if (preset >= SENS_PRESET_COUNT) preset = SENS_PRESET_DEFAULT;
    
    // Compute squared magnitude for early exit
    int32_t mag_sq = (int32_t)(*x) * (*x) + (int32_t)(*y) * (*y);
    if (mag_sq == 0) return;  // Nothing to do, stick centered
    
    float mag = sqrtf((float)mag_sq);
    const float MAX_MAG = 32768.0f;
    
    if (mag >= MAX_MAG) return;  // Already at limit, no curve needed
    
    float norm_mag = mag / MAX_MAG;
    
    // Linear interpolation between two LUT points
    float t = norm_mag * (LUT_SIZE - 1);
    int idx = (int)t;
    float frac = t - idx;
    
    float curved_norm_mag;
    if (idx >= LUT_SIZE - 1) {
        curved_norm_mag = 1.0f;
    } else {
        float low = g_preset_luts[preset][idx];
        float high = g_preset_luts[preset][idx + 1];
        float interp = low + frac * (high - low);
        curved_norm_mag = interp / NORMALIZED_MAX;
    }
    
    float new_mag = curved_norm_mag * MAX_MAG;
    float scale = new_mag / mag;
    
    *x = clamp((int32_t)((float)*x * scale));
    *y = clamp((int32_t)((float)*y * scale));
}

void apply_sensitivity_left(controller_t *slot, int16_t *x, int16_t *y) {
    if (!slot) return;
    if (!g_initialized) init_axis_system();
    
    uint8_t preset = atomic_load(&slot->sensitivity_left_preset);
    apply_sensitivity_core(preset, x, y);
}

void apply_sensitivity_right(controller_t *slot, int16_t *x, int16_t *y) {
    if (!slot) return;
    if (!g_initialized) init_axis_system();
    
    uint8_t preset = atomic_load(&slot->sensitivity_right_preset);
    apply_sensitivity_core(preset, x, y);
}

void apply_deadzone(int16_t *x, int16_t *y, uint8_t deadzone_pct) {
    // Validation: ensure deadzone_pct is between 0 and 100
    // (SHM corruption might have out-of-range values)
    uint8_t dz = deadzone_pct;
    if (dz > 100) {
        syslog(LOG_WARNING, "AXIS: Invalid deadzone_pct (%d), using 100", dz);
        dz = 100;
    }
    
    if (dz == 0) return;
    if (dz >= 100) {
        *x = 0;
        *y = 0;
        return;
    }
    
    float mag = sqrtf((float)(*x * *x + *y * *y));
    const float MAX_MAG = 32768.0f;
    float threshold = (dz / 100.0f) * MAX_MAG;
    
    if (mag <= threshold) {
        *x = 0;
        *y = 0;
        return;
    }
    
    if (mag > MAX_MAG) mag = MAX_MAG;
    
    float new_mag = threshold + (mag - threshold) *
                    (MAX_MAG - threshold) / (MAX_MAG - threshold);
    
    float scale = new_mag / mag;
    
    *x = clamp((int32_t)((float)*x * scale));
    *y = clamp((int32_t)((float)*y * scale));
}
