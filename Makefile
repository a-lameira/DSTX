# ==============================================================================
# DSTX Makefile – Static (Alpine/Musl) and Dynamic (Development) Builds
# ==============================================================================

CC = gcc

# ------------------------------------------------------------------------------
# Static compilation settings (for distribution)
# ------------------------------------------------------------------------------
CFLAGS_STATIC = -static -Os -D_GNU_SOURCE -D_LARGEFILE64_SOURCE=1 -U_FORTIFY_SOURCE -Wall -Wextra -pthread

# Directory where the static dbus library has been installed (must exist)
DBUS_STATIC_DIR = /usr/local/dbus-static
DBUS_CFLAGS_STATIC = -I$(DBUS_STATIC_DIR)/include/dbus-1.0 -I$(DBUS_STATIC_DIR)/lib/dbus-1.0/include
DBUS_LIBS_STATIC = -L$(DBUS_STATIC_DIR)/lib -ldbus-1

# Static libraries for core and bridge
LIBS_STATIC_CORE = -lz -lrt -lpthread -lm -lcjson
LIBS_STATIC_BRIDGE = $(DBUS_LIBS_STATIC) -lz -lrt -lpthread -lm -lcjson

# ------------------------------------------------------------------------------
# Dynamic compilation settings (development)
# ------------------------------------------------------------------------------
CFLAGS_DYNAMIC = -O2 -g -D_GNU_SOURCE -D_LARGEFILE64_SOURCE=1 -U_FORTIFY_SOURCE -Wall -Wextra -pthread

# Debug compilation settings (with detailed logs)
CFLAGS_DEBUG = -O0 -g -D_GNU_SOURCE -D_LARGEFILE64_SOURCE=1 -U_FORTIFY_SOURCE -Wall -Wextra -pthread \
               -DDSTX_DEBUG -DDSTX_DEBUG_VERBOSE

# Dynamic libraries for core
LIBS_DYNAMIC_CORE = -lz -lrt -lpthread -lm -lcjson

# Dynamic D-Bus: use pkg-config (if available)
PKG_CONFIG = pkg-config
DBUS_CFLAGS_DYNAMIC := $(shell $(PKG_CONFIG) --cflags dbus-1 2>/dev/null)
DBUS_LIBS_DYNAMIC := $(shell $(PKG_CONFIG) --libs dbus-1 2>/dev/null)

# If pkg-config fails, try common paths
ifeq ($(DBUS_CFLAGS_DYNAMIC),)
    DBUS_CFLAGS_DYNAMIC = -I/usr/include/dbus-1.0 -I/usr/lib/x86_64-linux-gnu/dbus-1.0/include
    DBUS_LIBS_DYNAMIC = -ldbus-1
    $(warning pkg-config not found, using default D-Bus paths)
endif

# ------------------------------------------------------------------------------
# Check if D-Bus is available (for warnings)
# ------------------------------------------------------------------------------
DBUS_TEST_CMD = $(CC) $(CFLAGS_DYNAMIC) $(DBUS_CFLAGS_DYNAMIC) -c -o /dev/null -x c /dev/null -include dbus/dbus.h 2>/dev/null
DBUS_AVAILABLE_DYNAMIC := $(shell $(DBUS_TEST_CMD) && echo 1 || echo 0)

# ------------------------------------------------------------------------------
# Directories and sources
# ------------------------------------------------------------------------------
SRC_DIR = src
OBJ_DIR_STATIC = obj_static
OBJ_DIR_DYNAMIC = obj_dynamic
OBJ_DIR_DEBUG = obj_debug

TARGET = dstx
BRIDGE_TARGET = dstx-dbus

# Core sources (including keys.c)
SRCS_CORE = $(SRC_DIR)/main.c \
            $(SRC_DIR)/daemon.c \
            $(SRC_DIR)/ui.c \
            $(SRC_DIR)/display.c \
            $(SRC_DIR)/commands.c \
            $(SRC_DIR)/utils.c \
            $(SRC_DIR)/settings.c \
            $(SRC_DIR)/drivers.c \
            $(SRC_DIR)/output.c \
            $(SRC_DIR)/led.c \
            $(SRC_DIR)/nsw.c \
            $(SRC_DIR)/uhid.c \
            $(SRC_DIR)/axes.c \
            $(SRC_DIR)/keys.c

OBJS_CORE_STATIC = $(SRCS_CORE:$(SRC_DIR)/%.c=$(OBJ_DIR_STATIC)/%.o)
OBJS_CORE_DYNAMIC = $(SRCS_CORE:$(SRC_DIR)/%.c=$(OBJ_DIR_DYNAMIC)/%.o)
OBJS_CORE_DEBUG = $(SRCS_CORE:$(SRC_DIR)/%.c=$(OBJ_DIR_DEBUG)/%.o)

# D-Bus bridge sources (refactored)
BRIDGE_SRCS = $(SRC_DIR)/dbus-main.c \
              $(SRC_DIR)/dbus-monitor.c \
              $(SRC_DIR)/dbus-handlers.c \
              $(SRC_DIR)/dbus-utils.c \
              $(SRC_DIR)/dbus-signals.c \
              $(SRC_DIR)/dbus-systemd.c \
              $(SRC_DIR)/keys.c

OBJS_BRIDGE_STATIC = $(BRIDGE_SRCS:$(SRC_DIR)/%.c=$(OBJ_DIR_STATIC)/%.o)
OBJS_BRIDGE_DYNAMIC = $(BRIDGE_SRCS:$(SRC_DIR)/%.c=$(OBJ_DIR_DYNAMIC)/%.o)
OBJS_BRIDGE_DEBUG = $(BRIDGE_SRCS:$(SRC_DIR)/%.c=$(OBJ_DIR_DEBUG)/%.o)

# ------------------------------------------------------------------------------
# Generic rules
# ------------------------------------------------------------------------------
$(OBJ_DIR_STATIC):
	mkdir -p $(OBJ_DIR_STATIC)

$(OBJ_DIR_DYNAMIC):
	mkdir -p $(OBJ_DIR_DYNAMIC)

$(OBJ_DIR_DEBUG):
	mkdir -p $(OBJ_DIR_DEBUG)

# ------------------------------------------------------------------------------
# Static compilation (core + bridge)
# ------------------------------------------------------------------------------
$(OBJ_DIR_STATIC)/%.o: $(SRC_DIR)/%.c | $(OBJ_DIR_STATIC)
	$(CC) $(CFLAGS_STATIC) $(DBUS_CFLAGS_STATIC) -c $< -o $@
	@echo "🔨 Static: $<"

$(TARGET): $(OBJS_CORE_STATIC) | $(OBJ_DIR_STATIC)
	$(CC) $(CFLAGS_STATIC) -o $@ $^ $(LIBS_STATIC_CORE)
	@echo "✅ Static core compiled: $@"

$(BRIDGE_TARGET): $(OBJS_BRIDGE_STATIC) | $(OBJ_DIR_STATIC)
	$(CC) $(CFLAGS_STATIC) -o $@ $^ $(LIBS_STATIC_BRIDGE)
	@echo "✅ Static bridge compiled: $@"

static-all: clean-static $(TARGET) $(BRIDGE_TARGET)
	@echo "=========================================="
	@echo "✅ Static compilation of both completed"
	@echo "   Core:  $(TARGET)"
	@echo "   Bridge: $(BRIDGE_TARGET)"
	@echo "=========================================="
	@ldd $(TARGET) 2>&1 | head -1
	@ldd $(BRIDGE_TARGET) 2>&1 | head -1

# ------------------------------------------------------------------------------
# Dynamic compilation (development)
# ------------------------------------------------------------------------------
$(OBJ_DIR_DYNAMIC)/%.o: $(SRC_DIR)/%.c | $(OBJ_DIR_DYNAMIC)
	$(CC) $(CFLAGS_DYNAMIC) $(DBUS_CFLAGS_DYNAMIC) -c $< -o $@
	@echo "🔨 Dynamic: $<"

# Dynamic core
dynamic-core: $(OBJS_CORE_DYNAMIC) | $(OBJ_DIR_DYNAMIC)
	$(CC) $(CFLAGS_DYNAMIC) -o $(TARGET) $^ $(LIBS_DYNAMIC_CORE)
	@echo "✅ Dynamic core compiled: $(TARGET)"
	@ldd $(TARGET) 2>&1 | head -1

# Dynamic bridge (only compiles if D-Bus header exists)
ifeq ($(DBUS_AVAILABLE_DYNAMIC),1)
dynamic-bridge: $(OBJS_BRIDGE_DYNAMIC) | $(OBJ_DIR_DYNAMIC)
	$(CC) $(CFLAGS_DYNAMIC) -o $(BRIDGE_TARGET) $^ $(DBUS_LIBS_DYNAMIC) $(LIBS_DYNAMIC_CORE)
	@echo "✅ Dynamic bridge compiled: $(BRIDGE_TARGET)"
	@ldd $(BRIDGE_TARGET) 2>&1 | head -1
else
dynamic-bridge:
	@echo "⚠️  D-Bus bridge not compiled (dbus/dbus.h header not found)"
endif

# Dynamic compilation of everything (core + bridge if possible)
dynamic-all: clean-dynamic dynamic-core dynamic-bridge
	@echo "=========================================="
	@echo "✅ Dynamic compilation completed"
	@echo "   Core:  $(TARGET)"
ifeq ($(DBUS_AVAILABLE_DYNAMIC),1)
	@echo "   Bridge: $(BRIDGE_TARGET)"
else
	@echo "   Bridge: not compiled (missing dependency)"
endif
	@echo "=========================================="

# ------------------------------------------------------------------------------
# Debug compilation (with detailed logs - DSTX_DEBUG and DSTX_DEBUG_VERBOSE)
# ------------------------------------------------------------------------------
$(OBJ_DIR_DEBUG)/%.o: $(SRC_DIR)/%.c | $(OBJ_DIR_DEBUG)
	$(CC) $(CFLAGS_DEBUG) $(DBUS_CFLAGS_DYNAMIC) -c $< -o $@
	@echo "🐛 Debug: $<"

debug-core: $(OBJS_CORE_DEBUG) | $(OBJ_DIR_DEBUG)
	$(CC) $(CFLAGS_DEBUG) -o $(TARGET) $^ $(LIBS_DYNAMIC_CORE)
	@echo "✅ Core compiled in DEBUG mode: $(TARGET)"
	@echo "   (Detailed logs enabled via DSTX_DEBUG and DSTX_DEBUG_VERBOSE)"

ifeq ($(DBUS_AVAILABLE_DYNAMIC),1)
debug-bridge: $(OBJS_BRIDGE_DEBUG) | $(OBJ_DIR_DEBUG)
	$(CC) $(CFLAGS_DEBUG) -o $(BRIDGE_TARGET) $^ $(DBUS_LIBS_DYNAMIC) $(LIBS_DYNAMIC_CORE)
	@echo "✅ Bridge compiled in DEBUG mode: $(BRIDGE_TARGET)"
else
debug-bridge:
	@echo "⚠️  D-Bus bridge not compiled (dbus/dbus.h header not found)"
endif

debug-all: clean-debug debug-core debug-bridge
	@echo "=========================================="
	@echo "✅ DEBUG compilation completed"
	@echo "   Core:  $(TARGET) (with DSTX_DEBUG)"
ifeq ($(DBUS_AVAILABLE_DYNAMIC),1)
	@echo "   Bridge: $(BRIDGE_TARGET)"
else
	@echo "   Bridge: not compiled"
endif
	@echo "=========================================="

# ------------------------------------------------------------------------------
# Cleanup
# ------------------------------------------------------------------------------
clean-static:
	rm -rf $(OBJ_DIR_STATIC) $(TARGET) $(BRIDGE_TARGET)
	@echo "🧹 Static cleanup completed"

clean-dynamic:
	rm -rf $(OBJ_DIR_DYNAMIC) $(TARGET) $(BRIDGE_TARGET)
	@echo "🧹 Dynamic cleanup completed"

clean-debug:
	rm -rf $(OBJ_DIR_DEBUG) $(TARGET) $(BRIDGE_TARGET)
	@echo "🧹 DEBUG cleanup completed"

clean-all:
	rm -rf $(OBJ_DIR_STATIC) $(OBJ_DIR_DYNAMIC) $(OBJ_DIR_DEBUG) $(TARGET) $(BRIDGE_TARGET)
	@echo "🧹 Full cleanup completed"

# ------------------------------------------------------------------------------
# Installation and uninstallation (calls infrastructure script)
# ------------------------------------------------------------------------------
install:
	@if [ -f $(SRC_DIR)/../dstx-daemon.sh ]; then \
		sudo $(SRC_DIR)/../dstx-daemon.sh; \
	else \
		echo "Error: dstx-daemon.sh script not found"; \
		exit 1; \
	fi

uninstall:
	@if [ -f $(SRC_DIR)/../dstx-daemon.sh ]; then \
		echo "Running uninstallation via script..."; \
		sudo $(SRC_DIR)/../dstx-daemon.sh; \
	else \
		echo "Error: dstx-daemon.sh script not found"; \
		exit 1; \
	fi

# ------------------------------------------------------------------------------
# Information
# ------------------------------------------------------------------------------
info:
	@echo "=== DSTX Makefile (Static / Dynamic / Debug) ==="
	@echo "CC:                   $(CC)"
	@echo "CFLAGS_STATIC:        $(CFLAGS_STATIC)"
	@echo "CFLAGS_DYNAMIC:       $(CFLAGS_DYNAMIC)"
	@echo "CFLAGS_DEBUG:         $(CFLAGS_DEBUG)"
	@echo "DBUS_STATIC_DIR:      $(DBUS_STATIC_DIR)"
	@echo "DBUS_CFLAGS_STATIC:   $(DBUS_CFLAGS_STATIC)"
	@echo "DBUS_CFLAGS_DYNAMIC:  $(DBUS_CFLAGS_DYNAMIC)"
	@echo "DBUS_LIBS_STATIC:     $(DBUS_LIBS_STATIC)"
	@echo "DBUS_LIBS_DYNAMIC:    $(DBUS_LIBS_DYNAMIC)"
	@echo "DBUS_AVAILABLE_DYNAMIC: $(DBUS_AVAILABLE_DYNAMIC)"
	@echo "LIBS_STATIC_CORE:     $(LIBS_STATIC_CORE)"
	@echo "LIBS_DYNAMIC_CORE:    $(LIBS_DYNAMIC_CORE)"
	@echo ""
	@echo "Targets:"
	@echo "  static-all    – compile core and bridge statically"
	@echo "  dynamic-all   – compile core and (if possible) bridge dynamically"
	@echo "  dynamic-core  – compile only core dynamically"
	@echo "  dynamic-bridge – compile only bridge dynamically (if dependencies ok)"
	@echo "  debug-all     – compile core and bridge in DEBUG mode (detailed logs)"
	@echo "  debug-core    – compile only core in DEBUG mode"
	@echo "  debug-bridge  – compile only bridge in DEBUG mode"
	@echo "  install       – install the system (calls dstx-daemon.sh)"
	@echo "  uninstall     – uninstall (calls dstx-daemon.sh)"
	@echo "  clean-static  – clean static compilation files"
	@echo "  clean-dynamic – clean dynamic compilation files"
	@echo "  clean-debug   – clean DEBUG compilation files"
	@echo "  clean-all     – clean everything"
	@echo "  info          – show this message"

.PHONY: static-all dynamic-all dynamic-core dynamic-bridge debug-all debug-core debug-bridge \
        clean-static clean-dynamic clean-debug clean-all install uninstall info
