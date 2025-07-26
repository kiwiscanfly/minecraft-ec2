# Minecraft Paper Server with BedrockConnect on AWS EC2

⚠️ **Work In Progress** - Nintendo Switch connectivity is not yet fully functional.

Complete infrastructure setup for running a Minecraft Paper server with BedrockConnect support, enabling Nintendo Switch and other Bedrock clients to connect to Java Edition servers.

## 🚀 Quick Start

1. **Deploy the server:**
   ```bash
   ./deploy.sh
   ```

2. **Check server status:**
   ```bash
   ./diagnostics.sh [PUBLIC_IP]  # IP auto-detected from .env.json if omitted
   ```

3. **Destroy all resources:**
   ```bash
   ./destroy.sh
   ```

## 🚨 Current Status

- ✅ Infrastructure deploys successfully
- ✅ All Docker containers start
- ✅ Java Edition connections work
- ❌ Nintendo Switch connections via BedrockConnect (debugging in progress)
- ✅ Automated backups configured
- ✅ Monitoring and diagnostics functional

## 📁 Project Structure

```
minecraft-ec2/
├── minecraft-bedrock-server.yaml    # CloudFormation template
├── setup.sh                         # Server setup script (idempotent)
├── deploy.sh                        # Deployment script
├── destroy.sh                       # Resource cleanup script
├── diagnostics.sh                   # Comprehensive diagnostics
├── update-dns.sh                    # DNS configuration updater
├── watch-dns.sh                     # Real-time DNS monitoring
├── backup-world.sh                  # Manual backup script
├── restore-world.sh                 # Backup restoration script
├── setup-auto-backup.sh             # Automated backup configuration
├── .env.json                        # Auto-generated deployment variables (not committed)
└── spec.md                          # Detailed specification
```

### .env.json Auto-Configuration

After running `./deploy.sh`, a `.env.json` file is automatically created with deployment variables:

```json
{
  "STACK_NAME": "minecraft-sydney",
  "KEY_NAME": "minecraft-sydney-key", 
  "INSTANCE_TYPE": "t4g.medium",
  "REGION": "ap-southeast-2",
  "SSH_LOCATION": "0.0.0.0/0",
  "PUBLIC_IP": "52.63.189.233",
  "DEPLOYED_AT": "2024-07-26T20:15:30Z"
}
```

**Benefits:**
- Scripts automatically detect server IP and credentials
- No need to remember or lookup deployment details
- Simplifies running diagnostics and maintenance commands
- File is automatically excluded from git commits

## 🏗️ Architecture

The setup includes three Docker containers:

1. **minecraft-paper**: Minecraft Java server with Geyser + Floodgate plugins
2. **bedrock-connect**: Proxy for Bedrock client connections
3. **dns-server**: BIND9 DNS server for Featured Server redirection

## 🎮 Connection Instructions

### Java Edition
Connect to: `[PUBLIC_IP]:25565`

### Nintendo Switch (Bedrock Edition)
1. Go to System Settings → Internet → Internet Settings
2. Select your WiFi → Change Settings → DNS Settings → Manual
3. Primary DNS: `[PUBLIC_IP]`
4. Secondary DNS: `8.8.8.8`
5. Launch Minecraft → Servers → Select any Featured Server
6. You'll see "My Minecraft Server" - click to join!

## 🔧 Management Commands

### Deployment
```bash
# Deploy with default settings (t4g.medium, us-east-1)
./deploy.sh

# Deploy with custom settings
./deploy.sh my-stack my-key t4g.small us-west-2
```

### SSH Access

After deployment, you'll have a private key file to access your server:

```bash
# Get your server's public IP from deployment output
./deploy.sh  # Note the PublicIP in the output

# SSH into the server (replace IP with your actual IP)
ssh -i minecraft-sydney-key.pem ec2-user@12.34.56.78
```

**SSH Key Setup:**
- Key file: `minecraft-sydney-key.pem` (created automatically)
- Username: `ec2-user` (default for Amazon Linux)
- Make sure key has correct permissions: `chmod 400 minecraft-sydney-key.pem`

**Common SSH Tasks:**
```bash
# SSH into server
ssh -i minecraft-sydney-key.pem ec2-user@[PUBLIC_IP]

# View running containers
docker ps

# Check Minecraft server logs
docker logs minecraft-paper

# Create manual backup
sudo /usr/local/bin/backup-world.sh

# View backup logs
sudo tail -f /var/log/minecraft-backup/backup-$(date +%Y-%m-%d).log

# Run server commands via RCON
docker exec minecraft-paper rcon-cli list
docker exec minecraft-paper rcon-cli say "Hello players!"
```

**Troubleshooting SSH Issues:**
```bash
# If connection refused - check security group allows your IP
# If permission denied - check key file permissions
chmod 400 minecraft-sydney-key.pem

# If wrong IP - get current IP from CloudFormation
aws cloudformation describe-stacks --stack-name minecraft-sydney --region ap-southeast-2 --query 'Stacks[0].Outputs'
```

### Monitoring
```bash
# Run comprehensive diagnostics from your local machine
./diagnostics.sh [PUBLIC_IP]    # IP auto-detected from .env.json if omitted

# Watch DNS queries in real-time
./watch-dns.sh [PUBLIC_IP]      # IP auto-detected from .env.json if omitted

# Update DNS configuration if needed
./update-dns.sh [PUBLIC_IP]     # IP auto-detected from .env.json if omitted
```

### Backup Management (via SSH)

```bash
# SSH into server first
ssh -i minecraft-sydney-key.pem ec2-user@[PUBLIC_IP]

# Manual backup
sudo /usr/local/bin/backup-world.sh

# List available backups
aws s3 ls s3://minecraft-sydney-minecraft-backups-[ACCOUNT-ID]/ --region ap-southeast-2

# Restore from backup (replace with actual backup name)
sudo ./restore-world.sh minecraft-world-backup-2024-01-20_15-30-45

# View backup logs
sudo ls -la /var/log/minecraft-backup/
sudo tail /var/log/minecraft-backup/backup-$(date +%Y-%m-%d).log

# Check cron job status
crontab -l
sudo tail /var/log/cron
```

### Cleanup
```bash
# Destroy all AWS resources
./destroy.sh

# Destroy specific stack
./destroy.sh my-stack us-west-2
```

## 📊 Cost Estimate

- **t4g.medium**: ~$24.53/month
- **EBS Storage (20GB)**: ~$2.40/month
- **Elastic IP**: ~$3.65/month (when instance is stopped)
- **Data Transfer**: Variable

**Total**: ~$27-30/month for 24/7 operation

## 🔒 Security Features

- VPC with public subnet and Internet Gateway
- Security groups with minimal required ports
- IAM roles with least privilege access
- EBS encryption enabled
- SSH key-based authentication

## 🛠️ Troubleshooting

### Known Issues

1. **Nintendo Switch can't connect (WIP)**
   - BedrockConnect shows transfer but connection doesn't reach Minecraft server
   - Currently debugging Geyser/BedrockConnect communication
   - Temporary workaround: None yet

### Common Issues

1. **Server not responding**
   - Run `./diagnostics.sh [PUBLIC_IP]` for comprehensive check
   - Wait 5-10 minutes for initial setup
   - Check container logs: `docker logs minecraft-paper`

2. **Setup script fails**
   - Ensure you're running with sudo: `sudo ./setup.sh`
   - Check if services are already running
   - Script is idempotent - safe to rerun

3. **DNS resolution issues**
   - Use `./diagnostics.sh` to check DNS functionality
   - Verify security groups allow UDP/TCP port 53

### Performance Tuning

- **t4g.small**: 5-10 players
- **t4g.medium**: 10-20 players (recommended)
- **t4g.large**: 20-30+ players

Adjust `VIEW_DISTANCE` and `SIMULATION_DISTANCE` in docker-compose.yml for performance.

## 📋 Requirements

- AWS CLI configured
- Docker and Docker Compose (automatically installed)
- EC2 key pair (automatically created)

## 🔗 How It Works

1. **DNS Redirection**: Custom BIND9 server redirects Featured Server domains to BedrockConnect
2. **Server Selection**: BedrockConnect presents your custom server list
3. **Transfer Packet**: Uses Minecraft's Transfer Packet to redirect to your server
4. **Protocol Translation**: Geyser translates between Bedrock and Java protocols

This provides a seamless experience where Nintendo Switch users only see your server in the Featured Servers list.

## 📞 Support

For issues:
1. Run `./monitor.sh [PUBLIC_IP]` for health checks
2. SSH to server and run `./troubleshoot.sh` for detailed diagnostics
3. Check CloudFormation events in AWS Console
4. Review container logs with `docker logs [container-name]`