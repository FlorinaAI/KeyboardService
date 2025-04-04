# 🌸 Florina Keyboard Service 🌸

One day I spilled water on my keyboard and now my keyboard is silly. ✨

NumPad8 - Dead
Space - Compose

## 📦 Installation 📦

```bash
# First, make the install script executable
chmod +x install.sh

# Then run it with sudo (it needs special permissions)
sudo ./install.sh
```

The installer will:
1. Ask where you want to install (default is `/opt/FlorinaKeyboard`)
2. Help you find your keyboard device
3. Install all the necessary Python packages
4. Set up a systemd service so it starts automatically
5. Create special udev rules for permissions

## 🗑️ Uninstallation 🗑️

```bash
# Make the uninstall script executable
chmod +x uninstall.sh

# Run it with sudo
sudo ./uninstall.sh
```

The uninstaller will:
1. Stop and disable the service
2. Remove all the files
3. Clean up permissions
4. Create backups of important files just in case!