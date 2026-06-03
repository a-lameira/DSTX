#!/bin/bash
set -e

BIN_SRC="${1:-/app/bin}"
DEST_BIN="/usr/local/bin"

echo "=== Installing DSTX system components ==="

# ==============================================================================
# DSTX GROUP
# ==============================================================================

if getent group dstx > /dev/null 2>&1; then
    echo "✓ dstx group already exists"
else
    echo "→ Creating dstx group..."
    groupadd -r dstx
fi

# Detect the real user even under pkexec/sudo
if [ -n "$SUDO_USER" ]; then
    CURRENT_USER="$SUDO_USER"
elif [ -n "$PKEXEC_UID" ]; then
    CURRENT_USER=$(getent passwd "$PKEXEC_UID" | cut -d: -f1)
else
    CURRENT_USER="$USER"
fi

if [ -n "$CURRENT_USER" ] && [ "$CURRENT_USER" != "root" ]; then
    if id -nG "$CURRENT_USER" | grep -qw "dstx"; then
        echo "✓ User $CURRENT_USER already belongs to the dstx group"
    else
        echo "→ Adding user $CURRENT_USER to the dstx group..."
        usermod -a -G dstx "$CURRENT_USER"
        echo "⚠️ IMPORTANT: Log out and log back in for the changes to take effect"
    fi
fi

# ==============================================================================
# UDEV RULES
# ==============================================================================

echo "→ Configuring udev rules..."
cat > /etc/udev/rules.d/99-dstx.rules <<'EOF'
KERNEL=="hidraw*", ATTRS{idVendor}=="054c", ATTRS{idProduct}=="05c4", MODE="0660", GROUP="dstx"
KERNEL=="hidraw*", ATTRS{idVendor}=="054c", ATTRS{idProduct}=="09cc", MODE="0660", GROUP="dstx"
KERNEL=="hidraw*", ATTRS{idVendor}=="054c", ATTRS{idProduct}=="0ce6", MODE="0660", GROUP="dstx"
KERNEL=="hidraw*", ATTRS{idVendor}=="057e", ATTRS{idProduct}=="2009", MODE="0660", GROUP="dstx"
KERNEL=="uinput", MODE="0660", GROUP="dstx", OPTIONS+="static_node=uinput"
EOF
udevadm control --reload-rules &>/dev/null
echo "✓ udev rules configured"

# ==============================================================================
# BINARIES
# ==============================================================================

echo "→ Copying binaries..."
cp -f "$BIN_SRC/dstx" "$DEST_BIN/"
cp -f "$BIN_SRC/dstx-dbus" "$DEST_BIN/"
chmod 755 "$DEST_BIN/dstx" "$DEST_BIN/dstx-dbus"
echo "✓ Binaries installed"

# ==============================================================================
# SYSTEMD SERVICES
# ==============================================================================

echo "→ Configuring systemd services..."
cat > /etc/systemd/system/dstx-daemon.service <<'EOF'
[Unit]
Description=DSTX Daemon
After=network.target

[Service]
LimitMEMLOCK=infinity
Type=simple
ExecStartPre=/bin/rm -f /dev/shm/dstx_shared_mem
ExecStart=/usr/local/bin/dstx --daemon
Restart=on-failure
RestartSec=1s
User=root
Group=dstx
Nice=-20
CPUSchedulingPolicy=fifo
CPUSchedulingPriority=99

[Install]
WantedBy=multi-user.target
EOF

cat > /etc/systemd/system/dstx-dbus.service <<'EOF'
[Unit]
Description=DSTX D-Bus Bridge
After=network.target

[Service]
Type=simple
ExecStart=/usr/local/bin/dstx-dbus
Restart=always
RestartSec=2s
User=root
Group=dstx

[Install]
WantedBy=multi-user.target
EOF

echo "✓ Services configured"

# ==============================================================================
# POLICIES
# ==============================================================================

echo "→ Configuring policies..."
cat > /etc/polkit-1/rules.d/10-dstx.rules <<'EOF'
polkit.addRule(function(action, subject) {
    if ((action.id == "org.freedesktop.systemd1.manage-units") &&
        action.lookup("unit") == "dstx-daemon.service" &&
        subject.isInGroup("dstx")) {
        return polkit.Result.YES;
    }
});
EOF

cat > /etc/sudoers.d/dstx <<'EOF'
%dstx ALL=(ALL) NOPASSWD: /usr/bin/systemctl enable dstx-daemon.service, /usr/bin/systemctl disable dstx-daemon.service, /usr/bin/systemctl daemon-reload
EOF
chmod 440 /etc/sudoers.d/dstx

cat > /etc/dbus-1/system.d/org.dstx.Bridge.conf <<'EOF'
<!DOCTYPE busconfig PUBLIC "-//freedesktop//DTD D-BUS Bus Configuration 1.0//EN" "http://www.freedesktop.org/standards/dbus/1.0/busconfig.dtd">
<busconfig>
  <policy group="dstx">
    <allow own="org.dstx.Bridge"/>
    <allow send_destination="org.dstx.Bridge"/>
    <allow receive_sender="org.dstx.Bridge"/>
  </policy>
  <policy user="root">
    <allow own="org.dstx.Bridge"/>
  </policy>
</busconfig>
EOF

echo "✓ Policies configured"

# ==============================================================================
# START SERVICES
# ==============================================================================

echo "→ Starting services..."
systemctl daemon-reload
systemctl enable --now dstx-daemon.service dstx-dbus.service 2>/dev/null || true
echo "✓ Services started"

echo ""
echo "=========================================="
echo "✅ Installation complete!"
echo "=========================================="
echo ""
echo "⚠️ Log out and log back in to apply group permissions"
echo ""
echo "To check the services:"
echo "  systemctl status dstx-daemon dstx-dbus"
echo ""
echo "To run the GUI:"
echo "  flatpak run org.dstx.gui"
echo "=========================================="
