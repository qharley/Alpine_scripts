#!/bin/sh

# Step 1: Install necessary dependencies (if not already installed)
apk update
apk add rsync nginx

# Step 2: Define variables for Alpine mirror
MIRROR_PATH="/srv/alpine-mirror"
ALPINE_VERSIONS="v3.20"
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

# Step 5: Define variables for Debian and Proxmox mirrors
DEBIAN_PATH="/srv/debian-mirror"
DEBIAN_HOST="deb.debian.org::debian"
PROXMOX_PATH="/srv/proxmox-mirror"
PROXMOX_HOST="download.proxmox.com::debian"

# Step 6: Create directories for Debian and Proxmox mirrors
mkdir -p "${DEBIAN_PATH}"
mkdir -p "${PROXMOX_PATH}"

# Step 7: Rsync the Debian repositories, including security
echo "Syncing Debian repositories..."
rsync -avz --delete "${DEBIAN_HOST}/dists/bookworm/main/" "${DEBIAN_PATH}/dists/bookworm/main/" || {
    echo "Rsync failed for Debian main repo" >&2
}
rsync -avz --delete "${DEBIAN_HOST}/dists/bookworm/contrib/" "${DEBIAN_PATH}/dists/bookworm/contrib/" || {
    echo "Rsync failed for Debian contrib repo" >&2
}
rsync -avz --delete "${DEBIAN_HOST}/dists/bookworm-updates/main/" "${DEBIAN_PATH}/dists/bookworm-updates/main/" || {
    echo "Rsync failed for Debian updates main repo" >&2
}
rsync -avz --delete "${DEBIAN_HOST}/dists/bookworm-updates/contrib/" "${DEBIAN_PATH}/dists/bookworm-updates/contrib/" || {
    echo "Rsync failed for Debian updates contrib repo" >&2
}

# Additional rsync command for the Debian security repository
SECURITY_HOST="security.debian.org::debian-security"
rsync -avz --delete "${SECURITY_HOST}/dists/bookworm-security/main/" "${DEBIAN_PATH}/dists/bookworm-security/main/" || {
    echo "Rsync failed for Debian security main repo" >&2
}
rsync -avz --delete "${SECURITY_HOST}/dists/bookworm-security/contrib/" "${DEBIAN_PATH}/dists/bookworm-security/contrib/" || {
    echo "Rsync failed for Debian security contrib repo" >&2
}

# Step 8: Rsync the Proxmox repository
echo "Syncing Proxmox repository..."
rsync -avz --delete "${PROXMOX_HOST}/dists/bookworm/pve-no-subscription/" "${PROXMOX_PATH}/dists/bookworm/pve-no-subscription/" || {
    echo "Rsync failed for Proxmox repo" >&2
}

# Step 9: Configure Nginx to serve all mirrors
cat <<EOF > /etc/nginx/http.d/default.conf
server {
        listen 80 default_server;
        listen [::]:80 default_server;

        location /alpine {
            root /srv/alpine-mirror;
            autoindex on;
        }

        location /debian {
            root /srv/debian-mirror;
            autoindex on;
        }

        location /proxmox {
            root /srv/proxmox-mirror;
            autoindex on;
        }
}
EOF

# Step 10: Set permissions for all mirrors
chown -R nginx:nginx /srv/alpine-mirror /srv/debian-mirror /srv/proxmox-mirror
chmod -R 755 /srv/alpine-mirror /srv/debian-mirror /srv/proxmox-mirror

# Step 11: Enable and start nginx
rc-update add nginx
service nginx start
nginx -s reload

# Step 12: Set up cron jobs for regular sync
sed -i '/rsync.*deb.debian.org::debian/d' /etc/crontabs/root
echo "3 3 * * * /bin/sh /path/to/this/script.sh" >> /etc/crontabs/root  # Alpine sync at 3:00 AM
echo "0 4 * * * /bin/sh /path/to/this/script.sh" >> /etc/crontabs/root  # Debian/Proxmox sync at 4:00 AM

# Step 13: Restart cron
rc-service crond restart

echo "Mirror setup for Alpine, Debian, and Proxmox repositories is complete!"
