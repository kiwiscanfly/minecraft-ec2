#!/bin/bash

# Minecraft Server Destruction Script
# DESTROYS ALL AWS RESOURCES created by the deployment
# Usage: ./destroy.sh [stack-name] [region] [key-name]

set -e

# Disable AWS CLI pager to prevent vi sessions
export AWS_PAGER=""

# Default values (configured for Sydney deployment)
STACK_NAME=${1:-minecraft-sydney}
REGION=${2:-ap-southeast-2}
KEY_NAME=${3:-minecraft-sydney-key}

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