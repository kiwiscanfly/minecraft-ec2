#!/bin/bash

# Comprehensive Minecraft Server Diagnostic Script
# Usage: ./diagnostics.sh [public-ip]

# Function to load variables from .env.json
load_env_json() {
    if [ -f ".env.json" ]; then
        export PUBLIC_IP=$(cat .env.json | grep -o '"PUBLIC_IP": *"[^"]*"' | cut -d'"' -f4)
        export SSH_KEY=$(cat .env.json | grep -o '"KEY_NAME": *"[^"]*"' | cut -d'"' -f4).pem
        export STACK_NAME=$(cat .env.json | grep -o '"STACK_NAME": *"[^"]*"' | cut -d'"' -f4)
        export REGION=$(cat .env.json | grep -o '"REGION": *"[^"]*"' | cut -d'"' -f4)
    fi
}

# Try to get PUBLIC_IP from parameter or .env.json
PUBLIC_IP="${1}"
if [ -z "$PUBLIC_IP" ]; then
    load_env_json
    if [ -z "$PUBLIC_IP" ]; then
        echo "Usage: $0 <public-ip>"
        echo "Example: $0 12.34.56.78"
        echo "Or ensure .env.json exists from a previous deployment"
        exit 1
    fi
    echo "📋 Using PUBLIC_IP from .env.json: $PUBLIC_IP"
fi

# Set SSH key (from .env.json or default)
if [ -z "$SSH_KEY" ]; then
    SSH_KEY="minecraft-sydney-key.pem"
fi

TIMESTAMP=$(date +"%Y-%m-%d_%H-%M-%S")
REPORT_FILE="/tmp/minecraft-diagnostics-$TIMESTAMP.log"

echo "🔍 COMPREHENSIVE MINECRAFT SERVER DIAGNOSTICS"
echo "=============================================="
echo "Server IP: $PUBLIC_IP"
echo "Timestamp: $(date)"
echo "Report will be saved to: $REPORT_FILE"
echo ""

# Function to log both to console and file
log_both() {
    echo "$1" | tee -a "$REPORT_FILE"
}

# Function to run commands and capture output
run_check() {
    local title="$1"
    local command="$2"
    
    log_both ""
    log_both "=== $title ==="
    log_both "Command: $command"
    log_both "$(printf '=%.0s' {1..50})"
    
    if eval "$command" >> "$REPORT_FILE" 2>&1; then
        local output=$(eval "$command" 2>/dev/null)
        echo "$output"
        echo "$output" >> "$REPORT_FILE"
    else
        local error_msg="❌ Command failed: $command"
        log_both "$error_msg"
    fi
}

# Initialize report file
{
    echo "MINECRAFT SERVER DIAGNOSTIC REPORT"
    echo "=================================="
    echo "Generated: $(date)"
    echo "Server IP: $PUBLIC_IP"
    echo "Hostname: $(hostname)"
    echo ""
} > "$REPORT_FILE"

# 1. BASIC CONNECTIVITY TESTS
echo "1️⃣ BASIC CONNECTIVITY"
echo "====================="

echo "🌐 Testing DNS Server (port 53)..."
if nc -z -w5 "$PUBLIC_IP" 53; then
    echo "✅ DNS server responding"
    
    echo "🔍 Testing DNS resolution..."
    for domain in "mco.lbsg.net" "geo.hivebedrock.network" "mco.cubecraft.net"; do
        result=$(nslookup "$domain" "$PUBLIC_IP" 2>/dev/null | grep "Address:" | tail -1 | awk '{print $2}')
        if [ "$result" = "$PUBLIC_IP" ]; then
            echo "✅ $domain → $result (correct)"
        else
            echo "❌ $domain → $result (should be $PUBLIC_IP)"
        fi
    done
else
    echo "❌ DNS server not responding"
fi

echo ""
echo "🎮 Testing game server ports..."
ports=("25565:Java Edition" "19132:BedrockConnect" "19133:Geyser")
for port_info in "${ports[@]}"; do
    port=$(echo "$port_info" | cut -d: -f1)
    name=$(echo "$port_info" | cut -d: -f2)
    
    if [ "$port" = "19132" ] || [ "$port" = "19133" ]; then
        protocol="udp"
        nc_opts="-zvu"
    else
        protocol="tcp"
        nc_opts="-zv"
    fi
    
    if nc $nc_opts -w5 "$PUBLIC_IP" "$port" >/dev/null 2>&1; then
        echo "✅ $name (port $port/$protocol) responding"
    else
        echo "❌ $name (port $port/$protocol) not responding"
    fi
done

echo ""
echo "🔐 Testing SSH (port 22)..."
if nc -z -w5 "$PUBLIC_IP" 22; then
    echo "✅ SSH server responding"
else
    echo "❌ SSH server not responding"
fi

echo ""
echo "2️⃣ DOCKER CONTAINER STATUS"
echo "==========================="

run_check "Docker Container Status" "ssh -i $SSH_KEY -o ConnectTimeout=10 ec2-user@$PUBLIC_IP 'docker ps --format \"table {{.Names}}\\t{{.Status}}\\t{{.Ports}}\"'"

echo ""
echo "3️⃣ GEYSER PLUGIN STATUS"
echo "======================="

run_check "Geyser Plugin Files" "ssh -i $SSH_KEY -o ConnectTimeout=10 ec2-user@$PUBLIC_IP 'docker exec minecraft-paper ls -la /plugins/ | grep -i geyser'"

run_check "Geyser Startup Logs" "ssh -i $SSH_KEY -o ConnectTimeout=10 ec2-user@$PUBLIC_IP 'docker logs minecraft-paper 2>&1 | grep -i geyser | tail -10'"

run_check "Geyser Port Binding" "ssh -i $SSH_KEY -o ConnectTimeout=10 ec2-user@$PUBLIC_IP 'docker exec minecraft-paper netstat -tulpn 2>/dev/null | grep 19132'"

echo ""
echo "4️⃣ BEDROCKCONNECT STATUS"
echo "========================"

run_check "BedrockConnect Configuration" "ssh -i $SSH_KEY -o ConnectTimeout=10 ec2-user@$PUBLIC_IP 'docker exec bedrock-connect cat /config/serverlist.json 2>/dev/null'"

run_check "BedrockConnect Recent Logs" "ssh -i $SSH_KEY -o ConnectTimeout=10 ec2-user@$PUBLIC_IP 'docker logs bedrock-connect --tail 20 2>&1'"

echo ""
echo "5️⃣ DNS SERVER STATUS"
echo "==================="

run_check "DNS Configuration" "ssh -i $SSH_KEY -o ConnectTimeout=10 ec2-user@$PUBLIC_IP 'docker inspect minecraft-dns --format \"{{range .Config.Env}}{{println .}}{{end}}\" | grep DNS_A'"

run_check "DNS Server Logs" "ssh -i $SSH_KEY -o ConnectTimeout=10 ec2-user@$PUBLIC_IP 'docker logs minecraft-dns --tail 15 2>&1'"

echo ""
echo "6️⃣ NETWORK CONNECTIVITY"
echo "======================="

run_check "Container Network Info" "ssh -i $SSH_KEY -o ConnectTimeout=10 ec2-user@$PUBLIC_IP 'docker network inspect minecraft_minecraft_net --format \"{{json .IPAM.Config}}\"'"

run_check "Container IP Addresses" "ssh -i $SSH_KEY -o ConnectTimeout=10 ec2-user@$PUBLIC_IP 'docker inspect minecraft-paper bedrock-connect minecraft-dns --format \"{{.Name}}: {{range .NetworkSettings.Networks}}{{.IPAddress}}{{end}}\"'"

echo ""
echo "7️⃣ SYSTEM HEALTH & PERFORMANCE"
echo "=============================="

run_check "System Resources" "ssh -i $SSH_KEY -o ConnectTimeout=10 ec2-user@$PUBLIC_IP 'free -h && echo && df -h'"

run_check "System Load & Performance" "ssh -i $SSH_KEY -o ConnectTimeout=10 ec2-user@$PUBLIC_IP 'uptime && echo \"Load average: \$(cat /proc/loadavg | awk \"{print \\\$1, \\\$2, \\\$3}\")\" && echo \"Memory pressure: \$(cat /proc/pressure/memory | grep avg10 | awk \"{print \\\$2}\" 2>/dev/null || echo \"N/A\")\"'"

run_check "Docker Service Status" "ssh -i $SSH_KEY -o ConnectTimeout=10 ec2-user@$PUBLIC_IP 'docker --version && echo \"Docker service: \$(systemctl is-active docker)\"'"

run_check "Docker Disk Usage" "ssh -i $SSH_KEY -o ConnectTimeout=10 ec2-user@$PUBLIC_IP 'docker system df'"

run_check "System Conflicts Check" "ssh -i $SSH_KEY -o ConnectTimeout=10 ec2-user@$PUBLIC_IP 'if systemctl is-active systemd-resolved >/dev/null 2>&1; then echo \"⚠️ WARNING: systemd-resolved is running (may conflict with Docker DNS)\"; echo \"💡 Consider: sudo systemctl disable systemd-resolved\"; else echo \"✅ No systemd-resolved conflicts\"; fi'"

run_check "Port Conflicts" "ssh -i $SSH_KEY -o ConnectTimeout=10 ec2-user@$PUBLIC_IP 'echo \"Listening ports on critical services:\" && netstat -tuln | grep -E \":(53|25565|19132|22)\\s\"'"

echo ""
echo "8️⃣ QUICK FIXES & RECOMMENDATIONS"
echo "================================"

echo "Based on diagnostic results:"
echo ""

# Check if Geyser is running
if ssh -i $SSH_KEY -o ConnectTimeout=10 ec2-user@"$PUBLIC_IP" 'docker logs minecraft-paper 2>&1 | grep -q "Started Geyser on UDP port 19132"' 2>/dev/null; then
    echo "✅ Geyser appears to be running correctly"
else
    echo "❌ Geyser may not be starting properly"
    echo "   Fix: ssh -i $SSH_KEY ec2-user@$PUBLIC_IP 'docker restart minecraft-paper'"
fi

# Check if BedrockConnect config exists
if ssh -i $SSH_KEY -o ConnectTimeout=10 ec2-user@"$PUBLIC_IP" 'docker exec bedrock-connect test -f /config/serverlist.json' 2>/dev/null; then
    echo "✅ BedrockConnect configuration exists"
else
    echo "❌ BedrockConnect configuration missing"
    echo "   Fix: ssh -i $SSH_KEY ec2-user@$PUBLIC_IP './update-dns.sh $PUBLIC_IP'"
fi

# Check DNS resolution
if nslookup mco.lbsg.net "$PUBLIC_IP" 2>/dev/null | grep -q "$PUBLIC_IP"; then
    echo "✅ DNS redirection working"
else
    echo "❌ DNS redirection not working"
    echo "   Fix: ssh -i $SSH_KEY ec2-user@$PUBLIC_IP 'docker restart minecraft-dns'"
fi

echo ""
echo "🔧 MANUAL DEBUGGING COMMANDS"
echo "============================"
echo "• Check all logs: ssh -i $SSH_KEY ec2-user@$PUBLIC_IP 'docker logs minecraft-paper; docker logs bedrock-connect; docker logs minecraft-dns'"
echo "• Restart services: ssh -i $SSH_KEY ec2-user@$PUBLIC_IP 'docker restart minecraft-paper bedrock-connect minecraft-dns'"
echo "• Restart all containers: ssh -i $SSH_KEY ec2-user@$PUBLIC_IP 'cd /opt/minecraft && docker-compose restart'"
echo "• View live logs: ssh -i $SSH_KEY ec2-user@$PUBLIC_IP 'docker logs -f minecraft-paper'"
echo "• Restart Docker service: ssh -i $SSH_KEY ec2-user@$PUBLIC_IP 'sudo systemctl restart docker'"
echo "• Free up disk space: ssh -i $SSH_KEY ec2-user@$PUBLIC_IP 'docker system prune -f'"
echo "• Update configuration: ./update-dns.sh $PUBLIC_IP"
echo "• Monitor in real-time: ./watch-dns.sh $PUBLIC_IP"
echo "• Check deployment logs: ssh -i $SSH_KEY ec2-user@$PUBLIC_IP 'sudo cat /var/log/cloud-init-output.log'"
echo ""

echo "📋 NINTENDO SWITCH SETUP"
echo "========================"
echo "1. Set Primary DNS on Switch to: $PUBLIC_IP"
echo "2. Set Secondary DNS to: 8.8.8.8"
echo "3. Restart Nintendo Switch after DNS change"
echo "4. Connect to any Featured Server (e.g., The Hive, CubeCraft)"
echo "5. You should see your custom server in the list"
echo ""

echo "📊 DIAGNOSTIC COMPLETE"
echo "======================"
echo "Full report saved to: $REPORT_FILE"
echo "You can review the complete logs with: cat $REPORT_FILE"
echo ""
echo "Summary:"
if nc -z -w5 "$PUBLIC_IP" 53 && nc -zvu -w5 "$PUBLIC_IP" 19132 >/dev/null 2>&1 && nc -zvu -w5 "$PUBLIC_IP" 19133 >/dev/null 2>&1; then
    echo "✅ All core services appear to be running"
    echo "If Nintendo Switch still can't connect, check the BedrockConnect and Geyser logs above"
else
    echo "❌ One or more services are not responding"
    echo "Check the diagnostic details above and run the suggested fixes"
fi

# Save summary to report
{
    echo ""
    echo "=== DIAGNOSTIC SUMMARY ==="
    echo "Timestamp: $(date)"
    echo "DNS (53): $(nc -z -w5 "$PUBLIC_IP" 53 && echo "OK" || echo "FAIL")"
    echo "Java (25565): $(nc -z -w5 "$PUBLIC_IP" 25565 && echo "OK" || echo "FAIL")"
    echo "BedrockConnect (19132): $(nc -zvu -w5 "$PUBLIC_IP" 19132 >/dev/null 2>&1 && echo "OK" || echo "FAIL")"
    echo "Geyser (19133): $(nc -zvu -w5 "$PUBLIC_IP" 19133 >/dev/null 2>&1 && echo "OK" || echo "FAIL")"
} >> "$REPORT_FILE"