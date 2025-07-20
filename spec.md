# Complete Guide: Minecraft Paper Server with BedrockConnect on AWS EC2

## Instance Recommendation

**Recommended: t4g.medium** - This ARM-based instance with 4GB RAM provides the best balance of performance and cost at approximately $24.53/month. The t4g.medium offers 40% better price/performance compared to Intel-based instances and can comfortably run both Paper server and BedrockConnect with good performance for 10-20 players.

## How BedrockConnect Works

BedrockConnect enables Nintendo Switch and other Bedrock Edition consoles to connect to Java Edition servers through a two-step process:

1. **DNS Redirection**: Nintendo Switch is configured to use a DNS server that redirects Featured Server connections
2. **Transfer Packet**: When connecting to a Featured Server, BedrockConnect intercepts the connection and presents a server list, then uses Minecraft's Transfer Packet to redirect the console to your Java server
3. **Protocol Translation**: The actual Java server must run Geyser (either as a plugin or standalone) to translate between Bedrock and Java protocols in real-time

BedrockConnect itself is NOT a proxy - it only handles the initial redirection. Geyser performs the actual protocol translation throughout the gameplay session.

## Self-Hosted DNS Configuration

This setup includes a BIND9 DNS server that redirects Minecraft Featured Servers to your BedrockConnect instance, eliminating the need to use public DNS servers. The DNS server runs in a Docker container alongside your Minecraft services.

## Complete CloudFormation Template

Save this as `minecraft-bedrock-server.yaml`:

```yaml
AWSTemplateFormatVersion: '2010-09-09'
Description: 'Minecraft Paper Server with BedrockConnect on EC2 using Docker'

Parameters:
  InstanceType:
    Description: 'EC2 Instance type'
    Type: String
    Default: t4g.medium
    AllowedValues:
      - t2.small
      - t4g.small
      - t4g.medium
      - t3.small
      - t3.medium
    ConstraintDescription: 'Must be a valid EC2 instance type'

  KeyName:
    Description: 'Name of existing EC2 KeyPair for SSH access'
    Type: AWS::EC2::KeyPair::KeyName
    ConstraintDescription: 'Must be the name of an existing EC2 KeyPair'

  SSHLocation:
    Description: 'IP address range that can SSH to the EC2 instance'
    Type: String
    Default: 0.0.0.0/0
    AllowedPattern: '^(([0-9]|[1-9][0-9]|1[0-9]{2}|2[0-4][0-9]|25[0-5])\.){3}([0-9]|[1-9][0-9]|1[0-9]{2}|2[0-4][0-9]|25[0-5])(\/([0-9]|[1-2][0-9]|3[0-2]))$'
    ConstraintDescription: 'Must be a valid IP CIDR range'

Resources:
  # VPC Configuration
  VPC:
    Type: AWS::EC2::VPC
    Properties:
      CidrBlock: 10.0.0.0/16
      EnableDnsHostnames: true
      EnableDnsSupport: true
      Tags:
        - Key: Name
          Value: !Sub '${AWS::StackName}-VPC'

  InternetGateway:
    Type: AWS::EC2::InternetGateway
    Properties:
      Tags:
        - Key: Name
          Value: !Sub '${AWS::StackName}-IGW'

  InternetGatewayAttachment:
    Type: AWS::EC2::VPCGatewayAttachment
    Properties:
      InternetGatewayId: !Ref InternetGateway
      VpcId: !Ref VPC

  PublicSubnet:
    Type: AWS::EC2::Subnet
    Properties:
      VpcId: !Ref VPC
      AvailabilityZone: !Select [0, !GetAZs '']
      CidrBlock: 10.0.1.0/24
      MapPublicIpOnLaunch: true
      Tags:
        - Key: Name
          Value: !Sub '${AWS::StackName}-Public-Subnet'

  PublicRouteTable:
    Type: AWS::EC2::RouteTable
    Properties:
      VpcId: !Ref VPC
      Tags:
        - Key: Name
          Value: !Sub '${AWS::StackName}-Public-Routes'

  DefaultPublicRoute:
    Type: AWS::EC2::Route
    DependsOn: InternetGatewayAttachment
    Properties:
      RouteTableId: !Ref PublicRouteTable
      DestinationCidrBlock: 0.0.0.0/0
      GatewayId: !Ref InternetGateway

  PublicSubnetRouteTableAssociation:
    Type: AWS::EC2::SubnetRouteTableAssociation
    Properties:
      RouteTableId: !Ref PublicRouteTable
      SubnetId: !Ref PublicSubnet

  # Security Group Configuration
  MinecraftSecurityGroup:
    Type: AWS::EC2::SecurityGroup
    Properties:
      GroupName: !Sub '${AWS::StackName}-Minecraft-SG'
      GroupDescription: 'Security group for Minecraft server'
      VpcId: !Ref VPC
      SecurityGroupIngress:
        # SSH Access
        - IpProtocol: tcp
          FromPort: 22
          ToPort: 22
          CidrIp: !Ref SSHLocation
          Description: 'SSH access'
        # DNS (TCP)
        - IpProtocol: tcp
          FromPort: 53
          ToPort: 53
          CidrIp: 0.0.0.0/0
          Description: 'DNS TCP'
        # DNS (UDP)
        - IpProtocol: udp
          FromPort: 53
          ToPort: 53
          CidrIp: 0.0.0.0/0
          Description: 'DNS UDP'
        # Minecraft Java Edition
        - IpProtocol: tcp
          FromPort: 25565
          ToPort: 25565
          CidrIp: 0.0.0.0/0
          Description: 'Minecraft Java Edition'
        # Minecraft Bedrock Edition (TCP)
        - IpProtocol: tcp
          FromPort: 19132
          ToPort: 19132
          CidrIp: 0.0.0.0/0
          Description: 'Minecraft Bedrock TCP'
        # Minecraft Bedrock Edition (UDP)
        - IpProtocol: udp
          FromPort: 19132
          ToPort: 19133
          CidrIp: 0.0.0.0/0
          Description: 'Minecraft Bedrock UDP'
      SecurityGroupEgress:
        - IpProtocol: -1
          CidrIp: 0.0.0.0/0
          Description: 'Allow all outbound traffic'
      Tags:
        - Key: Name
          Value: !Sub '${AWS::StackName}-Minecraft-SG'

  # IAM Role for EC2
  EC2Role:
    Type: AWS::IAM::Role
    Properties:
      RoleName: !Sub '${AWS::StackName}-EC2-Role'
      AssumeRolePolicyDocument:
        Version: '2012-10-17'
        Statement:
          - Effect: Allow
            Principal:
              Service: ec2.amazonaws.com
            Action: sts:AssumeRole
      ManagedPolicyArns:
        - arn:aws:iam::aws:policy/AmazonSSMManagedInstanceCore
        - arn:aws:iam::aws:policy/CloudWatchAgentServerPolicy
      Tags:
        - Key: Name
          Value: !Sub '${AWS::StackName}-EC2-Role'

  EC2InstanceProfile:
    Type: AWS::IAM::InstanceProfile
    Properties:
      InstanceProfileName: !Sub '${AWS::StackName}-EC2-InstanceProfile'
      Path: '/'
      Roles:
        - !Ref EC2Role

  # EC2 Instance
  MinecraftInstance:
    Type: AWS::EC2::Instance
    DependsOn: InternetGatewayAttachment
    Properties:
      ImageId: ami-0c02fb55956c7d316  # Amazon Linux 2 AMI for x86_64 (update for your region)
      # For t4g instances (ARM), use: ami-0e4d0bb9670ea8db0
      InstanceType: !Ref InstanceType
      KeyName: !Ref KeyName
      IamInstanceProfile: !Ref EC2InstanceProfile
      SubnetId: !Ref PublicSubnet
      SecurityGroupIds:
        - !Ref MinecraftSecurityGroup
      BlockDeviceMappings:
        - DeviceName: /dev/xvda
          Ebs:
            VolumeType: gp3
            VolumeSize: 20
            DeleteOnTermination: true
            Encrypted: true
      UserData:
        Fn::Base64: !Sub |
          #!/bin/bash -xe
          
          # Update system
          yum update -y
          
          # Install Docker
          amazon-linux-extras install docker -y
          systemctl start docker
          systemctl enable docker
          usermod -a -G docker ec2-user
          
          # Install Docker Compose
          curl -L "https://github.com/docker/compose/releases/latest/download/docker-compose-$(uname -s)-$(uname -m)" -o /usr/local/bin/docker-compose
          chmod +x /usr/local/bin/docker-compose
          ln -s /usr/local/bin/docker-compose /usr/bin/docker-compose
          
          # Create directory structure
          mkdir -p /opt/minecraft/{data,plugins,bedrock-config,dns/zones}
          chown -R ec2-user:ec2-user /opt/minecraft
          
          # Create Docker Compose file
          cat > /opt/minecraft/docker-compose.yml << 'EOF'
          version: '3.8'
          
          services:
            minecraft-paper:
              image: itzg/minecraft-server
              container_name: minecraft-paper
              restart: unless-stopped
              ports:
                - "25565:25565"
              environment:
                EULA: "TRUE"
                TYPE: "PAPER"
                VERSION: "1.21.4"
                MEMORY: "2G"
                INIT_MEMORY: "1G"
                MAX_MEMORY: "2G"
                USE_AIKAR_FLAGS: "true"
                JVM_XX_OPTS: >-
                  -XX:+UseG1GC
                  -XX:+ParallelRefProcEnabled
                  -XX:MaxGCPauseMillis=200
                  -XX:+UnlockExperimentalVMOptions
                  -XX:+DisableExplicitGC
                  -XX:+AlwaysPreTouch
                  -XX:G1HeapRegionSize=8M
                  -XX:G1HeapWastePercent=5
                  -XX:G1MixedGCCountTarget=4
                  -XX:InitiatingHeapOccupancyPercent=15
                  -XX:G1MixedGCLiveThresholdPercent=90
                  -XX:G1RSetUpdatingPauseTimePercent=5
                  -XX:+PerfDisableSharedMem
                MOTD: "Paper Server with BedrockConnect"
                MODE: "survival"
                DIFFICULTY: "normal"
                MAX_PLAYERS: 20
                VIEW_DISTANCE: 10
                SIMULATION_DISTANCE: 8
                PLUGINS: |
                  https://download.geysermc.org/v2/projects/geyser/versions/latest/builds/latest/downloads/spigot
                  https://download.geysermc.org/v2/projects/floodgate/versions/latest/builds/latest/downloads/spigot
              volumes:
                - minecraft_data:/data
                - minecraft_plugins:/plugins
              networks:
                minecraft_net:
                  ipv4_address: 172.20.0.10
              deploy:
                resources:
                  limits:
                    memory: 2.5G
                    cpus: '1.5'
                  reservations:
                    memory: 2G
                    cpus: '1.0'
          
            bedrock-connect:
              image: strausmann/minecraft-bedrock-connect:2
              container_name: bedrock-connect
              restart: unless-stopped
              ports:
                - "19132:19132/udp"
              environment:
                NODB: "true"
                SERVER_LIMIT: 25
                KICK_INACTIVE: "true"
                CUSTOM_SERVERS: "/config/serverlist.json"
                USER_SERVERS: "false"
                FEATURED_SERVERS: "false"
              volumes:
                - bedrock_connect_config:/config
              networks:
                minecraft_net:
                  ipv4_address: 172.20.0.20
              deploy:
                resources:
                  limits:
                    memory: 256M
                    cpus: '0.3'
                  reservations:
                    memory: 128M
                    cpus: '0.2'
              depends_on:
                - minecraft-paper
          
            dns-server:
              image: internetsystemsconsortium/bind9:9.18
              container_name: minecraft-dns
              restart: unless-stopped
              ports:
                - "53:53/tcp"
                - "53:53/udp"
              volumes:
                - ./dns/named.conf.options:/etc/bind/named.conf.options
                - ./dns/named.conf.local:/etc/bind/named.conf.local
                - ./dns/zones:/etc/bind/zones
                - dns_cache:/var/cache/bind
              networks:
                minecraft_net:
                  ipv4_address: 172.20.0.5
              deploy:
                resources:
                  limits:
                    memory: 128M
                    cpus: '0.2'
          
          networks:
            minecraft_net:
              driver: bridge
              ipam:
                config:
                  - subnet: 172.20.0.0/16
          
          volumes:
            minecraft_data:
              driver: local
            minecraft_plugins:
              driver: local
            bedrock_connect_config:
              driver: local
            dns_cache:
              driver: local
          EOF
          
          # Create BedrockConnect server list configuration
          INSTANCE_IP=$(curl -s http://169.254.169.254/latest/meta-data/public-ipv4)
          
          cat > /opt/minecraft/bedrock-config/serverlist.json << EOF
          {
            "servers": [
              {
                "name": "My Minecraft Server",
                "iconUrl": "",
                "address": "$INSTANCE_IP",
                "port": 19132
              }
            ]
          }
          EOF
          
          # Create DNS configuration files
          # Get the instance's public IP
          INSTANCE_IP=$(curl -s http://169.254.169.254/latest/meta-data/public-ipv4)
          
          # Create BIND9 configuration
          cat > /opt/minecraft/dns/named.conf.options << EOF
          options {
              directory "/var/cache/bind";
              
              recursion yes;
              allow-query { any; };
              
              forwarders {
                  8.8.8.8;
                  8.8.4.4;
              };
              
              listen-on { any; };
              listen-on-v6 { none; };
              
              dnssec-validation no;
          };
          EOF
          
          cat > /opt/minecraft/dns/named.conf.local << EOF
          // Minecraft Bedrock Featured Servers
          zone "mco.mineplex.com" {
              type master;
              file "/etc/bind/zones/db.minecraft";
          };
          
          zone "geo.hivebedrock.network" {
              type master;
              file "/etc/bind/zones/db.minecraft";
          };
          
          zone "mco.cubecraft.net" {
              type master;
              file "/etc/bind/zones/db.minecraft";
          };
          
          zone "mco.lbsg.net" {
              type master;
              file "/etc/bind/zones/db.minecraft";
          };
          
          zone "play.inpvp.net" {
              type master;
              file "/etc/bind/zones/db.minecraft";
          };
          
          zone "play.galaxite.net" {
              type master;
              file "/etc/bind/zones/db.minecraft";
          };
          EOF
          
          # Create zone file that redirects to BedrockConnect
          cat > /opt/minecraft/dns/zones/db.minecraft << EOF
          \$TTL 60
          @       IN      SOA     ns1.minecraft.local. admin.minecraft.local. (
                                  2023010101      ; Serial
                                  3600            ; Refresh
                                  1800            ; Retry
                                  604800          ; Expire
                                  60 )            ; Negative Cache TTL
          
          @       IN      NS      ns1.minecraft.local.
          @       IN      A       172.20.0.20
          *       IN      A       172.20.0.20
          EOF
          
          # Create Geyser config
          mkdir -p /opt/minecraft/plugins/Geyser-Spigot
          cat > /opt/minecraft/plugins/Geyser-Spigot/config.yml << 'EOF'
          bedrock:
            address: 0.0.0.0
            port: 19132
            clone-remote-port: false
            motd1: "Geyser"
            motd2: "Minecraft Server"
            server-name: "Geyser"
          
          remote:
            address: auto
            port: 25565
            auth-type: floodgate
          
          debug-mode: false
          EOF
          
          # Set permissions
          chown -R 1000:1000 /opt/minecraft
          
          # Start services
          cd /opt/minecraft
          docker-compose up -d
          
          # Signal CloudFormation completion
          /opt/aws/bin/cfn-signal -e $? --stack ${AWS::StackName} --resource MinecraftInstance --region ${AWS::Region}
      Tags:
        - Key: Name
          Value: !Sub '${AWS::StackName}-Minecraft-Server'
    CreationPolicy:
      ResourceSignal:
        Timeout: PT15M

  # Elastic IP for consistent access
  ElasticIP:
    Type: AWS::EC2::EIP
    Properties:
      Domain: vpc
      InstanceId: !Ref MinecraftInstance
      Tags:
        - Key: Name
          Value: !Sub '${AWS::StackName}-EIP'

Outputs:
  InstanceId:
    Description: 'EC2 Instance ID'
    Value: !Ref MinecraftInstance

  PublicIP:
    Description: 'Public IP address of the server'
    Value: !Ref ElasticIP

  SSHCommand:
    Description: 'SSH command to connect to the instance'
    Value: !Sub 'ssh -i ${KeyName}.pem ec2-user@${ElasticIP}'

  MinecraftJavaConnection:
    Description: 'Minecraft Java Edition connection address'
    Value: !Sub '${ElasticIP}:25565'

  MinecraftBedrockConnection:
    Description: 'Minecraft Bedrock Edition connection address'
    Value: !Sub '${ElasticIP}:19132'

  BedrockConnectDNS:
    Description: 'DNS server to configure on Nintendo Switch'
    Value: !Ref ElasticIP
```

## Docker Compose Configuration

The Docker Compose configuration (already included in the CloudFormation template) includes Paper server, BedrockConnect, and a BIND9 DNS server:

```yaml
version: '3.8'

services:
  minecraft-paper:
    image: itzg/minecraft-server
    container_name: minecraft-paper
    restart: unless-stopped
    ports:
      - "25565:25565"
    environment:
      EULA: "TRUE"
      TYPE: "PAPER"
      VERSION: "1.21.4"
      # Memory Settings (Optimized for t4g.medium with 4GB RAM)
      MEMORY: "2G"
      INIT_MEMORY: "1G"
      MAX_MEMORY: "2G"
      # Performance Optimization
      USE_AIKAR_FLAGS: "true"
      # Server Configuration
      MOTD: "Paper Server with BedrockConnect"
      MODE: "survival"
      DIFFICULTY: "normal"
      MAX_PLAYERS: 20
      VIEW_DISTANCE: 10
      SIMULATION_DISTANCE: 8
      # Auto-download Geyser and Floodgate plugins
      PLUGINS: |
        https://download.geysermc.org/v2/projects/geyser/versions/latest/builds/latest/downloads/spigot
        https://download.geysermc.org/v2/projects/floodgate/versions/latest/builds/latest/downloads/spigot
    volumes:
      - minecraft_data:/data
      - minecraft_plugins:/plugins
    networks:
      minecraft_net:
        ipv4_address: 172.20.0.10
    deploy:
      resources:
        limits:
          memory: 2.5G
          cpus: '1.5'

  bedrock-connect:
    image: strausmann/minecraft-bedrock-connect:2
    container_name: bedrock-connect
    restart: unless-stopped
    ports:
      - "19132:19132/udp"
    environment:
      NODB: "true"
      SERVER_LIMIT: 25
      CUSTOM_SERVERS: "/config/serverlist.json"
    volumes:
      - bedrock_connect_config:/config
    networks:
      minecraft_net:
        ipv4_address: 172.20.0.20
    deploy:
      resources:
        limits:
          memory: 256M
          cpus: '0.3'

  dns-server:
    image: internetsystemsconsortium/bind9:9.18
    container_name: minecraft-dns
    restart: unless-stopped
    ports:
      - "53:53/tcp"
      - "53:53/udp"
    volumes:
      - dns_config:/etc/bind
      - dns_cache:/var/cache/bind
    networks:
      minecraft_net:
        ipv4_address: 172.20.0.5
    deploy:
      resources:
        limits:
          memory: 128M
          cpus: '0.2'

networks:
  minecraft_net:
    driver: bridge
    ipam:
      config:
        - subnet: 172.20.0.0/16

volumes:
  minecraft_data:
    driver: local
  minecraft_plugins:
    driver: local
  bedrock_connect_config:
    driver: local
  dns_config:
    driver: local
  dns_cache:
    driver: local
```

## Deployment Instructions via AWS CLI

1. **Prepare your AWS environment**:
```bash
# Configure AWS CLI if not already done
aws configure

# Create or import an EC2 key pair
aws ec2 create-key-pair --key-name minecraft-key --query 'KeyMaterial' --output text > minecraft-key.pem
chmod 400 minecraft-key.pem
```

2. **Deploy the CloudFormation stack**:
```bash
# Deploy the stack
aws cloudformation create-stack \
  --stack-name minecraft-bedrock-server \
  --template-body file://minecraft-bedrock-server.yaml \
  --parameters ParameterKey=KeyName,ParameterValue=minecraft-key \
               ParameterKey=InstanceType,ParameterValue=t4g.medium \
               ParameterKey=SSHLocation,ParameterValue=0.0.0.0/0 \
  --capabilities CAPABILITY_NAMED_IAM \
  --region us-east-1

# Monitor deployment status
aws cloudformation describe-stacks \
  --stack-name minecraft-bedrock-server \
  --query 'Stacks[0].StackStatus' \
  --region us-east-1

# Wait for completion
aws cloudformation wait stack-create-complete \
  --stack-name minecraft-bedrock-server \
  --region us-east-1

# Get outputs
aws cloudformation describe-stacks \
  --stack-name minecraft-bedrock-server \
  --query 'Stacks[0].Outputs' \
  --region us-east-1
```

3. **Update the stack** (if needed):
```bash
aws cloudformation update-stack \
  --stack-name minecraft-bedrock-server \
  --template-body file://minecraft-bedrock-server.yaml \
  --parameters ParameterKey=KeyName,UsePreviousValue=true \
               ParameterKey=InstanceType,ParameterValue=t4g.small \
  --capabilities CAPABILITY_NAMED_IAM
```

## Nintendo Switch Connection Instructions

1. **Configure DNS on Nintendo Switch**:
   - Go to System Settings → Internet → Internet Settings
   - Select your WiFi network → Change Settings
   - DNS Settings → Manual
   - Primary DNS: `[Your EC2 Instance Public IP]`
   - Secondary DNS: `8.8.8.8`
   - Save settings

2. **Connect to your server**:
   - Launch Minecraft
   - Go to Servers tab
   - Select any Featured Server (e.g., The Hive, Mineplex, CubeCraft)
   - You'll automatically see only your server: "My Minecraft Server"
   - Click to join - no need to enter IP addresses!

## How BedrockConnect Works (Technical Details)

BedrockConnect enables cross-platform play through DNS redirection:

1. **DNS Hijacking**: Your self-hosted BIND9 DNS server redirects Featured Server domains to BedrockConnect
2. **Server Selection Menu**: BedrockConnect presents your custom server list
3. **Transfer Packet**: Uses Minecraft's native Transfer Packet to redirect to your server
4. **Protocol Translation**: Geyser translates between Bedrock and Java protocols

### Self-Hosted DNS Advantages

- **Complete Control**: No dependency on third-party DNS servers
- **Better Security**: All DNS queries stay within your infrastructure
- **Lower Latency**: Direct connection without intermediate hops
- **Simplified Experience**: Players only see your server, no confusing menus
- **Privacy**: No external logging of your players' connections

### BedrockConnect Configuration

With `FEATURED_SERVERS: "false"` and `USER_SERVERS: "false"`, BedrockConnect:
- Only shows servers from your custom serverlist.json
- Removes the "Featured Servers" section
- Removes the "Add Server" option
- Provides a clean, single-server experience

The DNS server redirects these Featured Server domains to your BedrockConnect:
- `mco.mineplex.com`
- `geo.hivebedrock.network`
- `mco.cubecraft.net`
- `mco.lbsg.net`
- `play.inpvp.net`
- `play.galaxite.net`

## Networking Configuration Details

The setup creates an isolated Docker network where:
- Paper server listens on port 25565 (Java Edition)
- Geyser listens on port 19132 (Bedrock Edition)
- Both services communicate internally via Docker network
- Security groups allow both TCP and UDP traffic on required ports

## Best Practices for AWS Minecraft Hosting

1. **Instance Selection**: 
   - Use t4g.small or t4g.medium for better performance
   - ARM instances offer 40% better price/performance

2. **Storage**:
   - Use GP3 volumes with 3000 IOPS for world data
   - Enable EBS snapshots for backups

3. **Monitoring**:
   - Set up CloudWatch alarms for CPU and memory
   - Monitor server TPS (ticks per second)

4. **Cost Optimization**:
   - Use scheduled scaling to shut down when inactive
   - Consider spot instances for development servers

5. **Security**:
   - Restrict SSH access to specific IPs
   - Keep software updated regularly
   - Use IAM roles instead of hardcoded credentials

## Troubleshooting Common Issues

1. **Nintendo Switch can't connect**:
   - Verify DNS settings are correct
   - Restart the console after DNS changes
   - Check security group allows UDP port 19132

2. **Performance expectations**:
   - Supports 20-30 concurrent players comfortably
   - View distance of 10 chunks with smooth performance
   - Minimal lag with proper optimization

3. **DNS server issues**:
   - Check DNS is running: `docker logs minecraft-dns`
   - Test DNS resolution: `nslookup mco.lbsg.net [Your-EC2-IP]`
   - Ensure port 53 is open in security groups
   - May need to disable systemd-resolved on the host

This setup provides a robust, self-contained Minecraft server solution with your own DNS server, accessible from both Java and Bedrock editions. The t4g.medium instance offers excellent performance for the price, capable of handling 20-30 players smoothly. The total monthly cost of approximately $30 includes the instance, storage, and typical data transfer, making it very competitive with commercial Minecraft hosting services while giving you full control over your server and DNS infrastructure.