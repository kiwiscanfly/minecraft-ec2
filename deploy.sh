#!/bin/bash

# Minecraft Server Deployment Script
# Usage: ./deploy.sh [stack-name] [key-name] [instance-type] [region]

set -e

# Disable AWS CLI pager to prevent vi sessions
export AWS_PAGER=""

# Default values (configured for Sydney deployment)
STACK_NAME=${1:-minecraft-sydney}
KEY_NAME=${2:-minecraft-sydney-key}
INSTANCE_TYPE=${3:-t4g.medium}
REGION=${4:-ap-southeast-2}
SSH_LOCATION=${5:-0.0.0.0/0}

echo "🚀 Deploying Minecraft Server Infrastructure..."
echo "Stack Name: $STACK_NAME"
echo "Key Name: $KEY_NAME"
echo "Instance Type: $INSTANCE_TYPE"
echo "Region: $REGION"
echo ""

# Check if AWS CLI is configured
if ! aws sts get-caller-identity &>/dev/null; then
    echo "❌ AWS CLI not configured. Please run 'aws configure' first."
    exit 1
fi

# Create key pair if it doesn't exist
echo "🔑 Checking/Creating EC2 Key Pair..."
if ! aws ec2 describe-key-pairs --key-names "$KEY_NAME" --region "$REGION" &>/dev/null; then
    echo "Creating new key pair: $KEY_NAME"
    aws ec2 create-key-pair \
        --key-name "$KEY_NAME" \
        --query 'KeyMaterial' \
        --output text \
        --region "$REGION" > "${KEY_NAME}.pem"
    chmod 400 "${KEY_NAME}.pem"
    echo "✅ Key pair created and saved as ${KEY_NAME}.pem"
else
    echo "✅ Key pair $KEY_NAME already exists"
fi

# Check if stack already exists
if aws cloudformation describe-stacks --stack-name "$STACK_NAME" --region "$REGION" &>/dev/null; then
    echo "⚠️  Stack $STACK_NAME already exists. Updating..."
    ACTION="update-stack"
else
    echo "📦 Creating new stack: $STACK_NAME"
    ACTION="create-stack"
fi

# Deploy CloudFormation stack
echo "🔨 Deploying CloudFormation stack..."
aws cloudformation $ACTION \
    --stack-name "$STACK_NAME" \
    --template-body file://minecraft-bedrock-server.yaml \
    --parameters \
        ParameterKey=KeyName,ParameterValue="$KEY_NAME" \
        ParameterKey=InstanceType,ParameterValue="$INSTANCE_TYPE" \
        ParameterKey=SSHLocation,ParameterValue="$SSH_LOCATION" \
    --capabilities CAPABILITY_NAMED_IAM \
    --region "$REGION"

# Wait for stack completion
echo "⏳ Waiting for stack deployment to complete..."
if [ "$ACTION" = "create-stack" ]; then
    aws cloudformation wait stack-create-complete \
        --stack-name "$STACK_NAME" \
        --region "$REGION"
else
    aws cloudformation wait stack-update-complete \
        --stack-name "$STACK_NAME" \
        --region "$REGION"
fi

# Get stack outputs
echo "📊 Getting stack outputs..."
OUTPUTS=$(aws cloudformation describe-stacks \
    --stack-name "$STACK_NAME" \
    --query 'Stacks[0].Outputs' \
    --region "$REGION" \
    --output table)

echo ""
echo "🎉 Deployment Complete!"
echo ""
echo "$OUTPUTS"
echo ""

# Get the public IP for convenience
PUBLIC_IP=$(aws cloudformation describe-stacks \
    --stack-name "$STACK_NAME" \
    --query 'Stacks[0].Outputs[?OutputKey==`PublicIP`].OutputValue' \
    --output text \
    --region "$REGION")

# Create .env.server.json file with deployment variables
echo "📝 Creating .env.server.json with deployment variables..."
cat > .env.server.json << EOF
{
  "STACK_NAME": "$STACK_NAME",
  "KEY_NAME": "$KEY_NAME",
  "INSTANCE_TYPE": "$INSTANCE_TYPE",
  "REGION": "$REGION",
  "SSH_LOCATION": "$SSH_LOCATION",
  "PUBLIC_IP": "$PUBLIC_IP",
  "DEPLOYED_AT": "$(date -u +"%Y-%m-%dT%H:%M:%SZ")"
}
EOF
echo "✅ Created .env.server.json with deployment variables"

# Upload setup script and configuration files to the server
echo "📤 Uploading setup script to server..."
scp -i "${KEY_NAME}.pem" -o StrictHostKeyChecking=no setup.sh ec2-user@"$PUBLIC_IP":~/

# Upload world configuration if it exists
if [ -f ".env.world.json" ]; then
    echo "📤 Uploading world configuration (.env.world.json)..."
    scp -i "${KEY_NAME}.pem" -o StrictHostKeyChecking=no .env.world.json ec2-user@"$PUBLIC_IP":~/
elif [ -f ".env.world.json.example" ]; then
    echo "📤 Uploading example world configuration (.env.world.json.example)..."
    scp -i "${KEY_NAME}.pem" -o StrictHostKeyChecking=no .env.world.json.example ec2-user@"$PUBLIC_IP":~/
else
    echo "⚠️  No world configuration found - server will use built-in defaults"
fi

echo "🔧 Running Minecraft setup script on server..."
if ssh -i "${KEY_NAME}.pem" -o ConnectTimeout=30 -o StrictHostKeyChecking=no ec2-user@"$PUBLIC_IP" "sudo ./setup.sh $PUBLIC_IP $STACK_NAME $REGION"; then
    echo "✅ Minecraft setup completed successfully!"
else
    echo "❌ Setup script failed. You can run it manually:"
    echo "   ssh -i ${KEY_NAME}.pem ec2-user@$PUBLIC_IP 'sudo ./setup.sh $PUBLIC_IP $STACK_NAME $REGION'"
fi

echo ""
echo "🌐 Your Minecraft server details:"
echo "   Public IP: $PUBLIC_IP"
echo "   Java Edition: $PUBLIC_IP:25565"
echo "   Bedrock Edition: $PUBLIC_IP:19132"
echo "   DNS Server (for Nintendo Switch): $PUBLIC_IP"
echo ""
echo "🔧 To connect via SSH:"
echo "   ssh -i ${KEY_NAME}.pem ec2-user@$PUBLIC_IP"
echo ""
echo "📱 Nintendo Switch Setup:"
echo "   1. Go to System Settings → Internet → Internet Settings"
echo "   2. Select your WiFi → Change Settings → DNS Settings → Manual"
echo "   3. Primary DNS: $PUBLIC_IP"
echo "   4. Secondary DNS: 8.8.8.8"
echo "   5. Launch Minecraft → Servers → Select any Featured Server"
echo ""
echo "🔍 To check server status:"
echo "   ./diagnostics.sh $PUBLIC_IP"
echo ""
echo "⚠️  Note: Allow a few minutes for all services to fully start."
echo "💥 To destroy all resources: ./destroy.sh $STACK_NAME $REGION"