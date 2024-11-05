#!/bin/sh

# Step 1: Install necessary dependencies (if not already installed)
# Install rsync, nginx, and apt-mirror for Debian
apk update
apk add rsync nginx apt-mirror

# Step 2: Define variables for the Alpine mirror
MIRROR_PATH="/srv/alpine-mirror"
ALPINE_VERSIONS="v3.20"  # Add more versions as needed
ARCH="x86_64"
MIRROR_HOST="rsync.alpinelinux.org::alpine"
LOCK_FILE="/var/lock/alpine-mirror-sync.lock"

# Step 3: Create directory structure for Alpine repos
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
    trap "rm -f $LOCK_FILE" EXIT  # Clean up lock file on exit

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

# Step 5: Set up Debian/Proxmox mirror paths
DEBIAN_PATH="/srv/debian-mirror"
mkdir -p "${DEBIAN_PATH}"

# Step 6: Configure apt-mirror for Debian and Proxmox
cat <<EOF > /etc/apt/mirror.list
set base_path ${DEBIAN_PATH}
set nthreads 20
set _tilde 0

deb http://deb.debian.org/debian bookworm main contrib
deb http://deb.debian.org/debian bookworm-updates main contrib
deb http://security.debian.org/debian-security bookworm-security main contrib
deb http://download.proxmox.com/debian/pve bookworm pve-no-subscription
clean http://deb.debian.org/debian
clean http://download.proxmox.com/debian/pve
EOF

# Step 7: Run apt-mirror for Debian and Proxmox repositories
apt-mirror

# Step 8: Configure Nginx to serve both Alpine and Debian mirrors
cat <<EOF > /etc/nginx/http.d/default.conf
# Nginx configuration for serving Alpine and Debian mirrors

server {
        listen 80 default_server;
        listen [::]:80 default_server;

        location /alpine {
            root /srv/alpine-mirror;
            autoindex on;
        }

        location /debian {
            root /srv/debian-mirror/mirror;
            autoindex on;
        }
}
EOF

# Step 9: Set permissions for both mirrors
chown -R nginx:nginx /srv/alpine-mirror /srv/debian-mirror
chmod -R 755 /srv/alpine-mirror /srv/debian-mirror

# Step 10: Enable and start nginx (if not already running)
rc-update add nginx
service nginx start
nginx -s reload

# Step 11: Set up cron jobs for Alpine and Debian mirrors
sed -i '/rsync.*alpinelinux.org::alpine/d' /etc/crontabs/root
echo "3 3 * * * /bin/sh /path/to/this/script.sh" >> /etc/crontabs/root  # Alpine sync at 3:00 AM
echo "0 4 * * * apt-mirror" >> /etc/crontabs/root  # Debian/Proxmox sync at 4:00 AM

# Step 12: Restart cron
rc-service crond restart

echo "Mirror setup for Alpine, Debian, and Proxmox repositories is complete!"
