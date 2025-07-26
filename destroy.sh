#!/bin/bash

# Minecraft Server Destruction Script
# DESTROYS ALL AWS RESOURCES created by the deployment
# Usage: ./destroy.sh [stack-name] [region] [key-name]

set -e

# Disable AWS CLI pager to prevent vi sessions
export AWS_PAGER=""

# Function to load variables from .env.json
load_env_json() {
    if [ -f ".env.json" ]; then
        export STACK_NAME_FROM_JSON=$(cat .env.json | grep -o '"STACK_NAME": *"[^"]*"' | cut -d'"' -f4)
        export REGION_FROM_JSON=$(cat .env.json | grep -o '"REGION": *"[^"]*"' | cut -d'"' -f4)
        export KEY_NAME_FROM_JSON=$(cat .env.json | grep -o '"KEY_NAME": *"[^"]*"' | cut -d'"' -f4)
    fi
}

# Load from .env.json if available
load_env_json

# Use parameters or .env.json values or defaults
STACK_NAME=${1:-${STACK_NAME_FROM_JSON:-minecraft-sydney}}
REGION=${2:-${REGION_FROM_JSON:-ap-southeast-2}}
KEY_NAME=${3:-${KEY_NAME_FROM_JSON:-minecraft-sydney-key}}

echo "💥 DESTROYING Minecraft Server Infrastructure..."
echo "Stack Name: $STACK_NAME"
echo "Region: $REGION"
echo ""

# Warning prompt
read -p "⚠️  This will PERMANENTLY DELETE all resources. Type 'DESTROY' to confirm: " confirmation
if [ "$confirmation" != "DESTROY" ]; then
    echo "❌ Destruction cancelled."
    exit 0
fi

echo "🔍 Checking if stack exists..."
if ! aws cloudformation describe-stacks --stack-name "$STACK_NAME" --region "$REGION" &>/dev/null; then
    echo "❌ Stack $STACK_NAME does not exist in region $REGION"
    exit 1
fi

# Get stack resources before deletion for cleanup verification
echo "📋 Getting stack resources..."
aws cloudformation list-stack-resources \
    --stack-name "$STACK_NAME" \
    --region "$REGION" \
    --output table

echo ""
echo "🗑️  Deleting CloudFormation stack..."
aws cloudformation delete-stack \
    --stack-name "$STACK_NAME" \
    --region "$REGION"

echo "⏳ Waiting for stack deletion to complete..."
aws cloudformation wait stack-delete-complete \
    --stack-name "$STACK_NAME" \
    --region "$REGION"

# Optional: Delete the key pair
echo ""
read -p "🔑 Delete EC2 Key Pair '$KEY_NAME'? (y/N): " delete_key
if [[ $delete_key =~ ^[Yy]$ ]]; then
    if aws ec2 describe-key-pairs --key-names "$KEY_NAME" --region "$REGION" &>/dev/null; then
        aws ec2 delete-key-pair --key-name "$KEY_NAME" --region "$REGION"
        echo "✅ Key pair $KEY_NAME deleted"
        
        # Remove local key file if it exists
        if [ -f "${KEY_NAME}.pem" ]; then
            rm "${KEY_NAME}.pem"
            echo "✅ Local key file ${KEY_NAME}.pem deleted"
        fi
    else
        echo "⚠️  Key pair $KEY_NAME not found"
    fi
else
    echo "🔑 Key pair $KEY_NAME preserved"
fi

# Clean up .env.json if it exists
if [ -f ".env.json" ]; then
    echo ""
    read -p "🗑️  Delete .env.json file? (y/N): " delete_env
    if [[ $delete_env =~ ^[Yy]$ ]]; then
        rm .env.json
        echo "✅ .env.json file deleted"
    else
        echo "📋 .env.json file preserved"
    fi
fi

echo ""
echo "✅ DESTRUCTION COMPLETE!"
echo "🔍 All AWS resources have been deleted:"
echo "   - EC2 Instance"
echo "   - Elastic IP"
echo "   - Security Group"
echo "   - VPC, Subnet, Internet Gateway, Route Table"
echo "   - IAM Role and Instance Profile"
echo ""
echo "💰 No further AWS charges will be incurred for this stack."