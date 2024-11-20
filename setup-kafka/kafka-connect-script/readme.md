# Kafka Connect Installation Script

Production-ready script for installing and configuring Kafka Connect with multiple connectors across different environments (development, testing, and production).

## Features

- Multi-environment support (dev/test/prod)
- Pre-configured connectors:
  - Debezium CDC Connectors:
    - MySQL
    - PostgreSQL
    - MongoDB
    - SQL Server
    - Oracle
  - JDBC Connectors (Source & Sink)
  - Database Drivers included
- Environment-specific configurations
- Automatic worker scaling
- Monitoring setup
- Security configurations

## Prerequisites

- Apache Kafka 3.x installed
- Linux-based OS (Ubuntu, RHEL, CentOS)
- Root or sudo privileges
- Java 11 or later
- Internet connectivity

## Quick Start

1. Make script executable:
```bash
chmod +x install-connect.sh
```

2. Install based on environment:
```bash
# Development
sudo ./install-connect.sh --env dev

# Testing
sudo ./install-connect.sh --env test

# Production
sudo ./install-connect.sh --env prod
```

## Installation Options

```
Options:
  -e, --env ENV               Environment (dev/test/prod) (default: dev)
  -w, --workers NUMBER        Number of workers (default: 3)
  -x, --heap-size SIZE        Connect heap size (default: 1G)
  -d, --data-dir DIR          Connect directory (default: /opt/kafka/connect)
  -p, --port PORT             Connect REST port (default: 8083)
  -r, --replication FACTOR    Replication factor (default: 1)
  -h, --retention-hours HOURS Log retention hours (default: 168)
  --help                      Display help message
```

## Environment Configurations

### Development (dev)
```bash
sudo ./install-connect.sh --env dev
```
- Single worker
- 1GB heap size
- No replication
- 24-hour log retention

### Testing (test)
```bash
sudo ./install-connect.sh --env test --workers 2
```
- Two workers minimum
- 2GB heap size
- Replication factor: 2
- Basic monitoring
- 72-hour log retention

### Production (prod)
```bash
sudo ./install-connect.sh --env prod --workers 5 --heap-size 8G
```
- Three workers minimum
- 4GB heap minimum
- Replication factor: 3
- SSL/TLS enabled
- Advanced monitoring
- 168-hour log retention

## Common Commands

### Service Management
```bash
# Start Kafka Connect
sudo systemctl start kafka-connect-[env]

# Stop Kafka Connect
sudo systemctl stop kafka-connect-[env]

# Check status
sudo systemctl status kafka-connect-[env]

# View logs
sudo journalctl -u kafka-connect-[env] -f
```

### Connector Management
```bash
# List available connectors
curl -s localhost:8083/connector-plugins | jq '.[].class'

# List active connectors
curl -s localhost:8083/connectors | jq

# Check connector status
curl -s localhost:8083/connectors/[name]/status | jq

# Delete connector
curl -X DELETE localhost:8083/connectors/[name]
```

## Connector Configuration Examples

### MySQL CDC (Debezium)
```json
{
  "name": "mysql-cdc",
  "config": {
    "connector.class": "io.debezium.connector.mysql.MySqlConnector",
    "database.hostname": "mysql_host",
    "database.port": "3306",
    "database.user": "debezium",
    "database.password": "dbz_password",
    "database.server.id": "1",
    "database.server.name": "mysql_server",
    "database.include.list": "inventory",
    "database.history.kafka.bootstrap.servers": "localhost:9092",
    "database.history.kafka.topic": "schema-changes.inventory"
  }
}
```

### PostgreSQL CDC (Debezium)
```json
{
  "name": "postgres-cdc",
  "config": {
    "connector.class": "io.debezium.connector.postgresql.PostgresConnector",
    "database.hostname": "postgres_host",
    "database.port": "5432",
    "database.user": "debezium",
    "database.password": "dbz_password",
    "database.dbname": "inventory",
    "database.server.name": "postgres_server",
    "plugin.name": "pgoutput"
  }
}
```

### JDBC Source
```json
{
  "name": "jdbc-source",
  "config": {
    "connector.class": "io.confluent.connect.jdbc.JdbcSourceConnector",
    "connection.url": "jdbc:mysql://localhost:3306/test",
    "connection.user": "user",
    "connection.password": "password",
    "topic.prefix": "mysql-",
    "mode": "timestamp",
    "timestamp.column.name": "updated_at"
  }
}
```

## Troubleshooting

### Connector Not Found
```bash
# Check connector installation directory
ls -l /opt/kafka/connect/*/

# Verify connector plugins are loaded
curl -s localhost:8083/connector-plugins | jq
```

### Connection Issues
```bash
# Check if service is running
sudo systemctl status kafka-connect-[env]

# Check for connection errors in logs
sudo journalctl -u kafka-connect-[env] -f

# Verify Kafka connectivity
nc -zv localhost 9092
```

### Performance Issues
1. Check heap usage:
```bash
jconsole localhost:9999
```

2. Monitor worker load:
```bash
curl -s localhost:8083/connectors/[name]/status | jq '.tasks[].trace'
```

3. Check system resources:
```bash
top -u kafka
```

## Scaling

### Adding Workers
1. Stop Kafka Connect:
```bash
sudo systemctl stop kafka-connect-[env]
```

2. Update configuration:
```bash
sudo ./install-connect.sh --env prod --workers 5
```

3. Start Kafka Connect:
```bash
sudo systemctl start kafka-connect-[env]
```

## Security (Production)

1. SSL/TLS Configuration:
- Certificates located in `/etc/kafka/secrets/`
- Client authentication required
- TLS 1.2+ enforced

2. Network Security:
- Restricted port access
- Internal network connectivity only
- Firewall rules for ports 8083, 9092

3. Monitoring:
- JMX metrics enabled
- Producer/Consumer interceptors
- Log monitoring

## Maintenance

### Updating Connectors
1. Stop the service:
```bash
sudo systemctl stop kafka-connect-[env]
```

2. Run installation with new versions:
```bash
sudo ./install-connect.sh --env prod [options]
```

3. Start the service:
```bash
sudo systemctl start kafka-connect-[env]
```

### Log Management
- Logs located in `/var/log/kafka-connect-[env]/`
- Automatic rotation based on retention period
- Monitoring alerts for errors

## Best Practices

1. Production Deployment:
- Use at least 3 workers
- Enable SSL/TLS
- Set appropriate memory
- Configure monitoring
- Regular backups

2. Connector Configuration:
- Set appropriate batch sizes
- Configure error handling
- Set retry policies
- Monitor task status

3. Performance:
- Tune JVM settings
- Monitor system resources
- Balance worker loads
- Regular maintenance

## Support

For issues and suggestions:
1. Check the troubleshooting guide
2. Review service logs
3. Verify configurations
4. Check [Kafka Connect documentation](https://kafka.apache.org/documentation/#connect)
