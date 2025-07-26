# Minecraft Paper Server with BedrockConnect on AWS EC2

[![AWS](https://img.shields.io/badge/AWS-EC2-orange.svg)](https://aws.amazon.com/ec2/)
[![Minecraft](https://img.shields.io/badge/Minecraft-Paper%201.21.8-green.svg)](https://papermc.io/)
[![BedrockConnect](https://img.shields.io/badge/BedrockConnect-Cross--Platform-blue.svg)](https://github.com/Pugmatt/BedrockConnect)
[![License](https://img.shields.io/badge/License-MIT-yellow.svg)](LICENSE)

**Complete AWS infrastructure for running a Minecraft Paper server with BedrockConnect support, enabling cross-platform gameplay between Java and Bedrock editions.**

## ✨ Features

- 🏗️ **One-click AWS deployment** with CloudFormation
- 🎮 **Cross-platform support** - Java Edition + Bedrock/Nintendo Switch via BedrockConnect  
- 🛡️ **Production-ready security** with restricted security groups and monitoring
- 📊 **CloudWatch monitoring** with custom dashboard and alerts
- 🌍 **Easy world management** with live configuration updates
- 🔄 **Automated backups** to S3 with lifecycle management
- 💰 **Cost-optimized** for personal/small group usage (~$30/month)
- 🔧 **Infrastructure as Code** - fully reproducible deployments

## 🚀 Quick Start

### Prerequisites
- AWS CLI configured with appropriate permissions
- An existing EC2 Key Pair (or script will create one)
- `git`, `ssh`, and `scp` installed locally

### Deployment
```bash
# Clone the repository
git clone https://github.com/kiwiscanfly/minecraft-ec2.git
cd minecraft-ec2

# Deploy the server (takes ~10 minutes)
./deploy.sh

# Configure your world (optional)
./configure-world.sh --interactive

# Check server status
./diagnostics.sh
```

### Nintendo Switch Setup
1. Go to System Settings → Internet → Internet Settings
2. Select your WiFi → Change Settings → DNS Settings → Manual  
3. Set Primary DNS to your server's public IP
4. Set Secondary DNS to 8.8.8.8
5. Launch Minecraft → Servers → Connect to any Featured Server
6. Your custom server will appear in the list!

## 🎯 What's Included

### Infrastructure
- AWS EC2 instance with optimized networking (VPC, subnets, security groups)
- CloudFormation template for reproducible deployments
- CloudWatch monitoring with custom dashboard and alerts
- S3 bucket for automated world backups
- Elastic IP for consistent server access

### Minecraft Server Stack
- **Paper Server** - High-performance Minecraft Java Edition server
- **Geyser** - Protocol translation for Bedrock/Java cross-play
- **BedrockConnect** - Nintendo Switch connection via DNS redirection
- **Floodgate** - UUID linking between Java and Bedrock players

### Management Tools
- Live configuration updates (game mode, difficulty, etc.)
- Comprehensive diagnostics and monitoring scripts  
- Automated backup and restore functionality
- Real-time DNS query monitoring for troubleshooting

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
├── configure-world.sh               # World configuration script
├── .env.server.json                 # Auto-generated deployment variables (not committed)
├── .env.world.json                  # World configuration settings (not committed)
└── spec.md                          # Detailed specification
```

### .env.server.json Auto-Configuration

After running `./deploy.sh`, a `.env.server.json` file is automatically created with deployment variables:

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

### .env.world.json World Configuration

Configure your Minecraft world settings using the world configuration file:

```bash
# Create world configuration from example template
cp .env.world.json.example .env.world.json

# Or create/edit world configuration interactively
./configure-world.sh --interactive

# Quick mode switches
./configure-world.sh --creative      # Switch to creative mode
./configure-world.sh --survival      # Switch to survival mode

# Reset to defaults (copies from .env.world.json.example)
./configure-world.sh --reset
```

**Example .env.world.json:**
```json
{
  "world": {
    "name": "My Creative Server",
    "mode": "creative",
    "difficulty": "normal",
    "max_players": 20,
    "view_distance": 10,
    "motd": "Welcome to my server!",
    "allow_flight": true,
    "enable_command_blocks": true
  },
  "geyser": {
    "server_name": "My Server",
    "motd1": "Cross-Platform",
    "motd2": "Minecraft Server"
  }
}
```

**World Settings Include:**
- Server name (appears in BedrockConnect list)
- Game mode (survival, creative, adventure, spectator)
- Difficulty level
- Player limits and view distances  
- PvP, flight, and command block settings
- Geyser configuration for Bedrock players

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
./diagnostics.sh [PUBLIC_IP]    # IP auto-detected from .env.server.json if omitted

# Watch DNS queries in real-time
./watch-dns.sh [PUBLIC_IP]      # IP auto-detected from .env.server.json if omitted

# Update DNS configuration if needed
./update-dns.sh [PUBLIC_IP]     # IP auto-detected from .env.server.json if omitted
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

### Common Issues

**Server not responding:**
```bash
# Run comprehensive diagnostics
./diagnostics.sh

# Check if all containers are running
ssh -i your-key.pem ec2-user@SERVER_IP 'docker ps'

# View server logs
ssh -i your-key.pem ec2-user@SERVER_IP 'docker logs minecraft-paper'
```

**Nintendo Switch connection issues:**
```bash
# Test DNS redirection
nslookup mco.lbsg.net YOUR_SERVER_IP

# Monitor DNS queries in real-time
./watch-dns.sh

# Restart BedrockConnect if needed
ssh -i your-key.pem ec2-user@SERVER_IP 'docker restart bedrock-connect'
```

**Deployment failures:**
- Ensure AWS CLI is configured: `aws sts get-caller-identity`
- Check CloudFormation console for detailed error messages
- Verify you have sufficient IAM permissions for EC2, VPC, and CloudFormation

### Getting Help

1. Run `./diagnostics.sh` and check the generated report
2. Review CloudWatch logs via the dashboard (see outputs)
3. Check [Issues](https://github.com/kiwiscanfly/minecraft-ec2/issues) for known problems
4. Create a new issue with diagnostic output if needed

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

## 🤝 Contributing

Contributions are welcome! Please feel free to submit a Pull Request. For major changes, please open an issue first to discuss what you would like to change.

## 📄 License

This project is licensed under the MIT License - see the [LICENSE](LICENSE) file for details.

## 📞 Support

For issues and support:
1. **First**: Run `./diagnostics.sh` for comprehensive health checks
2. **Check**: [Issues tab](https://github.com/kiwiscanfly/minecraft-ec2/issues) for known problems
3. **Create**: A new issue with diagnostic output if your problem isn't already reported
4. **Debug**: SSH to server and review container logs with `docker logs [container-name]`

When reporting issues, please include:
- Output from `./diagnostics.sh`
- Your deployment region and instance type
- Steps to reproduce the problem
- Any error messages from CloudFormation or container logs