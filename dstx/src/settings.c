/*
 * settings.c - Singleton configuration thread implementation
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
 * All profile management logic resides in this file and runs in a dedicated thread.
 *
 * - Rigorous validation of all fields read from JSON.
 * - Use of allowed ranges for each field.
 * - Fallback to default values in case of invalid data.
 */

#include "settings.h"
#include "keys.h"
#include "led.h"        // for LEDFX_COUNT
#include "axes.h"       // for SENS_PRESET_COUNT
#include <pthread.h>
#include <poll.h>
#include <sys/inotify.h>
#include <sys/stat.h>
#include <sys/time.h>
#include <cjson/cJSON.h>
#include <dirent.h>
#include <unistd.h>
#include <string.h>
#include <errno.h>

// ============================================================================
// PRIVATE STRUCTURES
// ============================================================================

#define PROFILE_NAME_LEN 64

typedef struct {
    char name[PROFILE_NAME_LEN];
    slot_config_t slots[MAX_SLOTS];
    uint64_t last_modified;
    uint32_t version;
} profile_t;

typedef struct {
    char base_dir[PATH_MAX];
    char profiles_dir[PATH_MAX];
    profile_t active_profile;
    char active_name[PROFILE_NAME_LEN];
    bool profile_dirty;
    struct timeval last_change;
    bool auto_save_enabled;
    unsigned int auto_save_delay_ms;
    int inotify_fd;
    int inotify_wd;
} profile_manager_t;

// Global thread context (singleton)
typedef struct {
    pthread_t thread;
    int pipefd[2];            // used to wake the thread on shutdown
    shared_data_t *shm;
    profile_manager_t pm;
    bool running;
} settings_ctx_t;

static settings_ctx_t g_ctx = {0};

// ============================================================================
// VALIDATION HELPERS
// ============================================================================

/**
 * safe_json_get_int_range - Extracts an integer from JSON and validates range.
 * @param obj: JSON object
 * @param key: Key name
 * @param out: Pointer to store the value (if found and valid)
 * @param min_val: Minimum allowed value (inclusive)
 * @param max_val: Maximum allowed value (inclusive)
 * @param default_val: Default value if key missing or invalid
 * @return true if key existed and was within range, false otherwise
 *         (out always receives a valid value: either read or default)
 */
static bool safe_json_get_int_range(cJSON *obj, const char *key, int *out,
                                     int min_val, int max_val, int default_val) {
    cJSON *item = cJSON_GetObjectItem(obj, key);
    if (!item) {
        *out = default_val;
        return false;
    }
    if (!cJSON_IsNumber(item)) {
        syslog(LOG_WARNING, "PROFILE: Field '%s' is not numeric, using default %d", key, default_val);
        *out = default_val;
        return false;
    }
    int val = item->valueint;
    if (val < min_val || val > max_val) {
        syslog(LOG_WARNING, "PROFILE: Field '%s'=%d out of range [%d..%d], using default %d",
               key, val, min_val, max_val, default_val);
        *out = default_val;
        return false;
    }
    *out = val;
    return true;
}

/**
 * safe_json_get_bool - Extracts a boolean (as integer 0/1) from JSON and validates.
 */
static bool safe_json_get_bool(cJSON *obj, const char *key, bool *out, bool default_val) {
    int val;
    bool found = safe_json_get_int_range(obj, key, &val, 0, 1, default_val ? 1 : 0);
    *out = (val != 0);
    return found;
}

/**
 * safe_json_get_uint8 - Extracts uint8 with range validation.
 */
static bool safe_json_get_uint8(cJSON *obj, const char *key, uint8_t *out,
                                 uint8_t min_val, uint8_t max_val, uint8_t default_val) {
    int tmp;
    bool found = safe_json_get_int_range(obj, key, &tmp, min_val, max_val, default_val);
    *out = (uint8_t)tmp;
    return found;
}

// ============================================================================
// INTERNAL FUNCTION PROTOTYPES
// ============================================================================

static bool load_profile_from_disk(profile_manager_t *pm, const char *name);
static bool save_profile_to_disk(profile_manager_t *pm, const char *name);
static void profile_manager_init(profile_manager_t *pm);
static void profile_manager_cleanup(profile_manager_t *pm);
static void profile_sync_shm_to_active(profile_manager_t *pm, shared_data_t *shm);
static void profile_apply_to_shm(profile_manager_t *pm, shared_data_t *shm);
static void profile_handle_auto_save(profile_manager_t *pm);
static void profile_handle_inotify(profile_manager_t *pm, shared_data_t *shm);
static void profile_process_requests(profile_manager_t *pm, shared_data_t *shm);
static void profile_list(profile_manager_t *pm, char *output, size_t output_size);
static void profile_update_inotify(profile_manager_t *pm);
static void profile_update_shm_current_name(shared_data_t *shm, const char *name);
static void profile_sync_auto_save_to_shm(profile_manager_t *pm, shared_data_t *shm);

// ============================================================================
// I/O AND MANAGEMENT FUNCTIONS IMPLEMENTATION
// ============================================================================

static void profile_sync_auto_save_to_shm(profile_manager_t *pm, shared_data_t *shm) {
    if (!pm || !shm) return;
    safe_shm_lock(&shm->proc_mutex);
    atomic_store(&shm->auto_save_enabled, pm->auto_save_enabled ? 1 : 0);
    atomic_store(&shm->auto_save_delay_ms, pm->auto_save_delay_ms);
    pthread_mutex_unlock(&shm->proc_mutex);
    syslog(LOG_DEBUG, "PROFILE: Synced auto-save to SHM: enabled=%d, delay=%u",
           pm->auto_save_enabled, pm->auto_save_delay_ms);
}

static void profile_update_shm_current_name(shared_data_t *shm, const char *name) {
    if (!shm) return;
    safe_shm_lock(&shm->proc_mutex);
    strncpy(shm->current_profile_name, name, PROFILE_NAME_LEN - 1);
    shm->current_profile_name[PROFILE_NAME_LEN - 1] = '\0';
    pthread_mutex_unlock(&shm->proc_mutex);
    syslog(LOG_DEBUG, "PROFILE: Updated SHM active profile name to '%s'", name);
}

static bool load_profile_from_disk(profile_manager_t *pm, const char *name) {
    char *path = NULL;
    if (asprintf(&path, "%s/%s.json", pm->profiles_dir, name) == -1) {
        syslog(LOG_ERR, "PROFILE: Failed to allocate path for profile %s", name);
        return false;
    }

    FILE *f = fopen(path, "r");
    free(path);
    if (!f) return false;

    fseek(f, 0, SEEK_END);
    long size = ftell(f);
    fseek(f, 0, SEEK_SET);
    char *json_str = malloc(size + 1);
    if (!json_str) {
        fclose(f);
        return false;
    }
    fread(json_str, 1, size, f);
    json_str[size] = '\0';
    fclose(f);

    cJSON *root = cJSON_Parse(json_str);
    free(json_str);
    if (!root) return false;

    cJSON *version = cJSON_GetObjectItem(root, "version");
    cJSON *last_mod = cJSON_GetObjectItem(root, "last_modified");
    cJSON *slots = cJSON_GetObjectItem(root, "slots");
    if (!version || !last_mod || !slots || !cJSON_IsArray(slots)) {
        cJSON_Delete(root);
        return false;
    }

    profile_t *prof = &pm->active_profile;
    strcpy(prof->name, name);
    prof->version = version->valueint;  // version does not need aggressive validation
    prof->last_modified = last_mod->valueint;

    int array_size = cJSON_GetArraySize(slots);
    for (int i = 0; i < MAX_SLOTS && i < array_size; i++) {
        cJSON *slot = cJSON_GetArrayItem(slots, i);
        if (!slot) continue;
        slot_config_t *cfg = &prof->slots[i];

        // LEDs and colors (0-255)
        safe_json_get_uint8(slot, "led_r", &cfg->led_r, 0, 255, 0);
        safe_json_get_uint8(slot, "led_g", &cfg->led_g, 0, 255, 0);
        safe_json_get_uint8(slot, "led_b", &cfg->led_b, 0, 255, 255);
        safe_json_get_uint8(slot, "led_base_r", &cfg->led_base_r, 0, 255, 0);
        safe_json_get_uint8(slot, "led_base_g", &cfg->led_base_g, 0, 255, 0);
        safe_json_get_uint8(slot, "led_base_b", &cfg->led_base_b, 0, 255, 255);

        // Numeric settings
        safe_json_get_uint8(slot, "rumble_gain", &cfg->rumble_gain, 0, 100, 100);
        safe_json_get_uint8(slot, "deadzone", &cfg->deadzone, 0, 100, 10);
        safe_json_get_uint8(slot, "global_brightness", &cfg->global_led_brightness, 0, 100, 80);
        safe_json_get_uint8(slot, "player_leds", &cfg->player_leds, 0, 5, 0);

        // Booleans (0/1)
        safe_json_get_bool(slot, "debounce", &cfg->debounce_enabled, true);
        safe_json_get_bool(slot, "emulate", &cfg->emulate_active, true);
        safe_json_get_bool(slot, "is_uhid", &cfg->is_uhid, false);
        safe_json_get_bool(slot, "led_reapply", &cfg->led_reapply, true);
        safe_json_get_bool(slot, "rumble_active", &cfg->rumble_active, true);
        safe_json_get_bool(slot, "invert_ly", &cfg->invert_ly, false);
        safe_json_get_bool(slot, "invert_ry", &cfg->invert_ry, false);
        safe_json_get_bool(slot, "triggers_digital", &cfg->treat_triggers_as_digital, false);

        // Sensitivity presets (0..SENS_PRESET_COUNT-1)
        safe_json_get_uint8(slot, "sensitivity_left", &cfg->sensitivity_left_preset,
                            0, SENS_PRESET_COUNT - 1, SENS_PRESET_DEFAULT);
        safe_json_get_uint8(slot, "sensitivity_right", &cfg->sensitivity_right_preset,
                            0, SENS_PRESET_COUNT - 1, SENS_PRESET_DEFAULT);

        // LED effects
        safe_json_get_uint8(slot, "led_effect", &cfg->led_effect,
                            0, LEDFX_COUNT - 1, 0);
        safe_json_get_uint8(slot, "led_effect_speed", &cfg->led_effect_speed,
                            1, 10, 5);
        safe_json_get_uint8(slot, "led_effect_brightness", &cfg->led_effect_brightness,
                            0, 100, 80);

        // Load keymap (array of integers) with individual validation
        cJSON *keymap_arr = cJSON_GetObjectItem(slot, "keymap");
        if (keymap_arr && cJSON_IsArray(keymap_arr)) {
            int keymap_size = cJSON_GetArraySize(keymap_arr);
            for (int k = 0; k < PHY_BTN_COUNT; k++) {
                uint8_t default_map = (k + 1); // identity: logical = physical+1
                if (k < keymap_size) {
                    cJSON *item = cJSON_GetArrayItem(keymap_arr, k);
                    if (item && cJSON_IsNumber(item)) {
                        int val = item->valueint;
                        if (val >= 0 && val < LOGICAL_BTN_COUNT) {
                            cfg->keymap[k] = (uint8_t)val;
                        } else {
                            syslog(LOG_WARNING, "PROFILE: Keymap[%d]=%d invalid, using identity (%d)",
                                   k, val, default_map);
                            cfg->keymap[k] = default_map;
                        }
                    } else {
                        cfg->keymap[k] = default_map;
                    }
                } else {
                    cfg->keymap[k] = default_map;
                }
            }
        } else {
            // Profile without keymap: initialize with identity
            keys_get_default_map(TYPE_DS4, cfg->keymap);
        }
    }
    cJSON_Delete(root);
    return true;
}

static bool save_profile_to_disk(profile_manager_t *pm, const char *name) {
    char *path = NULL;
    if (asprintf(&path, "%s/%s.json", pm->profiles_dir, name) == -1) {
        syslog(LOG_ERR, "PROFILE: Failed to allocate path for profile %s", name);
        return false;
    }

    char *tmp_path = NULL;
    if (asprintf(&tmp_path, "%s.tmp", path) == -1) {
        free(path);
        syslog(LOG_ERR, "PROFILE: Failed to allocate temporary path for %s", name);
        return false;
    }

    cJSON *root = cJSON_CreateObject();
    if (!root) {
        free(path);
        free(tmp_path);
        return false;
    }
    cJSON_AddNumberToObject(root, "version", pm->active_profile.version);
    cJSON_AddNumberToObject(root, "last_modified", time(NULL));

    cJSON *slots = cJSON_AddArrayToObject(root, "slots");
    for (int i = 0; i < MAX_SLOTS; i++) {
        cJSON *slot = cJSON_CreateObject();
        slot_config_t *cfg = &pm->active_profile.slots[i];
        cJSON_AddNumberToObject(slot, "led_r", cfg->led_r);
        cJSON_AddNumberToObject(slot, "led_g", cfg->led_g);
        cJSON_AddNumberToObject(slot, "led_b", cfg->led_b);
        cJSON_AddNumberToObject(slot, "led_base_r", cfg->led_base_r);
        cJSON_AddNumberToObject(slot, "led_base_g", cfg->led_base_g);
        cJSON_AddNumberToObject(slot, "led_base_b", cfg->led_base_b);
        cJSON_AddNumberToObject(slot, "rumble_gain", cfg->rumble_gain);
        cJSON_AddNumberToObject(slot, "deadzone", cfg->deadzone);
        cJSON_AddNumberToObject(slot, "global_brightness", cfg->global_led_brightness);
        cJSON_AddNumberToObject(slot, "player_leds", cfg->player_leds);
        cJSON_AddNumberToObject(slot, "debounce", cfg->debounce_enabled);
        cJSON_AddNumberToObject(slot, "emulate", cfg->emulate_active);
        cJSON_AddNumberToObject(slot, "is_uhid", cfg->is_uhid);
        cJSON_AddNumberToObject(slot, "led_reapply", cfg->led_reapply);
        cJSON_AddNumberToObject(slot, "rumble_active", cfg->rumble_active);
        cJSON_AddNumberToObject(slot, "invert_ly", cfg->invert_ly);
        cJSON_AddNumberToObject(slot, "invert_ry", cfg->invert_ry);
        cJSON_AddNumberToObject(slot, "sensitivity_left", cfg->sensitivity_left_preset);
        cJSON_AddNumberToObject(slot, "sensitivity_right", cfg->sensitivity_right_preset);
        cJSON_AddNumberToObject(slot, "led_effect", cfg->led_effect);
        cJSON_AddNumberToObject(slot, "led_effect_speed", cfg->led_effect_speed);
        cJSON_AddNumberToObject(slot, "led_effect_brightness", cfg->led_effect_brightness);
        cJSON_AddNumberToObject(slot, "triggers_digital", cfg->treat_triggers_as_digital);

        // Save keymap as integer array
        cJSON *keymap_arr = cJSON_AddArrayToObject(slot, "keymap");
        for (int k = 0; k < PHY_BTN_COUNT; k++) {
            cJSON_AddItemToArray(keymap_arr, cJSON_CreateNumber(cfg->keymap[k]));
        }

        cJSON_AddItemToArray(slots, slot);
    }

    char *json_str = cJSON_Print(root);
    cJSON_Delete(root);
    if (!json_str) {
        free(path);
        free(tmp_path);
        return false;
    }

    FILE *f = fopen(tmp_path, "w");
    if (!f) {
        free(json_str);
        free(path);
        free(tmp_path);
        return false;
    }
    fprintf(f, "%s", json_str);
    fclose(f);
    free(json_str);

    int rename_result = rename(tmp_path, path);
    free(tmp_path);
    free(path);
    return (rename_result == 0);
}

static void profile_update_inotify(profile_manager_t *pm) {
    if (pm->inotify_fd < 0) return;
    if (pm->inotify_wd >= 0) {
        inotify_rm_watch(pm->inotify_fd, pm->inotify_wd);
        pm->inotify_wd = -1;
    }
    char *profile_path = NULL;
    if (asprintf(&profile_path, "%s/%s.json", pm->profiles_dir, pm->active_name) == -1) {
        syslog(LOG_WARNING, "PROFILE: Failed to allocate path to monitor %s", pm->active_name);
        return;
    }
    pm->inotify_wd = inotify_add_watch(pm->inotify_fd, profile_path, IN_MODIFY);
    if (pm->inotify_wd < 0) {
        syslog(LOG_WARNING, "PROFILE: Could not monitor %s", profile_path);
    } else {
        syslog(LOG_DEBUG, "PROFILE: Monitoring %s", profile_path);
    }
    free(profile_path);
}

static void profile_manager_init(profile_manager_t *pm) {
    memset(pm, 0, sizeof(*pm));

    // Default configuration directory: /etc/dstx
    strcpy(pm->base_dir, "/etc/dstx");
    mkdir(pm->base_dir, 0755);
    snprintf(pm->profiles_dir, sizeof(pm->profiles_dir), "%s/profiles", pm->base_dir);
    mkdir(pm->profiles_dir, 0755);

    pm->auto_save_enabled = true;
    pm->auto_save_delay_ms = 2000;
    pm->profile_dirty = false;
    pm->inotify_fd = inotify_init1(IN_NONBLOCK | IN_CLOEXEC);
    if (pm->inotify_fd < 0) {
        syslog(LOG_WARNING, "PROFILE: Failed to initialize inotify");
    }

    // Load "default" profile or create a new one
    strcpy(pm->active_name, "Default");
    if (!load_profile_from_disk(pm, pm->active_name)) {
        // Create default profile
        profile_t *prof = &pm->active_profile;
        strcpy(prof->name, pm->active_name);
        prof->version = 1;
        prof->last_modified = time(NULL);
        for (int i = 0; i < MAX_SLOTS; i++) {
            slot_config_t *cfg = &prof->slots[i];
            cfg->led_r = cfg->led_base_r = 0;
            cfg->led_g = cfg->led_base_g = 0;
            cfg->led_b = cfg->led_base_b = 255;
            cfg->rumble_gain = 100;
            cfg->deadzone = 10;
            cfg->global_led_brightness = 80;
            cfg->player_leds = 0;
            cfg->debounce_enabled = true;
            cfg->emulate_active = true;
            cfg->is_uhid = false;
            cfg->led_reapply = true;
            cfg->rumble_active = true;
            cfg->invert_ly = cfg->invert_ry = false;
            cfg->sensitivity_left_preset = SENS_PRESET_DEFAULT;
            cfg->sensitivity_right_preset = SENS_PRESET_DEFAULT;
            cfg->led_effect = 0;
            cfg->led_effect_speed = 5;
            cfg->led_effect_brightness = 80;
            cfg->treat_triggers_as_digital = false;
            // Initialize keymap with identity mapping
            keys_get_default_map(TYPE_DS4, cfg->keymap);
        }
        save_profile_to_disk(pm, pm->active_name);
    }

    profile_update_inotify(pm);
}

static void profile_manager_cleanup(profile_manager_t *pm) {
    if (pm->profile_dirty && pm->auto_save_enabled) {
        save_profile_to_disk(pm, pm->active_name);
    }
    if (pm->inotify_fd >= 0) {
        if (pm->inotify_wd >= 0) inotify_rm_watch(pm->inotify_fd, pm->inotify_wd);
        close(pm->inotify_fd);
        pm->inotify_fd = -1;
    }
}

static void profile_sync_shm_to_active(profile_manager_t *pm, shared_data_t *shm) {
    bool changed = false;

    safe_shm_lock(&shm->proc_mutex);
    for (int i = 0; i < MAX_SLOTS; i++) {
        slot_config_t *cfg = &pm->active_profile.slots[i];
        controller_t *ctrl = &shm->slots[i];
        slot_config_t new_cfg;
        controller_to_slot_config(&new_cfg, ctrl);

        // Field-by-field comparison
        if (cfg->led_r != new_cfg.led_r ||
            cfg->led_g != new_cfg.led_g ||
            cfg->led_b != new_cfg.led_b ||
            cfg->led_base_r != new_cfg.led_base_r ||
            cfg->led_base_g != new_cfg.led_base_g ||
            cfg->led_base_b != new_cfg.led_base_b ||
            cfg->rumble_gain != new_cfg.rumble_gain ||
            cfg->deadzone != new_cfg.deadzone ||
            cfg->global_led_brightness != new_cfg.global_led_brightness ||
            cfg->player_leds != new_cfg.player_leds ||
            cfg->debounce_enabled != new_cfg.debounce_enabled ||
            cfg->emulate_active != new_cfg.emulate_active ||
            cfg->is_uhid != new_cfg.is_uhid ||
            cfg->led_reapply != new_cfg.led_reapply ||
            cfg->rumble_active != new_cfg.rumble_active ||
            cfg->invert_ly != new_cfg.invert_ly ||
            cfg->invert_ry != new_cfg.invert_ry ||
            cfg->sensitivity_left_preset != new_cfg.sensitivity_left_preset ||
            cfg->sensitivity_right_preset != new_cfg.sensitivity_right_preset ||
            cfg->led_effect != new_cfg.led_effect ||
            cfg->led_effect_speed != new_cfg.led_effect_speed ||
            cfg->led_effect_brightness != new_cfg.led_effect_brightness ||
            cfg->treat_triggers_as_digital != new_cfg.treat_triggers_as_digital ||
            memcmp(cfg->keymap, new_cfg.keymap, sizeof(cfg->keymap)) != 0) {

            *cfg = new_cfg;
            changed = true;
        }
    }
    pthread_mutex_unlock(&shm->proc_mutex);

    if (changed) {
        pm->active_profile.last_modified = time(NULL);
        pm->profile_dirty = true;
        gettimeofday(&pm->last_change, NULL);
    }
}

static void profile_apply_to_shm(profile_manager_t *pm, shared_data_t *shm) {
    safe_shm_lock(&shm->proc_mutex);
    for (int i = 0; i < MAX_SLOTS; i++) {
        slot_config_t *cfg = &pm->active_profile.slots[i];
        controller_t *ctrl = &shm->slots[i];
        slot_config_to_controller(cfg, ctrl);
        atomic_store(&ctrl->led_dirty, true);
    }
    pthread_mutex_unlock(&shm->proc_mutex);
}

static void profile_handle_auto_save(profile_manager_t *pm) {
    if (!pm->auto_save_enabled || !pm->profile_dirty) return;
    struct timeval now;
    gettimeofday(&now, NULL);
    long elapsed_ms = (now.tv_sec - pm->last_change.tv_sec) * 1000 +
                      (now.tv_usec - pm->last_change.tv_usec) / 1000;
    if (elapsed_ms >= (long)pm->auto_save_delay_ms) {
        if (save_profile_to_disk(pm, pm->active_name)) {
            pm->profile_dirty = false;
            syslog(LOG_DEBUG, "PROFILE: Profile '%s' saved automatically", pm->active_name);
        } else {
            syslog(LOG_ERR, "PROFILE: Failed to save profile '%s'", pm->active_name);
        }
    }
}

static void profile_handle_inotify(profile_manager_t *pm, shared_data_t *shm) {
    if (pm->inotify_fd < 0) return;
    char buffer[4096] __attribute__ ((aligned(__alignof__(struct inotify_event))));
    ssize_t len = read(pm->inotify_fd, buffer, sizeof(buffer));
    if (len <= 0) return;

    for (char *ptr = buffer; ptr < buffer + len; ) {
        struct inotify_event *event = (struct inotify_event *)ptr;
        if (event->mask & IN_MODIFY) {
            if (pm->profile_dirty) {
                syslog(LOG_WARNING, "PROFILE: Profile file modified externally, but there are unsaved local changes. Ignoring reload.");
            } else {
                if (load_profile_from_disk(pm, pm->active_name)) {
                    profile_apply_to_shm(pm, shm);
                    profile_sync_auto_save_to_shm(pm, shm);
                    syslog(LOG_INFO, "PROFILE: Profile '%s' reloaded (external modification)", pm->active_name);
                    profile_update_shm_current_name(shm, pm->active_name);
                } else {
                    syslog(LOG_ERR, "PROFILE: Failed to reload profile '%s'", pm->active_name);
                }
            }
        }
        ptr += sizeof(struct inotify_event) + event->len;
    }
}

static void profile_process_requests(profile_manager_t *pm, shared_data_t *shm) {
    int req = atomic_load(&shm->profile_request);
    if (req == 0) return;

    char name[PROFILE_NAME_LEN];
    safe_shm_lock(&shm->proc_mutex);
    strncpy(name, shm->profile_name, sizeof(name)-1);
    name[sizeof(name)-1] = '\0';
    pthread_mutex_unlock(&shm->proc_mutex);

    int result = 0;
    char msg[512];
    msg[0] = '\0';

    switch (req) {
        case 1: { // load
            if (load_profile_from_disk(pm, name)) {
                strcpy(pm->active_name, name);
                profile_update_inotify(pm);
                profile_apply_to_shm(pm, shm);
                profile_sync_auto_save_to_shm(pm, shm);
                snprintf(msg, sizeof(msg), "Profile '%s' loaded", name);
                result = 1;
                profile_update_shm_current_name(shm, pm->active_name);
            } else {
                result = -1;
                snprintf(msg, sizeof(msg), "Failed to load profile '%s'", name);
            }
            break;
        }
        case 2: { // save
            if (save_profile_to_disk(pm, name)) {
                if (strcmp(name, pm->active_name) == 0) {
                    pm->profile_dirty = false;
                }
                snprintf(msg, sizeof(msg), "Profile '%s' saved", name);
                result = 1;
            } else {
                result = -1;
                snprintf(msg, sizeof(msg), "Failed to save profile '%s'", name);
            }
            break;
        }
        case 3: { // delete
            char *path = NULL;
            if (asprintf(&path, "%s/%s.json", pm->profiles_dir, name) == -1) {
                result = -1;
                snprintf(msg, sizeof(msg), "Failed to allocate path to delete '%s'", name);
                break;
            }
            if (unlink(path) == 0) {
                snprintf(msg, sizeof(msg), "Profile '%s' deleted", name);
                if (strcmp(name, pm->active_name) == 0) {
                    load_profile_from_disk(pm, "Default");
                    strcpy(pm->active_name, "Default");
                    profile_update_inotify(pm);
                    profile_apply_to_shm(pm, shm);
                    profile_sync_auto_save_to_shm(pm, shm);
                    profile_update_shm_current_name(shm, pm->active_name);
                }
                result = 1;
            } else {
                result = -1;
                snprintf(msg, sizeof(msg), "Failed to delete profile '%s'", name);
            }
            free(path);
            break;
        }
        case 4: { // list
            char list_buf[4096] = {0};
            profile_list(pm, list_buf, sizeof(list_buf));
            safe_shm_lock(&shm->proc_mutex);
            strncpy(shm->profile_response_msg, list_buf, sizeof(shm->profile_response_msg)-1);
            shm->profile_response_msg[sizeof(shm->profile_response_msg)-1] = '\0';
            pthread_mutex_unlock(&shm->proc_mutex);
            result = 1;
            break;
        }
        case 5: { // set auto-save
            int enabled = atomic_load(&shm->auto_save_enabled);
            int delay = atomic_load(&shm->auto_save_delay_ms);
            if (enabled != -1) pm->auto_save_enabled = (enabled != 0);
            if (delay > 0) pm->auto_save_delay_ms = delay;
            snprintf(msg, sizeof(msg), "Auto-save %s, delay=%dms",
                     pm->auto_save_enabled ? "enabled" : "disabled", pm->auto_save_delay_ms);
            result = 1;
            // After changing values in profile_manager, sync with SHM
            profile_sync_auto_save_to_shm(pm, shm);
            break;
        }
        default:
            result = -1;
            snprintf(msg, sizeof(msg), "Unknown request: %d", req);
            break;
    }

    safe_shm_lock(&shm->proc_mutex);
    atomic_store(&shm->profile_response, result);
    if (req != 4 && msg[0] != '\0') {
        strncpy(shm->profile_response_msg, msg, sizeof(shm->profile_response_msg)-1);
        shm->profile_response_msg[sizeof(shm->profile_response_msg)-1] = '\0';
    }
    atomic_store(&shm->profile_request, 0);
    pthread_mutex_unlock(&shm->proc_mutex);
}

static void profile_list(profile_manager_t *pm, char *output, size_t output_size) {
    output[0] = '\0';
    DIR *d = opendir(pm->profiles_dir);
    if (!d) return;
    struct dirent *ent;
    while ((ent = readdir(d)) != NULL) {
        if (ent->d_type == DT_REG) {
            char *dot = strrchr(ent->d_name, '.');
            if (dot && strcmp(dot, ".json") == 0) {
                *dot = '\0';
                if (strlen(output) + strlen(ent->d_name) + 2 < output_size) {
                    strcat(output, ent->d_name);
                    strcat(output, "\n");
                }
            }
        }
    }
    closedir(d);
}

// ============================================================================
// THREAD WORKER
// ============================================================================

static void* settings_worker(void *arg) {
    settings_ctx_t *ctx = arg;
    struct pollfd fds[1];
    fds[0].fd = ctx->pipefd[0];
    fds[0].events = POLLIN;

    profile_apply_to_shm(&ctx->pm, ctx->shm);
    profile_sync_auto_save_to_shm(&ctx->pm, ctx->shm);
    profile_update_shm_current_name(ctx->shm, ctx->pm.active_name);

    while (ctx->running) {
        int ret = poll(fds, 1, 200);

        profile_sync_shm_to_active(&ctx->pm, ctx->shm);
        profile_process_requests(&ctx->pm, ctx->shm);
        profile_handle_auto_save(&ctx->pm);
        profile_handle_inotify(&ctx->pm, ctx->shm);

        if (ret > 0) {
            char dummy[8];
            read(ctx->pipefd[0], dummy, sizeof(dummy));
        }
    }

    return NULL;
}

// ============================================================================
// PUBLIC FUNCTIONS
// ============================================================================

void settings_init(shared_data_t *shm) {
    if (!shm) {
        syslog(LOG_ERR, "SETTINGS: Invalid SHM");
        return;
    }

    memset(&g_ctx, 0, sizeof(g_ctx));
    g_ctx.shm = shm;
    g_ctx.running = true;

    if (pipe(g_ctx.pipefd) == -1) {
        syslog(LOG_ERR, "SETTINGS: pipe() failed: %s", strerror(errno));
        return;
    }

    profile_manager_init(&g_ctx.pm);

    if (pthread_create(&g_ctx.thread, NULL, settings_worker, &g_ctx) != 0) {
        syslog(LOG_ERR, "SETTINGS: pthread_create failed");
        close(g_ctx.pipefd[0]);
        close(g_ctx.pipefd[1]);
        memset(&g_ctx, 0, sizeof(g_ctx));
    }
}

void settings_shutdown(void) {
    if (!g_ctx.running) return;

    g_ctx.running = false;
    write(g_ctx.pipefd[1], "x", 1);
    pthread_join(g_ctx.thread, NULL);

    profile_manager_cleanup(&g_ctx.pm);
    close(g_ctx.pipefd[0]);
    close(g_ctx.pipefd[1]);
    memset(&g_ctx, 0, sizeof(g_ctx));
}
