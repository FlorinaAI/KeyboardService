#!/bin/bash

set -e

LOG_FILE="/tmp/florina_uninstall.log"
exec > >(tee -a "$LOG_FILE") 2>&1
echo "📝 Uninstallation log saved to: $LOG_FILE"

if [[ $EUID -ne 0 ]]; then
    echo "✋ Script must be run as root: sudo ./uninstall.sh" >&2
    exit 1
fi

SERVICE_NAME="FlorinaKeyboard.service"

echo "🛑 Stopping service..."
if systemctl is-active --quiet "$SERVICE_NAME"; then
    echo "Service is running, stopping it now..."
    systemctl stop "$SERVICE_NAME" 2>/dev/null || true
else
    echo "Service is not running"
fi

if systemctl list-unit-files | grep -q "$SERVICE_NAME"; then
    if systemctl is-enabled --quiet "$SERVICE_NAME" 2>/dev/null; then
        echo "Service is enabled, disabling it now..."
        systemctl disable "$SERVICE_NAME" 2>/dev/null || true
    else
        echo "Service is not enabled"
    fi
else
    echo "Service is not installed"
fi

SERVICE_FILE="/etc/systemd/system/$SERVICE_NAME"
echo "🗑️  Removing service file..."
if [[ -f "$SERVICE_FILE" ]]; then
    cp "$SERVICE_FILE" "${SERVICE_FILE}.bak.$(date +%Y%m%d_%H%M%S)" 2>/dev/null || true
    echo "📦 Created backup of service file"
    
    rm -f "$SERVICE_FILE"
    echo "✅ Service file removed"
else
    echo "ℹ️ Service file not found"
fi
systemctl daemon-reload

UDEV_RULE="/etc/udev/rules.d/FlorinaKeyboard.rules"
echo "🗑️  Removing udev rules..."
if [[ -f "$UDEV_RULE" ]]; then
    cp "$UDEV_RULE" "${UDEV_RULE}.bak.$(date +%Y%m%d_%H%M%S)" 2>/dev/null || true
    echo "📦 Created backup of udev rules"
    
    rm -f "$UDEV_RULE"
    echo "✅ Udev rules removed"
else
    echo "ℹ️ Udev rules not found"
fi
udevadm control --reload-rules
udevadm trigger

ORIGINAL_USER=$(logname || echo "${SUDO_USER:-$(whoami)}")
echo "👤 Checking if user '$ORIGINAL_USER' is in 'input' group..."
if groups "$ORIGINAL_USER" | grep -q input; then
    echo "User is in 'input' group. Do you want to remove them? (y/n)"
    read -r response
    if [[ "$response" == "y" ]]; then
        gpasswd -d "$ORIGINAL_USER" input
        echo "✅ User $ORIGINAL_USER removed from 'input' group"
    else
        echo "ℹ️ User will remain in 'input' group"
    fi
else
    echo "ℹ️ User $ORIGINAL_USER not in 'input' group"
fi

echo "🔍 Locating installation directory..."
if ls "$SERVICE_FILE.bak."* >/dev/null 2>&1; then
    INSTALL_DIR=$(grep 'WorkingDirectory=' "$SERVICE_FILE.bak."* 2>/dev/null | cut -d= -f2 | head -1 || echo "")
fi

if [[ -z "$INSTALL_DIR" ]]; then
    INSTALL_DIR=$(find /opt /home -type d -name FlorinaKeyboard 2>/dev/null | head -1)
fi

if [[ -n "$INSTALL_DIR" ]]; then
    echo "Found installation directory: $INSTALL_DIR"
    echo "Do you want to create a backup before deletion? (y/n)"
    read -r backup_response
    if [[ "$backup_response" == "y" ]]; then
        BACKUP_DIR="${INSTALL_DIR}_backup_$(date +%Y%m%d_%H%M%S)"
        echo "📦 Creating backup to $BACKUP_DIR"
        cp -r "$INSTALL_DIR" "$BACKUP_DIR" 2>/dev/null || true
    fi
    
    echo "🧹 Cleaning up $INSTALL_DIR..."
    rm -rf "$INSTALL_DIR"
    echo "✅ Installation directory removed"
else
    echo "⚠️  Installation directory not found!"
    read -p "🔧 Enter manual path to delete (leave empty to skip): " MANUAL_PATH
    if [[ -n "$MANUAL_PATH" ]]; then
        if [[ -d "$MANUAL_PATH" ]]; then
            rm -rf "$MANUAL_PATH"
            echo "✅ Directory $MANUAL_PATH removed"
        else
            echo "❌ Directory $MANUAL_PATH not found"
        fi
    fi
fi

echo "🔒 Resetting uinput permissions..."
if [[ -e "/dev/uinput" ]]; then
    chmod 600 /dev/uinput 2>/dev/null || true
    echo "✅ Uinput permissions reset"
else
    echo "ℹ️ Uinput device not found"
fi

echo "🔍 Verifying removal..."
REMAINING_FILES=0

if systemctl list-unit-files | grep -q "$SERVICE_NAME"; then
    echo "⚠️ Warning: Service may still be registered with systemd"
    REMAINING_FILES=1
fi

if [[ -f "$SERVICE_FILE" ]]; then
    echo "⚠️ Warning: Service file still exists"
    REMAINING_FILES=1
fi

if [[ -f "$UDEV_RULE" ]]; then
    echo "⚠️ Warning: Udev rule still exists"
    REMAINING_FILES=1
fi

if [[ -n "$INSTALL_DIR" ]] && [[ -d "$INSTALL_DIR" ]]; then
    echo "⚠️ Warning: Installation directory still exists"
    REMAINING_FILES=1
fi

if [[ $REMAINING_FILES -eq 0 ]]; then
    echo "✅ All components successfully removed!"
else
    echo "⚠️ Some components may not have been completely removed"
fi

echo "✅ Uninstallation completed!"
echo "📝 Uninstallation log saved to: $LOG_FILE"
echo "ℹ️ A system reboot is recommended to apply all changes"