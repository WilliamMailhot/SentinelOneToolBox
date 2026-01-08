#!/bin/bash

# Colors for better visual output
CYAN='\033[0;36m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m' # No Color

# Clear the screen
clear

echo -e "${GREEN}SentinelOne LogStash Server Configurator${NC}"
echo ""

# Prompt for API Key
echo -e "${YELLOW}Please enter your SentinelOne API key:${NC}"
read API_KEY
echo ""

# Validate that API key is not empty
if [ -z "$API_KEY" ]; then
    echo -e "${YELLOW}⚠ Warning: No API key provided!${NC}"
    exit 1
fi

echo -e "${GREEN}✓ API key received successfully!${NC}"
echo ""

# Export API key for use throughout the script
export SENTINELONE_API_KEY="$API_KEY"

# Check system resources
echo -e "${CYAN}═══════════════════════════════════════════════════════════════════${NC}"
echo -e "${YELLOW}Checking System Resources...${NC}"
echo -e "${CYAN}═══════════════════════════════════════════════════════════════════${NC}"
echo ""

TOTAL_MEM=$(free -m | awk '/^Mem:/{print $2}')
AVAILABLE_MEM=$(free -m | awk '/^Mem:/{print $7}')

echo -e "${CYAN}Total Memory: ${TOTAL_MEM}MB${NC}"
echo -e "${CYAN}Available Memory: ${AVAILABLE_MEM}MB${NC}"

if [ "$TOTAL_MEM" -lt 2048 ]; then
    echo -e "${YELLOW}⚠ WARNING: System has less than 2GB RAM${NC}"
    echo -e "${YELLOW}  LogStash requires at least 2GB for stable operation${NC}"
    echo -e "${YELLOW}  Consider using at least a t3.small EC2 instance${NC}"
    read -p "Continue anyway? (y/n): " CONTINUE_LOW_MEM
    if [[ ! "$CONTINUE_LOW_MEM" =~ ^[Yy]$ ]]; then
        echo -e "${YELLOW}Installation cancelled${NC}"
        exit 1
    fi
fi
echo ""

echo -e "${CYAN}═══════════════════════════════════════════════════════════════════${NC}"
echo -e "${YELLOW}Installing LogStash...${NC}"
echo -e "${CYAN}═══════════════════════════════════════════════════════════════════${NC}"
echo ""

# Install LogStash
echo -e "${CYAN}[1/4] Adding Elastic GPG key...${NC}"
wget -qO - https://artifacts.elastic.co/GPG-KEY-elasticsearch | sudo gpg --dearmor -o /usr/share/keyrings/elastic-keyring.gpg

echo -e "${CYAN}[2/4] Installing apt-transport-https...${NC}"
sudo apt-get install -y apt-transport-https

echo -e "${CYAN}[3/4] Adding Elastic repository...${NC}"
echo "deb [signed-by=/usr/share/keyrings/elastic-keyring.gpg] https://artifacts.elastic.co/packages/9.x/apt stable main" | sudo tee -a /etc/apt/sources.list.d/elastic-9.x.list

echo -e "${CYAN}[4/4] Installing LogStash...${NC}"
sudo apt-get update && sudo apt-get install -y logstash

echo ""
echo -e "${CYAN}Enabling LogStash service...${NC}"
sudo systemctl enable logstash

# Configure LogStash to use privileged ports
echo -e "${CYAN}Configuring LogStash for privileged ports...${NC}"
sudo setcap 'cap_net_bind_service=+ep' /usr/share/logstash/jdk/bin/java

echo -e "${GREEN}✓ LogStash installation complete and service enabled!${NC}"
echo ""

# Install SentinelOne Collector
echo -e "${CYAN}═══════════════════════════════════════════════════════════════════${NC}"
echo -e "${YELLOW}Installing SentinelOne Collector...${NC}"
echo -e "${CYAN}═══════════════════════════════════════════════════════════════════${NC}"
echo ""

curl -sO https://www.scalyr.com/install-agent.sh
sudo bash ./install-agent.sh --use-aio-package --set-api-key "$API_KEY" --set-scalyr-server "https://xdr.us1.sentinelone.net" --start-agent --force-apt

echo ""
echo -e "${CYAN}Enabling SentinelOne Collector service...${NC}"
sudo systemctl enable scalyr-agent-2
echo -e "${GREEN}✓ SentinelOne Collector installation complete and service enabled!${NC}"
echo ""

# Store data source info for later scalyr configuration
SCALYR_CONFIG_NEEDED=true

# Configure data sources
echo -e "${CYAN}═══════════════════════════════════════════════════════════════════${NC}"
echo -e "${YELLOW}Data Source Configuration${NC}"
echo -e "${CYAN}═══════════════════════════════════════════════════════════════════${NC}"
echo ""

# Ask for number of data sources
echo -e "${YELLOW}How many data sources do you want to configure for LogStash?${NC}"
read -p "Number of sources: " NUM_SOURCES
echo ""

# Validate input
if ! [[ "$NUM_SOURCES" =~ ^[0-9]+$ ]] || [ "$NUM_SOURCES" -lt 1 ]; then
    echo -e "${YELLOW}⚠ Invalid number. Please enter a positive integer.${NC}"
    exit 1
fi

# Array to store configurations
declare -a DATA_SOURCES
declare -a DATA_PORTS
declare -a DATA_TYPES

# Collect information for each data source
for ((i=1; i<=NUM_SOURCES; i++)); do
    echo -e "${GREEN}═══ Data Source $i of $NUM_SOURCES ═══${NC}"
    
    # Get source name
    read -p "Enter name for data source $i: " SOURCE_NAME
    
    # Get port number
    read -p "Enter port number for $SOURCE_NAME: " SOURCE_PORT
    
    # Validate port number
    if ! [[ "$SOURCE_PORT" =~ ^[0-9]+$ ]] || [ "$SOURCE_PORT" -lt 1 ] || [ "$SOURCE_PORT" -gt 65535 ]; then
        echo -e "${YELLOW}⚠ Invalid port number. Using default port 5000${NC}"
        SOURCE_PORT=5000
    fi
    
    # Check for port 514 and rsyslog conflict
    if [ "$SOURCE_PORT" -eq 514 ]; then
        echo -e "${YELLOW}⚠ Port 514 detected - this is typically used by rsyslog${NC}"
        
        # Check if rsyslog is running and using port 514
        if systemctl is-active --quiet rsyslog && sudo ss -ulnp | grep -q ":514 "; then
            echo -e "${YELLOW}⚠ rsyslog is currently using port 514${NC}"
            echo -e "${CYAN}Options:${NC}"
            echo "  1) Disable rsyslog on port 514 (recommended)"
            echo "  2) Use a different port (e.g., 1514)"
            echo "  3) Continue anyway (may cause conflicts)"
            read -p "Choice (1-3): " RSYSLOG_CHOICE
            
            case $RSYSLOG_CHOICE in
                1)
                    echo -e "${CYAN}Disabling rsyslog network listener on port 514...${NC}"
                    # Comment out UDP/TCP syslog listening in rsyslog
                    sudo sed -i 's/^module(load="imudp")/# module(load="imudp")/' /etc/rsyslog.conf
                    sudo sed -i 's/^input(type="imudp" port="514")/# input(type="imudp" port="514")/' /etc/rsyslog.conf
                    sudo sed -i 's/^module(load="imtcp")/# module(load="imtcp")/' /etc/rsyslog.conf
                    sudo sed -i 's/^input(type="imtcp" port="514")/# input(type="imtcp" port="514")/' /etc/rsyslog.conf
                    sudo systemctl restart rsyslog
                    echo -e "${GREEN}✓ rsyslog port 514 disabled${NC}"
                    ;;
                2)
                    echo -e "${YELLOW}Please enter a new port number:${NC}"
                    read -p "New port: " SOURCE_PORT
                    if ! [[ "$SOURCE_PORT" =~ ^[0-9]+$ ]]; then
                        SOURCE_PORT=1514
                        echo -e "${YELLOW}Invalid input, using port 1514${NC}"
                    fi
                    ;;
                3)
                    echo -e "${YELLOW}⚠ Continuing with port 514 - conflicts may occur${NC}"
                    ;;
            esac
        fi
    fi
    
    # Warn about privileged ports
    if [ "$SOURCE_PORT" -lt 1024 ] && [ "$SOURCE_PORT" -ne 514 ]; then
        echo -e "${YELLOW}⚠ Port $SOURCE_PORT is a privileged port (<1024)${NC}"
        echo -e "${CYAN}  LogStash has been configured with CAP_NET_BIND_SERVICE capability${NC}"
    fi
    
    # Get input type
    echo -e "${CYAN}Select input type:${NC}"
    echo "  1) TCP"
    echo "  2) UDP"
    echo "  3) Syslog"
    echo "  4) Beats"
    read -p "Choice (1-4): " INPUT_TYPE_CHOICE
    
    case $INPUT_TYPE_CHOICE in
        1) INPUT_TYPE="tcp" ;;
        2) INPUT_TYPE="udp" ;;
        3) INPUT_TYPE="syslog" ;;
        4) INPUT_TYPE="beats" ;;
        *) INPUT_TYPE="tcp" ;;
    esac
    
    DATA_SOURCES+=("$SOURCE_NAME")
    DATA_PORTS+=("$SOURCE_PORT")
    DATA_TYPES+=("$INPUT_TYPE")
    
    echo -e "${GREEN}✓ $SOURCE_NAME configured on port $SOURCE_PORT ($INPUT_TYPE)${NC}"
    echo ""
done

# Create LogStash configuration files
echo -e "${CYAN}═══════════════════════════════════════════════════════════════════${NC}"
echo -e "${YELLOW}Creating LogStash Configuration Files...${NC}"
echo -e "${CYAN}═══════════════════════════════════════════════════════════════════${NC}"
echo ""

LOGSTASH_CONF_DIR="/etc/logstash/conf.d"
LOGSTASH_LOG_DIR="/var/log/logstash"

# Create log directory if it doesn't exist
if [ ! -d "$LOGSTASH_LOG_DIR" ]; then
    echo -e "${CYAN}Creating LogStash log directory...${NC}"
    sudo mkdir -p "$LOGSTASH_LOG_DIR"
    sudo chown logstash:logstash "$LOGSTASH_LOG_DIR"
    sudo chmod 755 "$LOGSTASH_LOG_DIR"
    echo -e "${GREEN}✓ Created $LOGSTASH_LOG_DIR${NC}"
fi
echo ""

for ((i=0; i<${#DATA_SOURCES[@]}; i++)); do
    SOURCE_NAME="${DATA_SOURCES[$i]}"
    SOURCE_PORT="${DATA_PORTS[$i]}"
    INPUT_TYPE="${DATA_TYPES[$i]}"
    
    # Sanitize source name for filename
    SAFE_NAME=$(echo "$SOURCE_NAME" | tr '[:upper:]' '[:lower:]' | tr ' ' '_' | tr -cd '[:alnum:]_-')
    CONFIG_FILE="$LOGSTASH_CONF_DIR/${SAFE_NAME}.conf"
    
    echo -e "${CYAN}Creating configuration for $SOURCE_NAME...${NC}"
    
    # Start the configuration file
    sudo tee "$CONFIG_FILE" > /dev/null << EOF
# Configuration for $SOURCE_NAME
# Port: $SOURCE_PORT
# Type: $INPUT_TYPE

input {
EOF

    # Add appropriate input configuration based on type
    case $INPUT_TYPE in
        "tcp")
            sudo tee -a "$CONFIG_FILE" > /dev/null << EOF
  tcp {
    port => $SOURCE_PORT
    tags => ["$SOURCE_NAME", "tcp"]
  }
EOF
            ;;
        "udp")
            sudo tee -a "$CONFIG_FILE" > /dev/null << EOF
  udp {
    port => $SOURCE_PORT
    tags => ["$SOURCE_NAME", "udp"]
  }
EOF
            ;;
        "syslog")
            sudo tee -a "$CONFIG_FILE" > /dev/null << EOF
  syslog {
    port => $SOURCE_PORT
    tags => ["$SOURCE_NAME", "syslog"]
  }
EOF
            ;;
        "beats")
            sudo tee -a "$CONFIG_FILE" > /dev/null << EOF
  beats {
    port => $SOURCE_PORT
    tags => ["$SOURCE_NAME", "beats"]
  }
EOF
            ;;
    esac
    
    # Close input block and add output section with logic isolation
    sudo tee -a "$CONFIG_FILE" > /dev/null << EOF
}

output {
  # Conditional check ensures data isolation in merged pipelines
  if "$SOURCE_NAME" in [tags] {
    file {
      path => "$LOGSTASH_LOG_DIR/${SAFE_NAME}.log"
      codec => line { format => "%{message}" }
    }
  }
}
EOF
    
    echo -e "${GREEN}✓ Created $CONFIG_FILE${NC}"
    echo -e "${CYAN}  → Output: $LOGSTASH_LOG_DIR/${SAFE_NAME}.log${NC}"
done

# Configure logrotate
echo -e "${CYAN}═══════════════════════════════════════════════════════════════════${NC}"
echo -e "${YELLOW}Configuring Log Rotation...${NC}"
echo -e "${CYAN}═══════════════════════════════════════════════════════════════════${NC}"
echo ""

LOGROTATE_CONF="/etc/logrotate.d/logstash-datasources"

echo -e "${CYAN}Creating logrotate configuration...${NC}"

# Create logrotate configuration for all LogStash data source logs
sudo tee "$LOGROTATE_CONF" > /dev/null << EOF
# LogStash Data Source Log Rotation Configuration
$LOGSTASH_LOG_DIR/*.log {
    hourly
    size 1G
    rotate 7
    compress
    delaycompress
    missingok
    notifempty
    create 0644 logstash logstash
    sharedscripts
    postrotate
        /usr/bin/systemctl reload logstash > /dev/null 2>&1 || true
    endscript
}
EOF

echo -e "${GREEN}✓ Created logrotate configuration: $LOGROTATE_CONF${NC}"
echo -e "${CYAN}  → Logs rotate hourly if size > 1GB, keep 7 rotations${NC}"
echo ""

# Setup hourly cron job for logrotate
echo -e "${CYAN}Setting up hourly logrotate cron job...${NC}"

LOGROTATE_HOURLY="/etc/cron.hourly/logrotate-logstash"

sudo tee "$LOGROTATE_HOURLY" > /dev/null << 'EOF'
#!/bin/bash
/usr/sbin/logrotate /etc/logrotate.d/logstash-datasources
EOF

sudo chmod +x "$LOGROTATE_HOURLY"

echo -e "${GREEN}✓ Created hourly cron job: $LOGROTATE_HOURLY${NC}"
echo ""

# Configure SentinelOne Collector to monitor LogStash logs
echo -e "${CYAN}═══════════════════════════════════════════════════════════════════${NC}"
echo -e "${YELLOW}Configuring SentinelOne Collector to Monitor Logs...${NC}"
echo -e "${CYAN}═══════════════════════════════════════════════════════════════════${NC}"
echo ""

SCALYR_CONFIG="/etc/scalyr-agent-2/agent.json"

if [ -f "$SCALYR_CONFIG" ]; then
    echo -e "${CYAN}Backing up original configuration...${NC}"
    sudo cp "$SCALYR_CONFIG" "${SCALYR_CONFIG}.backup"
    
    # Build the logs array entries
    LOGS_ENTRIES=""
    for ((i=0; i<${#DATA_SOURCES[@]}; i++)); do
        SAFE_NAME=$(echo "${DATA_SOURCES[$i]}" | tr '[:upper:]' '[:lower:]' | tr ' ' '_' | tr -cd '[:alnum:]_-')
        LOG_PATH="$LOGSTASH_LOG_DIR/${SAFE_NAME}.log"
        
        if [ $i -eq 0 ]; then
            LOGS_ENTRIES="       { path: \"${LOG_PATH}\", attributes: {parser: \"accessLog\"} }"
        else
            LOGS_ENTRIES="${LOGS_ENTRIES},\n       { path: \"${LOG_PATH}\", attributes: {parser: \"accessLog\"} }"
        fi
    done
    
    # Update the logs section in agent.json
    echo -e "${CYAN}Updating agent.json with log file paths...${NC}"
    
    # Use sed to replace the logs array
    sudo sed -i '/logs: \[/,/\]/c\    logs: [\n'"${LOGS_ENTRIES}"'\n    ],' "$SCALYR_CONFIG"
    
    echo -e "${GREEN}✓ Updated SentinelOne Collector configuration${NC}"
    echo -e "${CYAN}  → Added ${#DATA_SOURCES[@]} log file(s) to monitor${NC}"
    
    # Restart scalyr-agent-2 to apply changes
    echo -e "${CYAN}Restarting SentinelOne Collector...${NC}"
    sudo scalyr-agent-2 restart
    
    # Verify it started successfully
    sleep 2
    if sudo systemctl is-active --quiet scalyr-agent-2; then
        echo -e "${GREEN}✓ SentinelOne Collector restarted successfully${NC}"
    else
        echo -e "${YELLOW}⚠ SentinelOne Collector may need manual restart${NC}"
        echo -e "${CYAN}  Check status: sudo scalyr-agent-2 status${NC}"
    fi
else
    echo -e "${YELLOW}⚠ SentinelOne configuration file not found at $SCALYR_CONFIG${NC}"
fi
echo ""

# Restart LogStash service
echo -e "${YELLOW}Do you want to restart LogStash now? (y/n)${NC}"
echo -e "${CYAN}Note: This may take 30-60 seconds. Your SSH connection should remain stable.${NC}"
read -p "Restart: " RESTART_CHOICE

if [[ "$RESTART_CHOICE" =~ ^[Yy]$ ]]; then
    echo -e "${CYAN}Restarting LogStash service...${NC}"
    echo -e "${YELLOW}Please wait, this may take up to 60 seconds...${NC}"
    
    # Start LogStash in background to prevent SSH blocking
    sudo systemctl restart logstash &
    LOGSTASH_PID=$!
    
    # Wait a bit and check status
    sleep 5
    
    if sudo systemctl is-active --quiet logstash; then
        echo -e "${GREEN}✓ LogStash is starting up...${NC}"
    else
        echo -e "${YELLOW}⚠ LogStash is still starting (this is normal)${NC}"
    fi
    
    echo -e "${CYAN}Check status in a few moments with: ${YELLOW}sudo systemctl status logstash${NC}"
else
    echo -e "${YELLOW}⚠ Remember to restart LogStash manually to apply changes:${NC}"
    echo -e "${CYAN}  sudo systemctl restart logstash${NC}"
fi

echo ""
echo -e "${GREEN}═══════════════════════════════════════════════════════════════════${NC}"
echo -e "${GREEN}✓ Configuration complete!${NC}"
echo -e "${GREEN}═══════════════════════════════════════════════════════════════════${NC}"
echo ""
echo -e "${CYAN}Summary of installed components:${NC}"
echo -e "${GREEN}  ✓ LogStash 9.x (enabled)${NC}"
echo -e "${GREEN}  ✓ SentinelOne Collector (enabled & monitoring logs)${NC}"
echo -e "${GREEN}  ✓ $NUM_SOURCES Data Source(s) configured${NC}"
echo -e "${GREEN}  ✓ Logrotate configured (hourly, 1GB threshold, 7 rotations)${NC}"
echo ""
echo -e "${CYAN}Service Status:${NC}"
echo -e "${GREEN}  • logstash - enabled and ready${NC}"
echo -e "${GREEN}  • scalyr-agent-2 - enabled and monitoring $NUM_SOURCES log file(s)${NC}"
echo ""
echo -e "${CYAN}Log files location:${NC}"
for ((i=0; i<${#DATA_SOURCES[@]}; i++)); do
    SAFE_NAME=$(echo "${DATA_SOURCES[$i]}" | tr '[:upper:]' '[:lower:]' | tr ' ' '_' | tr -cd '[:alnum:]_-')
    echo -e "${YELLOW}  $LOGSTASH_LOG_DIR/${SAFE_NAME}.log${NC}"
done
echo ""
echo -e "${CYAN}Useful commands:${NC}"
echo -e "  View logs: ${YELLOW}tail -f $LOGSTASH_LOG_DIR/<datasource>.log${NC}"
echo -e "  Check LogStash status: ${YELLOW}sudo systemctl status logstash${NC}"
echo -e "  Check SentinelOne status: ${YELLOW}sudo scalyr-agent-2 status${NC}"
echo -e "  Restart SentinelOne: ${YELLOW}sudo scalyr-agent-2 restart${NC}"
echo -e "  View SentinelOne config: ${YELLOW}sudo cat /etc/scalyr-agent-2/agent.json${NC}"
echo -e "  Test logrotate: ${YELLOW}sudo logrotate -f /etc/logrotate.d/logstash-datasources${NC}"
echo -e "  Manual rotation: ${YELLOW}sudo /etc/cron.hourly/logrotate-logstash${NC}"
echo -e "  View LogStash logs: ${YELLOW}sudo journalctl -u logstash -f${NC}"
echo ""
echo -e "${GREEN}═══════════════════════════════════════════════════════════════════${NC}"
echo -e "${GREEN}Configuration Summary - Point Your Logs Here${NC}"
echo -e "${GREEN}═══════════════════════════════════════════════════════════════════${NC}"
echo ""

# Get local IP address
LOCAL_IP=$(hostname -I | awk '{print $1}')
if [ -z "$LOCAL_IP" ]; then
    LOCAL_IP=$(ip route get 1 | awk '{print $7;exit}')
fi

echo -e "${CYAN}Server IP Address:${NC} ${YELLOW}${LOCAL_IP}${NC}"
echo ""
echo -e "${CYAN}Data Source Configuration:${NC}"
echo -e "${GREEN}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"

for ((i=0; i<${#DATA_SOURCES[@]}; i++)); do
    SAFE_NAME=$(echo "${DATA_SOURCES[$i]}" | tr '[:upper:]' '[:lower:]' | tr ' ' '_' | tr -cd '[:alnum:]_-')
    echo -e "${YELLOW}${DATA_SOURCES[$i]}${NC}"
    echo -e "  IP:Port    → ${CYAN}${LOCAL_IP}:${DATA_PORTS[$i]}${NC}"
    echo -e "  Protocol   → ${CYAN}${DATA_TYPES[$i]}${NC}"
    echo -e "  Log File   → ${CYAN}$LOGSTASH_LOG_DIR/${SAFE_NAME}.log${NC}"
    echo ""
done

echo -e "${GREEN}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
echo -e "${YELLOW}Configure your devices to send logs to the IP:Port combinations above${NC}"
echo ""
echo -e "${CYAN}═══════════════════════════════════════════════════════════════════${NC}"
echo -e "${YELLOW}⚠ IMPORTANT - Parser Configuration${NC}"
echo -e "${CYAN}═══════════════════════════════════════════════════════════════════${NC}"
echo ""
echo -e "${YELLOW}The SentinelOne Collector is currently configured with default parsers.${NC}"
echo -e "${YELLOW}You may need to update the parser settings in:${NC}"
echo -e "  ${CYAN}/etc/scalyr-agent-2/agent.json${NC}"
echo ""
echo -e "${CYAN}Each log file entry uses:${NC} ${YELLOW}attributes: {parser: \"accessLog\"}${NC}"
echo ""
echo -e "${CYAN}Depending on your data sources, you may need different parsers:${NC}"
echo -e "  • Syslog data → ${YELLOW}parser: \"systemLog\"${NC} or ${YELLOW}parser: \"syslog\"${NC}"
echo -e "  • Apache/Nginx → ${YELLOW}parser: \"accessLog\"${NC}"
echo -e "  • JSON logs → ${YELLOW}parser: \"json\"${NC}"
echo -e "  • Custom format → Create a custom parser in SentinelOne${NC}"
echo ""
echo -e "${YELLOW}To update parsers:${NC}"
echo -e "  1. Edit: ${CYAN}sudo nano /etc/scalyr-agent-2/agent.json${NC}"
echo -e "  2. Modify the ${CYAN}parser${NC} field for each log entry"
echo -e "  3. Restart: ${CYAN}sudo scalyr-agent-2 restart${NC}"
echo ""
