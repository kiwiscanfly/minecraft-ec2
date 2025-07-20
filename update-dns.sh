#!/bin/bash

# Update DNS Configuration Script
# Run this to update the DNS server configuration on the deployed server
# Usage: ./update-dns.sh [public-ip]

set -e

PUBLIC_IP="$1"

if [ -z "$PUBLIC_IP" ]; then
    echo "Usage: $0 <public-ip>"
    echo "Example: $0 12.34.56.78"
    exit 1
fi

echo "🔧 Updating DNS server configuration on $PUBLIC_IP"
echo "================================================="

# Create the new DNS service configuration using the public IP
NEW_DNS_CONFIG='  dns-server:
    image: cytopia/bind:latest
    container_name: minecraft-dns
    restart: unless-stopped
    ports:
      - "53:53/tcp"
      - "53:53/udp"
    environment:
      - DNS_FORWARDER=8.8.8.8,8.8.4.4
      - DNS_A=mco.mineplex.com='$PUBLIC_IP',geo.hivebedrock.network='$PUBLIC_IP',mco.cubecraft.net='$PUBLIC_IP',mco.lbsg.net='$PUBLIC_IP',play.inpvp.net='$PUBLIC_IP',play.galaxite.net='$PUBLIC_IP'
      - ALLOW_QUERY=any
      - ALLOW_RECURSION=any
      - DNSSEC_VALIDATE=no
    networks:
      minecraft_net:
        ipv4_address: 172.20.0.5
    deploy:
      resources:
        limits:
          memory: 128M
          cpus: '\''0.2'\'''

echo "📤 Uploading new configuration..."

# SSH into server and update the docker-compose.yml
ssh -i minecraft-sydney-key.pem ec2-user@"$PUBLIC_IP" << EOF
echo "📁 Backing up current docker-compose.yml..."
sudo cp /opt/minecraft/docker-compose.yml /opt/minecraft/docker-compose.yml.backup.$(date +%Y%m%d-%H%M%S)

echo "🔧 Updating DNS server configuration..."
# Create a temporary script to update the docker-compose.yml
echo "📍 Using public IP: $PUBLIC_IP"

cat > /tmp/update-dns.py << PYTHON_EOF
import re
import sys

# Read the docker-compose.yml file
with open('/opt/minecraft/docker-compose.yml', 'r') as f:
    content = f.read()

# Define the new DNS service configuration with public IP
new_dns_config = '''  dns-server:
    image: cytopia/bind:latest
    container_name: minecraft-dns
    restart: unless-stopped
    ports:
      - "53:53/tcp"
      - "53:53/udp"
    environment:
      - DNS_FORWARDER=8.8.8.8,8.8.4.4
      - DNS_A=mco.mineplex.com=$PUBLIC_IP,geo.hivebedrock.network=$PUBLIC_IP,mco.cubecraft.net=$PUBLIC_IP,mco.lbsg.net=$PUBLIC_IP,play.inpvp.net=$PUBLIC_IP,play.galaxite.net=$PUBLIC_IP
      - ALLOW_QUERY=any
      - ALLOW_RECURSION=any
      - DNSSEC_VALIDATE=no
    networks:
      minecraft_net:
        ipv4_address: 172.20.0.5
    deploy:
      resources:
        limits:
          memory: 128M
          cpus: '0.2' '''

# Replace the DNS server section using regex
pattern = r'  dns-server:.*?(?=\n\w|\nvolumes:|\nnetworks:|\Z)'
updated_content = re.sub(pattern, new_dns_config, content, flags=re.DOTALL)

# Write the updated content back
with open('/opt/minecraft/docker-compose.yml', 'w') as f:
    f.write(updated_content)

print("✅ docker-compose.yml updated successfully")
PYTHON_EOF

# Run the Python script to update the file
sudo python3 /tmp/update-dns.py

echo "🔄 Restarting DNS container..."
cd /opt/minecraft
sudo docker-compose down dns-server
sudo docker-compose up -d dns-server

echo "⏳ Waiting for DNS server to start..."
sleep 5

echo "📋 Checking DNS container status..."
sudo docker ps | grep minecraft-dns

echo "📝 Checking DNS logs..."
sudo docker logs minecraft-dns | tail -10

echo "🧹 Cleaning up..."
rm /tmp/update-dns.py

echo ""
echo "✅ DNS server configuration updated!"
echo "🔍 Test with: nslookup google.com $PUBLIC_IP"
echo "🎮 Test Minecraft DNS: nslookup mco.lbsg.net $PUBLIC_IP"
EOF

echo ""
echo "🎉 DNS update complete!"
echo "💡 Run the monitor script to verify: ./monitor.sh $PUBLIC_IP"