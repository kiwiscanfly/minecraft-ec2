#!/bin/bash

# Minecraft World Configuration Script
# Usage: ./configure-world.sh [--interactive] [--creative] [--survival] [--reset]

set -e

WORLD_CONFIG_FILE=".env.world.json"

# Function to create default world configuration from example
create_default_config() {
    if [ -f ".env.world.json.example" ]; then
        cp ".env.world.json.example" "$WORLD_CONFIG_FILE"
        echo "✅ Created world configuration from example: $WORLD_CONFIG_FILE"
    else
        echo "❌ No .env.world.json.example found!"
        echo "Please ensure .env.world.json.example exists in the project directory."
        echo "This file should contain the default world configuration template."
        return 1
    fi
}

# Function to update world mode
set_creative_mode() {
    if [ ! -f "$WORLD_CONFIG_FILE" ]; then
        create_default_config
    fi
    
    # Update the JSON file to set creative mode and enable flight
    sed -i.bak 's/"mode": "[^"]*"/"mode": "creative"/g' "$WORLD_CONFIG_FILE"
    sed -i.bak 's/"allow_flight": [^,]*/"allow_flight": true/g' "$WORLD_CONFIG_FILE"
    sed -i.bak 's/"enable_command_blocks": [^,]*/"enable_command_blocks": true/g' "$WORLD_CONFIG_FILE"
    rm "${WORLD_CONFIG_FILE}.bak" 2>/dev/null || true
    
    echo "✅ Set world to CREATIVE mode"
    echo "   - Flight enabled"
    echo "   - Command blocks enabled"
}

set_survival_mode() {
    if [ ! -f "$WORLD_CONFIG_FILE" ]; then
        create_default_config
    fi
    
    # Update the JSON file to set survival mode
    sed -i.bak 's/"mode": "[^"]*"/"mode": "survival"/g' "$WORLD_CONFIG_FILE"
    sed -i.bak 's/"allow_flight": [^,]*/"allow_flight": false/g' "$WORLD_CONFIG_FILE"
    rm "${WORLD_CONFIG_FILE}.bak" 2>/dev/null || true
    
    echo "✅ Set world to SURVIVAL mode"
    echo "   - Flight disabled"
}

# Function to run interactive configuration
interactive_config() {
    echo "🎮 Interactive Minecraft World Configuration"
    echo "============================================"
    
    if [ ! -f "$WORLD_CONFIG_FILE" ]; then
        create_default_config
    fi
    
    # Load current values
    CURRENT_NAME=$(cat "$WORLD_CONFIG_FILE" | grep -o '"name": *"[^"]*"' | head -1 | cut -d'"' -f4)
    CURRENT_MODE=$(cat "$WORLD_CONFIG_FILE" | grep -o '"mode": *"[^"]*"' | cut -d'"' -f4)
    CURRENT_DIFFICULTY=$(cat "$WORLD_CONFIG_FILE" | grep -o '"difficulty": *"[^"]*"' | cut -d'"' -f4)
    CURRENT_MAX_PLAYERS=$(cat "$WORLD_CONFIG_FILE" | grep -o '"max_players": *[0-9]*' | cut -d':' -f2 | tr -d ' ')
    
    echo ""
    echo "Current settings:"
    echo "  Name: $CURRENT_NAME"
    echo "  Mode: $CURRENT_MODE"
    echo "  Difficulty: $CURRENT_DIFFICULTY"
    echo "  Max Players: $CURRENT_MAX_PLAYERS"
    echo ""
    
    # Server name
    read -p "Server name [$CURRENT_NAME]: " NEW_NAME
    NEW_NAME=${NEW_NAME:-$CURRENT_NAME}
    
    # Game mode
    echo ""
    echo "Game modes:"
    echo "  1) Survival"
    echo "  2) Creative" 
    echo "  3) Adventure"
    echo "  4) Spectator"
    read -p "Select mode (1-4) [current: $CURRENT_MODE]: " MODE_CHOICE
    
    case $MODE_CHOICE in
        1) NEW_MODE="survival" ;;
        2) NEW_MODE="creative" ;;
        3) NEW_MODE="adventure" ;;
        4) NEW_MODE="spectator" ;;
        *) NEW_MODE=$CURRENT_MODE ;;
    esac
    
    # Difficulty
    echo ""
    echo "Difficulty levels:"
    echo "  1) Peaceful"
    echo "  2) Easy"
    echo "  3) Normal"
    echo "  4) Hard"
    read -p "Select difficulty (1-4) [current: $CURRENT_DIFFICULTY]: " DIFF_CHOICE
    
    case $DIFF_CHOICE in
        1) NEW_DIFFICULTY="peaceful" ;;
        2) NEW_DIFFICULTY="easy" ;;
        3) NEW_DIFFICULTY="normal" ;;
        4) NEW_DIFFICULTY="hard" ;;
        *) NEW_DIFFICULTY=$CURRENT_DIFFICULTY ;;
    esac
    
    # Max players
    read -p "Max players (1-100) [$CURRENT_MAX_PLAYERS]: " NEW_MAX_PLAYERS
    NEW_MAX_PLAYERS=${NEW_MAX_PLAYERS:-$CURRENT_MAX_PLAYERS}
    
    # Update the JSON file
    sed -i.bak "s/\"name\": \"[^\"]*\"/\"name\": \"$NEW_NAME\"/g" "$WORLD_CONFIG_FILE"
    sed -i.bak "s/\"mode\": \"[^\"]*\"/\"mode\": \"$NEW_MODE\"/g" "$WORLD_CONFIG_FILE"
    sed -i.bak "s/\"difficulty\": \"[^\"]*\"/\"difficulty\": \"$NEW_DIFFICULTY\"/g" "$WORLD_CONFIG_FILE"
    sed -i.bak "s/\"max_players\": [0-9]*/\"max_players\": $NEW_MAX_PLAYERS/g" "$WORLD_CONFIG_FILE"
    
    # Set flight based on creative mode
    if [ "$NEW_MODE" = "creative" ]; then
        sed -i.bak 's/"allow_flight": [^,]*/"allow_flight": true/g' "$WORLD_CONFIG_FILE"
        sed -i.bak 's/"enable_command_blocks": [^,]*/"enable_command_blocks": true/g' "$WORLD_CONFIG_FILE"
    fi
    
    rm "${WORLD_CONFIG_FILE}.bak" 2>/dev/null || true
    
    echo ""
    echo "✅ World configuration updated!"
    echo "   Name: $NEW_NAME"
    echo "   Mode: $NEW_MODE"
    echo "   Difficulty: $NEW_DIFFICULTY" 
    echo "   Max Players: $NEW_MAX_PLAYERS"
}

# Function to apply live configuration changes (no restart required)
apply_live_changes() {
    if [ ! -f ".env.server.json" ]; then
        echo "❌ No .env.server.json found. Deploy the server first with ./deploy.sh"
        return 1
    fi
    
    PUBLIC_IP=$(cat .env.server.json | grep -o '"PUBLIC_IP": *"[^"]*"' | cut -d'"' -f4)
    SSH_KEY=$(cat .env.server.json | grep -o '"KEY_NAME": *"[^"]*"' | cut -d'"' -f4).pem
    
    if [ -z "$PUBLIC_IP" ]; then
        echo "❌ Could not find PUBLIC_IP in .env.server.json"
        return 1
    fi
    
    # Get current world settings
    CURRENT_MODE=$(cat "$WORLD_CONFIG_FILE" | grep -o '"mode": *"[^"]*"' | cut -d'"' -f4)
    CURRENT_DIFFICULTY=$(cat "$WORLD_CONFIG_FILE" | grep -o '"difficulty": *"[^"]*"' | cut -d'"' -f4)
    CURRENT_PVP=$(cat "$WORLD_CONFIG_FILE" | grep -o '"pvp": *[a-z]*' | cut -d':' -f2 | tr -d ' ')
    CURRENT_FLIGHT=$(cat "$WORLD_CONFIG_FILE" | grep -o '"allow_flight": *[a-z]*' | cut -d':' -f2 | tr -d ' ')
    CURRENT_CMD_BLOCKS=$(cat "$WORLD_CONFIG_FILE" | grep -o '"enable_command_blocks": *[a-z]*' | cut -d':' -f2 | tr -d ' ')
    
    echo "🔄 Applying live configuration changes to server at $PUBLIC_IP..."
    echo "   Mode: $CURRENT_MODE"
    echo "   Difficulty: $CURRENT_DIFFICULTY"
    echo "   PvP: $CURRENT_PVP"
    echo "   Command Blocks: $CURRENT_CMD_BLOCKS"
    
    # Apply live changes via RCON
    ssh -i "$SSH_KEY" -o StrictHostKeyChecking=no ec2-user@"$PUBLIC_IP" << REMOTE_EOF
        echo "📡 Applying live server changes via RCON..."
        
        # Set difficulty
        docker exec minecraft-paper rcon-cli "difficulty $CURRENT_DIFFICULTY"
        
        # Set default game mode for new players
        docker exec minecraft-paper rcon-cli "defaultgamemode $CURRENT_MODE"
        
        # Change ALL currently online players to the new game mode
        echo "🎮 Changing all online players to $CURRENT_MODE mode..."
        docker exec minecraft-paper rcon-cli "gamemode $CURRENT_MODE @a"
        
        # Enable force gamemode to ensure offline players get the new mode when they join
        docker exec minecraft-paper rcon-cli "gamerule forceGamemode true"
        
        # Set PvP
        docker exec minecraft-paper rcon-cli "gamerule pvp $CURRENT_PVP"
        
        # Set command blocks
        docker exec minecraft-paper rcon-cli "gamerule enableCommandBlock $CURRENT_CMD_BLOCKS"
        
        # If creative mode, enable some helpful game rules
        if [ "$CURRENT_MODE" = "creative" ]; then
            docker exec minecraft-paper rcon-cli "gamerule keepInventory true"
            docker exec minecraft-paper rcon-cli "gamerule mobGriefing false"
            docker exec minecraft-paper rcon-cli "say Server switched to Creative Mode! Have fun building!"
            echo "✅ Creative mode optimizations applied"
        fi
        
        # If survival mode, set appropriate game rules
        if [ "$CURRENT_MODE" = "survival" ]; then
            docker exec minecraft-paper rcon-cli "gamerule keepInventory false"
            docker exec minecraft-paper rcon-cli "gamerule mobGriefing true"
            docker exec minecraft-paper rcon-cli "say Server switched to Survival Mode! Good luck!"
            echo "✅ Survival mode settings applied"
        fi
        
        # Show current online players
        echo "📋 Current online players:"
        docker exec minecraft-paper rcon-cli "list"
        
        echo "✅ Live configuration changes applied!"
        echo "Note: Some settings (max players, view distance, MOTD) require server restart"
REMOTE_EOF
}

# Function to apply full configuration (requires restart)
apply_full_restart() {
    if [ ! -f ".env.server.json" ]; then
        echo "❌ No .env.server.json found. Deploy the server first with ./deploy.sh"
        return 1
    fi
    
    PUBLIC_IP=$(cat .env.server.json | grep -o '"PUBLIC_IP": *"[^"]*"' | cut -d'"' -f4)
    SSH_KEY=$(cat .env.server.json | grep -o '"KEY_NAME": *"[^"]*"' | cut -d'"' -f4).pem
    
    if [ -z "$PUBLIC_IP" ]; then
        echo "❌ Could not find PUBLIC_IP in .env.server.json"
        return 1
    fi
    
    echo "🔄 Applying full configuration to server at $PUBLIC_IP (requires restart)..."
    
    # Upload the world config and restart services
    scp -i "$SSH_KEY" -o StrictHostKeyChecking=no "$WORLD_CONFIG_FILE" ec2-user@"$PUBLIC_IP":~/
    
    ssh -i "$SSH_KEY" -o StrictHostKeyChecking=no ec2-user@"$PUBLIC_IP" << 'REMOTE_EOF'
        sudo cp .env.world.json /opt/minecraft/
        cd /opt/minecraft
        sudo docker-compose down
        sudo ./setup.sh $(cat .env.server.json | grep -o '"PUBLIC_IP": *"[^"]*"' | cut -d'"' -f4) \
                        $(cat .env.server.json | grep -o '"STACK_NAME": *"[^"]*"' | cut -d'"' -f4) \
                        $(cat .env.server.json | grep -o '"REGION": *"[^"]*"' | cut -d'"' -f4)
REMOTE_EOF
    
    echo "✅ Full configuration applied successfully!"
}

# Function to choose application method
apply_to_server() {
    echo ""
    echo "How do you want to apply the changes?"
    echo "  1) Live changes only (no restart) - applies game mode, difficulty, PvP, command blocks"
    echo "  2) Full restart (all settings) - applies max players, view distance, MOTD, etc."
    echo "  3) Both (live changes first, then ask about restart)"
    read -p "Select option (1-3): " APPLY_METHOD
    
    case $APPLY_METHOD in
        1)
            apply_live_changes
            ;;
        2)
            apply_full_restart
            ;;
        3)
            apply_live_changes
            echo ""
            read -p "Also apply settings requiring restart? (y/N): " RESTART_TOO
            if [[ $RESTART_TOO =~ ^[Yy]$ ]]; then
                apply_full_restart
            fi
            ;;
        *)
            echo "❌ Invalid selection"
            return 1
            ;;
    esac
}

# Main script logic
case "$1" in
    --interactive|-i)
        interactive_config
        echo ""
        read -p "Apply to running server? (y/N): " APPLY
        if [[ $APPLY =~ ^[Yy]$ ]]; then
            apply_to_server
        fi
        ;;
    --creative|-c)
        set_creative_mode
        echo ""
        read -p "Apply to running server? (y/N): " APPLY
        if [[ $APPLY =~ ^[Yy]$ ]]; then
            apply_to_server
        fi
        ;;
    --survival|-s)
        set_survival_mode
        echo ""
        read -p "Apply to running server? (y/N): " APPLY
        if [[ $APPLY =~ ^[Yy]$ ]]; then
            apply_to_server
        fi
        ;;
    --reset|-r)
        if [ -f "$WORLD_CONFIG_FILE" ]; then
            cp "$WORLD_CONFIG_FILE" "${WORLD_CONFIG_FILE}.backup"
            echo "📋 Backed up existing config to ${WORLD_CONFIG_FILE}.backup"
        fi
        create_default_config
        ;;
    --help|-h|*)
        echo "Minecraft World Configuration Script"
        echo ""
        echo "Usage: $0 [OPTION]"
        echo ""
        echo "Options:"
        echo "  -i, --interactive    Interactive configuration wizard"
        echo "  -c, --creative       Set server to creative mode"
        echo "  -s, --survival       Set server to survival mode"
        echo "  -r, --reset          Reset to default configuration"
        echo "  -h, --help           Show this help message"
        echo ""
        echo "Examples:"
        echo "  $0 --interactive     # Configure server interactively"
        echo "  $0 --creative        # Quick switch to creative mode (with live update option)"
        echo "  $0 --survival        # Quick switch to survival mode (with live update option)"
        echo ""
        echo "Live vs Full Updates:"
        echo "  Live updates: Game mode, difficulty, PvP, command blocks (no restart)"
        echo "  Full updates: Max players, view distance, MOTD (requires restart)"
        echo ""
        echo "Configuration file: $WORLD_CONFIG_FILE"
        if [ -f "$WORLD_CONFIG_FILE" ]; then
            echo "✅ Configuration file exists"
        else
            echo "❌ No configuration file found (will create default)"
        fi
        ;;
esac