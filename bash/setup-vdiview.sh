#!/bin/sh

# bash -c "$(wget -qLO - https://raw.githubusercontent.com/qharley/Alpine_scripts/refs/heads/main/bash/setup-vdiview.sh)"

# Configuration Interface
echo "============================================"
echo "  Alpine VDI View Setup - Configuration"
echo "============================================"
echo ""
echo "Press Enter to use default values shown in [brackets]"
echo ""

# VDI Client Title
printf "VDI Client Title [VDI Client]: "
read VDI_TITLE
VDI_TITLE=${VDI_TITLE:-"VDI Client"}

# Theme
printf "Theme (DarkBlue/LightGreen/DarkGrey) [DarkBlue]: "
read VDI_THEME
VDI_THEME=${VDI_THEME:-"DarkBlue"}

# Proxmox Host IP (Required)
while [ -z "$PVE_HOST" ]; do
    printf "Proxmox Host IP (e.g., 192.168.1.100): "
    read PVE_HOST
    if [ -z "$PVE_HOST" ]; then
        echo "  Error: Proxmox host IP is required!"
    fi
done

# Proxmox Port
printf "Proxmox Port [8006]: "
read PVE_PORT
PVE_PORT=${PVE_PORT:-"8006"}

# Kiosk Mode
printf "Enable Kiosk Mode? (true/false) [false]: "
read VDI_KIOSK
VDI_KIOSK=${VDI_KIOSK:-"False"}

# Fullscreen
printf "Enable Fullscreen? (true/false) [true]: "
read VDI_FULLSCREEN
VDI_FULLSCREEN=${VDI_FULLSCREEN:-"True"}

# Guest Type
printf "Guest Type (qemu/lxc) [qemu]: "
read VDI_GUEST_TYPE
VDI_GUEST_TYPE=${VDI_GUEST_TYPE:-"qemu"}

# Show Reset Button
printf "Show Reset Button? (true/false) [false]: "
read VDI_SHOW_RESET
VDI_SHOW_RESET=${VDI_SHOW_RESET:-"False"}

# Show Power Button
printf "Show Power Button? (true/false) [false]: "
read VDI_SHOW_POWER
VDI_SHOW_POWER=${VDI_SHOW_POWER:-"False"}

# TLS Verify
printf "Verify TLS certificates? (true/false) [false]: "
read PVE_TLS_VERIFY
PVE_TLS_VERIFY=${PVE_TLS_VERIFY:-"False"}

# Proxy Redirect (Optional)
printf "SPICE Proxy Redirect (e.g., pve.example.lan:3128) [none]: "
read PROXY_REDIRECT_HOST
if [ -n "$PROXY_REDIRECT_HOST" ]; then
    printf "Proxy Target IP [%s]: " "$PVE_HOST"
    read PROXY_REDIRECT_TARGET
    PROXY_REDIRECT_TARGET=${PROXY_REDIRECT_TARGET:-"$PVE_HOST"}
fi
# Host Subject (Optional)
printf "TLS Host Subject (e.g., OU=PVE, O=Proxmox Virtual Environment, CN=pve.example.lan) [none]: "
read HOST_SUBJECT

echo ""
echo "============================================"
echo "Configuration Summary:"
echo "  Title: $VDI_TITLE"
echo "  Theme: $VDI_THEME"
echo "  Proxmox Host: $PVE_HOST:$PVE_PORT"
echo "  Kiosk Mode: $VDI_KIOSK"
echo "  Fullscreen: $VDI_FULLSCREEN"
echo "  Guest Type: $VDI_GUEST_TYPE"
if [ -n "$PROXY_REDIRECT_HOST" ]; then
    echo "  Proxy: $PROXY_REDIRECT_HOST = $PROXY_REDIRECT_TARGET"
fi
echo "============================================"
echo ""
printf "Proceed with installation? (yes/no) [yes]: "
read CONFIRM
CONFIRM=${CONFIRM:-"yes"}

if [ "$CONFIRM" != "yes" ] && [ "$CONFIRM" != "y" ]; then
    echo "Installation cancelled."
    exit 0
fi

echo ""
echo "Starting installation..."
echo ""

# Pre-installation checks
echo "[0/9] Performing pre-installation checks..."

# Check if running as root
if [ "$(id -u)" -ne 0 ]; then
    echo "ERROR: This script must be run as root"
    exit 1
fi

# Check if /dev is properly mounted as devtmpfs
if ! mount | grep -q "devtmpfs on /dev"; then
    echo "WARNING: /dev is not mounted as devtmpfs"
    echo "This is required for udev and XORG to function properly."
    echo ""
    echo "To fix this issue:"
    echo "  1. Edit /etc/fstab and add: devtmpfs  /dev  devtmpfs  defaults  0  0"
    echo "  2. Reboot the system"
    echo "  3. Run this script again"
    echo ""
    printf "Continue anyway? (not recommended) (yes/no) [no]: "
    read CONTINUE_WITHOUT_DEVTMPFS
    CONTINUE_WITHOUT_DEVTMPFS=${CONTINUE_WITHOUT_DEVTMPFS:-"no"}
    if [ "$CONTINUE_WITHOUT_DEVTMPFS" != "yes" ] && [ "$CONTINUE_WITHOUT_DEVTMPFS" != "y" ]; then
        echo "Installation aborted. Please configure devtmpfs and try again."
        exit 1
    fi
    echo "WARNING: Continuing without proper /dev mount. System may not function correctly."
fi

echo "✓ Pre-installation checks completed"
echo ""

# Step 1: Install necessary dependencies (if not already installed)
echo "[1/9] Updating package repositories..."
if ! apk update; then
    echo "ERROR: Failed to update package repositories"
    exit 1
fi
echo "✓ Package repositories updated successfully"
echo ""

# Step 2: Setup XORG base
echo "[2/9] Setting up XORG base and window manager..."
if ! setup-xorg-base; then
    echo "ERROR: Failed to setup XORG base"
    echo ""
    echo "This is likely because /dev is not properly configured as devtmpfs."
    echo "Please ensure your system meets the requirements:"
    echo "  - /dev must be mounted as devtmpfs"
    echo "  - System must be running on physical hardware or a VM (not a container)"
    echo "  - Kernel must support devtmpfs"
    exit 1
fi
if ! apk add openbox xterm terminus-font font-noto; then
    echo "ERROR: Failed to install XORG packages"
    exit 1
fi
echo "✓ XORG and Openbox installed successfully"
echo ""

# Step 3: Add vdi user
echo "[3/9] Creating VDI user and configuring groups..."
if ! adduser vdi -D; then
    echo "ERROR: Failed to create vdi user"
    exit 1
fi
if ! addgroup vdi input; then
    echo "ERROR: Failed to add vdi user to input group"
    exit 1
fi
if ! addgroup vdi video; then
    echo "ERROR: Failed to add vdi user to video group"
    exit 1
fi
echo "✓ VDI user created and added to input/video groups"
echo ""

# Step 4: change /etc/motd to the bespoke welcome message:
echo "[4/9] Configuring system welcome message..."
if ! cat <<EOF > /etc/motd
Welcome to Alpine!

The Alpine Wiki contains a large amount of how-to guides and general
information about administrating Alpine systems.
See <http://wiki.alpinelinux.org/>.

If you see this message and did not expect it, you should reboot the system.
EOF
then
    echo "ERROR: Failed to update /etc/motd"
    exit 1
fi
echo "✓ Welcome message configured"
echo ""

#step 5: Add the vdi user dependencies
echo "[5/9] Installing Python and VDI dependencies..."
if ! apk add python3 py3-pip py3-pyside6 virt-viewer git; then
    echo "ERROR: Failed to install Python and VDI dependencies"
    exit 1
fi
echo "✓ Python and VDI dependencies installed successfully"
echo ""

# Step 6: Add pip packages as vdi user
echo "[6/9] Installing Python packages for VDI user..."
su vdi <<'VDIUSER'
cd ~ || exit 1
if ! pip install proxmoxer FreeSimpleGUI requests --break-system-packages; then
    echo "ERROR: Failed to install Python packages"
    exit 1
fi
echo "✓ Python packages installed successfully"
VDIUSER
if [ $? -ne 0 ]; then
    echo "ERROR: Failed during Python package installation"
    exit 1
fi
echo ""

# Step 7: Clone the VDIClient repository
echo "[7/9] Cloning VDIClient repository..."
if ! git clone https://github.com/qharley/PVE-VDIClient.git; then
    echo "ERROR: Failed to clone VDIClient repository"
    exit 1
fi
if ! chmod +x ~/PVE-VDIClient/vdiclient.py; then
    echo "ERROR: Failed to set execute permissions on vdiclient.py"
    exit 1
fi
echo "✓ VDIClient repository cloned successfully"
echo ""

# Step 8: Set up the VDIClient service
echo "[8/9] Configuring VDIClient..."
if ! mkdir -p ~/.config/VDIClient; then
    echo "ERROR: Failed to create VDIClient config directory"
    exit 1
fi
if ! cat <<EOF > ~/.config/VDIClient/config.ini
[General]
title = $VDI_TITLE
theme = $VDI_THEME
icon = /home/vdi/vdiclient.ico
logo = /home/vdi/vdiclient.png
kiosk = $VDI_KIOSK
fullscreen = $VDI_FULLSCREEN
inidebug = False
guest_type = $VDI_GUEST_TYPE
show_reset = $VDI_SHOW_RESET
show_power = $VDI_SHOW_POWER

[Hosts.Proxmox]
auth_backend = pve
auth_totp = False
tls_verify = $PVE_TLS_VERIFY
hostpool = { "$PVE_HOST" : "$PVE_PORT" }
EOF
then
    echo "ERROR: Failed to create VDIClient config file"
    exit 1
fi

# Add SpiceProxyRedirect section if configured
if [ -n "$PROXY_REDIRECT_HOST" ]; then
    echo "  Adding SPICE proxy configuration..."
    if ! cat <<EOF >> ~/.config/VDIClient/config.ini

[SpiceProxyRedirect]
$PROXY_REDIRECT_HOST = $PROXY_REDIRECT_TARGET
EOF
    then
        echo "ERROR: Failed to add proxy configuration"
        exit 1
    fi
fi

# Add AdditionalParameters section if host-subject is configured
if [ -n "$HOST_SUBJECT" ]; then
    echo "  Adding TLS host subject configuration..."
    if ! cat <<EOF >> ~/.config/VDIClient/config.ini

[AdditionalParameters]
type = spice
host-subject = $HOST_SUBJECT
EOF
    then
        echo "ERROR: Failed to add host subject configuration"
        exit 1
    fi
fi
echo "✓ VDIClient configured successfully"
echo ""

# Step 9: Set up Openbox configuration
echo "[9/9] Configuring Openbox window manager..."
if ! echo 'exec startx' >> ~/.profile; then
    echo "ERROR: Failed to update ~/.profile"
    exit 1
fi
if ! echo 'exec openbox-session' >> ~/.xinitrc; then
    echo "ERROR: Failed to update ~/.xinitrc"
    exit 1
fi
if ! cp -r /etc/xdg/openbox ~/.config; then
    echo "ERROR: Failed to copy Openbox configuration"
    exit 1
fi
if ! rm ~/.config/openbox/autostart; then
    echo "WARNING: Failed to remove default autostart file (may not exist)"
fi
if ! cat <<EOF > ~/.config/openbox/autostart
#!/bin/sh
while true
do
    ~/PVE-VDIClient/vdiclient.py
done
EOF
then
    echo "ERROR: Failed to create Openbox autostart script"
    exit 1
fi
echo "✓ Openbox configured successfully"
echo ""

exit

# Replace a line in /etc/inittab to login as vdi autoamtically
# replace the line:
# tty1::respawn:/sbin/getty 38400 tty1
# with:
# tty1::respawn:/bin/login -f vdi
echo "[Final] Configuring automatic login..."
if ! sed -i 's|^tty1::respawn:/sbin/getty 38400 tty1$|tty1::respawn:/bin/login -f vdi|' /etc/inittab; then
    echo "ERROR: Failed to configure automatic login in /etc/inittab"
    exit 1
fi
echo "✓ Automatic login configured"
echo ""
echo "============================================"
echo "  Installation Complete!"
echo "============================================"
echo "PVE VDI View setup is complete!"
echo "Reboot the system to start the VDI Client."
echo ""
echo "To reboot now, run: reboot"
echo "============================================"
