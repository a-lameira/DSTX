#!/bin/bash
set -e

echo "=== Removing DSTX system components ==="

systemctl stop dstx-dbus.service dstx-daemon.service 2>/dev/null || true
systemctl disable dstx-dbus.service dstx-daemon.service 2>/dev/null || true

rm -f /etc/systemd/system/dstx-{daemon,dbus}.service
rm -f /etc/udev/rules.d/99-dstx.rules
rm -f /etc/polkit-1/rules.d/10-dstx.rules
rm -f /etc/sudoers.d/dstx
rm -f /etc/dbus-1/system.d/org.dstx.Bridge.conf
rm -f /dev/shm/dstx_shared_mem
rm -f /usr/local/bin/dstx /usr/local/bin/dstx-dbus

systemctl daemon-reload
udevadm control --reload-rules 2>/dev/null

echo "✓ Uninstallation complete"
