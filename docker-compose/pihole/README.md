# Pi-hole v6 with Cloudflared DoH and DHCP Helper

This directory contains the Docker Compose configuration for a complete Pi-hole v6 setup with DNS-over-HTTPS (DoH) via Cloudflared and DHCP functionality using bridge networking.

## 🚀 Features

- **Pi-hole v6** - Network-wide ad blocking and DNS server
- **Cloudflared DoH Proxy** - Encrypted DNS queries to Cloudflare/Quad9
- **DHCP Support** - Bridge networking with DHCP helper for LAN DHCP functionality
- **Traefik Integration** - HTTPS access via reverse proxy
- **Comprehensive Blocking** - 12 curated adlists blocking 894,108+ domains

## 📋 Services

| Service | Description | Network | Ports |
|---------|-------------|---------|-------|
| `pihole` | DNS/DHCP server with web interface | bridge + proxy | 53/tcp, 53/udp, 8080/tcp |
| `cloudflared` | DoH proxy for encrypted DNS | bridge | 5053 (internal) |
| `dhcp-helper` | DHCP relay for bridge networking | host | - |

## 🌐 Network Architecture

```
Internet → Cloudflared (DoH) → Pi-hole → Clients
    ↓
DHCP Helper → Pi-hole DHCP → LAN Clients
    ↓
Traefik → Pi-hole Web Interface (HTTPS)
```

### Network Configuration
- **Backend Network**: `172.31.0.0/24` (bridge)
- **Pi-hole IP**: `172.31.0.100`
- **LAN DHCP Range**: `192.168.1.100-200`
- **Router Gateway**: `192.168.1.254`
- **Pi-hole Host IP**: `192.168.1.5`

## 🔧 Configuration

### Environment Variables Required

Create a `.env` file with:

```env
# Pi-hole Configuration
PIHOLE_PASSWORD=your_secure_password_here
TZ=Europe/Lisbon

# Traefik Dashboard Credentials (optional)
PIHOLE_DASHBOARD_CREDENTIALS=admin:$2y$05$hashedpassword
```

### DNS Configuration
- **Upstream DNS**: Cloudflared DoH proxy
- **DNSSEC**: Enabled
- **Custom DNS**: Local domain resolution for homelab services
- **Listening Mode**: All interfaces

### DHCP Configuration
- **Active**: Yes
- **Range**: 192.168.1.100-200
- **Lease Time**: 24 hours
- **Gateway**: 192.168.1.254
- **DNS Server**: Forces 192.168.1.5 (Pi-hole host IP)

## 📦 Quick Start

1. **Ensure prerequisites**:
   ```bash
   # Create directory structure
   mkdir -p /home/miki/homelab/docker/pihole/pihole
   
   # Set up environment
   cp .env.example .env
   # Edit .env with your values
   ```

2. **Start services**:
   ```bash
   docker compose up -d
   ```

3. **Verify functionality**:
   ```bash
   # Check service status
   docker compose ps
   
   # Test DNS resolution
   nslookup google.com 192.168.1.5
   
   # Check Pi-hole logs
   docker logs pihole
   ```

4. **Access web interface**:
   - **HTTPS**: https://pihole.your.domain/admin/
   - **HTTP**: http://192.168.1.5:8080/admin/

## 📊 Blocking Lists

The configuration includes 12 comprehensive adlists:

| List | Domains | Purpose |
|------|---------|---------|
| Steven Black's Hosts | 232,646 | Base comprehensive blocking |
| OISD Big | 203,554 | Popular comprehensive list |
| 1Hosts Pro | 350,521 | Professional-grade blocking |
| EasyList | 36,754 | Standard web ad blocking |
| EU List | 36,514 | European content filtering |
| YouTube Blocking (2 lists) | 33,693 | YouTube-specific ads |
| Portuguese List | 179 | Regional content |
| Smart TV Blocking | 242 | Samsung, LG, etc. |
| Anti-Adblock Killer | 5 | Bypass anti-adblocker detection |

**Total: 894,108 domains blocked** (799,729 unique)

## 🔒 Security Features

- **Environment variable secrets** - No hardcoded passwords
- **HTTPS access** - SSL/TLS encryption via Traefik
- **Network isolation** - Bridge networking with controlled access
- **Container security** - No new privileges, non-root execution
- **DNSSEC validation** - DNS security extensions enabled

## 🛠️ Maintenance

### Update Gravity Database
```bash
docker exec pihole pihole -g
```

### View Logs
```bash
# Pi-hole logs
docker logs pihole --tail 50

# Cloudflared logs
docker logs cloudflared --tail 20

# DHCP helper logs
docker logs dhcp-helper --tail 20
```

### Backup Configuration
```bash
# Backup Pi-hole data
tar -czf pihole-backup-$(date +%Y%m%d).tar.gz /home/miki/homelab/docker/pihole/
```

### Add Custom Adlists
1. Access web interface: https://pihole.your.domain/admin/
2. Navigate to: Group Management → Adlists
3. Add new list URL and comment
4. Update gravity: `docker exec pihole pihole -g`

## 🐛 Troubleshooting

### DNS Not Working
```bash
# Check Pi-hole status
docker exec pihole pihole status

# Test internal DNS
docker exec pihole nslookup google.com 127.0.0.1

# Check Cloudflared connectivity
docker logs cloudflared
```

### DHCP Issues
```bash
# Check DHCP helper logs
docker logs dhcp-helper

# Verify Pi-hole DHCP settings
docker exec pihole pihole -a -i

# Check DHCP leases
docker exec pihole cat /etc/pihole/dhcp.leases
```

### Web Interface Access
```bash
# Check Traefik routing
curl -I -H "Host: pihole.your.domain" http://localhost

# Direct access test
curl -I http://192.168.1.5:8080/admin/
```

## 📁 Directory Structure

```
/home/miki/homelab/docker-compose/pihole/
├── docker-compose.yaml    # Main configuration
├── .env                   # Environment variables
├── .env.example          # Template for environment setup
└── README.md             # This file

/home/miki/homelab/docker/pihole/pihole/
├── gravity.db            # Blocklist database
├── pihole-FTL.db        # Pi-hole FTL database
├── pihole.toml          # Pi-hole configuration
├── dhcp.leases          # DHCP lease information
├── dnsmasq.conf         # DNS configuration
├── custom.list          # Custom DNS entries
└── ...                  # Other Pi-hole files
```

## 🔗 Related Services

This Pi-hole setup integrates with:
- **Traefik** - Reverse proxy for HTTPS access
- **Portainer** - Container management
- **Cloudflare** - DNS-over-HTTPS upstream

## 📚 References

- [Pi-hole Documentation](https://docs.pi-hole.net/)
- [Cloudflared DoH Setup](https://docs.pi-hole.net/guides/dns/cloudflared/)
- [Docker Compose Reference](https://docs.docker.com/compose/)
- [Traefik Integration](https://doc.traefik.io/traefik/)
