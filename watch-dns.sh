#!/bin/bash

# DNS Query Monitoring Script
# Run this from your LOCAL machine to watch DNS queries in real-time
# Usage: ./watch-dns.sh [public-ip]

PUBLIC_IP="$1"

if [ -z "$PUBLIC_IP" ]; then
    echo "Usage: $0 <public-ip>"
    echo "Example: $0 16.176.252.122"
    exit 1
fi

echo "🔍 DNS Query Monitor for Nintendo Switch"
echo "========================================"
echo "Server: $PUBLIC_IP"
echo "Press Ctrl+C to stop monitoring"
echo ""
echo "Waiting for DNS queries..."
echo ""

# SSH into server and monitor DNS logs in real-time
ssh -i minecraft-sydney-key.pem ec2-user@"$PUBLIC_IP" << 'EOF'
echo "📡 Starting DNS query monitoring..."
echo "When you use your Nintendo Switch, queries will appear here:"
echo ""

# Function to monitor DNS queries
monitor_dns() {
    # Follow the DNS container logs
    docker logs -f minecraft-dns 2>&1 | while read line; do
        # Highlight important queries
        if echo "$line" | grep -E "(mco\.|geo\.|play\.)" >/dev/null; then
            echo "🎮 [$(date +%H:%M:%S)] MINECRAFT QUERY: $line"
        elif echo "$line" | grep -i "query" >/dev/null; then
            echo "📥 [$(date +%H:%M:%S)] DNS Query: $line"
        elif echo "$line" | grep -i "error" >/dev/null; then
            echo "❌ [$(date +%H:%M:%S)] ERROR: $line"
        elif echo "$line" | grep -E "(A Record:|FORWARDER:|Nintendo)" >/dev/null; then
            echo "ℹ️  [$(date +%H:%M:%S)] $line"
        fi
    done
}

# Alternative: Use tcpdump if available
monitor_tcpdump() {
    echo "📦 Monitoring DNS packets with tcpdump..."
    sudo tcpdump -i any -n port 53 2>/dev/null | while read line; do
        if echo "$line" | grep -E "(mco\.|geo\.|play\.)" >/dev/null; then
            echo "🎮 [NINTENDO] $line"
        else
            echo "📥 $line"
        fi
    done
}

# Check if we can use tcpdump
if command -v tcpdump >/dev/null 2>&1; then
    echo "Choose monitoring method:"
    echo "1) Docker logs (recommended)"
    echo "2) tcpdump (packet level)"
    read -p "Selection (1 or 2): " choice
    
    case $choice in
        2) monitor_tcpdump ;;
        *) monitor_dns ;;
    esac
else
    monitor_dns
fi
EOF