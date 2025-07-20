#!/bin/bash

# Minecraft World Backup Script
# Run this ON the EC2 instance via SSH
# Usage: ./backup-world.sh [stack-name] [region]

set -e

# Default values
STACK_NAME=${1:-minecraft-sydney}
REGION=${2:-ap-southeast-2}
TIMESTAMP=$(date +"%Y-%m-%d_%H-%M-%S")
BACKUP_NAME="minecraft-world-backup-${TIMESTAMP}"

echo "📦 Minecraft World Backup Tool"
echo "=============================="
echo "Stack: $STACK_NAME"
echo "Region: $REGION"
echo "Timestamp: $TIMESTAMP"
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
    echo "💡 Make sure the stack is deployed and includes the backup bucket"
    exit 1
fi

echo "✅ Found backup bucket: $BUCKET_NAME"
echo ""

# Check if Minecraft server is running
echo "🎮 Checking Minecraft server status..."
if docker ps | grep -q minecraft-paper; then
    echo "✅ Minecraft server is running"
    
    # Save the world and disable auto-save to ensure consistency
    echo "💾 Forcing world save and disabling auto-save..."
    docker exec minecraft-paper rcon-cli save-off
    docker exec minecraft-paper rcon-cli save-all flush
    sleep 5
    
    WORLD_SAVED=true
else
    echo "⚠️  Minecraft server is not running - backing up as-is"
    WORLD_SAVED=false
fi

# Create temporary backup directory
BACKUP_DIR="/tmp/$BACKUP_NAME"
mkdir -p "$BACKUP_DIR"

echo "📁 Creating backup archive..."

# Copy world data from Docker volume
echo "  📂 Copying world data..."
docker run --rm \
    -v minecraft_minecraft_data:/source:ro \
    -v "$BACKUP_DIR":/backup \
    busybox sh -c "
        cd /source && 
        tar czf /backup/world-data.tar.gz world world_nether world_the_end server.properties whitelist.json ops.json banned-players.json banned-ips.json
    "

# Copy plugin data
echo "  🔌 Copying plugin data..."
docker run --rm \
    -v minecraft_minecraft_plugins:/source:ro \
    -v "$BACKUP_DIR":/backup \
    busybox sh -c "
        cd /source && 
        tar czf /backup/plugins.tar.gz .
    "

# Create metadata file
echo "📝 Creating backup metadata..."
cat > "$BACKUP_DIR/backup-info.json" << EOF
{
    "backup_name": "$BACKUP_NAME",
    "timestamp": "$TIMESTAMP",
    "stack_name": "$STACK_NAME",
    "region": "$REGION",
    "server_version": "$(docker exec minecraft-paper cat /data/version 2>/dev/null || echo 'unknown')",
    "world_saved": $WORLD_SAVED,
    "backup_size_mb": "$(du -sm $BACKUP_DIR | cut -f1)"
}
EOF

# Re-enable auto-save if we disabled it
if [ "$WORLD_SAVED" = true ]; then
    echo "🔄 Re-enabling auto-save..."
    docker exec minecraft-paper rcon-cli save-on
fi

# Upload to S3
echo "☁️  Uploading backup to S3..."
aws s3 sync "$BACKUP_DIR" "s3://$BUCKET_NAME/$BACKUP_NAME/" --region "$REGION"

# Cleanup local backup
echo "🧹 Cleaning up local files..."
rm -rf "$BACKUP_DIR"

# Get backup size
BACKUP_SIZE=$(aws s3api head-object \
    --bucket "$BUCKET_NAME" \
    --key "$BACKUP_NAME/world-data.tar.gz" \
    --region "$REGION" \
    --query 'ContentLength' \
    --output text 2>/dev/null || echo "0")

BACKUP_SIZE_MB=$((BACKUP_SIZE / 1024 / 1024))

echo ""
echo "✅ Backup completed successfully!"
echo "📊 Backup Details:"
echo "   Name: $BACKUP_NAME"
echo "   S3 Location: s3://$BUCKET_NAME/$BACKUP_NAME/"
echo "   Size: ${BACKUP_SIZE_MB}MB"
echo ""
echo "📋 Available backups:"
aws s3 ls "s3://$BUCKET_NAME/" --region "$REGION" | grep "PRE minecraft-world-backup" | tail -5
echo ""
echo "💡 To restore: ./restore-world.sh $BACKUP_NAME"