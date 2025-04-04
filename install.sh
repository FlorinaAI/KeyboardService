#!/bin/bash

set -e

LOG_FILE="/tmp/florina_install.log"
exec > >(tee -a "$LOG_FILE") 2>&1
echo "📝 Installation log saved to: $LOG_FILE"

if [[ $EUID -ne 0 ]]; then
    echo "✋ Script must be run as root: sudo ./install.sh" >&2
    exit 1
fi

ORIGINAL_USER=$(logname || echo "${SUDO_USER:-$(whoami)}")
if [[ "$ORIGINAL_USER" == "root" ]]; then
    echo "❌ Do not run directly as root, use sudo with a normal user" >&2
    exit 1
fi

echo "🔍 Checking for required dependencies..."
for cmd in python3 pip3 udevadm grep; do
    if ! command -v $cmd &> /dev/null; then
        echo "❌ Required command '$cmd' not found. Please install it first." >&2
        exit 1
    fi
done

echo "📂 Installation Setup:"
read -p "Enter installation directory [/opt/FlorinaKeyboard]: " INSTALL_DIR
INSTALL_DIR=${INSTALL_DIR:-/opt/FlorinaKeyboard}
INSTALL_DIR=${INSTALL_DIR//\~/$HOME}  

if [[ -d "$INSTALL_DIR" ]]; then
    BACKUP_DIR="${INSTALL_DIR}_backup_$(date +%Y%m%d_%H%M%S)"
    echo "📦 Creating backup of existing installation to $BACKUP_DIR"
    cp -r "$INSTALL_DIR" "$BACKUP_DIR"
fi

echo "🖲️  Input Device Setup:"
read -p "Enter the input device path (e.g., /dev/input/event5): " DEVICE_PATH
DEVICE_PATH=${DEVICE_PATH:-/dev/input/event5}

if [[ ! -e "$DEVICE_PATH" ]]; then
    echo "❌ Error: Device $DEVICE_PATH does not exist!" >&2
    exit 1
fi

if ! udevadm info -q property -n "$DEVICE_PATH" 2>/dev/null | grep -q "ID_INPUT_KEYBOARD=1"; then
    echo "⚠️ Warning: Device may not be a keyboard. Continue anyway? (y/n)"
    read -r response
    if [[ "$response" != "y" ]]; then
        echo "Installation aborted."
        exit 1
    fi
fi

DEVICE_INFO=$(udevadm info --query=property --path=$(udevadm info -q path -n "$DEVICE_PATH") 2>/dev/null)

VENDOR_ID=$(echo "$DEVICE_INFO" | grep -oP 'ID_VENDOR_ID=\K\w+' | head -1)
PRODUCT_ID=$(echo "$DEVICE_INFO" | grep -oP 'ID_MODEL_ID=\K\w+' | head -1)

if [[ -z "$VENDOR_ID" || -z "$PRODUCT_ID" ]]; then
    echo "⚠️  Could not detect vendor/product IDs! Using fallback method."
    echo "ℹ️  Please manually enter device IDs when prompted."

    read -p "Enter Vendor ID (e.g., 046d): " VENDOR_ID
    read -p "Enter Product ID (e.g., c52b): " PRODUCT_ID
fi

echo "🔨 Creating directory: $INSTALL_DIR"
mkdir -p "$INSTALL_DIR"
chown -R "$ORIGINAL_USER:$ORIGINAL_USER" "$INSTALL_DIR"
chmod 755 "$INSTALL_DIR"

PYTHON_FILE="$INSTALL_DIR/FlorinaKeyboard.py"
echo "🐍 Writing Python script: $PYTHON_FILE"
cat > "$PYTHON_FILE" << EOF
#!/usr/bin/env python3

import time
from evdev import InputDevice, ecodes, UInput, InputEvent

device_path = "$DEVICE_PATH"

try:
    dev = InputDevice(device_path)
    dev.grab()
except Exception as e:
    print(f"Device error: {str(e)}")
    print("Check device permissions or run as root.")
    exit(1)

ui = UInput.from_device(dev, name="FlorinaKeyboard")

numlock_event = [
    InputEvent(0, 0, ecodes.EV_KEY, ecodes.KEY_NUMLOCK, 1),
    InputEvent(0, 0, ecodes.EV_KEY, ecodes.KEY_NUMLOCK, 0)
]

for event in numlock_event:
    ui.write_event(event)
ui.syn()

try:
    for event in dev.read_loop():
        if event.type == ecodes.EV_KEY:
            if event.code == ecodes.KEY_KP8:
                continue
            if event.code == ecodes.KEY_COMPOSE:
                event.code = ecodes.KEY_SPACE
            ui.write_event(event)
            ui.syn()
except KeyboardInterrupt:
    pass
except Exception as e:
    print(f"Error in event loop: {str(e)}")
finally:
    dev.ungrab()
EOF

chown "$ORIGINAL_USER:$ORIGINAL_USER" "$PYTHON_FILE"
chmod 755 "$PYTHON_FILE"

echo "🔧 Setting up virtual environment..."
sudo -u "$ORIGINAL_USER" python3 -m venv "$INSTALL_DIR/venv"
sudo -u "$ORIGINAL_USER" "$INSTALL_DIR/venv/bin/pip" install evdev

UDEV_RULE="/etc/udev/rules.d/FlorinaKeyboard.rules"
echo "🔧 Adding udev rules for device access..."

if [[ -f "$UDEV_RULE" ]]; then
    cp "$UDEV_RULE" "${UDEV_RULE}.bak"
    echo "📦 Created backup of existing udev rules"
fi

cat > "$UDEV_RULE" << EOF
SUBSYSTEM=="input", ATTRS{idVendor}=="$VENDOR_ID", ATTRS{idProduct}=="$PRODUCT_ID", GROUP="input", MODE="0660"

KERNEL=="uinput", GROUP="input", MODE="0660"
EOF

if ! lsmod | grep -q uinput; then
    echo "🔧 Loading uinput kernel module..."
    modprobe uinput
fi

udevadm control --reload-rules
udevadm trigger

echo "👤 Adding user to 'input' group..."
usermod -aG input "$ORIGINAL_USER"

SERVICE_FILE="/etc/systemd/system/FlorinaKeyboard.service"
echo "📦 Creating service: $SERVICE_FILE"

if [[ -f "$SERVICE_FILE" ]]; then
    cp "$SERVICE_FILE" "${SERVICE_FILE}.bak"
    echo "📦 Created backup of existing service file"
fi

cat > "$SERVICE_FILE" << EOF
[Unit]
Description=Florina Keyboard Service
After=graphical.target
Requires=display-manager.service

[Service]
Type=simple
ExecStart=$INSTALL_DIR/venv/bin/python $PYTHON_FILE
Restart=always
RestartSec=3
User=root
Group=root
WorkingDirectory=$INSTALL_DIR
Environment=DISPLAY=:0
Environment=XDG_RUNTIME_DIR=/run/user/$(id -u "$ORIGINAL_USER")
Environment=WAYLAND_DISPLAY=wayland-0

[Install]
WantedBy=multi-user.target
EOF

echo "🚀 Starting service..."
systemctl daemon-reload
systemctl enable FlorinaKeyboard.service
systemctl start FlorinaKeyboard.service

sleep 2
if systemctl is-active --quiet FlorinaKeyboard.service; then
    echo "✅ Service started successfully!"
else
    echo "⚠️ Service may not have started correctly. Check with: systemctl status FlorinaKeyboard.service"
fi

echo "✅ Installation completed successfully!"
echo "🔍 Check status: systemctl status FlorinaKeyboard.service"
echo "📝 Logs available at: $INSTALL_DIR/keyboard.log"
echo "🔄 Please reboot your system to apply all changes!"