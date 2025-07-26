#!/bin/bash

# Minecraft World Upload/Restore Script
# Uploads and restores a local world backup to the server
# Usage: ./upload-world.sh <backup-directory> [--force]

set -e

if [ $# -lt 1 ]; then
    echo "Usage: $0 <backup-directory> [--force]"
    echo ""
    echo "Examples:"
    echo "  $0 ./world-downloads/minecraft-world-2024-01-20_15-30-45"
    echo "  $0 ~/minecraft-backups/my-world --force"
    echo ""
    echo "Options:"
    echo "  --force    Skip confirmation prompt"
    exit 1
fi

BACKUP_DIR="$1"
FORCE_MODE="$2"

# Check if backup directory exists
if [ ! -d "$BACKUP_DIR" ]; then
    echo "❌ Backup directory not found: $BACKUP_DIR"
    exit 1
fi

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

# Check backup directory contents
echo "🔍 Checking backup directory contents..."
if [ ! -f "$BACKUP_DIR/world-data.tar.gz" ]; then
    echo "❌ world-data.tar.gz not found in backup directory"
    echo "💡 Make sure you're pointing to a directory created by download-world.sh"
    exit 1
fi

# Show backup info if available
if [ -f "$BACKUP_DIR/server-info.json" ]; then
    echo "📋 Backup Information:"
    cat "$BACKUP_DIR/server-info.json"
    echo ""
fi

# Warning and confirmation
echo "⚠️  WARNING: This will REPLACE the current world on the server!"
echo "   Server IP: $PUBLIC_IP"
echo "   Backup from: $BACKUP_DIR"
echo ""
echo "🔄 This process will:"
echo "   1. Stop the Minecraft server"
echo "   2. Backup current world (just in case)"
echo "   3. Upload and restore your backup"
echo "   4. Restart the server"
echo ""

if [ "$FORCE_MODE" != "--force" ]; then
    read -p "❓ Are you sure you want to continue? (yes/no): " CONFIRM
    if [ "$CONFIRM" != "yes" ]; then
        echo "❌ Operation cancelled"
        exit 1
    fi
fi

echo ""
echo "🚀 Starting world restore process..."

# Create temporary directory name
TIMESTAMP=$(date +"%Y-%m-%d_%H-%M-%S")
TEMP_UPLOAD_DIR="/tmp/minecraft-world-upload-$TIMESTAMP"

echo "📤 Uploading backup files to server..."
scp -i "$SSH_KEY" -o StrictHostKeyChecking=no -r "$BACKUP_DIR" ec2-user@"$PUBLIC_IP":"$TEMP_UPLOAD_DIR"

echo "🔄 Restoring world on server..."

ssh -i "$SSH_KEY" -o StrictHostKeyChecking=no ec2-user@"$PUBLIC_IP" << REMOTE_EOF
    set -e
    
    echo "🛑 Stopping Minecraft server..."
    cd /opt/minecraft
    docker-compose down || true
    
    echo "💾 Creating safety backup of current world..."
    SAFETY_BACKUP="/tmp/current-world-backup-$TIMESTAMP"
    mkdir -p "\$SAFETY_BACKUP"
    
    # Backup current world data
    docker run --rm \
        -v minecraft_minecraft_data:/source:ro \
        -v "\$SAFETY_BACKUP":/backup \
        busybox sh -c "
            cd /source && 
            tar czf /backup/current-world-data.tar.gz \
                world world_nether world_the_end \
                server.properties whitelist.json ops.json \
                banned-players.json banned-ips.json \
                usercache.json eula.txt \
                2>/dev/null || true
        " || echo "⚠️  Could not backup current world (might be empty)"
    
    echo "🗑️  Clearing current world data..."
    # Remove existing world data
    docker run --rm \
        -v minecraft_minecraft_data:/data \
        busybox sh -c "
            rm -rf /data/world /data/world_nether /data/world_the_end
            rm -f /data/server.properties /data/whitelist.json /data/ops.json
            rm -f /data/banned-players.json /data/banned-ips.json /data/usercache.json
        " || echo "⚠️  Some files might not exist"
    
    echo "📦 Extracting and restoring backup..."
    cd "$TEMP_UPLOAD_DIR"
    
    # Extract world data to Docker volume
    docker run --rm \
        -v "$TEMP_UPLOAD_DIR":/backup:ro \
        -v minecraft_minecraft_data:/data \
        busybox sh -c "
            cd /backup &&
            tar -xzf world-data.tar.gz -C /data/
        "
    
    # Extract plugins if they exist
    if [ -f "plugins.tar.gz" ]; then
        echo "🔌 Restoring plugins..."
        docker run --rm \
            -v "$TEMP_UPLOAD_DIR":/backup:ro \
            -v minecraft_minecraft_plugins:/plugins \
            busybox sh -c "
                cd /backup &&
                rm -rf /plugins/* &&
                tar -xzf plugins.tar.gz -C /plugins/
            "
    fi
    
    echo "🔧 Setting correct permissions..."
    # Fix ownership of restored files
    docker run --rm \
        -v minecraft_minecraft_data:/data \
        -v minecraft_minecraft_plugins:/plugins \
        busybox sh -c "
            chown -R 1000:1000 /data /plugins
        "
    
    echo "🚀 Starting Minecraft server..."
    cd /opt/minecraft
    docker-compose up -d
    
    echo "⏳ Waiting for server to start..."
    sleep 15
    
    echo "📊 Checking server status..."
    docker ps --format "table {{.Names}}\\t{{.Status}}\\t{{.Ports}}"
    
    echo "🧹 Cleaning up temporary files..."
    rm -rf "$TEMP_UPLOAD_DIR"
    
    echo "✅ World restore completed!"
    echo "💾 Current world backed up to: \$SAFETY_BACKUP"
    echo "🌍 Your restored world is now running!"
    
    # Give server a moment to fully start
    sleep 5
    
    # Try to get player list to verify server is working
    if docker exec minecraft-paper rcon-cli list 2>/dev/null; then
        echo "✅ Server is responding to commands"
    else
        echo "⚠️  Server may still be starting up - check logs if needed"
    fi
REMOTE_EOF

echo ""
echo "🎉 World restore completed successfully!"
echo "🌐 Server IP: $PUBLIC_IP"
echo "🎮 Java Edition: $PUBLIC_IP:25565"
echo "📱 Bedrock Edition: $PUBLIC_IP:19132"
echo ""
echo "🔍 To check server status:"
echo "   ./diagnostics.sh"
echo ""
echo "📋 To view server logs:"
echo "   ssh -i $SSH_KEY ec2-user@$PUBLIC_IP 'docker logs minecraft-paper'"