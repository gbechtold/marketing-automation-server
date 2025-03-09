#!/bin/bash

# Marketing Automation Server Installer
# This script sets up Twenty CRM, Activepieces, and Traefik on a fresh Ubuntu server

set -e  # Exit immediately if a command exits with a non-zero status

# Color codes for terminal output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m' # No Color

echo -e "${GREEN}======================================================${NC}"
echo -e "${GREEN}Marketing Automation Server Installation${NC}"
echo -e "${GREEN}======================================================${NC}"

# Check if running as root
if [ "$EUID" -ne 0 ]; then
  echo -e "${RED}Please run as root${NC}"
  exit 1
fi

# Prompt for domain names
read -p "Enter your CRM domain (e.g., crm.example.com): " CRM_DOMAIN
read -p "Enter your Automation domain (e.g., automation.example.com): " AUTOMATION_DOMAIN
read -p "Enter your email (for Let's Encrypt): " ACME_EMAIL

# Install Docker if not installed
if ! command -v docker &> /dev/null; then
    echo -e "${YELLOW}Docker not found. Installing Docker...${NC}"
    apt-get update
    apt-get install -y apt-transport-https ca-certificates curl software-properties-common
    curl -fsSL https://download.docker.com/linux/ubuntu/gpg | apt-key add -
    add-apt-repository "deb [arch=amd64] https://download.docker.com/linux/ubuntu $(lsb_release -cs) stable"
    apt-get update
    apt-get install -y docker-ce docker-ce-cli containerd.io
    systemctl enable docker
    systemctl start docker
    echo -e "${GREEN}Docker installed successfully${NC}"
else
    echo -e "${GREEN}Docker already installed${NC}"
fi

# Install Docker Compose if not installed
if ! command -v docker-compose &> /dev/null; then
    echo -e "${YELLOW}Docker Compose not found. Installing Docker Compose...${NC}"
    curl -L "https://github.com/docker/compose/releases/latest/download/docker-compose-$(uname -s)-$(uname -m)" -o /usr/local/bin/docker-compose
    chmod +x /usr/local/bin/docker-compose
    echo -e "${GREEN}Docker Compose installed successfully${NC}"
else
    echo -e "${GREEN}Docker Compose already installed${NC}"
fi

# Create Docker network for Traefik if it doesn't exist
if ! docker network ls | grep -q traefik-net; then
    echo -e "${YELLOW}Creating Docker network: traefik-net${NC}"
    docker network create traefik-net
    echo -e "${GREEN}Docker network created${NC}"
else
    echo -e "${GREEN}Docker network traefik-net already exists${NC}"
fi

# Create directories
mkdir -p ~/traefik ~/twenty ~/activepieces

# Setup Traefik
echo -e "${YELLOW}Setting up Traefik...${NC}"
cat > ~/traefik/.env << EOF
ACME_EMAIL=${ACME_EMAIL}
EOF

cat > ~/traefik/traefik.yml << EOF
# Static Configuration
entryPoints:
  web:
    address: ":80"
    http:
      redirections:
        entryPoint:
          to: websecure
          scheme: https
  websecure:
    address: ":443"

providers:
  docker:
    endpoint: "unix:///var/run/docker.sock"
    exposedByDefault: false
    network: traefik-net

certificatesResolvers:
  letsencrypt:
    acme:
      email: "${ACME_EMAIL}"
      storage: "/letsencrypt/acme.json"
      httpChallenge:
        entryPoint: "web"

api:
  dashboard: true
  insecure: true
EOF

cat > ~/traefik/docker-compose.yml << EOF
version: "3.8"

services:
  traefik:
    image: traefik:v2.10
    container_name: traefik
    restart: unless-stopped
    ports:
      - "80:80"
      - "443:443"
    volumes:
      - /var/run/docker.sock:/var/run/docker.sock:ro
      - ./traefik.yml:/traefik.yml:ro
      - ./letsencrypt:/letsencrypt
    networks:
      - traefik-net

networks:
  traefik-net:
    external: true
EOF

mkdir -p ~/traefik/letsencrypt
touch ~/traefik/letsencrypt/acme.json
chmod 600 ~/traefik/letsencrypt/acme.json

# Setup Twenty CRM
echo -e "${YELLOW}Setting up Twenty CRM...${NC}"
APP_SECRET=$(openssl rand -base64 32)
PG_PASSWORD=$(openssl rand -base64 12 | tr -dc 'a-zA-Z0-9')

cat > ~/twenty/.env << EOF
# Twenty CRM Environment Variables
TAG=latest
PG_DATABASE_USER=postgres
PG_DATABASE_PASSWORD=${PG_PASSWORD}
PG_DATABASE_HOST=db
PG_DATABASE_PORT=5432
REDIS_URL=redis://redis:6379
APP_SECRET=${APP_SECRET}
STORAGE_TYPE=local
STORAGE_LOCAL_PATH=.local-storage
SERVER_URL=https://${CRM_DOMAIN}
CRM_DOMAIN=${CRM_DOMAIN}
EOF

cat > ~/twenty/docker-compose.yml << EOF
version: "3.8"
services:
  change-vol-ownership:
    image: ubuntu
    user: root
    volumes:
      - server-local-data:/tmp/server-local-data
      - docker-data:/tmp/docker-data
    command: >
      bash -c "
      chown -R 1000:1000 /tmp/server-local-data
      && chown -R 1000:1000 /tmp/docker-data"

  server:
    image: twentycrm/twenty:\${TAG:-latest}
    volumes:
      - server-local-data:/app/packages/twenty-server/\${STORAGE_LOCAL_PATH:-.local-storage}
      - docker-data:/app/docker-data
    expose:
      - "3000"
    environment:
      NODE_PORT: 3000
      PG_DATABASE_URL: postgres://\${PG_DATABASE_USER:-postgres}:\${PG_DATABASE_PASSWORD:-postgres}@\${PG_DATABASE_HOST:-db}:\${PG_DATABASE_PORT:-5432}/default
      SERVER_URL: \${SERVER_URL}
      REDIS_URL: \${REDIS_URL:-redis://redis:6379}
      STORAGE_TYPE: \${STORAGE_TYPE}
      STORAGE_S3_REGION: \${STORAGE_S3_REGION}
      STORAGE_S3_NAME: \${STORAGE_S3_NAME}
      STORAGE_S3_ENDPOINT: \${STORAGE_S3_ENDPOINT}
      APP_SECRET: \${APP_SECRET:-replace_me_with_a_random_string}
    depends_on:
      change-vol-ownership:
        condition: service_completed_successfully
      db:
        condition: service_healthy
    healthcheck:
      test: curl --fail http://localhost:3000/healthz
      interval: 5s
      timeout: 5s
      retries: 10
    restart: always
    networks:
      - default
      - traefik-net
    labels:
      - "traefik.enable=true"
      - "traefik.http.routers.twentycrm.rule=Host(\`\${CRM_DOMAIN}\`)"
      - "traefik.http.routers.twentycrm.entrypoints=websecure"
      - "traefik.http.routers.twentycrm.tls=true"
      - "traefik.http.routers.twentycrm.tls.certresolver=letsencrypt"
      - "traefik.http.services.twentycrm.loadbalancer.server.port=3000"

  worker:
    image: twentycrm/twenty:\${TAG:-latest}
    command: ['yarn', 'worker:prod']
    environment:
      PG_DATABASE_URL: postgres://\${PG_DATABASE_USER:-postgres}:\${PG_DATABASE_PASSWORD:-postgres}@\${PG_DATABASE_HOST:-db}:\${PG_DATABASE_PORT:-5432}/default
      SERVER_URL: \${SERVER_URL}
      REDIS_URL: \${REDIS_URL:-redis://redis:6379}
      DISABLE_DB_MIGRATIONS: 'true'
      STORAGE_TYPE: \${STORAGE_TYPE}
      STORAGE_S3_REGION: \${STORAGE_S3_REGION}
      STORAGE_S3_NAME: \${STORAGE_S3_NAME}
      STORAGE_S3_ENDPOINT: \${STORAGE_S3_ENDPOINT}
      APP_SECRET: \${APP_SECRET:-replace_me_with_a_random_string}
    depends_on:
      db:
        condition: service_healthy
      server:
        condition: service_healthy
    restart: always
    networks:
      - default

  db:
    image: postgres:16
    volumes:
      - db-data:/var/lib/postgresql/data
    environment:
      POSTGRES_USER: \${PG_DATABASE_USER:-postgres}
      POSTGRES_PASSWORD: \${PG_DATABASE_PASSWORD:-postgres}
    healthcheck:
      test: pg_isready -U \${PG_DATABASE_USER:-postgres} -h localhost -d postgres
      interval: 5s
      timeout: 5s
      retries: 10
    restart: always
    networks:
      - default

  redis:
    image: redis
    restart: always
    networks:
      - default

volumes:
  docker-data:
  db-data:
  server-local-data:

networks:
  default:
  traefik-net:
    external: true
EOF

# Setup Activepieces
echo -e "${YELLOW}Setting up Activepieces...${NC}"
AP_ENCRYPTION_KEY=$(openssl rand -base64 24)
AP_JWT_SECRET=$(openssl rand -base64 24)
AP_PG_PASSWORD=$(openssl rand -base64 12 | tr -dc 'a-zA-Z0-9')

cat > ~/activepieces/.env << EOF
# Activepieces Environment Variables
AP_ENCRYPTION_KEY=${AP_ENCRYPTION_KEY}
AP_JWT_SECRET=${AP_JWT_SECRET}
AP_FRONTEND_URL=https://${AUTOMATION_DOMAIN}
AP_POSTGRES_HOST=postgres
AP_POSTGRES_PORT=5432
AP_POSTGRES_DATABASE=activepieces
AP_POSTGRES_USERNAME=activepieces
AP_POSTGRES_PASSWORD=${AP_PG_PASSWORD}
AP_REDIS_HOST=redis
AP_REDIS_PORT=6379
AP_SIGN_UP_ENABLED=true
AUTOMATION_DOMAIN=${AUTOMATION_DOMAIN}
EOF

cat > ~/activepieces/docker-compose.yml << EOF
version: "3.8"
services:
  activepieces:
    image: activepieces/activepieces:latest
    container_name: activepieces
    restart: unless-stopped
    depends_on:
      - postgres
      - redis
    environment:
      - AP_ENCRYPTION_KEY=\${AP_ENCRYPTION_KEY}
      - AP_JWT_SECRET=\${AP_JWT_SECRET}
      - AP_FRONTEND_URL=\${AP_FRONTEND_URL}
      - AP_POSTGRES_HOST=\${AP_POSTGRES_HOST}
      - AP_POSTGRES_PORT=\${AP_POSTGRES_PORT}
      - AP_POSTGRES_DATABASE=\${AP_POSTGRES_DATABASE}
      - AP_POSTGRES_USERNAME=\${AP_POSTGRES_USERNAME}
      - AP_POSTGRES_PASSWORD=\${AP_POSTGRES_PASSWORD}
      - AP_REDIS_HOST=\${AP_REDIS_HOST}
      - AP_REDIS_PORT=\${AP_REDIS_PORT}
      - AP_SIGN_UP_ENABLED=\${AP_SIGN_UP_ENABLED}
    expose:
      - "80"
    networks:
      - activepieces
      - traefik-net
    labels:
      - "traefik.enable=true"
      - "traefik.http.routers.activepieces.rule=Host(\`\${AUTOMATION_DOMAIN}\`)"
      - "traefik.http.routers.activepieces.entrypoints=websecure"
      - "traefik.http.routers.activepieces.tls=true"
      - "traefik.http.routers.activepieces.tls.certresolver=letsencrypt"
      - "traefik.http.services.activepieces.loadbalancer.server.port=80"

  postgres:
    image: postgres:14
    container_name: postgres
    restart: unless-stopped
    environment:
      - POSTGRES_DB=\${AP_POSTGRES_DATABASE}
      - POSTGRES_PASSWORD=\${AP_POSTGRES_PASSWORD}
      - POSTGRES_USER=\${AP_POSTGRES_USERNAME}
    volumes:
      - postgres_data:/var/lib/postgresql/data
    networks:
      - activepieces

  redis:
    image: redis:alpine
    container_name: redis
    restart: unless-stopped
    networks:
      - activepieces

networks:
  activepieces:
  traefik-net:
    external: true

volumes:
  postgres_data:
EOF

# Setup Windmill
echo -e "${YELLOW}Setting up Windmill...${NC}"
read -p "Enter your Windmill domain (e.g., windmill.example.com): " WINDMILL_DOMAIN

cat > ~/windmill/.env << EOF
# Windmill Environment Variables
DOMAIN=${WINDMILL_DOMAIN}
BASE_URL=https://${WINDMILL_DOMAIN}
EOF


# Start the services
echo -e "${YELLOW}Starting services...${NC}"
cd ~/traefik && docker-compose up -d
echo -e "${GREEN}Traefik started${NC}"

cd ~/twenty && docker-compose up -d
echo -e "${GREEN}Twenty CRM started${NC}"

cd ~/activepieces && docker-compose up -d
echo -e "${GREEN}Activepieces started${NC}"

cd ~/windmill && docker-compose up -d
echo -e "${GREEN}Windmill started${NC}"

echo -e "${GREEN}======================================================${NC}"
echo -e "${GREEN}Installation complete!${NC}"
echo -e "${GREEN}======================================================${NC}"
echo -e "${YELLOW}Your services are now running:${NC}"
echo -e "Twenty CRM: ${GREEN}https://${CRM_DOMAIN}${NC}"
echo -e "