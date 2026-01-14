#!/bin/bash

# Step 1: Install necessary dependencies
apt update
apt install -y rsync nginx apt-mirror

# Step 2: Define variables for the Alpine mirror
MIRROR_PATH="/srv/alpine-mirror"
ALPINE_VERSION="v3.20"
ARCH="x86_64"
MIRROR_HOST="rsync.alpinelinux.org::alpine"
LOCK_FILE="/var/lock/alpine-mirror-sync.lock"

# Step 3: Create directory structure for Alpine mirror
mkdir -p "${MIRROR_PATH}/alpine/${ALPINE_VERSION}/main/${ARCH}"
mkdir -p "${MIRROR_PATH}/alpine/${ALPINE_VERSION}/community/${ARCH}"

# Step 4: Rsync the Alpine repositories for initial setup
echo "Starting initial sync for Alpine main repository..."
rsync -avz --delete "${MIRROR_HOST}/${ALPINE_VERSION}/main/${ARCH}/" "${MIRROR_PATH}/alpine/${ALPINE_VERSION}/main/${ARCH}/" || {
    echo "Initial rsync failed for Alpine main repository" >&2
}

echo "Starting initial sync for Alpine community repository..."
rsync -avz --delete "${MIRROR_HOST}/${ALPINE_VERSION}/community/${ARCH}/" "${MIRROR_PATH}/alpine/${ALPINE_VERSION}/community/${ARCH}/" || {
    echo "Initial rsync failed for Alpine community repository" >&2
}

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
ALPINE_VERSION="v3.20"
ARCH="x86_64"
MIRROR_HOST="rsync.alpinelinux.org::alpine"
LOCK_FILE="/var/lock/alpine-mirror-sync.lock"

# Check if another instance of the script is running
if [ -f "$LOCK_FILE" ]; then
    echo "Sync already in progress. Exiting."
    exit 1
fi

# Create the lock file
touch "$LOCK_FILE"

# Ensure the lock file is removed even if the script exits unexpectedly
trap "rm -f $LOCK_FILE" EXIT

# Sync both main and community repositories for Alpine
echo "Starting sync for Alpine main repository..."
rsync -avz --delete "${MIRROR_HOST}/${ALPINE_VERSION}/main/${ARCH}/" "${MIRROR_PATH}/alpine/${ALPINE_VERSION}/main/${ARCH}/" || {
    echo "Rsync failed for Alpine main repository" >&2
}

echo "Starting sync for Alpine community repository..."
rsync -avz --delete "${MIRROR_HOST}/${ALPINE_VERSION}/community/${ARCH}/" "${MIRROR_PATH}/alpine/${ALPINE_VERSION}/community/${ARCH}/" || {
    echo "Rsync failed for Alpine community repository" >&2
}

echo "Sync completed for Alpine repositories."

# Lock file is automatically removed by the EXIT trap
EOF

# Make the sync-alpine.sh script executable
chmod +x /usr/local/bin/sync-alpine.sh

# Step 13: Set up cron job to run sync-alpine.sh daily at 3:00 AM
(crontab -l ; echo "0 3 * * * /usr/local/bin/sync-alpine.sh >> /var/log/alpine_mirror.log 2>&1") | crontab -

echo "Mirror setup and cron job configuration for Alpine, Debian, and Proxmox repositories is complete!"
