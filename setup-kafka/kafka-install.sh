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

# Function to print in color
print_color() {
    local color=$1
    local text=$2
    case $color in 
        "red") echo -e "\033[0;31m${text}\033[0m" ;;
        "green") echo -e "\033[0;32m${text}\033[0m" ;;
        "yellow") echo -e "\033[1;33m${text}\033[0m" ;;
        "blue") echo -e "\033[0;34m${text}\033[0m" ;;
    esac
}

# Function to display usage
usage() {
    print_color "blue" "Usage: $0 [OPTIONS]"
    echo "Options:"
    echo "  -v, --version VERSION         Kafka version (default: $KAFKA_VERSION)"
    echo "  -r, --replication FACTOR      Replication factor (default: $REPLICATION_FACTOR)"
    echo "  -p, --partitions NUMBER       Number of partitions (default: $NUM_PARTITIONS)"
    echo "  -m, --min-isr NUMBER         Minimum in-sync replicas (default: $MIN_INSYNC_REPLICAS)"
    echo "  -x, --heap-size SIZE         Kafka heap size (default: $KAFKA_HEAP_SIZE)"
    echo "  -d, --data-dir PATH          Data directory (default: $DATA_DIR)"
    echo "  -h, --retention-hours HOURS   Log retention hours (default: $LOG_RETENTION_HOURS)"
    echo "  -a, --auto-create BOOLEAN    Auto create topics (default: $AUTO_CREATE_TOPICS)"
    echo "  -k, --kafka-port PORT        Kafka listener port (default: $KAFKA_PORT)"
    echo "  -c, --controller-port PORT    Controller port (default: $CONTROLLER_PORT)"
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
        -a|--auto-create) AUTO_CREATE_TOPICS="$2"; shift 2 ;;
        -k|--kafka-port) KAFKA_PORT="$2"; shift 2 ;;
        -c|--controller-port) CONTROLLER_PORT="$2"; shift 2 ;;
        --help) usage ;;
        *) print_color "red" "Unknown parameter: $1"; usage ;;
    esac
done

# Function to check if a command exists
check_command() {
    if ! command -v $1 &> /dev/null; then
        print_color "red" "$1 could not be found. Installing..."
        sudo apt-get update && sudo apt-get install -y $1
    fi
}

# Validate inputs
validate_inputs() {
    if ! [[ "$REPLICATION_FACTOR" =~ ^[0-9]+$ ]] || [ "$REPLICATION_FACTOR" -lt 1 ]; then
        print_color "red" "Invalid replication factor. Must be a positive integer."
        exit 1
    fi
    if ! [[ "$NUM_PARTITIONS" =~ ^[0-9]+$ ]] || [ "$NUM_PARTITIONS" -lt 1 ]; then
        print_color "red" "Invalid number of partitions. Must be a positive integer."
        exit 1
    fi
}

# Main installation function
install_kafka() {
    print_color "blue" "Starting Kafka installation with following configuration:"
    echo "Kafka Version: $KAFKA_VERSION"
    echo "Replication Factor: $REPLICATION_FACTOR"
    echo "Number of Partitions: $NUM_PARTITIONS"
    echo "Min In-Sync Replicas: $MIN_INSYNC_REPLICAS"
    echo "Heap Size: $KAFKA_HEAP_SIZE"
    echo "Data Directory: $DATA_DIR"
    echo "Log Retention Hours: $LOG_RETENTION_HOURS"
    echo "Auto Create Topics: $AUTO_CREATE_TOPICS"
    echo "Kafka Port: $KAFKA_PORT"
    echo "Controller Port: $CONTROLLER_PORT"

    # Check for required commands
    check_command "wget"
    check_command "java"

    # Stop Kafka if running
    sudo systemctl stop kafka 2>/dev/null

    # Clean up existing installation
    print_color "yellow" "Cleaning up existing installation..."
    sudo rm -rf ${DATA_DIR}/kafka-logs/*
    sudo rm -rf /tmp/kraft-combined-logs/*

    # Create directories
    sudo mkdir -p ${DATA_DIR}
    sudo mkdir -p ${DATA_DIR}/kafka-logs
    sudo useradd -r -d ${DATA_DIR} kafka 2>/dev/null || true
    sudo chown -R kafka:kafka ${DATA_DIR}

    # Download and extract Kafka
    print_color "yellow" "Downloading Kafka..."
    cd /tmp
    wget "https://downloads.apache.org/kafka/${KAFKA_VERSION}/kafka_2.13-${KAFKA_VERSION}.tgz"
    tar -xzf "kafka_2.13-${KAFKA_VERSION}.tgz"
    sudo rm -rf ${DATA_DIR}/kafka
    sudo mv "kafka_2.13-${KAFKA_VERSION}" ${DATA_DIR}/kafka
    sudo chown -R kafka:kafka ${DATA_DIR}/kafka

    # Generate cluster ID
    print_color "yellow" "Generating Cluster ID..."
    export CLUSTER_ID=$(sudo -u kafka ${DATA_DIR}/kafka/bin/kafka-storage.sh random-uuid)
    echo "Using Cluster ID: $CLUSTER_ID"

    # Create server properties
    print_color "yellow" "Creating server properties..."
    sudo mkdir -p ${DATA_DIR}/kafka/config/kraft
    sudo tee ${DATA_DIR}/kafka/config/kraft/server.properties > /dev/null << EOL
# Server Basics
node.id=1
process.roles=broker,controller
controller.listener.names=CONTROLLER
listeners=PLAINTEXT://0.0.0.0:${KAFKA_PORT},CONTROLLER://0.0.0.0:${CONTROLLER_PORT}
advertised.listeners=PLAINTEXT://localhost:${KAFKA_PORT}
controller.quorum.voters=1@localhost:${CONTROLLER_PORT}
inter.broker.listener.name=PLAINTEXT

# Log Basics
log.dirs=${DATA_DIR}/kafka-logs
num.partitions=${NUM_PARTITIONS}
default.replication.factor=${REPLICATION_FACTOR}
min.insync.replicas=${MIN_INSYNC_REPLICAS}
offsets.topic.replication.factor=${REPLICATION_FACTOR}
transaction.state.log.replication.factor=${REPLICATION_FACTOR}
transaction.state.log.min.isr=${MIN_INSYNC_REPLICAS}

# Topic Settings
auto.create.topics.enable=${AUTO_CREATE_TOPICS}
delete.topic.enable=true

# Log Retention
log.retention.hours=${LOG_RETENTION_HOURS}
log.segment.bytes=1073741824
log.retention.check.interval.ms=300000

# Zookeeper-free Settings
controller.quorum.election.timeout.ms=1000
controller.quorum.fetch.timeout.ms=2000
EOL

    # Create systemd service
    print_color "yellow" "Creating systemd service..."
    sudo tee /etc/systemd/system/kafka.service > /dev/null << EOL
[Unit]
Description=Apache Kafka Server
Documentation=http://kafka.apache.org/documentation.html
Requires=network.target
After=network.target

[Service]
Type=simple
User=kafka
Environment="JAVA_HOME=/usr/lib/jvm/java-11-openjdk-amd64"
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
    sleep 10

    # Create test topic
    print_color "yellow" "Creating test topic..."
    sudo -u kafka ${DATA_DIR}/kafka/bin/kafka-topics.sh --create \
        --bootstrap-server localhost:${KAFKA_PORT} \
        --topic test-topic \
        --partitions ${NUM_PARTITIONS} \
        --replication-factor ${REPLICATION_FACTOR} \
        --if-not-exists

    # Verify installation
    if sudo systemctl is-active --quiet kafka; then
        print_color "green" "Kafka installation completed successfully!"
        echo "Cluster ID: $CLUSTER_ID"
        echo "Test the installation with:"
        echo "Producer: ${DATA_DIR}/kafka/bin/kafka-console-producer.sh --broker-list localhost:${KAFKA_PORT} --topic test-topic"
        echo "Consumer: ${DATA_DIR}/kafka/bin/kafka-console-consumer.sh --bootstrap-server localhost:${KAFKA_PORT} --topic test-topic --from-beginning"
    else
        print_color "red" "Kafka failed to start. Check logs with: sudo journalctl -u kafka"
        exit 1
    fi
}

# Run validation and installation
validate_inputs
install_kafka
