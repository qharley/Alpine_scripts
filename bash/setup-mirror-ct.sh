#!/usr/bin/env bash

# Copyright (c) 2024 qharley
# Author: qharley (Quentin Harley)
# License: MIT

First section copied from: alpine.sh
# Copyright (c) 2021-2024 tteck
# Author: tteck (tteckster)
# License: MIT
# https://github.com/community-scripts/ProxmoxVE/raw/main/LICENSE

source /dev/stdin <<< "$FUNCTIONS_FILE_PATH"

color
verb_ip6
catch_errors
setting_up_container
network_check
update_os

# Step 1: Install necessary dependencies (if not already installed)
# Install rsync and a web server (e.g., nginx)

msg_info "Installing Dependencies"
$STD apk add newt
$STD apk add curl
$STD apk add openssh
$STD apk add nano
$STD apk add mc
$STD apk add rsync
$STD apk add nginx
msg_ok "Installed Dependencies"

motd_ssh
customize

# Step 2: Define variables for the mirror
MIRROR_PATH="/srv/alpine-mirror"
ALPINE_VERSIONS="v3.20"  # Add more versions as needed
ARCH="x86_64"
MIRROR_HOST="rsync.alpinelinux.org::alpine"
LOCK_FILE="/var/lock/alpine-mirror-sync.lock"

# Step 3: Create the directory structure for both main and community repos
for VERSION in $ALPINE_VERSIONS; do
    mkdir -p "${MIRROR_PATH}/alpine/${VERSION}/main/${ARCH}"
    mkdir -p "${MIRROR_PATH}/alpine/${VERSION}/community/${ARCH}"
done

# Step 4: Rsync the repositories for all versions
for VERSION in $ALPINE_VERSIONS; do
    # Check if a lock file exists
    while [ -f "$LOCK_FILE" ]; do
        echo "Previous sync still in progress. Waiting..."
        sleep 600  # Wait for 10 minutes before checking again
    done

    # Create the lock file to prevent other jobs from starting
    touch "$LOCK_FILE"

    # Perform the sync for main and community repositories
    rsync -avz --delete "${MIRROR_HOST}/${VERSION}/main/${ARCH}/" "${MIRROR_PATH}/alpine/${VERSION}/main/${ARCH}/"
    rsync -avz --delete "${MIRROR_HOST}/${VERSION}/community/${ARCH}/" "${MIRROR_PATH}/alpine/${VERSION}/community/${ARCH}/"

    # Remove the lock file after the sync completes
    rm -f "$LOCK_FILE"
done

# Step 5: Set up the nginx configuration to serve the mirror
cat <<EOF > /etc/nginx/http.d/default.conf
# Alpine simple mirror config

server {
        listen 80 default_server;
        listen [::]:80 default_server;

        root /srv/alpine-mirror;
        autoindex on;

        location / {
            try_files \$uri \$uri/ =404;
        }
}
EOF

# Step 6: Set file permissions
chown -R nginx:nginx /srv/alpine-mirror 
chmod -R 755 /srv/alpine-mirror

# Step 7: Enable and start nginx (if not already running)
rc-update add nginx
service nginx start
service nginx restart

# Step 8: Procedurally create cron jobs for each version
# Clear any previous cron jobs related to the mirror
sed -i '/rsync.*alpinelinux.org::alpine/d' /etc/crontabs/root

# Add new cron jobs based on versions
SYNC_TIME=3  # Start cron jobs from 3 AM
for VERSION in $ALPINE_VERSIONS; do
    echo "$SYNC_TIME 3 * * * /bin/sh /path/to/this/script.sh" >> /etc/crontabs/root
    SYNC_TIME=$((SYNC_TIME + 1))  # Increment sync time for the next version
done

# Step 9: Restart cron
rc-service crond restart

echo "Alpine Linux mirror setup for ${ALPINE_VERSIONS} with lock mechanism is complete!"
