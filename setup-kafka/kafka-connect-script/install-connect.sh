#!/bin/bash

# Default values
KAFKA_VERSION="3.7.1"
DEBEZIUM_VERSION="2.4.0.Final"
JDBC_VERSION="10.7.3"
CONNECT_DIR="/opt/kafka/connect"
CONNECT_HEAP_SIZE="1G"
NUM_WORKERS=3
KEY_CONVERTER="org.apache.kafka.connect.json.JsonConverter"
VALUE_CONVERTER="org.apache.kafka.connect.json.JsonConverter"
ENV="dev"
REPLICATION_FACTOR=1
LOG_RETENTION_HOURS=168
CONNECT_PORT=8083

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
    echo "  -e, --env ENV               Environment (dev/test/prod) (default: $ENV)"
    echo "  -w, --workers NUMBER        Number of workers (default: $NUM_WORKERS)"
    echo "  -x, --heap-size SIZE        Connect heap size (default: $CONNECT_HEAP_SIZE)"
    echo "  -d, --data-dir DIR          Connect directory (default: $CONNECT_DIR)"
    echo "  -p, --port PORT             Connect REST port (default: $CONNECT_PORT)"
    echo "  -r, --replication FACTOR    Replication factor (default: $REPLICATION_FACTOR)"
    echo "  -h, --retention-hours HOURS Log retention hours (default: $LOG_RETENTION_HOURS)"
    echo "  --help                      Display this help message"
    exit 1
}

# Parse command line arguments
while [[ $# -gt 0 ]]; do
    case $1 in
        -e|--env) ENV="$2"; shift 2 ;;
        -w|--workers) NUM_WORKERS="$2"; shift 2 ;;
        -x|--heap-size) CONNECT_HEAP_SIZE="$2"; shift 2 ;;
        -d|--data-dir) CONNECT_DIR="$2"; shift 2 ;;
        -p|--port) CONNECT_PORT="$2"; shift 2 ;;
        -r|--replication) REPLICATION_FACTOR="$2"; shift 2 ;;
        -h|--retention-hours) LOG_RETENTION_HOURS="$2"; shift 2 ;;
        --help) usage ;;
        *) print_color "red" "Unknown parameter: $1"; usage ;;
    esac
done

# Set environment-specific configurations
case $ENV in
    "prod")
        if [ "$NUM_WORKERS" -lt 3 ]; then
            NUM_WORKERS=3
        fi
        if [ "$REPLICATION_FACTOR" -lt 3 ]; then
            REPLICATION_FACTOR=3
        fi
        CONNECT_HEAP_SIZE="4G"
        LOG_RETENTION_HOURS=168
        ;;
    "test")
        if [ "$NUM_WORKERS" -lt 2 ]; then
            NUM_WORKERS=2
        fi
        if [ "$REPLICATION_FACTOR" -lt 2 ]; then
            REPLICATION_FACTOR=2
        fi
        CONNECT_HEAP_SIZE="2G"
        LOG_RETENTION_HOURS=72
        ;;
    "dev")
        NUM_WORKERS=1
        REPLICATION_FACTOR=1
        CONNECT_HEAP_SIZE="1G"
        LOG_RETENTION_HOURS=24
        ;;
    *)
        print_color "red" "Invalid environment: $ENV"
        exit 1
        ;;
esac

# Install connectors function
install_connectors() {
    print_color "yellow" "Installing connectors for $ENV environment..."
    
    # Create directories
    sudo mkdir -p ${CONNECT_DIR}/{jdbc,debezium}
    cd /tmp

    # Install JDBC Connector & Drivers
    print_color "yellow" "Installing JDBC components..."
    wget -q "https://packages.confluent.io/maven/io/confluent/kafka-connect-jdbc/${JDBC_VERSION}/kafka-connect-jdbc-${JDBC_VERSION}.jar" -P ${CONNECT_DIR}/jdbc/
    wget -q "https://repo1.maven.org/maven2/mysql/mysql-connector-java/8.0.33/mysql-connector-java-8.0.33.jar" -P ${CONNECT_DIR}/jdbc/
    wget -q "https://jdbc.postgresql.org/download/postgresql-42.6.0.jar" -P ${CONNECT_DIR}/jdbc/
    
    # Install Debezium connectors
    CONNECTORS=(
        "mysql=debezium-connector-mysql"
        "postgres=debezium-connector-postgres"
        "mongodb=debezium-connector-mongodb"
        "sqlserver=debezium-connector-sqlserver"
        "oracle=debezium-connector-oracle"
    )

    for connector in "${CONNECTORS[@]}"; do
        NAME=${connector%=*}
        ARTIFACT=${connector#*=}
        wget -q "https://repo1.maven.org/maven2/io/debezium/${ARTIFACT}/${DEBEZIUM_VERSION}/${ARTIFACT}-${DEBEZIUM_VERSION}-plugin.tar.gz"
        tar -xzf "${ARTIFACT}-${DEBEZIUM_VERSION}-plugin.tar.gz" -C ${CONNECT_DIR}/debezium
        rm "${ARTIFACT}-${DEBEZIUM_VERSION}-plugin.tar.gz"
    done
}

# Create configuration for environment
create_connect_config() {
    print_color "yellow" "Creating Kafka Connect configuration for $ENV environment..."
    
    # Create connect configuration directory
    sudo mkdir -p ${CONNECT_DIR}/config
    
    sudo tee ${CONNECT_DIR}/config/connect-distributed.properties > /dev/null << EOL
# Core Configuration
bootstrap.servers=localhost:9092
group.id=connect-cluster-${ENV}
key.converter=${KEY_CONVERTER}
value.converter=${VALUE_CONVERTER}
key.converter.schemas.enable=true
value.converter.schemas.enable=true

# Workers Configuration
offset.storage.topic=connect-offsets-${ENV}
offset.storage.replication.factor=${REPLICATION_FACTOR}
offset.storage.partitions=${NUM_WORKERS}
config.storage.topic=connect-configs-${ENV}
config.storage.replication.factor=${REPLICATION_FACTOR}
status.storage.topic=connect-status-${ENV}
status.storage.replication.factor=${REPLICATION_FACTOR}
status.storage.partitions=${NUM_WORKERS}

# Workers
plugin.path=${CONNECT_DIR}
config.providers=file
config.providers.file.class=org.apache.kafka.common.config.provider.FileConfigProvider

# Rest API
rest.port=${CONNECT_PORT}
rest.advertised.host.name=localhost
rest.advertised.port=${CONNECT_PORT}

# Performance and Security
task.shutdown.graceful.timeout.ms=10000
offset.flush.interval.ms=5000
EOL

    # Add environment-specific configurations
    case $ENV in
        "prod")
            echo "
# Production Specific Settings
producer.interceptor.classes=io.confluent.monitoring.clients.interceptor.MonitoringProducerInterceptor
consumer.interceptor.classes=io.confluent.monitoring.clients.interceptor.MonitoringConsumerInterceptor
security.protocol=SSL
ssl.truststore.location=/etc/kafka/secrets/kafka.connect.truststore.jks
ssl.keystore.location=/etc/kafka/secrets/kafka.connect.keystore.jks
ssl.client.auth=required" >> ${CONNECT_DIR}/config/connect-distributed.properties
            ;;
        "test")
            echo "
# Test Environment Settings
producer.interceptor.classes=io.confluent.monitoring.clients.interceptor.MonitoringProducerInterceptor
consumer.interceptor.classes=io.confluent.monitoring.clients.interceptor.MonitoringConsumerInterceptor" >> ${CONNECT_DIR}/config/connect-distributed.properties
            ;;
    esac
}

# Create systemd service
create_systemd_service() {
    print_color "yellow" "Creating systemd service for $ENV environment..."
    
    sudo tee /etc/systemd/system/kafka-connect-${ENV}.service > /dev/null << EOL
[Unit]
Description=Kafka Connect Distributed (${ENV})
Documentation=http://kafka.apache.org/documentation.html
Requires=network.target
After=network.target kafka.service

[Service]
Type=simple
User=kafka
Environment="KAFKA_HEAP_OPTS=-Xmx${CONNECT_HEAP_SIZE} -Xms${CONNECT_HEAP_SIZE}"
Environment="KAFKA_JMX_OPTS=-Dcom.sun.management.jmxremote -Dcom.sun.management.jmxremote.port=9999 -Dcom.sun.management.jmxremote.authenticate=false -Dcom.sun.management.jmxremote.ssl=false"
Environment="KAFKA_LOG4J_OPTS=-Dlog4j.configuration=file:${CONNECT_DIR}/config/connect-log4j.properties"
ExecStart=/opt/kafka/kafka/bin/connect-distributed.sh ${CONNECT_DIR}/config/connect-distributed.properties
Restart=always
RestartSec=10
LimitNOFILE=100000

[Install]
WantedBy=multi-user.target
EOL

    sudo systemctl daemon-reload
}

# Main installation function
main() {
    print_color "yellow" "Starting Kafka Connect installation for $ENV environment..."
    
    # Install connectors
    install_connectors
    
    # Create configurations
    create_connect_config
    
    # Create systemd service
    create_systemd_service
    
    # Set permissions
    sudo chown -R kafka:kafka ${CONNECT_DIR}
    sudo chmod -R 755 ${CONNECT_DIR}
    
    # Start service
    sudo systemctl enable kafka-connect-${ENV}
    sudo systemctl start kafka-connect-${ENV}
    
    print_color "green" "Kafka Connect ($ENV) installation completed!"
    print_color "yellow" "Configuration Summary:"
    echo "Environment:        $ENV"
    echo "Number of Workers:  $NUM_WORKERS"
    echo "Heap Size:         $CONNECT_HEAP_SIZE"
    echo "Replication Factor: $REPLICATION_FACTOR"
    echo "Connect Port:      $CONNECT_PORT"
    
    echo -e "\n=== Useful Commands ==="
    echo -e "\n1. List all available connector plugins:"
    echo "curl -s localhost:${CONNECT_PORT}/connector-plugins | jq '.[].class'"
    
    echo -e "\n2. List active connectors:"
    echo "curl -s localhost:${CONNECT_PORT}/connectors | jq"
    
    echo -e "\n3. Monitor Kafka Connect logs:"
    echo "sudo journalctl -u kafka-connect-${ENV} -f"
    
    echo -e "\n4. Check service status:"
    echo "sudo systemctl status kafka-connect-${ENV}"
    
    echo -e "\n5. View specific connector status:"
    echo "curl -s localhost:${CONNECT_PORT}/connectors/[connector-name]/status | jq"
}

# Run installation
main
