#!/bin/bash

# Automated Backup Setup Script
# Run this ON the EC2 instance via SSH to set up daily backups
# Usage: ./setup-auto-backup.sh [stack-name] [region]

set -e

STACK_NAME=${1:-minecraft-sydney}
REGION=${2:-ap-southeast-2}

echo "⏰ Setting up automated Minecraft world backups"
echo "=============================================="
echo "Stack: $STACK_NAME"
echo "Region: $REGION"
echo ""

# Copy backup script to server
echo "📥 Installing backup script..."
sudo cp backup-world.sh /usr/local/bin/
sudo chmod +x /usr/local/bin/backup-world.sh

# Create log directory
sudo mkdir -p /var/log/minecraft-backup
sudo chown ec2-user:ec2-user /var/log/minecraft-backup

# Create backup wrapper script with logging
echo "📝 Creating backup wrapper script..."
cat > /tmp/minecraft-backup-wrapper.sh << 'EOF'
#!/bin/bash
LOGFILE="/var/log/minecraft-backup/backup-$(date +%Y-%m-%d).log"
echo "=== Backup started at $(date) ===" >> "$LOGFILE"
/usr/local/bin/backup-world.sh >> "$LOGFILE" 2>&1
BACKUP_EXIT_CODE=$?
echo "=== Backup finished at $(date) with exit code $BACKUP_EXIT_CODE ===" >> "$LOGFILE"

# Keep only last 7 days of logs
find /var/log/minecraft-backup/ -name "backup-*.log" -mtime +7 -delete

# Optional: Send notification on failure
if [ $BACKUP_EXIT_CODE -ne 0 ]; then
    echo "Backup failed with exit code $BACKUP_EXIT_CODE" | logger -t minecraft-backup
fi

exit $BACKUP_EXIT_CODE
EOF

sudo mv /tmp/minecraft-backup-wrapper.sh /usr/local/bin/
sudo chmod +x /usr/local/bin/minecraft-backup-wrapper.sh

# Set up cron job for daily backups at 3 AM
echo "⏰ Setting up cron job for daily backups..."
(crontab -l 2>/dev/null || true; echo "0 3 * * * /usr/local/bin/minecraft-backup-wrapper.sh") | crontab -

# Verify cron job
echo "✅ Cron job installed:"
crontab -l | grep minecraft-backup

echo ""
echo "✅ Automated backup setup complete!"
echo ""
echo "📋 Backup Schedule:"
echo "   - Daily at 3:00 AM server time"
echo "   - Logs saved to: /var/log/minecraft-backup/"
echo "   - Backups stored in S3 with 30-day retention"
echo ""
echo "🔧 Management Commands:"
echo "   - Manual backup: /usr/local/bin/backup-world.sh"
echo "   - View logs: ls -la /var/log/minecraft-backup/"
echo "   - Test cron: sudo run-parts --test /etc/cron.daily"
echo "   - Edit schedule: crontab -e"
echo ""
echo "💡 First backup will run tonight at 3 AM"