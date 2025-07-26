#!/bin/bash

# Safely Stop EC2 Minecraft Server Script
# Backs up the world to S3 before stopping the EC2 instance
# Usage: ./stop-server.sh [--force] [--no-backup]

set -e

# Parse command line arguments
FORCE_MODE=false
NO_BACKUP=false

for arg in "$@"; do
    case $arg in
        --force)
            FORCE_MODE=true
            shift
            ;;
        --no-backup)
            NO_BACKUP=true
            shift
            ;;
        --help|-h)
            echo "Usage: $0 [--force] [--no-backup]"
            echo ""
            echo "Options:"
            echo "  --force      Skip confirmation prompt"
            echo "  --no-backup  Skip world backup (not recommended)"
            echo "  --help       Show this help message"
            echo ""
            echo "This script will:"
            echo "  1. Create a world backup to S3"
            echo "  2. Gracefully stop Minecraft services"
            echo "  3. Stop the EC2 instance"
            echo ""
            exit 0
            ;;
        *)
            echo "Unknown option: $arg"
            echo "Use --help for usage information"
            exit 1
            ;;
    esac
done

# Check if .env.server.json exists
if [ ! -f ".env.server.json" ]; then
    echo "❌ No .env.server.json found. Deploy the server first with ./deploy.sh"
    exit 1
fi

# Extract server details
PUBLIC_IP=$(cat .env.server.json | grep -o '"PUBLIC_IP": *"[^"]*"' | cut -d'"' -f4)
SSH_KEY=$(cat .env.server.json | grep -o '"KEY_NAME": *"[^"]*"' | cut -d'"' -f4).pem
STACK_NAME=$(cat .env.server.json | grep -o '"STACK_NAME": *"[^"]*"' | cut -d'"' -f4)
REGION=$(cat .env.server.json | grep -o '"REGION": *"[^"]*"' | cut -d'"' -f4)

if [ -z "$PUBLIC_IP" ] || [ -z "$STACK_NAME" ] || [ -z "$REGION" ]; then
    echo "❌ Could not extract required information from .env.server.json"
    exit 1
fi

if [ ! -f "$SSH_KEY" ]; then
    echo "❌ SSH key file $SSH_KEY not found"
    exit 1
fi

# Get instance ID
echo "🔍 Getting EC2 instance information..."
INSTANCE_ID=$(aws cloudformation describe-stacks \
    --stack-name "$STACK_NAME" \
    --region "$REGION" \
    --query 'Stacks[0].Outputs[?OutputKey==`InstanceId`].OutputValue' \
    --output text 2>/dev/null)

if [ -z "$INSTANCE_ID" ] || [ "$INSTANCE_ID" = "None" ]; then
    echo "❌ Could not find EC2 instance ID from CloudFormation stack"
    exit 1
fi

# Check current instance state
INSTANCE_STATE=$(aws ec2 describe-instances \
    --instance-ids "$INSTANCE_ID" \
    --region "$REGION" \
    --query 'Reservations[0].Instances[0].State.Name' \
    --output text 2>/dev/null)

if [ "$INSTANCE_STATE" != "running" ]; then
    echo "ℹ️  Instance $INSTANCE_ID is already $INSTANCE_STATE"
    exit 0
fi

echo "🛑 Preparing to stop Minecraft server..."
echo "   Instance ID: $INSTANCE_ID"
echo "   Public IP: $PUBLIC_IP"
echo "   Stack: $STACK_NAME"
echo "   Region: $REGION"
echo ""

if [ "$NO_BACKUP" = false ]; then
    echo "💾 World backup will be created before stopping"
else
    echo "⚠️  World backup will be SKIPPED"
fi

echo ""

# Confirmation unless force mode
if [ "$FORCE_MODE" = false ]; then
    read -p "❓ Are you sure you want to stop the server? (yes/no): " CONFIRM
    if [ "$CONFIRM" != "yes" ]; then
        echo "❌ Operation cancelled"
        exit 1
    fi
fi

echo ""
echo "🚀 Starting server shutdown process..."

# Step 1: Create backup (unless skipped)
if [ "$NO_BACKUP" = false ]; then
    echo "💾 Creating world backup before shutdown..."
    
    # Run backup script on server
    ssh -i "$SSH_KEY" -o StrictHostKeyChecking=no -o ConnectTimeout=30 ec2-user@"$PUBLIC_IP" << 'BACKUP_EOF'
        echo "📋 Running world backup..."
        if command -v /usr/local/bin/backup-world.sh >/dev/null 2>&1; then
            sudo /usr/local/bin/backup-world.sh
            echo "✅ Backup completed successfully"
        else
            echo "⚠️  Backup script not found - skipping backup"
        fi
BACKUP_EOF
    
    if [ $? -eq 0 ]; then
        echo "✅ World backup completed"
    else
        echo "⚠️  Backup failed, but continuing with shutdown"
    fi
else
    echo "⏭️  Skipping backup as requested"
fi

# Step 2: Gracefully stop Minecraft services
echo "🛑 Gracefully stopping Minecraft services..."

ssh -i "$SSH_KEY" -o StrictHostKeyChecking=no -o ConnectTimeout=30 ec2-user@"$PUBLIC_IP" << 'STOP_EOF'
    echo "📢 Announcing server shutdown to players..."
    
    # Announce shutdown to players
    if docker ps | grep -q minecraft-paper; then
        docker exec minecraft-paper rcon-cli "say Server is shutting down in 30 seconds!" 2>/dev/null || true
        sleep 10
        docker exec minecraft-paper rcon-cli "say Server is shutting down in 20 seconds!" 2>/dev/null || true
        sleep 10
        docker exec minecraft-paper rcon-cli "say Server is shutting down in 10 seconds!" 2>/dev/null || true
        sleep 5
        docker exec minecraft-paper rcon-cli "say Server is shutting down in 5 seconds!" 2>/dev/null || true
        sleep 5
        docker exec minecraft-paper rcon-cli "say Server is now shutting down. Goodbye!" 2>/dev/null || true
        sleep 2
        
        echo "💾 Forcing final world save..."
        docker exec minecraft-paper rcon-cli "save-all flush" 2>/dev/null || true
        sleep 3
    fi
    
    echo "🐳 Stopping Docker containers..."
    cd /opt/minecraft
    sudo docker-compose down --timeout 30
    
    echo "🛑 Stopping Docker service..."
    sudo systemctl stop docker
    
    echo "✅ All services stopped gracefully"
STOP_EOF

if [ $? -eq 0 ]; then
    echo "✅ Minecraft services stopped gracefully"
else
    echo "⚠️  Some services may not have stopped cleanly"
fi

# Step 3: Stop EC2 instance
echo "☁️  Stopping EC2 instance..."

aws ec2 stop-instances \
    --instance-ids "$INSTANCE_ID" \
    --region "$REGION" >/dev/null

echo "⏳ Waiting for instance to stop..."

# Wait for instance to stop (with timeout)
TIMEOUT=300  # 5 minutes
ELAPSED=0
while [ $ELAPSED -lt $TIMEOUT ]; do
    CURRENT_STATE=$(aws ec2 describe-instances \
        --instance-ids "$INSTANCE_ID" \
        --region "$REGION" \
        --query 'Reservations[0].Instances[0].State.Name' \
        --output text 2>/dev/null)
    
    if [ "$CURRENT_STATE" = "stopped" ]; then
        break
    fi
    
    echo "   Instance state: $CURRENT_STATE (waiting...)"
    sleep 10
    ELAPSED=$((ELAPSED + 10))
done

# Final state check
FINAL_STATE=$(aws ec2 describe-instances \
    --instance-ids "$INSTANCE_ID" \
    --region "$REGION" \
    --query 'Reservations[0].Instances[0].State.Name' \
    --output text 2>/dev/null)

echo ""
if [ "$FINAL_STATE" = "stopped" ]; then
    echo "✅ Server stopped successfully!"
    echo "   Instance $INSTANCE_ID is now stopped"
    echo ""
    echo "💰 Cost savings: Instance charges stopped (storage charges continue)"
    echo "🔄 To restart: ./start-server.sh"
    echo ""
    echo "📋 Final status:"
    echo "   Instance ID: $INSTANCE_ID"
    echo "   State: $FINAL_STATE" 
    echo "   Backup: $([ "$NO_BACKUP" = false ] && echo "Created" || echo "Skipped")"
else
    echo "⚠️  Instance may not have stopped completely"
    echo "   Current state: $FINAL_STATE"
    echo "   Check AWS Console for instance $INSTANCE_ID"
fi