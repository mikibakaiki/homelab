# 🐳 Portainer - Docker Container Management

Portainer provides a web-based interface for managing Docker containers, images, networks, and volumes. This setup integrates with Traefik for automatic HTTPS and authentication.

## 🚀 Features

- **Web-based Docker management** - Manage containers, images, volumes, and networks
- **Multi-environment support** - Manage multiple Docker hosts from one interface
- **HTTPS access** via Traefik reverse proxy with automatic SSL
- **Container logs** - View and search container logs
- **Resource monitoring** - CPU, memory, and network usage
- **User management** - Role-based access control
- **Template system** - Deploy containers from pre-defined templates

## 📋 Quick Start

### Prerequisites

1. **Traefik must be running** (provides reverse proxy and SSL)
2. **Proxy network must exist**:
   ```bash
   docker network create proxy
   ```

### Setup

1. **Navigate to Portainer directory**:
   ```bash
   cd ~/homelab/docker-compose/portainer
   ```

2. **Copy environment file**:
   ```bash
   cp .env.example .env
   nano .env
   ```

3. **Configure environment variables**:
   ```env
   TZ=Europe/Lisbon
   DOMAIN_NAME=YOUR_DOMAIN
   ```

4. **Create data directory** (if it doesn't exist):
   ```bash
   mkdir -p ~/homelab/docker/portainer/data
   ```

5. **Start Portainer**:
   ```bash
   docker compose up -d
   ```

6. **Access Portainer**:
   - HTTPS: https://portainer.YOUR_DOMAIN
   - Direct HTTP: http://<PIHOLE_HOST_IP>:9000 (optional)

### First-Time Setup

On first access, you'll need to:
1. Create an admin account (username + password)
2. Connect to local Docker environment (automatic)
3. Start managing your containers!

## 🌐 Network Configuration

Portainer uses the **proxy network** to communicate with Traefik:

```yaml
networks:
  proxy:
    external: true
```

This network must be created before starting Portainer:
```bash
docker network create proxy
```

## 🔒 Security Features

### Built-in Security
- **Read-only Docker socket** - Portainer can't modify Docker daemon
- **User authentication** - Built-in user management with roles
- **No-new-privileges** - Container can't escalate privileges
- **SSL/TLS** - HTTPS-only access via Traefik

### Optional: Add Traefik Basic Auth

Uncomment these lines in `docker-compose.yaml`:
```yaml
- "traefik.http.routers.portainer-secure.middlewares=portainer-auth"
- "traefik.http.middlewares.portainer-auth.basicauth.users=${PORTAINER_DASHBOARD_CREDENTIALS}"
```

Generate credentials:
```bash
# Install htpasswd if needed
sudo apt-get install apache2-utils

# Generate password (replace 'admin' and 'password')
echo $(htpasswd -nB admin) | sed -e s/\\$/\\$\\$/g

# Add to .env file
PORTAINER_DASHBOARD_CREDENTIALS=admin:$$2y$$05$$hashedpassword
```

## 📊 Usage

### Managing Containers
- **View containers**: Dashboard → Containers
- **Start/Stop**: Click container → Start/Stop buttons
- **Logs**: Click container → Logs tab
- **Console**: Click container → Console tab (execute commands)
- **Stats**: Click container → Stats tab (CPU/Memory)

### Managing Images
- **Pull images**: Images → Add image
- **Build images**: Images → Build a new image
- **Remove unused**: Images → Remove unused images

### Managing Networks
- **View networks**: Networks
- **Create network**: Networks → Add network
- **Inspect**: Click network to see connected containers

### Managing Volumes
- **View volumes**: Volumes
- **Create volume**: Volumes → Add volume
- **Browse files**: Click volume → Browse (if supported)

## 🔧 Configuration

### Environment Variables

| Variable | Description | Default |
|----------|-------------|---------|
| `TZ` | Timezone for timestamps | `Europe/Lisbon` |
| `DOMAIN_NAME` | Your domain name | `YOUR_DOMAIN` |
| `PORTAINER_DASHBOARD_CREDENTIALS` | Optional basic auth | Not set |

### Ports

| Port | Purpose | Access |
|------|---------|--------|
| `9000` | HTTP interface | Direct access (optional) |
| `9443` | HTTPS interface | Direct access (optional) |
| `443` | HTTPS via Traefik | `https://portainer.${DOMAIN_NAME}` |

### Volumes

| Volume | Purpose |
|--------|---------|
| `/var/run/docker.sock` | Docker socket (read-only) |
| `/data` | Portainer configuration and database |

## 🛠️ Maintenance

### View Logs
```bash
cd ~/homelab/docker-compose/portainer
docker compose logs -f
```

### Restart Portainer
```bash
docker compose restart
```

### Update Portainer
```bash
# Pull latest image
docker compose pull

# Recreate container
docker compose up -d

# Remove old images
docker image prune -f
```

### Backup Portainer Data
```bash
# Stop Portainer
docker compose down

# Backup data directory
tar -czf portainer-backup-$(date +%Y%m%d).tar.gz ~/homelab/docker/portainer/data/

# Restart Portainer
docker compose up -d
```

### Restore Portainer Data
```bash
# Stop Portainer
docker compose down

# Restore data
tar -xzf portainer-backup-YYYYMMDD.tar.gz -C ~/homelab/docker/portainer/

# Restart Portainer
docker compose up -d
```

## 🐛 Troubleshooting

### Can't Access Portainer Web Interface

```bash
# Check if Portainer is running
docker ps | grep portainer

# Check logs for errors
docker logs portainer

# Verify on proxy network
docker network inspect proxy | grep portainer

# Test direct access
curl -I http://localhost:9000
```

### "network proxy not found" Error

```bash
# Create the proxy network
docker network create proxy

# Restart Portainer
docker compose down
docker compose up -d
```

### Traefik Can't Reach Portainer

```bash
# Ensure both on proxy network
docker network inspect proxy

# Check Traefik logs
docker logs traefik | grep portainer

# Restart both services
cd ~/homelab/docker-compose/traefik
docker compose restart

cd ~/homelab/docker-compose/portainer
docker compose restart
```

### Permission Denied on Docker Socket

```bash
# Check socket permissions
ls -l /var/run/docker.sock

# Should show: srw-rw---- 1 root docker

# Add user to docker group if needed
sudo usermod -aG docker $USER
newgrp docker
```

### Lost Admin Password

```bash
# Stop Portainer
docker compose down

# Remove Portainer database (CAUTION: loses all settings)
rm -rf ~/homelab/docker/portainer/data/*

# Restart Portainer (will prompt for new admin account)
docker compose up -d
```

## 📚 Advanced Usage

### Connect to Remote Docker Hosts

1. Go to **Settings** → **Endpoints** → **Add endpoint**
2. Choose **Docker** or **Docker Swarm**
3. Enter host details and credentials
4. Test connection and save

### Create Container Templates

1. Go to **App Templates**
2. Click **Add template**
3. Define container configuration
4. Users can deploy from templates

### Set Up Teams and Users

1. Go to **Users** → **Add user**
2. Assign users to teams
3. Set team access rights per environment

## 🔗 Integration with Other Services

### Manage All Homelab Services

From Portainer, you can manage:
- **Pi-hole**: Start/stop, view logs, check DNS queries
- **Traefik**: Monitor routing, check certificates
- **Cloudflared**: View DoH proxy status

### Quick Actions

```bash
# View all homelab containers
docker ps --format "table {{.Names}}\t{{.Status}}\t{{.Ports}}"

# Stop all homelab services
cd ~/homelab/docker-compose/pihole && docker compose down
cd ~/homelab/docker-compose/traefik && docker compose down
cd ~/homelab/docker-compose/portainer && docker compose down

# Start all homelab services
docker network create proxy 2>/dev/null || true
cd ~/homelab/docker-compose/traefik && docker compose up -d
cd ~/homelab/docker-compose/pihole && docker compose up -d
cd ~/homelab/docker-compose/portainer && docker compose up -d
```

## 📈 Status

**Access**: https://portainer.YOUR_DOMAIN  
**Default Port**: 9000 (HTTP), 9443 (HTTPS)  
**Data Location**: `~/homelab/docker/portainer/data`  
**Network**: `proxy` (external)

## 🙏 Resources

- **Official Documentation**: https://docs.portainer.io/
- **GitHub**: https://github.com/portainer/portainer
- **Community Forums**: https://community.portainer.io/

---

**Last Updated**: December 2, 2025  
**Portainer Version**: CE (Community Edition) Latest  
**Tested On**: Raspberry Pi 4, Docker 29.1.1
