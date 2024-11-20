#!/bin/bash

# Default values
KAFKA_VERSION="3.7.1"
REPLICATION_FACTOR=1
NUM_PARTITIONS=1
MIN_INSYNC_REPLICAS=1
KAFKA_HEAP_SIZE="1G"
DATA_DIR="/opt/kafka"
LOG_RETENTION_HOURS=168
AUTO_CREATE_TOPICS="false"
KAFKA_PORT=9092
CONTROLLER_PORT=9093

# Color codes
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m'

# Function to print colored messages
print_color() {
    COLOR=$1
    MSG=$2
    case $COLOR in
        "red") echo -e "${RED}${MSG}${NC}" ;;
        "green") echo -e "${GREEN}${MSG}${NC}" ;;
        "yellow") echo -e "${YELLOW}${MSG}${NC}" ;;
    esac
}

# Function to display usage
usage() {
    print_color "green" "Usage: $0 [OPTIONS]"
    echo "Options:"
    echo "  -v, --version VERSION         Kafka version (default: $KAFKA_VERSION)"
    echo "  -r, --replication FACTOR      Replication factor (default: $REPLICATION_FACTOR)"
    echo "  -p, --partitions NUMBER       Number of partitions (default: $NUM_PARTITIONS)"
    echo "  -m, --min-isr NUMBER         Minimum in-sync replicas (default: $MIN_INSYNC_REPLICAS)"
    echo "  -x, --heap-size SIZE         Kafka heap size (default: $KAFKA_HEAP_SIZE)"
    echo "  -d, --data-dir PATH          Data directory (default: $DATA_DIR)"
    echo "  -h, --retention-hours HOURS   Log retention hours (default: $LOG_RETENTION_HOURS)"
    echo "  --help                        Display this help message"
    exit 1
}

# Parse command line arguments
while [[ $# -gt 0 ]]; do
    case $1 in
        -v|--version) KAFKA_VERSION="$2"; shift 2 ;;
        -r|--replication) REPLICATION_FACTOR="$2"; shift 2 ;;
        -p|--partitions) NUM_PARTITIONS="$2"; shift 2 ;;
        -m|--min-isr) MIN_INSYNC_REPLICAS="$2"; shift 2 ;;
        -x|--heap-size) KAFKA_HEAP_SIZE="$2"; shift 2 ;;
        -d|--data-dir) DATA_DIR="$2"; shift 2 ;;
        -h|--retention-hours) LOG_RETENTION_HOURS="$2"; shift 2 ;;
        --help) usage ;;
        *) print_color "red" "Unknown parameter: $1"; usage ;;
    esac
done

# Detect OS and set appropriate commands
if [ -f /etc/os-release ]; then
    . /etc/os-release
    OS=$ID
    VERSION_ID=$VERSION_ID
fi

case $OS in
    ubuntu)
        print_color "green" "Detected Ubuntu system"
        INSTALL_CMD="apt-get"
        UPDATE_CMD="apt-get update"
        JAVA_PACKAGE="openjdk-11-jdk"
        JAVA_HOME="/usr/lib/jvm/java-11-openjdk-amd64"
        ;;
    amzn)
        print_color "green" "Detected Amazon Linux"
        INSTALL_CMD="yum"
        UPDATE_CMD="yum update"
        JAVA_PACKAGE="java-11-amazon-corretto"
        JAVA_HOME="/usr/lib/jvm/java-11-amazon-corretto"
        ;;
    rhel|centos)
        print_color "green" "Detected RHEL/CentOS system"
        INSTALL_CMD="yum"
        UPDATE_CMD="yum update"
        # Enable EPEL repository for RHEL/CentOS
        sudo $INSTALL_CMD install -y epel-release
        # Install Java
        JAVA_PACKAGE="java-11-openjdk-devel"
        JAVA_HOME="/usr/lib/jvm/java-11-openjdk"
        ;;
    *)
        print_color "red" "Unsupported operating system"
        exit 1
        ;;
esac


# Function to install packages
install_packages() {
    print_color "yellow" "Installing required packages..."
    
    # Install EPEL if RHEL/CentOS
    if [[ "$OS" == "rhel" ]] || [[ "$OS" == "centos" ]]; then
        sudo $INSTALL_CMD install -y epel-release
    fi
    
    # Update package list
    sudo $UPDATE_CMD -y

    # Install Java and wget
    sudo $INSTALL_CMD install -y $JAVA_PACKAGE wget

    # Verify Java installation
    if ! command -v java &> /dev/null; then
        print_color "red" "Java installation failed"
        exit 1
    fi

    # Set JAVA_HOME in environment if not already set
    if [ ! -f "/etc/profile.d/java.sh" ]; then
        echo "export JAVA_HOME=$JAVA_HOME" | sudo tee /etc/profile.d/java.sh
        echo "export PATH=\$PATH:\$JAVA_HOME/bin" | sudo tee -a /etc/profile.d/java.sh
        source /etc/profile.d/java.sh
    fi
}

# Function to setup system limits
setup_system_limits() {
    # Set up ulimit for kafka user
    sudo tee /etc/security/limits.d/kafka.conf > /dev/null << EOL
kafka soft nofile 65536
kafka hard nofile 65536
kafka soft nproc 32768
kafka hard nproc 32768
EOL

    # Set up sysctl parameters
    sudo tee /etc/sysctl.d/kafka.conf > /dev/null << EOL
vm.swappiness=1
net.core.wmem_max=16777216
net.core.rmem_max=16777216
net.ipv4.tcp_wmem=4096 65536 16777216
net.ipv4.tcp_rmem=4096 65536 16777216
EOL

    # Apply sysctl settings
    sudo sysctl -p /etc/sysctl.d/kafka.conf
}


# Main installation function
install_kafka() {
    # Install required packages
    install_packages

    # Stop Kafka if running
    sudo systemctl stop kafka 2>/dev/null

    # Clean up existing installation
    sudo rm -rf ${DATA_DIR}/kafka-logs/*
    sudo rm -rf /tmp/kraft-combined-logs/*

    # Create directories and set permissions
    sudo mkdir -p ${DATA_DIR}
    sudo mkdir -p ${DATA_DIR}/kafka-logs
    sudo useradd -r -d ${DATA_DIR} kafka 2>/dev/null || true
    sudo chown -R kafka:kafka ${DATA_DIR}

    # Download and extract Kafka
    print_color "yellow" "Downloading Kafka ${KAFKA_VERSION}..."
    cd /tmp
    wget "https://downloads.apache.org/kafka/${KAFKA_VERSION}/kafka_2.13-${KAFKA_VERSION}.tgz"
    if [ $? -ne 0 ]; then
        print_color "red" "Failed to download Kafka"
        exit 1
    fi

    tar -xzf "kafka_2.13-${KAFKA_VERSION}.tgz"
    sudo rm -rf ${DATA_DIR}/kafka
    sudo mv "kafka_2.13-${KAFKA_VERSION}" ${DATA_DIR}/kafka
    sudo chown -R kafka:kafka ${DATA_DIR}/kafka

    # Generate cluster ID
    print_color "yellow" "Generating Cluster ID..."
    CLUSTER_ID=$(sudo -u kafka ${DATA_DIR}/kafka/bin/kafka-storage.sh random-uuid)
    print_color "green" "Using Cluster ID: $CLUSTER_ID"

    # Create server properties
    sudo mkdir -p ${DATA_DIR}/kafka/config/kraft
    sudo tee ${DATA_DIR}/kafka/config/kraft/server.properties > /dev/null << EOL
# Server basics
node.id=1
process.roles=broker,controller
controller.listener.names=CONTROLLER
listeners=PLAINTEXT://0.0.0.0:${KAFKA_PORT},CONTROLLER://0.0.0.0:${CONTROLLER_PORT}
advertised.listeners=PLAINTEXT://localhost:${KAFKA_PORT}
controller.quorum.voters=1@localhost:${CONTROLLER_PORT}
inter.broker.listener.name=PLAINTEXT

# Log settings
log.dirs=${DATA_DIR}/kafka-logs
num.partitions=${NUM_PARTITIONS}
default.replication.factor=${REPLICATION_FACTOR}
min.insync.replicas=${MIN_INSYNC_REPLICAS}
offsets.topic.replication.factor=${REPLICATION_FACTOR}
transaction.state.log.replication.factor=${REPLICATION_FACTOR}
transaction.state.log.min.isr=${MIN_INSYNC_REPLICAS}

# Topic settings
auto.create.topics.enable=${AUTO_CREATE_TOPICS}
delete.topic.enable=true

# Log retention
log.retention.hours=${LOG_RETENTION_HOURS}
EOL

    # Create systemd service
    sudo tee /etc/systemd/system/kafka.service > /dev/null << EOL
[Unit]
Description=Apache Kafka Server
Documentation=http://kafka.apache.org/documentation.html
Requires=network.target
After=network.target

[Service]
Type=simple
User=kafka
Environment="JAVA_HOME=${JAVA_HOME}"
Environment="KAFKA_HEAP_OPTS=-Xmx${KAFKA_HEAP_SIZE} -Xms${KAFKA_HEAP_SIZE}"
Environment="KAFKA_JVM_PERFORMANCE_OPTS=-XX:+UseG1GC -XX:MaxGCPauseMillis=20 -XX:InitiatingHeapOccupancyPercent=35 -XX:+ExplicitGCInvokesConcurrent -Djava.awt.headless=true"
ExecStart=${DATA_DIR}/kafka/bin/kafka-server-start.sh ${DATA_DIR}/kafka/config/kraft/server.properties
ExecStop=${DATA_DIR}/kafka/bin/kafka-server-stop.sh
Restart=on-abnormal
LimitNOFILE=100000

[Install]
WantedBy=multi-user.target
EOL

    # Set permissions
    sudo chown -R kafka:kafka ${DATA_DIR}
    sudo chmod -R 750 ${DATA_DIR}/kafka-logs

    # Format storage
    print_color "yellow" "Formatting storage..."
    sudo -u kafka ${DATA_DIR}/kafka/bin/kafka-storage.sh format \
        -t $CLUSTER_ID \
        -c ${DATA_DIR}/kafka/config/kraft/server.properties

    # Start Kafka
    print_color "yellow" "Starting Kafka..."
    sudo systemctl daemon-reload
    sudo systemctl enable kafka
    sudo systemctl start kafka
    sleep 15

    # Verify installation
    if sudo systemctl is-active --quiet kafka; then
        print_color "green" "Kafka installation completed successfully!"
        print_color "green" "Creating test topic..."
        sudo -u kafka ${DATA_DIR}/kafka/bin/kafka-topics.sh --create \
            --bootstrap-server localhost:${KAFKA_PORT} \
            --topic test-topic \
            --partitions ${NUM_PARTITIONS} \
            --replication-factor ${REPLICATION_FACTOR} \
            --if-not-exists
    else
        print_color "red" "Kafka failed to start. Check logs with: sudo journalctl -u kafka"
        exit 1
    fi

    print_color "green" "Installation complete! Cluster ID: $CLUSTER_ID"
    print_color "yellow" "Use these commands to test:"
    echo "Producer: ${DATA_DIR}/kafka/bin/kafka-console-producer.sh --broker-list localhost:${KAFKA_PORT} --topic test-topic"
    echo "Consumer: ${DATA_DIR}/kafka/bin/kafka-console-consumer.sh --bootstrap-server localhost:${KAFKA_PORT} --topic test-topic --from-beginning"
}

# Run the installation
install_kafka
