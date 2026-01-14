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

# Step 1: Install necessary dependencies (if not already installed)
apk update

# Step 2: Setup XORG base
setup-xorg-base
apk add openbox xterm terminus-font font-noto

# Step 3: Add vdi user
adduser vdi -D
addgroup vdi input
addgroup vdi video

# Step 4: change /etc/motd to the bespoke welcome message:
cat <<EOF > /etc/motd
Welcome to Alpine!

The Alpine Wiki contains a large amount of how-to guides and general
information about administrating Alpine systems.
See <http://wiki.alpinelinux.org/>.

If you see this message and did not expect it, you should reboot the system.
EOF

#step 5: Add the vdi user dependencies
apk add python3 py3-pip py3-pyside6 virt-viewer git

# Step 6: Add pip packages as vdi user
su vdi
cd ~
pip install proxmoxer FreeSimpleGUI requests --break-system-packages

# Step 7: Clone the VDIClient repository
git clone https://github.com/qharley/PVE-VDIClient.git
chmod +x ~/PVE-VDIClient/vdiclient.py

# Step 8: Set up the VDIClient service
mkdir -p ~/.config/VDIClient
cat <<EOF > ~/.config/VDIClient/config.ini
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

# Add SpiceProxyRedirect section if configured
if [ -n "$PROXY_REDIRECT_HOST" ]; then
    cat <<EOF >> ~/.config/VDIClient/config.ini

[SpiceProxyRedirect]
$PROXY_REDIRECT_HOST = $PROXY_REDIRECT_TARGET
EOF
fi

# Add AdditionalParameters section if host-subject is configured
if [ -n "$HOST_SUBJECT" ]; then
    cat <<EOF >> ~/.config/VDIClient/config.ini

[AdditionalParameters]
type = spice
host-subject = $HOST_SUBJECT
EOF
fi

# Step 9: Set up Openbox configuration
echo 'exec startx' >> ~/.profile
echo 'exec openbox-session' >> ~/.xinitrc
cp -r /etc/xdg/openbox ~/.config
rm ~/.config/openbox/autostart
cat <<EOF > ~/.config/openbox/autostart
#!/bin/sh
while true
do
    ~/PVE-VDIClient/vdiclient.py
done
EOF

exit

# Replace a line in /etc/inittab to login as vdi autoamtically
# replace the line:
# tty1::respawn:/sbin/getty 38400 tty1
# with:
# tty1::respawn:/bin/login -f vdi
sed -i 's|^tty1::respawn:/sbin/getty 38400 tty1$|tty1::respawn:/bin/login -f vdi|' /etc/inittab

echo "PVE VDI View setup is complete!  Reboot to start the VDI Client."
