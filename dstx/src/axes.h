/*
 * axes.h - Analog stick processing for DSTX
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

#ifndef AXES_H
#define AXES_H

#include "dstx.h"

void init_axis_system(void);
void apply_sensitivity_preset_left(controller_t *slot, sensitivity_preset_t preset);
void apply_sensitivity_preset_right(controller_t *slot, sensitivity_preset_t preset);
const char* get_sensitivity_preset_name(sensitivity_preset_t preset);
void apply_sensitivity_left(controller_t *slot, int16_t *x, int16_t *y);
void apply_sensitivity_right(controller_t *slot, int16_t *x, int16_t *y);
void apply_deadzone(int16_t *x, int16_t *y, uint8_t deadzone_pct);

#endif
