#!/bin/bash

# Minecraft World Download Script
# Downloads the current world from the server to your local machine
# Usage: ./download-world.sh [download-directory]

set -e

# Check if .env.server.json exists
if [ ! -f ".env.server.json" ]; then
    echo "❌ No .env.server.json found. Deploy the server first with ./deploy.sh"
    exit 1
fi

# Extract server details
PUBLIC_IP=$(cat .env.server.json | grep -o '"PUBLIC_IP": *"[^"]*"' | cut -d'"' -f4)
SSH_KEY=$(cat .env.server.json | grep -o '"KEY_NAME": *"[^"]*"' | cut -d'"' -f4).pem
STACK_NAME=$(cat .env.server.json | grep -o '"STACK_NAME": *"[^"]*"' | cut -d'"' -f4)

if [ -z "$PUBLIC_IP" ]; then
    echo "❌ Could not find PUBLIC_IP in .env.server.json"
    exit 1
fi

if [ ! -f "$SSH_KEY" ]; then
    echo "❌ SSH key file $SSH_KEY not found"
    exit 1
fi

# Set download directory
DOWNLOAD_DIR=${1:-"./world-downloads"}
TIMESTAMP=$(date +"%Y-%m-%d_%H-%M-%S")
WORLD_BACKUP_DIR="$DOWNLOAD_DIR/minecraft-world-$TIMESTAMP"

echo "🌍 Downloading Minecraft world from server..."
echo "   Server IP: $PUBLIC_IP"
echo "   Download to: $WORLD_BACKUP_DIR"
echo ""

# Create download directory
mkdir -p "$WORLD_BACKUP_DIR"

echo "💾 Creating server-side backup..."

# Create backup on server and download
ssh -i "$SSH_KEY" -o StrictHostKeyChecking=no ec2-user@"$PUBLIC_IP" << REMOTE_EOF
    # Create temporary backup directory
    TEMP_BACKUP="/tmp/minecraft-world-backup-$TIMESTAMP"
    mkdir -p "\$TEMP_BACKUP"
    
    echo "🛑 Temporarily disabling world saves..."
    # Disable saves and flush to disk
    if docker ps | grep -q minecraft-paper; then
        docker exec minecraft-paper rcon-cli save-off 2>/dev/null || true
        docker exec minecraft-paper rcon-cli save-all flush 2>/dev/null || true
        sleep 5
        echo "✅ World saved and locked"
    fi
    
    echo "📦 Creating world backup..."
    # Create comprehensive world backup
    docker run --rm \
        -v minecraft_minecraft_data:/source:ro \
        -v "\$TEMP_BACKUP":/backup \
        busybox sh -c "
            cd /source && 
            tar czf /backup/world-data.tar.gz \
                world world_nether world_the_end \
                server.properties whitelist.json ops.json \
                banned-players.json banned-ips.json \
                usercache.json eula.txt \
                2>/dev/null || true
        "
    
    # Create plugin backup
    echo "🔌 Backing up plugins..."
    docker run --rm \
        -v minecraft_minecraft_plugins:/source:ro \
        -v "\$TEMP_BACKUP":/backup \
        busybox sh -c "
            cd /source && 
            tar czf /backup/plugins.tar.gz . 2>/dev/null || true
        "
    
    # Create server info
    cat > "\$TEMP_BACKUP/server-info.json" << INFO_EOF
{
    "backup_timestamp": "$TIMESTAMP",
    "server_ip": "$PUBLIC_IP",
    "stack_name": "$STACK_NAME",
    "minecraft_version": "1.21.8",
    "server_type": "Paper",
    "backup_type": "world_download"
}
INFO_EOF
    
    # Re-enable saves
    if docker ps | grep -q minecraft-paper; then
        docker exec minecraft-paper rcon-cli save-on 2>/dev/null || true
        echo "✅ World saves re-enabled"
    fi
    
    echo "✅ Server-side backup created at \$TEMP_BACKUP"
REMOTE_EOF

echo "📥 Downloading world files..."

# Download the backup files
scp -i "$SSH_KEY" -o StrictHostKeyChecking=no -r ec2-user@"$PUBLIC_IP":/tmp/minecraft-world-backup-$TIMESTAMP/* "$WORLD_BACKUP_DIR/"

echo "🧹 Cleaning up server-side temporary files..."
ssh -i "$SSH_KEY" -o StrictHostKeyChecking=no ec2-user@"$PUBLIC_IP" "rm -rf /tmp/minecraft-world-backup-$TIMESTAMP"

echo ""
echo "✅ World download completed!"
echo "📁 Downloaded to: $WORLD_BACKUP_DIR"
echo ""
echo "📋 Contents:"
ls -la "$WORLD_BACKUP_DIR"

echo ""
echo "🔄 To extract the world data:"
echo "   cd $WORLD_BACKUP_DIR"
echo "   tar -xzf world-data.tar.gz"
echo "   tar -xzf plugins.tar.gz -C plugins/"
echo ""
echo "📊 Backup info:"
if [ -f "$WORLD_BACKUP_DIR/server-info.json" ]; then
    cat "$WORLD_BACKUP_DIR/server-info.json"
fi

# Create extraction script for convenience
cat > "$WORLD_BACKUP_DIR/extract.sh" << 'EXTRACT_EOF'
#!/bin/bash
echo "🗂️ Extracting Minecraft world backup..."
tar -xzf world-data.tar.gz
mkdir -p plugins
tar -xzf plugins.tar.gz -C plugins/
echo "✅ Extraction completed!"
echo "📁 World files extracted to current directory"
echo "🔌 Plugins extracted to plugins/ directory"
EXTRACT_EOF

chmod +x "$WORLD_BACKUP_DIR/extract.sh"

echo "💡 Quick extract: cd $WORLD_BACKUP_DIR && ./extract.sh"