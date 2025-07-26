#!/bin/bash
set -e

# Minecraft Server Setup Script
# Usage: ./setup.sh <public-ip> <stack-name> <region>

PUBLIC_IP="$1"
STACK_NAME="$2"
REGION="$3"

if [ -z "$PUBLIC_IP" ] || [ -z "$STACK_NAME" ] || [ -z "$REGION" ]; then
    echo "Usage: $0 <public-ip> <stack-name> <region>"
    exit 1
fi

# Function to load world configuration from .env.world.json
load_world_config() {
    # Check for .env.world.json, fallback to example, or use defaults
    if [ -f ".env.world.json" ]; then
        echo "📋 Loading world configuration from .env.world.json"
        CONFIG_FILE=".env.world.json"
    elif [ -f ".env.world.json.example" ]; then
        echo "📋 Loading world configuration from .env.world.json.example (using defaults)"
        CONFIG_FILE=".env.world.json.example"
    else
        echo "⚠️  No world configuration found, using built-in defaults"
        CONFIG_FILE=""
    fi
    
    if [ -n "$CONFIG_FILE" ]; then
        
        # Extract world configuration values
        export WORLD_NAME=$(cat "$CONFIG_FILE" | grep -o '"name": *"[^"]*"' | head -1 | cut -d'"' -f4)
        export WORLD_MODE=$(cat "$CONFIG_FILE" | grep -o '"mode": *"[^"]*"' | cut -d'"' -f4)
        export WORLD_DIFFICULTY=$(cat "$CONFIG_FILE" | grep -o '"difficulty": *"[^"]*"' | cut -d'"' -f4)
        export WORLD_MAX_PLAYERS=$(cat "$CONFIG_FILE" | grep -o '"max_players": *[0-9]*' | cut -d':' -f2 | tr -d ' ')
        export WORLD_VIEW_DISTANCE=$(cat "$CONFIG_FILE" | grep -o '"view_distance": *[0-9]*' | cut -d':' -f2 | tr -d ' ')
        export WORLD_SIMULATION_DISTANCE=$(cat "$CONFIG_FILE" | grep -o '"simulation_distance": *[0-9]*' | cut -d':' -f2 | tr -d ' ')
        export WORLD_MOTD=$(cat "$CONFIG_FILE" | grep -o '"motd": *"[^"]*"' | cut -d'"' -f4)
        export WORLD_PVP=$(cat "$CONFIG_FILE" | grep -o '"pvp": *[a-z]*' | cut -d':' -f2 | tr -d ' ')
        export WORLD_ENABLE_COMMAND_BLOCKS=$(cat "$CONFIG_FILE" | grep -o '"enable_command_blocks": *[a-z]*' | cut -d':' -f2 | tr -d ' ')
        export WORLD_SPAWN_PROTECTION=$(cat "$CONFIG_FILE" | grep -o '"spawn_protection": *[0-9]*' | cut -d':' -f2 | tr -d ' ')
        export WORLD_HARDCORE=$(cat "$CONFIG_FILE" | grep -o '"hardcore": *[a-z]*' | cut -d':' -f2 | tr -d ' ')
        export WORLD_ALLOW_FLIGHT=$(cat "$CONFIG_FILE" | grep -o '"allow_flight": *[a-z]*' | cut -d':' -f2 | tr -d ' ')
        export WORLD_ALLOW_NETHER=$(cat "$CONFIG_FILE" | grep -o '"allow_nether": *[a-z]*' | cut -d':' -f2 | tr -d ' ')
        export WORLD_LEVEL_TYPE=$(cat "$CONFIG_FILE" | grep -o '"level_type": *"[^"]*"' | cut -d'"' -f4)
        export WORLD_LEVEL_SEED=$(cat "$CONFIG_FILE" | grep -o '"level_seed": *"[^"]*"' | cut -d'"' -f4)
        
        # Geyser configuration
        export GEYSER_SERVER_NAME=$(cat "$CONFIG_FILE" | grep -o '"server_name": *"[^"]*"' | cut -d'"' -f4)
        export GEYSER_MOTD1=$(cat "$CONFIG_FILE" | grep -o '"motd1": *"[^"]*"' | cut -d'"' -f4)
        export GEYSER_MOTD2=$(cat "$CONFIG_FILE" | grep -o '"motd2": *"[^"]*"' | cut -d'"' -f4)
        
        # BedrockConnect configuration
        export BC_ICON_URL=$(cat "$CONFIG_FILE" | grep -o '"icon_url": *"[^"]*"' | cut -d'"' -f4)
        
    else
        echo "⚠️  No world configuration files found (.env.world.json or .env.world.json.example)"
        echo "Using minimal built-in defaults - consider creating .env.world.json.example"
        # Minimal fallback defaults
        export WORLD_NAME="My Minecraft Server"
        export WORLD_MODE="survival"
        export WORLD_DIFFICULTY="normal"
        export WORLD_MAX_PLAYERS=20
        export WORLD_VIEW_DISTANCE=10
        export WORLD_SIMULATION_DISTANCE=8
        export WORLD_MOTD="Paper Server with BedrockConnect"
        export WORLD_PVP="true"
        export WORLD_ENABLE_COMMAND_BLOCKS="false"
        export WORLD_SPAWN_PROTECTION=16
        export WORLD_HARDCORE="false"
        export WORLD_ALLOW_FLIGHT="false"
        export WORLD_ALLOW_NETHER="true"
        export WORLD_LEVEL_TYPE="minecraft:normal"
        export WORLD_LEVEL_SEED=""
        export GEYSER_SERVER_NAME="Geyser"
        export GEYSER_MOTD1="Geyser"
        export GEYSER_MOTD2="Minecraft Server"
        export BC_ICON_URL=""
    fi
}

# Load world configuration
load_world_config

echo "Setting up Minecraft server with:"
echo "  Public IP: $PUBLIC_IP"
echo "  Stack Name: $STACK_NAME"
echo "  Region: $REGION"
echo "  World Name: $WORLD_NAME"
echo "  Mode: $WORLD_MODE"
echo "  Difficulty: $WORLD_DIFFICULTY"
echo "  Max Players: $WORLD_MAX_PLAYERS"

# Update system
echo "📦 Updating system packages..."
dnf update -y

# Install Docker if not already installed
if ! command -v docker &> /dev/null; then
    echo "🐳 Installing Docker..."
    dnf install -y docker
    systemctl start docker
    systemctl enable docker
    usermod -a -G docker ec2-user
else
    echo "✅ Docker already installed"
    # Ensure Docker is running
    if ! systemctl is-active --quiet docker; then
        echo "🔄 Starting Docker service..."
        systemctl start docker
    fi
fi

# Install Docker Compose v2 if not already installed
if [ ! -f /usr/local/bin/docker-compose ]; then
    echo "🔧 Installing Docker Compose..."
    DOCKER_COMPOSE_VERSION=$(curl -s https://api.github.com/repos/docker/compose/releases/latest | grep -Po '"tag_name": "\K[^"]*')
    curl -L "https://github.com/docker/compose/releases/download/$DOCKER_COMPOSE_VERSION/docker-compose-$(uname -s)-$(uname -m)" -o /usr/local/bin/docker-compose
    chmod +x /usr/local/bin/docker-compose
    # Create symlink for 'docker compose' command
    mkdir -p /usr/local/lib/docker/cli-plugins
    ln -sf /usr/local/bin/docker-compose /usr/local/lib/docker/cli-plugins/docker-compose
else
    echo "✅ Docker Compose already installed"
fi

# Create directory structure
echo "📁 Setting up directory structure..."
mkdir -p /opt/minecraft/{data,plugins,bedrock-config,dns/zones}
chown -R ec2-user:ec2-user /opt/minecraft

# Stop existing containers if running
if [ -f /opt/minecraft/docker-compose.yml ]; then
    echo "🛑 Stopping existing containers..."
    cd /opt/minecraft
    docker-compose down || true
    cd -
fi

# Create Docker Compose file with IP substitution
echo "📝 Creating Docker Compose configuration..."
cat > /opt/minecraft/docker-compose.yml << EOF
services:
  minecraft-paper:
    image: itzg/minecraft-server
    container_name: minecraft-paper
    restart: unless-stopped
    ports:
      - "25565:25565"
      - "19133:19132/udp"
    environment:
      EULA: "TRUE"
      TYPE: "PAPER"
      VERSION: "1.21.8"
      MEMORY: "2G"
      INIT_MEMORY: "1G"
      MAX_MEMORY: "2G"
      USE_AIKAR_FLAGS: "true"
      JVM_XX_OPTS: >-
        -XX:+UseG1GC
        -XX:+ParallelRefProcEnabled
        -XX:MaxGCPauseMillis=200
        -XX:+UnlockExperimentalVMOptions
        -XX:+DisableExplicitGC
        -XX:+AlwaysPreTouch
        -XX:G1HeapRegionSize=8M
        -XX:G1HeapWastePercent=5
        -XX:G1MixedGCCountTarget=4
        -XX:InitiatingHeapOccupancyPercent=15
        -XX:G1MixedGCLiveThresholdPercent=90
        -XX:G1RSetUpdatingPauseTimePercent=5
        -XX:+PerfDisableSharedMem
      MOTD: "$WORLD_MOTD"
      MODE: "$WORLD_MODE"
      DIFFICULTY: "$WORLD_DIFFICULTY"
      MAX_PLAYERS: $WORLD_MAX_PLAYERS
      VIEW_DISTANCE: $WORLD_VIEW_DISTANCE
      SIMULATION_DISTANCE: $WORLD_SIMULATION_DISTANCE
      PVP: "$WORLD_PVP"
      ENABLE_COMMAND_BLOCK: "$WORLD_ENABLE_COMMAND_BLOCKS"
      SPAWN_PROTECTION: $WORLD_SPAWN_PROTECTION
      HARDCORE: "$WORLD_HARDCORE"
      ALLOW_FLIGHT: "$WORLD_ALLOW_FLIGHT"
      ALLOW_NETHER: "$WORLD_ALLOW_NETHER"
      LEVEL_TYPE: "$WORLD_LEVEL_TYPE"
      SEED: "$WORLD_LEVEL_SEED"
      PLUGINS: |
        https://download.geysermc.org/v2/projects/geyser/versions/latest/builds/latest/downloads/spigot
        https://download.geysermc.org/v2/projects/floodgate/versions/latest/builds/latest/downloads/spigot
        https://hangarcdn.papermc.io/plugins/ViaVersion/ViaVersion/versions/5.4.1/PAPER/ViaVersion-5.4.1.jar
    volumes:
      - minecraft_data:/data
      - minecraft_plugins:/plugins
    networks:
      minecraft_net:
        ipv4_address: 172.20.0.10
    deploy:
      resources:
        limits:
          memory: 2.5G
          cpus: '1.5'
        reservations:
          memory: 2G
          cpus: '1.0'

  bedrock-connect:
    image: strausmann/minecraft-bedrock-connect:2
    container_name: bedrock-connect
    restart: unless-stopped
    ports:
      - "19132:19132/udp"
    environment:
      NODB: "true"
      SERVER_LIMIT: 25
      KICK_INACTIVE: "true"
      CUSTOM_SERVERS: "/config/serverlist.json"
      USER_SERVERS: "false"
      FEATURED_SERVERS: "false"
    volumes:
      - ./bedrock-config:/config
    networks:
      minecraft_net:
        ipv4_address: 172.20.0.20
    deploy:
      resources:
        limits:
          memory: 256M
          cpus: '0.3'
        reservations:
          memory: 128M
          cpus: '0.2'
    depends_on:
      - minecraft-paper

  dns-server:
    image: cytopia/bind:latest
    container_name: minecraft-dns
    restart: unless-stopped
    ports:
      - "53:53/tcp"
      - "53:53/udp"
    environment:
      - DNS_FORWARDER=8.8.8.8,8.8.4.4
      - DNS_A=mco.mineplex.com=$PUBLIC_IP,geo.hivebedrock.network=$PUBLIC_IP,mco.cubecraft.net=$PUBLIC_IP,mco.lbsg.net=$PUBLIC_IP,play.inpvp.net=$PUBLIC_IP,play.galaxite.net=$PUBLIC_IP
      - ALLOW_QUERY=any
      - ALLOW_RECURSION=any
      - DNSSEC_VALIDATE=no
    networks:
      minecraft_net:
        ipv4_address: 172.20.0.5
    deploy:
      resources:
        limits:
          memory: 128M
          cpus: '0.2'

networks:
  minecraft_net:
    driver: bridge
    ipam:
      config:
        - subnet: 172.20.0.0/16

volumes:
  minecraft_data:
    driver: local
  minecraft_plugins:
    driver: local
  bedrock_connect_config:
    driver: local
  dns_cache:
    driver: local
EOF

# Create BedrockConnect server list configuration
# Create directory if it doesn't exist
mkdir -p /opt/minecraft/bedrock-config

cat > /opt/minecraft/bedrock-config/serverlist.json << EOF
[
  {
    "name": "$WORLD_NAME",
    "iconUrl": "$BC_ICON_URL",
    "address": "$PUBLIC_IP",
    "port": 19133
  }
]
EOF

# Set correct permissions for BedrockConnect container (UID 1000)
chown -R 1000:1000 /opt/minecraft/bedrock-config
chmod 644 /opt/minecraft/bedrock-config/serverlist.json

# Create DNS configuration files

# Create BIND9 configuration
cat > /opt/minecraft/dns/named.conf.options << EOF
options {
    directory "/var/cache/bind";
    
    recursion yes;
    allow-query { any; };
    
    forwarders {
        8.8.8.8;
        8.8.4.4;
    };
    
    listen-on { any; };
    listen-on-v6 { none; };
    
    dnssec-validation no;
};
EOF

cat > /opt/minecraft/dns/named.conf.local << EOF
// Minecraft Bedrock Featured Servers
zone "mco.mineplex.com" {
    type master;
    file "/etc/bind/zones/db.minecraft";
};

zone "geo.hivebedrock.network" {
    type master;
    file "/etc/bind/zones/db.minecraft";
};

zone "mco.cubecraft.net" {
    type master;
    file "/etc/bind/zones/db.minecraft";
};

zone "mco.lbsg.net" {
    type master;
    file "/etc/bind/zones/db.minecraft";
};

zone "play.inpvp.net" {
    type master;
    file "/etc/bind/zones/db.minecraft";
};

zone "play.galaxite.net" {
    type master;
    file "/etc/bind/zones/db.minecraft";
};
EOF

# Create zone file that redirects to BedrockConnect
cat > /opt/minecraft/dns/zones/db.minecraft << EOF
\$TTL 60
@       IN      SOA     ns1.minecraft.local. admin.minecraft.local. (
                        2023010101      ; Serial
                        3600            ; Refresh
                        1800            ; Retry
                        604800          ; Expire
                        60 )            ; Negative Cache TTL

@       IN      NS      ns1.minecraft.local.
@       IN      A       172.20.0.20
*       IN      A       172.20.0.20
EOF

# Create Geyser config
mkdir -p /opt/minecraft/plugins/Geyser-Spigot
cat > /opt/minecraft/plugins/Geyser-Spigot/config.yml << EOF
bedrock:
  address: 0.0.0.0
  port: 19132
  clone-remote-port: false
  motd1: "$GEYSER_MOTD1"
  motd2: "$GEYSER_MOTD2"
  server-name: "$GEYSER_SERVER_NAME"

remote:
  address: auto
  port: 25565
  auth-type: floodgate

floodgate:
  use-global-linking: false

debug-mode: false
EOF

# Create Floodgate config
mkdir -p /opt/minecraft/plugins/floodgate
cat > /opt/minecraft/plugins/floodgate/config.yml << EOF
# Floodgate configuration
# This file is automatically generated - do not edit manually

# The prefix for Bedrock players when they join
username-prefix: "."

# Replace spaces in Bedrock usernames with underscores
replace-spaces: true

# Database settings (using default SQLite)
database:
  type: sqlite
  
# Player linking settings  
player-linking:
  enabled: false
  
# Whether to send Floodgate data
send-floodgate-data: true

# Debug mode
debug: false
EOF

# Set permissions
chown -R 1000:1000 /opt/minecraft

# Create backup script
echo "💾 Setting up backup scripts..."
cat > /usr/local/bin/backup-world.sh << BACKUP_EOF
#!/bin/bash
# Minecraft World Backup Script (Auto-generated)
set -e

STACK_NAME="$STACK_NAME"
REGION="$REGION"
TIMESTAMP=$(date +"%Y-%m-%d_%H-%M-%S")
BACKUP_NAME="minecraft-world-backup-$TIMESTAMP"

# Get S3 bucket name
BUCKET_NAME=$(aws cloudformation describe-stacks --stack-name "$STACK_NAME" --region "$REGION" --query 'Stacks[0].Outputs[?OutputKey==`BackupBucket`].OutputValue' --output text)

# Create backup
BACKUP_DIR="/tmp/$BACKUP_NAME"
mkdir -p "$BACKUP_DIR"

# Save world if server is running
if docker ps | grep -q minecraft-paper; then
    docker exec minecraft-paper rcon-cli save-off 2>/dev/null || true
    docker exec minecraft-paper rcon-cli save-all flush 2>/dev/null || true
    sleep 5
fi

# Create world backup
docker run --rm -v minecraft_minecraft_data:/source:ro -v "$BACKUP_DIR":/backup busybox sh -c "cd /source && tar czf /backup/world-data.tar.gz world world_nether world_the_end server.properties whitelist.json ops.json banned-players.json banned-ips.json 2>/dev/null || true"

# Create plugin backup
docker run --rm -v minecraft_minecraft_plugins:/source:ro -v "$BACKUP_DIR":/backup busybox sh -c "cd /source && tar czf /backup/plugins.tar.gz . 2>/dev/null || true"

# Create metadata
cat > "$BACKUP_DIR/backup-info.json" << EOF
{
    "backup_name": "$BACKUP_NAME",
    "timestamp": "$TIMESTAMP",
    "stack_name": "$STACK_NAME",
    "region": "$REGION"
}
EOF

# Re-enable save
if docker ps | grep -q minecraft-paper; then
    docker exec minecraft-paper rcon-cli save-on 2>/dev/null || true
fi

# Upload to S3
aws s3 sync "$BACKUP_DIR" "s3://$BUCKET_NAME/$BACKUP_NAME/" --region "$REGION"

# Cleanup
rm -rf "$BACKUP_DIR"

echo "Backup completed: $BACKUP_NAME"
BACKUP_EOF

chmod +x /usr/local/bin/backup-world.sh

# Set up automated daily backups
mkdir -p /var/log/minecraft-backup
chown ec2-user:ec2-user /var/log/minecraft-backup

# Create backup wrapper with logging
cat > /usr/local/bin/minecraft-backup-wrapper.sh << 'WRAPPER_EOF'
#!/bin/bash
LOGFILE="/var/log/minecraft-backup/backup-$(date +%Y-%m-%d).log"
echo "=== Backup started at $(date) ===" >> "$LOGFILE"
/usr/local/bin/backup-world.sh >> "$LOGFILE" 2>&1
BACKUP_EXIT_CODE=$?
echo "=== Backup finished at $(date) with exit code $BACKUP_EXIT_CODE ===" >> "$LOGFILE"
find /var/log/minecraft-backup/ -name "backup-*.log" -mtime +7 -delete
exit $BACKUP_EXIT_CODE
WRAPPER_EOF

chmod +x /usr/local/bin/minecraft-backup-wrapper.sh

# Install and set up cron for daily backups at 3 AM
if ! command -v crontab &> /dev/null; then
    echo "📅 Installing cron service..."
    dnf install -y cronie
fi

# Ensure cron service is running
systemctl enable crond
systemctl start crond

# Set up backup cron job
echo "⏰ Setting up automated backups..."
mkdir -p /var/spool/cron
echo "0 3 * * * /usr/local/bin/minecraft-backup-wrapper.sh" > /var/spool/cron/ec2-user
chmod 600 /var/spool/cron/ec2-user
chown ec2-user:ec2-user /var/spool/cron/ec2-user
systemctl restart crond

# Start services
echo "🚀 Starting Minecraft services..."
cd /opt/minecraft
docker-compose up -d

# Wait for services to start
echo "⏳ Waiting for services to initialize..."
sleep 10

# Check service status
echo ""
echo "📊 Service Status:"
docker ps --format "table {{.Names}}\t{{.Status}}\t{{.Ports}}"

echo ""
echo "✅ Minecraft server setup completed!"
echo "🌐 Server IP: $PUBLIC_IP"
echo ""
echo "📱 Nintendo Switch Setup:"
echo "   1. Set Primary DNS to: $PUBLIC_IP"
echo "   2. Set Secondary DNS to: 8.8.8.8"
echo "   3. Connect to any Featured Server"
echo ""