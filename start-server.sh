#!/bin/bash

# Safely Start EC2 Minecraft Server Script
# Starts the EC2 instance and all Minecraft services
# Usage: ./start-server.sh [--force]

set -e

# Parse command line arguments
FORCE_MODE=false

for arg in "$@"; do
    case $arg in
        --force)
            FORCE_MODE=true
            shift
            ;;
        --help|-h)
            echo "Usage: $0 [--force]"
            echo ""
            echo "Options:"
            echo "  --force  Skip confirmation prompt"
            echo "  --help   Show this help message"
            echo ""
            echo "This script will:"
            echo "  1. Start the EC2 instance"
            echo "  2. Wait for instance to be ready"
            echo "  3. Start Docker and Minecraft services"
            echo "  4. Show connection information"
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

echo "🚀 Preparing to start Minecraft server..."
echo "   Instance ID: $INSTANCE_ID"
echo "   Current State: $INSTANCE_STATE"
echo "   Public IP: $PUBLIC_IP"
echo "   Stack: $STACK_NAME"
echo "   Region: $REGION"
echo ""

if [ "$INSTANCE_STATE" = "running" ]; then
    echo "ℹ️  Instance is already running"
    echo "🔍 Checking if Minecraft services are running..."
    
    # Check if services are running
    if ssh -i "$SSH_KEY" -o StrictHostKeyChecking=no -o ConnectTimeout=10 ec2-user@"$PUBLIC_IP" 'docker ps | grep -q minecraft-paper' 2>/dev/null; then
        echo "✅ Minecraft services are already running"
        echo ""
        echo "🌐 Connection Information:"
        echo "   Java Edition: $PUBLIC_IP:25565"
        echo "   Bedrock Edition: $PUBLIC_IP:19132"
        echo "   Nintendo Switch DNS: $PUBLIC_IP"
        exit 0
    else
        echo "⚠️  Instance is running but Minecraft services are stopped"
        echo "🔄 Will restart Minecraft services..."
    fi
elif [ "$INSTANCE_STATE" = "stopped" ]; then
    # Confirmation unless force mode
    if [ "$FORCE_MODE" = false ]; then
        read -p "❓ Start the Minecraft server? (yes/no): " CONFIRM
        if [ "$CONFIRM" != "yes" ]; then
            echo "❌ Operation cancelled"
            exit 1
        fi
    fi
else
    echo "⚠️  Instance is in state: $INSTANCE_STATE"
    echo "❌ Cannot start instance in this state. Check AWS Console."
    exit 1
fi

echo ""
echo "🚀 Starting server..."

# Step 1: Start EC2 instance (if stopped)
if [ "$INSTANCE_STATE" = "stopped" ]; then
    echo "☁️  Starting EC2 instance..."
    
    aws ec2 start-instances \
        --instance-ids "$INSTANCE_ID" \
        --region "$REGION" >/dev/null
    
    echo "⏳ Waiting for instance to start..."
    
    # Wait for instance to be running
    TIMEOUT=300  # 5 minutes
    ELAPSED=0
    while [ $ELAPSED -lt $TIMEOUT ]; do
        CURRENT_STATE=$(aws ec2 describe-instances \
            --instance-ids "$INSTANCE_ID" \
            --region "$REGION" \
            --query 'Reservations[0].Instances[0].State.Name' \
            --output text 2>/dev/null)
        
        if [ "$CURRENT_STATE" = "running" ]; then
            echo "✅ Instance is now running"
            break
        fi
        
        echo "   Instance state: $CURRENT_STATE (waiting...)"
        sleep 10
        ELAPSED=$((ELAPSED + 10))
    done
    
    if [ "$CURRENT_STATE" != "running" ]; then
        echo "❌ Instance failed to start within timeout"
        exit 1
    fi
    
    # Wait for SSH to be available
    echo "⏳ Waiting for SSH to become available..."
    TIMEOUT=180  # 3 minutes
    ELAPSED=0
    while [ $ELAPSED -lt $TIMEOUT ]; do
        if ssh -i "$SSH_KEY" -o StrictHostKeyChecking=no -o ConnectTimeout=5 ec2-user@"$PUBLIC_IP" 'echo "SSH Ready"' >/dev/null 2>&1; then
            echo "✅ SSH is now available"
            break
        fi
        
        echo "   SSH not ready yet (waiting...)"
        sleep 10
        ELAPSED=$((ELAPSED + 10))
    done
    
    if [ $ELAPSED -ge $TIMEOUT ]; then
        echo "❌ SSH failed to become available within timeout"
        exit 1
    fi
fi

# Step 2: Start Minecraft services
echo "🐳 Starting Minecraft services..."

ssh -i "$SSH_KEY" -o StrictHostKeyChecking=no -o ConnectTimeout=30 ec2-user@"$PUBLIC_IP" << 'START_EOF'
    echo "🔄 Starting Docker service..."
    sudo systemctl start docker
    
    # Wait for Docker to be ready
    echo "⏳ Waiting for Docker to be ready..."
    TIMEOUT=60
    ELAPSED=0
    while [ $ELAPSED -lt $TIMEOUT ]; do
        if sudo docker ps >/dev/null 2>&1; then
            echo "✅ Docker is ready"
            break
        fi
        sleep 2
        ELAPSED=$((ELAPSED + 2))
    done
    
    if [ $ELAPSED -ge $TIMEOUT ]; then
        echo "❌ Docker failed to start properly"
        exit 1
    fi
    
    echo "🚀 Starting Minecraft containers..."
    cd /opt/minecraft
    
    # Start all services
    sudo docker-compose up -d
    
    echo "⏳ Waiting for services to initialize..."
    sleep 15
    
    echo "📊 Service Status:"
    docker ps --format "table {{.Names}}\t{{.Status}}\t{{.Ports}}"
    
    echo ""
    echo "✅ All services started successfully!"
START_EOF

if [ $? -ne 0 ]; then
    echo "❌ Failed to start Minecraft services"
    exit 1
fi

# Step 3: Wait for Minecraft server to be fully ready
echo "⏳ Waiting for Minecraft server to fully start..."
sleep 30

# Test connectivity
echo "🔍 Testing server connectivity..."

# Test Java Edition port
if nc -z -w5 "$PUBLIC_IP" 25565 2>/dev/null; then
    echo "✅ Java Edition port (25565) responding"
else
    echo "⚠️  Java Edition port not yet responding (may still be starting)"
fi

# Test Bedrock port
if nc -z -u -w5 "$PUBLIC_IP" 19132 2>/dev/null; then
    echo "✅ Bedrock Edition port (19132) responding"
else
    echo "⚠️  Bedrock Edition port not yet responding (may still be starting)"
fi

echo ""
echo "🎉 Server startup completed!"
echo ""
echo "🌐 Connection Information:"
echo "   Java Edition: $PUBLIC_IP:25565"
echo "   Bedrock Edition: $PUBLIC_IP:19132"
echo "   Nintendo Switch DNS: $PUBLIC_IP"
echo ""
echo "📱 Nintendo Switch Setup:"
echo "   1. Set Primary DNS to: $PUBLIC_IP"
echo "   2. Set Secondary DNS to: 8.8.8.8"
echo "   3. Connect to any Featured Server"
echo ""
echo "🔍 To check server status:"
echo "   ./diagnostics.sh"
echo ""
echo "💡 If services are still starting, wait a few more minutes and check with ./diagnostics.sh"