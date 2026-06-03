#!/bin/bash

# ==============================================================================
# DSTX INFRASTRUCTURE MANAGEMENT SCRIPT (INSTALLER/UNINSTALLER)
# ==============================================================================
SERVICE_NAME="dstx-daemon"
BRIDGE_SERVICE_NAME="dstx-dbus"
UDEV_PATH="/etc/udev/rules.d/99-dstx.rules"
SYSTEMD_PATH="/etc/systemd/system/dstx-daemon.service"
BRIDGE_SYSTEMD_PATH="/etc/systemd/system/dstx-dbus.service"
POLKIT_PATH="/etc/polkit-1/rules.d/10-dstx.rules"
DBUS_POLICY_PATH="/etc/dbus-1/system.d/org.dstx.Bridge.conf"
SUDOERS_PATH="/etc/sudoers.d/dstx"
SHM_FILE="/dev/shm/dstx_shared_mem"
APP_GROUP="dstx"

# Get absolute path of the directory where this script is located
SCRIPT_DIR=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" &> /dev/null && pwd)
BINARY_SRC="$SCRIPT_DIR/dstx"
BRIDGE_BINARY_SRC="$SCRIPT_DIR/dstx-dbus"

# Destination paths (after installation)
BINARY_DST="/usr/local/bin/dstx"
BRIDGE_BINARY_DST="/usr/local/bin/dstx-dbus"

# Colors for feedback
GREEN='\033[0;32m'
BLUE='\033[0;34m'
YELLOW='\033[1;33m'
RED='\033[0;33m'
NC='\033[0m'  # No Color

# ------------------------------------------------------------------------------
# Root check
# ------------------------------------------------------------------------------
if [ "$EUID" -ne 0 ]; then 
    echo -e "${RED}ERROR: This script requires root privileges. Use: sudo $0${NC}"
    exit 1
fi

# ------------------------------------------------------------------------------
# INSTALLATION FUNCTION
# ------------------------------------------------------------------------------
install_dstx() {
    echo -e "${BLUE}--- Starting Environment Setup ---${NC}"

    # Daemon binary check
    if [ ! -f "$BINARY_SRC" ]; then
        echo -e "${RED}ERROR: Binary 'dstx' not found at: $BINARY_SRC${NC}"
        echo -e "${YELLOW}Make sure the 'dstx' file is in the same folder as this script.${NC}"
        return 1
    fi

    # D-Bus bridge binary check (optional)
    HAS_BRIDGE=false
    if [ -f "$BRIDGE_BINARY_SRC" ]; then
        HAS_BRIDGE=true
    else
        echo -e "${YELLOW}WARNING: D-Bus bridge binary 'dstx-dbus' not found. The bridge will not be installed.${NC}"
    fi

    # Copy binaries to /usr/local/bin
    echo -e "${GREEN}[1/9] Installing binaries to /usr/local/bin...${NC}"
    cp "$BINARY_SRC" "$BINARY_DST"
    chmod 755 "$BINARY_DST"
    if [ "$HAS_BRIDGE" = true ]; then
        cp "$BRIDGE_BINARY_SRC" "$BRIDGE_BINARY_DST"
        chmod 755 "$BRIDGE_BINARY_DST"
    fi

    # Create dedicated group
    echo -e "${GREEN}[2/9] Creating system group '$APP_GROUP'...${NC}"
    groupadd -f "$APP_GROUP"

    # UDEV rules (expanded for all known IDs)
    echo -e "${GREEN}[3/9] Creating udev rules...${NC}"
    cat <<EOF > "$UDEV_PATH"
# DualShock 4 (USB and Bluetooth)
KERNEL=="hidraw*", ATTRS{idVendor}=="054c", ATTRS{idProduct}=="05c4", MODE="0660", GROUP="$APP_GROUP"
KERNEL=="hidraw*", ATTRS{idVendor}=="054c", ATTRS{idProduct}=="09cc", MODE="0660", GROUP="$APP_GROUP"
KERNEL=="hidraw*", ATTRS{idVendor}=="054c", ATTRS{idProduct}=="0ba0", MODE="0660", GROUP="$APP_GROUP"

# DualSense (USB and Bluetooth)
KERNEL=="hidraw*", ATTRS{idVendor}=="054c", ATTRS{idProduct}=="0ce6", MODE="0660", GROUP="$APP_GROUP"
KERNEL=="hidraw*", ATTRS{idVendor}=="054c", ATTRS{idProduct}=="0df2", MODE="0660", GROUP="$APP_GROUP"

# Nintendo Switch Pro Controller (USB and Bluetooth)
KERNEL=="hidraw*", ATTRS{idVendor}=="057e", ATTRS{idProduct}=="2009", MODE="0660", GROUP="$APP_GROUP"
KERNEL=="hidraw*", ATTRS{idVendor}=="057e", ATTRS{idProduct}=="2017", MODE="0660", GROUP="$APP_GROUP"

# uinput (for emulation)
KERNEL=="uinput", MODE="0660", GROUP="$APP_GROUP", OPTIONS+="static_node=uinput"
EOF
    udevadm control --reload-rules && udevadm trigger

    # Systemd service (daemon)
    echo -e "${GREEN}[4/9] Configuring Systemd service for the daemon...${NC}"
    cat <<EOF > "$SYSTEMD_PATH"
[Unit]
Description=DSTX Daemon Service
After=network.target

[Service]
LimitMEMLOCK=infinity
Type=simple
ExecStartPre=/usr/bin/rm -f $SHM_FILE
ExecStart=$BINARY_DST --daemon
Restart=on-failure
RestartSec=1s
User=root
Group=$APP_GROUP
Nice=-20
CPUSchedulingPolicy=fifo
CPUSchedulingPriority=99
ExecStartPost=/usr/bin/sleep 0.1

[Install]
WantedBy=multi-user.target
EOF

    # Systemd service (D-Bus bridge) - if binary exists
    if [ "$HAS_BRIDGE" = true ]; then
        echo -e "${GREEN}[5/9] Configuring Systemd service for the D-Bus bridge...${NC}"
        cat <<EOF > "$BRIDGE_SYSTEMD_PATH"
[Unit]
Description=DSTX D-Bus Bridge
After=network.target

[Service]
Type=simple
ExecStart=$BRIDGE_BINARY_DST
Restart=always
RestartSec=2s
User=root
Group=$APP_GROUP

[Install]
WantedBy=multi-user.target
EOF
    fi

    systemctl daemon-reload

    # Polkit rules (for regular users to control the daemon service)
    echo -e "${GREEN}[6/9] Creating Polkit authorization...${NC}"
    cat <<EOF > "$POLKIT_PATH"
polkit.addRule(function(action, subject) {
    if ((action.id == "org.freedesktop.systemd1.manage-units" ||
         action.id == "org.freedesktop.systemd1.manage-unit-files") &&
        action.lookup("unit") == "$SERVICE_NAME.service" &&
        subject.isInGroup("$APP_GROUP")) {
        return polkit.Result.YES;
    }
});
EOF

    # Sudoers rules (for passwordless enable/disable)
    echo -e "${GREEN}[7/9] Creating sudoers authorization for enable/disable...${NC}"
    cat <<EOF > "$SUDOERS_PATH"
# Allow users of group $APP_GROUP to enable/disable the DSTX service without password
%$APP_GROUP ALL=(ALL) NOPASSWD: /usr/bin/systemctl enable $SERVICE_NAME.service, /usr/bin/systemctl disable $SERVICE_NAME.service, /usr/bin/systemctl daemon-reload
EOF
    chmod 440 "$SUDOERS_PATH"

    # D-Bus policy for the bridge
    echo -e "${GREEN}[8/9] Creating D-Bus policy for the bridge...${NC}"
    cat <<EOF > "$DBUS_POLICY_PATH"
<!DOCTYPE busconfig PUBLIC "-//freedesktop//DTD D-BUS Bus Configuration 1.0//EN"
 "http://www.freedesktop.org/standards/dbus/1.0/busconfig.dtd">
<busconfig>
  <policy group="$APP_GROUP">
    <allow own="org.dstx.Bridge"/>
    <allow send_destination="org.dstx.Bridge"/>
    <allow receive_sender="org.dstx.Bridge"/>
  </policy>
  <policy user="root">
    <allow own="org.dstx.Bridge"/>
  </policy>
</busconfig>
EOF

    # User group membership
    echo -e "${GREEN}[9/9] Checking group permissions...${NC}"
    USER_NAME=${SUDO_USER:-$USER}
    if ! groups "$USER_NAME" | grep -q "\b$APP_GROUP\b"; then
        usermod -aG "$APP_GROUP" "$USER_NAME"
        echo -e "${YELLOW}User '$USER_NAME' added to group '$APP_GROUP'.${NC}"
        echo -e "${YELLOW}NOTE: You need to restart your session to apply the permissions.${NC}"
    fi

    # Enable and start services
    echo -e "${GREEN}Enabling and starting services...${NC}"
    systemctl enable "$SERVICE_NAME"
    systemctl start "$SERVICE_NAME"
    if [ "$HAS_BRIDGE" = true ]; then
        systemctl enable "$BRIDGE_SERVICE_NAME"
        systemctl start "$BRIDGE_SERVICE_NAME"
    fi

    echo -e "\n${GREEN}Installation completed successfully!${NC}"
    echo -e "${BLUE}Services have been started automatically.${NC}"
    echo -e "${BLUE}To check status:${NC}"
    echo -e "  sudo systemctl status $SERVICE_NAME"
    if [ "$HAS_BRIDGE" = true ]; then
        echo -e "  sudo systemctl status $BRIDGE_SERVICE_NAME"
    fi
}

# ------------------------------------------------------------------------------
# UNINSTALLATION FUNCTION
# ------------------------------------------------------------------------------
uninstall_dstx() {
    echo -e "${YELLOW}--- Starting Removal of System Files ---${NC}"

    echo -e "${RED}[-] Stopping services...${NC}"
    systemctl stop "$BRIDGE_SERVICE_NAME" 2>/dev/null
    systemctl stop "$SERVICE_NAME" 2>/dev/null
    systemctl disable "$BRIDGE_SERVICE_NAME" 2>/dev/null
    systemctl disable "$SERVICE_NAME" 2>/dev/null
    
    echo -e "${RED}[-] Removing binaries from /usr/local/bin...${NC}"
    rm -f "$BINARY_DST"
    rm -f "$BRIDGE_BINARY_DST"

    echo -e "${RED}[-] Removing system files...${NC}"
    rm -f "$SYSTEMD_PATH"
    rm -f "$BRIDGE_SYSTEMD_PATH"
    rm -f "$UDEV_PATH"
    rm -f "$POLKIT_PATH"
    rm -f "$SUDOERS_PATH"
    rm -f "$DBUS_POLICY_PATH"
    rm -f "$SHM_FILE"

    systemctl daemon-reload
    udevadm control --reload-rules

    echo -e "\n${GREEN}Removal completed.${NC}"
}

# ------------------------------------------------------------------------------
# RESTORATION FUNCTION
# ------------------------------------------------------------------------------
restore_dstx() {
    echo -e "${BLUE}=== RESTORING DSTX INFRASTRUCTURE ===${NC}"
    uninstall_dstx
    echo -e "${BLUE}Please wait... reinstalling...${NC}"
    sleep 1
    install_dstx
    echo -e "${GREEN}Environment restored successfully!${NC}"
}

# ------------------------------------------------------------------------------
# MAIN MENU
# ------------------------------------------------------------------------------
clear
echo -e "${BLUE}==========================================${NC}"
echo -e "${BLUE}          DSTX INFRASTRUCTURE TOOL        ${NC}"
echo -e "${BLUE}==========================================${NC}"
echo -e "1) Setup Environment (Install)"
echo -e "2) Remove Files (Uninstall)"
echo -e "3) Restore Environment (Reinstall)"
echo -e "4) Exit"
echo -ne "\nChoose an option: "
read -r OPT

case $OPT in
    1) install_dstx ;;
    2) uninstall_dstx ;;
    3) restore_dstx ;;
    4) exit 0 ;;
    *) echo -e "${RED}Invalid option.${NC}"; exit 1 ;;
esac
