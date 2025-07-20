#!/bin/bash

# Minecraft World Restore Script
# Run this ON the EC2 instance via SSH
# Usage: ./restore-world.sh [backup-name] [stack-name] [region]

set -e

# Check if backup name provided
if [ -z "$1" ]; then
    echo "❌ Please provide a backup name"
    echo "Usage: $0 <backup-name> [stack-name] [region]"
    echo ""
    echo "Available backups:"
    aws s3 ls s3://minecraft-sydney-minecraft-backups-*/  2>/dev/null | grep "PRE minecraft-world-backup" | tail -10 || echo "No backups found"
    exit 1
fi

# Default values
BACKUP_NAME="$1"
STACK_NAME=${2:-minecraft-sydney}
REGION=${3:-ap-southeast-2}

echo "🔄 Minecraft World Restore Tool"
echo "==============================="
echo "Backup: $BACKUP_NAME"
echo "Stack: $STACK_NAME"
echo "Region: $REGION"
echo ""

# Get S3 bucket name from CloudFormation stack
echo "🔍 Getting S3 bucket name from CloudFormation..."
BUCKET_NAME=$(aws cloudformation describe-stacks \
    --stack-name "$STACK_NAME" \
    --region "$REGION" \
    --query 'Stacks[0].Outputs[?OutputKey==`BackupBucket`].OutputValue' \
    --output text)

if [ -z "$BUCKET_NAME" ] || [ "$BUCKET_NAME" = "None" ]; then
    echo "❌ Could not find backup bucket in CloudFormation stack"
    exit 1
fi

echo "✅ Found backup bucket: $BUCKET_NAME"

# Check if backup exists
echo "🔍 Checking if backup exists..."
if ! aws s3 ls "s3://$BUCKET_NAME/$BACKUP_NAME/" --region "$REGION" >/dev/null 2>&1; then
    echo "❌ Backup '$BACKUP_NAME' not found in bucket"
    echo ""
    echo "Available backups:"
    aws s3 ls "s3://$BUCKET_NAME/" --region "$REGION" | grep "PRE minecraft-world-backup"
    exit 1
fi

echo "✅ Backup found"

# Warning prompt
echo ""
echo "⚠️  WARNING: This will REPLACE your current Minecraft world!"
echo "⚠️  All current progress will be LOST!"
echo ""
read -p "Type 'RESTORE' to confirm: " confirmation
if [ "$confirmation" != "RESTORE" ]; then
    echo "❌ Restore cancelled"
    exit 0
fi

# Check if Minecraft server is running
echo "🛑 Stopping Minecraft server..."
if docker ps | grep -q minecraft-paper; then
    echo "  📢 Notifying players of impending restart..."
    docker exec minecraft-paper rcon-cli say "Server restarting for world restore in 30 seconds!"
    sleep 10
    docker exec minecraft-paper rcon-cli say "Server restarting in 20 seconds!"
    sleep 10
    docker exec minecraft-paper rcon-cli say "Server restarting in 10 seconds!"
    sleep 5
    docker exec minecraft-paper rcon-cli say "Server restarting in 5 seconds!"
    sleep 5
    
    docker-compose -f /opt/minecraft/docker-compose.yml stop minecraft-paper
    echo "✅ Minecraft server stopped"
else
    echo "ℹ️  Minecraft server was not running"
fi

# Create temporary restore directory
RESTORE_DIR="/tmp/restore-$BACKUP_NAME"
mkdir -p "$RESTORE_DIR"

echo "⬇️  Downloading backup from S3..."
aws s3 sync "s3://$BUCKET_NAME/$BACKUP_NAME/" "$RESTORE_DIR/" --region "$REGION"

# Verify backup files exist
if [ ! -f "$RESTORE_DIR/world-data.tar.gz" ]; then
    echo "❌ world-data.tar.gz not found in backup"
    rm -rf "$RESTORE_DIR"
    exit 1
fi

echo "📋 Backup Information:"
if [ -f "$RESTORE_DIR/backup-info.json" ]; then
    cat "$RESTORE_DIR/backup-info.json" | jq . 2>/dev/null || cat "$RESTORE_DIR/backup-info.json"
else
    echo "  No metadata available"
fi
echo ""

# Backup current world (just in case)
echo "💾 Creating safety backup of current world..."
SAFETY_BACKUP="/tmp/pre-restore-backup-$(date +%Y%m%d-%H%M%S)"
mkdir -p "$SAFETY_BACKUP"
docker run --rm \
    -v minecraft_minecraft_data:/source:ro \
    -v "$SAFETY_BACKUP":/backup \
    busybox sh -c "cd /source && tar czf /backup/current-world.tar.gz world world_nether world_the_end server.properties 2>/dev/null || true"

echo "✅ Current world backed up to: $SAFETY_BACKUP"

# Clear current world data
echo "🗑️  Clearing current world data..."
docker run --rm \
    -v minecraft_minecraft_data:/data \
    busybox sh -c "rm -rf /data/world /data/world_nether /data/world_the_end"

# Restore world data
echo "📂 Restoring world data..."
docker run --rm \
    -v minecraft_minecraft_data:/data \
    -v "$RESTORE_DIR":/restore \
    busybox sh -c "cd /data && tar xzf /restore/world-data.tar.gz"

# Restore plugins if available
if [ -f "$RESTORE_DIR/plugins.tar.gz" ]; then
    echo "🔌 Restoring plugin data..."
    docker run --rm \
        -v minecraft_minecraft_plugins:/plugins \
        -v "$RESTORE_DIR":/restore \
        busybox sh -c "cd /plugins && tar xzf /restore/plugins.tar.gz"
fi

# Fix permissions
echo "🔧 Fixing permissions..."
docker run --rm \
    -v minecraft_minecraft_data:/data \
    busybox chown -R 1000:1000 /data

# Cleanup
echo "🧹 Cleaning up..."
rm -rf "$RESTORE_DIR"

# Start Minecraft server
echo "🚀 Starting Minecraft server..."
docker-compose -f /opt/minecraft/docker-compose.yml start minecraft-paper

# Wait for server to start
echo "⏳ Waiting for server to initialize..."
sleep 30

# Check if server started successfully
if docker ps | grep -q minecraft-paper; then
    echo ""
    echo "✅ World restore completed successfully!"
    echo "🎮 Minecraft server is running"
    echo "💾 Safety backup saved at: $SAFETY_BACKUP"
    echo ""
    echo "📊 Server status:"
    docker logs minecraft-paper --tail 5
else
    echo ""
    echo "❌ Server failed to start after restore"
    echo "🔧 Check logs: docker logs minecraft-paper"
    echo "💾 You can find the safety backup at: $SAFETY_BACKUP"
fi