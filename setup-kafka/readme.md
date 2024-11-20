# Kafka KRaft Installation Scripts

This repository contains scripts for easy installation and management of Apache Kafka using the KRaft consensus protocol (no ZooKeeper required). The scripts provide a flexible way to deploy Kafka in different environments, from development to production.

## Features

- 🚀 Easy installation and uninstallation of Kafka with KRaft
- ⚙️ Configurable parameters for different environments
- 🔄 Support for different replication factors and partition counts
- 🧹 Clean uninstallation process
- 🔍 Built-in validation and error handling
- 📝 Detailed logging and status messages
- 🎨 Color-coded output for better readability

## Prerequisites

- Ubuntu/Debian-based system
- Sudo privileges
- Internet connection
- Basic understanding of Kafka concepts

## Quick Start

1. Clone the repository:
```bash
git clone https://github.com/yourusername/kafka-kraft-scripts.git
cd kafka-kraft-scripts
```

2. Make scripts executable:
```bash
chmod +x kafka-install.sh kafka-uninstall.sh
```

3. Run the installation script with default settings (suitable for testing):
```bash
./kafka-install.sh
```

## Installation Options

The installation script supports various configuration options:

```bash
./kafka-install.sh [OPTIONS]

Options:
  -v, --version VERSION         Kafka version (default: 3.7.1)
  -r, --replication FACTOR      Replication factor (default: 1)
  -p, --partitions NUMBER       Number of partitions (default: 1)
  -m, --min-isr NUMBER         Minimum in-sync replicas (default: 1)
  -x, --heap-size SIZE         Kafka heap size (default: 1G)
  -d, --data-dir PATH          Data directory (default: /opt/kafka)
  -h, --retention-hours HOURS   Log retention hours (default: 168)
  -a, --auto-create BOOLEAN    Auto create topics (default: false)
  -k, --kafka-port PORT        Kafka listener port (default: 9092)
  -c, --controller-port PORT    Controller port (default: 9093)
  --help                       Display help message
```

## Example Configurations

### Testing Environment
```bash
./kafka-install.sh --replication 1 --partitions 1 --heap-size 1G
```

### Development Environment
```bash
./kafka-install.sh \
  --replication 2 \
  --partitions 3 \
  --heap-size 2G \
  --retention-hours 48 \
  --auto-create true
```

### Production Environment
```bash
./kafka-install.sh \
  --replication 3 \
  --partitions 6 \
  --min-isr 2 \
  --heap-size 4G \
  --retention-hours 168 \
  --data-dir /data/kafka
```

## Testing the Installation

After installation, you can test the setup using:

1. Create a test producer:
```bash
/opt/kafka/kafka/bin/kafka-console-producer.sh --broker-list localhost:9092 --topic test-topic
```

2. Create a test consumer (in another terminal):
```bash
/opt/kafka/kafka/bin/kafka-console-consumer.sh --bootstrap-server localhost:9092 --topic test-topic --from-beginning
```

## Common Operations

### List Topics
```bash
/opt/kafka/kafka/bin/kafka-topics.sh --list --bootstrap-server localhost:9092
```

### Create a New Topic
```bash
/opt/kafka/kafka/bin/kafka-topics.sh --create \
  --bootstrap-server localhost:9092 \
  --topic my-topic \
  --partitions 1 \
  --replication-factor 1
```

### Describe a Topic
```bash
/opt/kafka/kafka/bin/kafka-topics.sh --describe \
  --bootstrap-server localhost:9092 \
  --topic my-topic
```

## Service Management

### Check Kafka Status
```bash
sudo systemctl status kafka
```

### Start/Stop/Restart Kafka
```bash
sudo systemctl start kafka
sudo systemctl stop kafka
sudo systemctl restart kafka
```

### View Kafka Logs
```bash
sudo journalctl -u kafka -f
```

## Directory Structure

- `/opt/kafka/kafka`: Kafka installation directory
- `/opt/kafka/kafka-logs`: Kafka data directory
- `/opt/kafka/kafka/config/kraft`: KRaft configuration directory

## Troubleshooting

### Common Issues

1. **Port Already in Use**
   ```bash
   sudo netstat -plnt | grep 9092
   sudo kill -9 <PID>
   ```

2. **Permission Issues**
   ```bash
   sudo chown -R kafka:kafka /opt/kafka
   sudo chmod -R 750 /opt/kafka
   ```

3. **Cluster ID Mismatch**
   ```bash
   sudo rm -rf /opt/kafka/kafka-logs/*
   sudo ./kafka-install.sh
   ```

### Getting Help

1. Check the logs:
```bash
sudo journalctl -u kafka -n 100 --no-pager
```

2. Verify the configuration:
```bash
cat /opt/kafka/kafka/config/kraft/server.properties
```

## Contributing

Contributions are welcome! Please feel free to submit a Pull Request.

## License

This project is licensed under the MIT License - see the [LICENSE](LICENSE) file for details.

## Acknowledgments

- Apache Kafka Documentation
- Kafka KRaft Documentation
- Community Contributors

## Disclaimer

These scripts are provided as-is, without any warranty. Always test in a non-production environment first.
