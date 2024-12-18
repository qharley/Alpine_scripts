#!/bin/bash
# Copyright (c) 2024 qharley

# wget https://github.com/qharley/Alpine_scripts/raw/refs/heads/main/bash/setup-mirrors.sh && chmod +x setup-mirrors.sh && ./setup-mirrors.sh

# Step 1: Install necessary dependencies
apt update
apt install -y rsync nginx apt-mirror

# Step 2: Define variables for the Alpine mirror
MIRROR_PATH="/srv/alpine-mirror"
ALPINE_VERSIONS="v3.20"
ARCH="x86_64"
MIRROR_HOST="rsync.alpinelinux.org::alpine"
LOCK_FILE="/var/lock/alpine-mirror-sync.lock"

# Step 3: Create directory structure for Alpine mirror
for VERSION in $ALPINE_VERSIONS; do
    mkdir -p "${MIRROR_PATH}/alpine/${VERSION}/main/${ARCH}"
    mkdir -p "${MIRROR_PATH}/alpine/${VERSION}/community/${ARCH}"
done

# Step 4: Rsync the Alpine repositories
for VERSION in $ALPINE_VERSIONS; do
    while [ -f "$LOCK_FILE" ]; do
        echo "Previous sync still in progress. Waiting..."
        sleep 600
    done

    touch "$LOCK_FILE"
    trap "rm -f $LOCK_FILE" EXIT

    rsync -avz --delete "${MIRROR_HOST}/${VERSION}/main/${ARCH}/" "${MIRROR_PATH}/alpine/${VERSION}/main/${ARCH}/" || {
        echo "Rsync failed for Alpine ${VERSION} main repo" >&2
        continue
    }
    rsync -avz --delete "${MIRROR_HOST}/${VERSION}/community/${ARCH}/" "${MIRROR_PATH}/alpine/${VERSION}/community/${ARCH}/" || {
        echo "Rsync failed for Alpine ${VERSION} community repo" >&2
        continue
    }

    rm -f "$LOCK_FILE"
done

# Step 5: Set up apt-mirror for Debian and Proxmox
DEBIAN_PATH="/srv/debian-mirror"
mkdir -p "${DEBIAN_PATH}"

cat <<EOF > /etc/apt/mirror.list
set base_path ${DEBIAN_PATH}
set nthreads 20
set _tilde 0

deb http://deb.debian.org/debian bookworm main contrib
deb http://deb.debian.org/debian bookworm-updates main contrib
deb http://security.debian.org/debian-security bookworm-security main contrib
deb http://download.proxmox.com/debian/pve bookworm pve-no-subscription

clean http://deb.debian.org/debian
clean http://security.debian.org/debian-security
clean http://download.proxmox.com/debian/pve
EOF

# Step 6: Run apt-mirror to sync Debian and Proxmox repositories
apt-mirror

# Step 7: Configure Nginx to serve both Alpine and Debian mirrors
cat <<EOF > /etc/nginx/sites-available/mirror.conf
server {
    listen 80;
    listen [::]:80;

    # Alpine mirror
    location /alpine {
        root /srv/alpine-mirror;
        autoindex on;
    }

    # Debian mirror
    location /debian {
        root /srv/debian-mirror/mirror/deb.debian.org;
        autoindex on;
    }

    # Debian Security mirror
    location /debian-security {
        root /srv/debian-mirror/mirror/security.debian.org;
        autoindex on;
    }

    # Proxmox mirror
    location /pve {
        root /srv/debian-mirror/mirror/download.proxmox.com/debian;
        autoindex on;
    }
}
EOF

# Step 8: Enable the Nginx mirror configuration
ln -sf /etc/nginx/sites-available/mirror.conf /etc/nginx/sites-enabled/mirror.conf
rm -f /etc/nginx/sites-enabled/default  # Remove the default config if it exists

# Step 9: Set permissions for all mirrors
chown -R www-data:www-data /srv/alpine-mirror /srv/debian-mirror
chmod -R 755 /srv/alpine-mirror /srv/debian-mirror

# Step 10: Enable and start Nginx
systemctl enable nginx
systemctl start nginx

# Step 11: Test and reload Nginx configuration
nginx -t && nginx -s reload

# Step 12: Create sync-alpine.sh script for cron job
cat <<'EOF' > /usr/local/bin/sync-alpine.sh
#!/bin/bash

# Define variables for the Alpine mirror
MIRROR_PATH="/srv/alpine-mirror"
ALPINE_VERSIONS="v3.20"
ARCH="x86_64"
MIRROR_HOST="rsync.alpinelinux.org::alpine"
LOCK_FILE="/var/lock/alpine-mirror-sync.lock"

# Rsync the Alpine repositories
for VERSION in $ALPINE_VERSIONS; do
    while [ -f "$LOCK_FILE" ]; do
        echo "Previous sync still in progress. Waiting..."
        sleep 600
    done

    touch "$LOCK_FILE"
    trap "rm -f $LOCK_FILE" EXIT

    rsync -avz --delete "${MIRROR_HOST}/${VERSION}/main/${ARCH}/" "${MIRROR_PATH}/alpine/${VERSION}/main/${ARCH}/" || {
        echo "Rsync failed for Alpine ${VERSION} main repo" >&2
        continue
    }
    rsync -avz --delete "${MIRROR_HOST}/${VERSION}/community/${ARCH}/" "${MIRROR_PATH}/alpine/${VERSION}/community/${ARCH}/" || {
        echo "Rsync failed for Alpine ${VERSION} community repo" >&2
        continue
    }

    rm -f "$LOCK_FILE"
done

echo "Sync completed for Alpine repositories."

# Lock file is automatically removed by the EXIT trap
EOF

# Make the sync-alpine.sh script executable
chmod +x /usr/local/bin/sync-alpine.sh

# Step 13: Set up cron job to run sync-alpine.sh daily at 3:00 AM
(crontab -l ; echo "0 3 * * * /usr/local/bin/sync-alpine.sh >> /var/log/alpine_mirror.log 2>&1") | crontab -
# Step 14: Set up cron job to run apt-mirror daily at 4:00 AM
(crontab -l ; echo "0 4 * * * apt-mirror") | crontab -
echo ""
echo "Mirror setup for Alpine, Debian, and Proxmox repositories is complete!"
