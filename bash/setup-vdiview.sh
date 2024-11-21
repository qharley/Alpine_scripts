#!/bin/sh

# bash -c "$(wget -qLO - https://raw.githubusercontent.com/qharley/Alpine_scripts/refs/heads/main/bash/setup-vdiview.sh)"

# Step 1: Install necessary dependencies (if not already installed)
apk update

# Step 2: Setup XORG base
setup-xorg-base
apk add openbox xterm terminus-font font-noto

# Step 3: Add vdi user
adduser vdi -p XPL@bT3rm
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
su vdi -p XPL@bT3rm
pip install proxmoxer FreeSimpleGUI requests --break-system-packages

# Step 7: Clone the VDIClient repository
git clone https://github.com/qharley/PVE-VDIClient.git
chmod +x ~/PVE-VDIClient/VDIClient.py

# Step 8: Set up the VDIClient service
mkdir -p ~/.config/VDIClient
cat <<EOF > ~/.config/VDIClient/config.ini
[General]

EOF

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

# Replace a line in /etc/inittab to login as vdi autoamtically
sed -i 's/^#\(.*\)1:2345:respawn:\/sbin\/agetty.*/\11:2345:respawn:\/sbin\/agetty --noclear --autologin vdi tty1 linux/' /etc/inittab


echo "PVE VDI View setup is complete!  Reboot to start the VDI Client."
