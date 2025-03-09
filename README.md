# Marketing Automation Server

This repository contains a complete setup for a marketing automation system using:

- **[Twenty CRM](https://twenty.com/)**: A modern, open-source CRM platform
- **[Activepieces](https://www.activepieces.com/)**: An open-source workflow automation tool
- **[Traefik](https://traefik.io/)**: A modern, Docker-friendly edge router for routing and SSL

This setup deploys all services with Docker Compose and uses Traefik as a reverse proxy to handle routing and automatic SSL certificate management.

## Prerequisites

- A server running Linux (Ubuntu is recommended)
- Root access to the server
- Domain names pointing to your server (for Twenty CRM and Activepieces)
- Open ports 80 and 443 on your firewall

## Quick Start

```bash
# Clone this repository
git clone https://github.com/gbechtold/marketing-automation-server.git
cd marketing-automation-server

# Make the install script executable
chmod +x install.sh

# Run the installer
./install.sh
```

The installer will:

1. Install Docker and Docker Compose if not already installed
2. Create the necessary Docker network
3. Set up Traefik with Let's Encrypt for SSL
4. Set up Twenty CRM
5. Set up Activepieces
6. Start all services

## Manual Setup

If you prefer a manual setup, follow these steps:

### 1. Set up Traefik

```bash
mkdir -p ~/traefik/letsencrypt
cd ~/traefik

# Create .env file
cp .env-example .env
# Edit with your information
nano .env

# Create the traefik.yml file
cp traefik.yml .

# Create acme.json for SSL certificates
touch letsencrypt/acme.json
chmod 600 letsencrypt/acme.json

# Start Traefik
docker-compose up -d
```

### 2. Set up Twenty CRM

```bash
mkdir -p ~/twenty
cd ~/twenty

# Create .env file
cp .env-example .env
# Edit with your information
nano .env

# Start Twenty CRM
docker-compose up -d
```

### 3. Set up Activepieces

```bash
mkdir -p ~/activepieces
cd ~/activepieces

# Create .env file
cp .env-example .env
# Edit with your information
nano .env

# Start Activepieces
docker-compose up -d
```

## Configuration

### Traefik

Traefik is configured to:

- Redirect HTTP to HTTPS
- Obtain and renew SSL certificates automatically from Let's Encrypt
- Use Docker provider to detect services to route

Edit `~/traefik/.env` to configure:

- Your email address for Let's Encrypt

### Twenty CRM

Twenty CRM is a modern, open-source CRM platform designed for collaboration and customization.

Edit `~/twenty/.env` to configure:

- Database credentials
- Server URL
- App secret for security
- Storage options

### Activepieces

Activepieces is an open-source workflow automation tool similar to Zapier or Make.com.

Edit `~/activepieces/.env` to configure:

- Security keys (encryption key and JWT secret)
- Frontend URL
- Database credentials
- Redis configuration
- Signup settings

## Directory Structure

```
marketing-automation-server/
├── .gitignore                     # Git ignore file
├── README.md                      # This documentation
├── install.sh                     # One-line installation script
├── activepieces/                  # Activepieces configuration
│   ├── docker-compose.yml         # Docker Compose configuration
│   └── .env-example               # Example environment file
├── twenty/                        # Twenty CRM configuration
│   ├── docker-compose.yml         # Docker Compose configuration
│   └── .env-example               # Example environment file
└── traefik/                       # Traefik configuration
    ├── docker-compose.yml         # Docker Compose configuration
    ├── traefik.yml                # Traefik static configuration
    └── .env-example               # Example environment file
```

## Backup and Restore

The setup uses Docker volumes for data persistence. To back up your data:

```bash
# Backup Twenty CRM data
docker run --rm -v twenty_db-data:/source -v /path/to/backup:/backup ubuntu tar -czf /backup/twenty-db-backup.tar.gz -C /source .

# Backup Activepieces data
docker run --rm -v activepieces_postgres_data:/source -v /path/to/backup:/backup ubuntu tar -czf /backup/activepieces-db-backup.tar.gz -C /source .
```

To restore from backup:

```bash
# Restore Twenty CRM data
docker run --rm -v twenty_db-data:/target -v /path/to/backup:/backup ubuntu bash -c "rm -rf /target/* && tar -xzf /backup/twenty-db-backup.tar.gz -C /target"

# Restore Activepieces data
docker run --rm -v activepieces_postgres_data:/target -v /path/to/backup:/backup ubuntu bash -c "rm -rf /target/* && tar -xzf /backup/activepieces-db-backup.tar.gz -C /target"
```

## Security Considerations

- The Traefik dashboard is enabled with insecure access for simplicity. For production, consider disabling it or securing it with authentication.
- Environment files contain sensitive information. Keep them secure and never commit them to version control.
- Consider setting up a firewall to only allow traffic on ports 80 and 443.

## Troubleshooting

### SSL Certificate Issues

If you have issues with SSL certificates:

```bash
# Check Traefik logs
docker-compose -f ~/traefik/docker-compose.yml logs

# Ensure acme.json has the right permissions
chmod 600 ~/traefik/letsencrypt/acme.json
```

### Container Connectivity Issues

If containers cannot connect to each other:

```bash
# Verify the traefik-net network exists
docker network ls | grep traefik-net

# Check container logs
docker-compose -f ~/twenty/docker-compose.yml logs server
docker-compose -f ~/activepieces/docker-compose.yml logs activepieces
```

## License

This project is licensed under the MIT License - see the LICENSE file for details.

## Credits

- [Twenty CRM](https://github.com/twentyhq/twenty)
- [Activepieces](https://github.com/activepieces/activepieces)
- [Traefik](https://github.com/traefik/traefik)
