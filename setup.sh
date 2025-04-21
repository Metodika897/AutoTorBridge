#!/bin/bash
bridges_count=$1
ports=(443 80 993 995 587 110 143 25)
or_ports=(9001 9002 9000 9100 9090 9993 9030 9007)
names=("first" "second" "third" "fourth" "fifth" "sixth" "seventh" "eighth")

# setup_unattended_upgrades.sh
# This script configures Debian's Unattended Upgrades to:
# 1. Automatically update all packages.
# 2. Automatically restart services after upgrades.
# 3. Automatically respond "no" to configuration file replacement prompts.
# 4. Limit system reboots to once every two weeks if strictly required.

set -e  # Exit immediately if a command exits with a non-zero status.

# Ensure the script is run as root.
if [ "$(id -u)" -ne 0 ]; then
    echo "This script must be run as root. Use sudo or switch to the root user."
    exit 1
fi

#Ensure user enter value between 1 and 8
#https://archive.torproject.org/websites/lists.torproject.org/pipermail/tor-relays/2023-June/021226.html
case $bridges_count in
[1-8])
echo "Script is going to setup $bridges_count bridges" 
sleep 1s;;
*)
echo "Number of bridges must be between 1 and 8"
exit 1
esac

echo "Starting Unattended Upgrades setup..."

# ----------------------------
# 1. Install Necessary Packages
# ----------------------------
echo "Installing required packages..."

apt update
apt install -y unattended-upgrades podman podman-compose nftables curl jq

# ----------------------------
# 2. Enable Unattended Upgrades
# ----------------------------
echo "Enabling Unattended Upgrades..."

# Enable the unattended-upgrades service.
# This modifies /etc/apt/apt.conf.d/20auto-upgrades
AUTO_UPGRADES_CONFIG="/etc/apt/apt.conf.d/20auto-upgrades"

cat > "$AUTO_UPGRADES_CONFIG" <<EOF
APT::Periodic::Update-Package-Lists "1";
APT::Periodic::Unattended-Upgrade "1";
EOF

# ----------------------------
# 3. Configure Unattended Upgrades
# ----------------------------
echo "Configuring Unattended Upgrades settings..."

# Backup existing configuration files if they exist.
BACKUP_DIR="/etc/apt/apt.conf.d/backup_unattended_upgrades_$(date +%F_%T)"
mkdir -p "$BACKUP_DIR"

CONFIG_50="/etc/apt/apt.conf.d/50unattended-upgrades"
CONFIG_10="/etc/apt/apt.conf.d/10periodic"

if [ -f "$CONFIG_50" ]; then
    cp "$CONFIG_50" "$BACKUP_DIR/"
    echo "Backup of $CONFIG_50 created at $BACKUP_DIR/"
fi

if [ -f "$CONFIG_10" ]; then
    cp "$CONFIG_10" "$BACKUP_DIR/"
    echo "Backup of $CONFIG_10 created at $BACKUP_DIR/"
fi

# Configure /etc/apt/apt.conf.d/50unattended-upgrades
cat > "$CONFIG_50" <<EOF
// 50unattended-upgrades

Unattended-Upgrade::Allowed-Origins {
    "\${distro_id}:\${distro_codename}";
    "\${distro_id}:\${distro_codename}-updates";
    "\${distro_id}:\${distro_codename}-proposed";
    "\${distro_id}:\${distro_codename}-backports";
    "\${distro_id}:\${distro_codename}-security";
};

Unattended-Upgrade::Automatic-Reboot "true";
Unattended-Upgrade::Automatic-Reboot-Time "02:00";

Unattended-Upgrade::Automatic-Reboot-WithUsers "false";

Unattended-Upgrade::Mail "";
Unattended-Upgrade::MailOnlyOnError "false";

Unattended-Upgrade::Remove-Unused-Dependencies "true";
Unattended-Upgrade::InstallOnShutdown "false";

Unattended-Upgrade::Automatic-Reboot-Successful "true";

Unattended-Upgrade::DPkg::Options {
   "--force-confdef";
   "--force-confold";
};

Unattended-Upgrade::Enable-Restore-Terminal "false";
EOF

# Configure /etc/apt/apt.conf.d/10periodic
cat > "$CONFIG_10" <<EOF
// 10periodic

APT::Periodic::Update-Package-Lists "1";
APT::Periodic::Unattended-Upgrade "1";
APT::Periodic::Automatic-Reboot "1";
APT::Periodic::Automatic-Reboot-Time "02:00";
EOF

# ----------------------------
# 4. Enable and Start Unattended Upgrades Service
# ----------------------------
echo "Enabling and starting Unattended Upgrades service..."

systemctl enable unattended-upgrades
systemctl start unattended-upgrades

# ----------------------------
# 5. Create Reboot Management Script
# ----------------------------
echo "Creating reboot management script..."

REBOOT_SCRIPT="/usr/local/bin/unattended-upgrades-reboot.sh"

cat > "$REBOOT_SCRIPT" <<'EOF'
#!/bin/bash

# /usr/local/bin/unattended-upgrades-reboot.sh

# Variables
REBOOT_TIMESTAMP_FILE="/var/log/last_unattended_reboot"
REBOOT_INTERVAL_SECONDS=1209600  # 2 weeks in seconds

# Check if a reboot is required
if [ -f /var/run/reboot-required ]; then
    CURRENT_TIMESTAMP=$(date +%s)

    if [ -f "$REBOOT_TIMESTAMP_FILE" ]; then
        LAST_REBOOT_TIMESTAMP=$(cat "$REBOOT_TIMESTAMP_FILE")
        DIFF=$((CURRENT_TIMESTAMP - LAST_REBOOT_TIMESTAMP))
        if [ "$DIFF" -ge "$REBOOT_INTERVAL_SECONDS" ]; then
            echo "Reboot required and interval elapsed. Rebooting now..."
            echo "$CURRENT_TIMESTAMP" > "$REBOOT_TIMESTAMP_FILE"
            /sbin/shutdown -r now
        else
            echo "Reboot required but within interval. Skipping reboot."
        fi
    else
        # Timestamp file doesn't exist; create it and reboot
        echo "$CURRENT_TIMESTAMP" > "$REBOOT_TIMESTAMP_FILE"
        echo "Reboot required. Rebooting now..."
        /sbin/shutdown -r now
    fi
else
    echo "No reboot required."
fi
EOF

# Make the script executable
chmod +x "$REBOOT_SCRIPT"

# ----------------------------
# 6. Ensure Reboot Timestamp File Exists
# ----------------------------
echo "Ensuring reboot timestamp file exists..."

REBOOT_TIMESTAMP_FILE="/var/log/last_unattended_reboot"
touch "$REBOOT_TIMESTAMP_FILE"
chmod 644 "$REBOOT_TIMESTAMP_FILE"

# ----------------------------
# 7. Create Cron Job for Reboot Management Script
# ----------------------------
echo "Creating cron job for reboot management script..."

CRON_JOB="0 3 * * * $REBOOT_SCRIPT >> /var/log/unattended-upgrades-reboot.log 2>&1"

# Check if the cron job already exists
(crontab -l 2>/dev/null | grep -F "$REBOOT_SCRIPT") || \
    (echo "$CRON_JOB" | crontab -u root -)

echo "Cron job added: $CRON_JOB"

# ----------------------------
# 8. Verify Configuration
# ----------------------------
echo "Verifying Unattended Upgrades configuration..."

# Dry run to check configuration
unattended-upgrade --dry-run --debug

echo "Unattended Upgrades setup completed successfully."

# ----------------------------
# 9. Optional: Display Summary
# ----------------------------
echo "----------------------------------------"
echo "Summary of Unattended Upgrades Setup:"
echo "----------------------------------------"
echo "1. Packages installed: unattended-upgrades, update-notifier-common"
echo "2. Configuration files:"
echo "   - /etc/apt/apt.conf.d/50unattended-upgrades"
echo "   - /etc/apt/apt.conf.d/10periodic"
echo "3. Reboot management script: $REBOOT_SCRIPT"
echo "4. Reboot timestamp file: $REBOOT_TIMESTAMP_FILE"
echo "5. Cron job scheduled at 3:00 AM daily to manage reboots."
echo "6. Unattended Upgrades service enabled and started."
echo "7. Configuration verified with a dry run."
echo "----------------------------------------"

# ----------------------------
# 10. Enable Firewall
# ----------------------------

systemctl enable nftables
systemctl start nftables

# ----------------------------
# 11. Configure Firewall
# ----------------------------

nft add rule inet filter input ct state related,established counter accept
nft add rule inet filter input iif lo counter accept
nft add rule inet filter input tcp dport 22 counter accept # Ssh access
for ((i = 0 ; i < $bridges_count ; i++)); do
  nft add rule inet filter input tcp dport ${ports[i]} counter accept # Bridge access
done
nft add rule inet filter input counter drop # Drop everyting else
nft list ruleset > /etc/nftables.conf

for ((i = 0 ; i < $bridges_count ; i++)); do

# ----------------------------
# 12. Configure Podman Compose Bridge
# ----------------------------

PODMAN="/home/bridge_$i/podman-compose.yml"
PODMAN_ENV="/home/bridge_$i/.env"
if [ ! -f "$PODMAN" ]; then
    mkdir -p "$PODMAN"
    rm -r "$PODMAN"
fi
cat > "$PODMAN" <<EOF
services:
  obfs4-bridge:
    image: docker.io/thetorproject/obfs4-bridge:latest
    environment:
      # Exit with an error message if OR_PORT is unset or empty.
      - OR_PORT=\${OR_PORT:?Env var OR_PORT is not set.}
      # Exit with an error message if PT_PORT is unset or empty.
      - PT_PORT=\${PT_PORT:?Env var PT_PORT is not set.}
      # Exit with an error message if EMAIL is unset or empty.
      - EMAIL=\${EMAIL:?Env var EMAIL is not set.}
      # Nickname with default value: "DockerObfs4Bridge"
      - NICKNAME=\${NICKNAME:-PodmanObfs4Bridge}
    env_file:
      - .env
    volumes:
      - /var/lib/tor
    ports:
      - \${OR_PORT}:\${OR_PORT}
      - \${PT_PORT}:\${PT_PORT}
    restart: unless-stopped
EOF

cat > "$PODMAN_ENV" <<EOF
#Your bridge nickname
NICKNAME=OnionBridge${names[i]}
# Your bridge's Tor port.
OR_PORT=${or_ports[i]}
# Your bridge's obfs4 port.
PT_PORT=${ports[i]}
# Your email address.
EMAIL=example@example.com
# Enable additional setup
OBFS4_ENABLE_ADDITIONAL_VARIABLES=1
#Config
OBFS4V_AssumeReachable=1
OBFS4V_PublishServerDescriptor=0
#ExitPolicy does not make any diffrence in this configuration
#OBFS4V_ExitPolicy=reject *:*
#IAT? https://archive.torproject.org/websites/lists.torproject.org/pipermail/tor-relays/2021-February/019370.html
EOF

# ----------------------------
# 13. Enable Bridge
# ----------------------------

SERVICE="/etc/systemd/system/${names[i]}.obfs4.service"
cat > "$SERVICE" <<EOF
[Unit]
Description=${names[i]}Obfs4Bridge
After=network-online.target
Wants=network-online.target

[Service]
Type=oneshot
RemainAfterExit=true
ExecStart=/usr/bin/podman-compose -f $PODMAN up -d 
ExecStop=/usr/bin/podman-compose -f $PODMAN down

[Install]
WantedBy=multi-user.target
EOF

systemctl enable ${names[i]}.obfs4.service
systemctl start ${names[i]}.obfs4.service

done

# ----------------------------
# 15. Display bridges configuration
# ----------------------------

IP="$(curl -s -X GET https://check.torproject.org/api/ip | jq -r .IP)"
CONTAINERS="$(podman ps -f name=obfs4-bridge --quiet)"

array=($CONTAINERS)
clear
for index in "${!array[@]}"
do
    PORT="$(podman exec ${array[index]} env | grep PT_PORT | cut -d'=' -f2)"
    LINE="$(podman exec ${array[index]} cat /var/lib/tor/pt_state/obfs4_bridgeline.txt | tail -1)"
    FINGERPRINT="$(podman exec ${array[index]} cat /var/lib/tor/fingerprint | cut -d' ' -f2)"
    LINE=${LINE/<IP ADDRESS>/$IP}
    LINE=${LINE/<PORT>/$PORT}
    LINE=${LINE/<FINGERPRINT>/$FINGERPRINT}
    LINE=${LINE/Bridge /}
    echo $LINE
done

