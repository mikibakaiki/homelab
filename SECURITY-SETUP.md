# =============================================================================
# HOMELAB SECURITY SETUP GUIDE
# =============================================================================

This file explains how to set up your sensitive configuration files safely.

## 🔐 SECURITY OVERVIEW

This homelab setup uses several sensitive files that should NEVER be committed to git:
- API tokens and keys
- Passwords and credentials  
- SSL certificates and private keys
- Database files with personal data
- Log files with potentially sensitive information

## 📋 REQUIRED SETUP STEPS

### 1. Copy Example Files to Real Files

```bash
# In /homelab/docker-compose/traefik/
cp .env.example .env
cp cf-token.example cf-token

# In /homelab/docker/traefik/
cp config.yaml.example config.yaml
cp traefik.yaml.example traefik.yaml

# In /homelab/docker-compose/pihole/
cp .env.example .env
```

### 2. Fill in Your Actual Values

#### Traefik Config Files:
- `config.yaml`: Update domain names and server IPs to match your setup
- `traefik.yaml`: Update email address for Let's Encrypt notifications

#### Traefik (.env):
- `TRAEFIK_DASHBOARD_CREDENTIALS`: Generate with `htpasswd -nbB admin yourpassword`
- `CF_DNS_API_TOKEN`: Get from Cloudflare dashboard
- `ACME_EMAIL`: Your email for Let's Encrypt notifications
- `DOMAIN_NAME`: Your actual domain

#### Pi-hole (.env):
- `PIHOLE_PASSWORD`: Strong password for Pi-hole admin
- `TZ`: Your timezone
- Network settings matching your actual setup

#### Cloudflare Token (cf-token):
- Replace contents with your actual Cloudflare API token
- Required permissions: Zone:Read, DNS:Edit for your domain

### 3. Verify File Permissions

```bash
# Make sure sensitive files are not world-readable
chmod 600 .env cf-token
```

## 🛡️ WHAT'S PROTECTED

The .gitignore file protects:

### Credentials & Secrets:
- `.env` files (environment variables)
- `cf-token` (Cloudflare API token)
- `*.pem`, `*.key`, `*.crt` (certificates & private keys)
- Authentication files

### Application Data:
- Pi-hole databases and logs
- Traefik ACME certificates
- Docker volumes and data directories
- All log files

### System Files:
- OS-specific files (.DS_Store, Thumbs.db)
- Editor temp files
- Backup files

## 🚨 IMPORTANT REMINDERS

1. **NEVER commit real .env files** - only commit .env.example files
2. **NEVER commit API tokens or certificates**
3. **Use strong, unique passwords** for all services
4. **Regularly rotate API tokens and passwords**
5. **Keep backups** of your configurations (securely, outside git)

## 🔍 VERIFY YOUR SETUP

Check what files would be committed:
```bash
git status
git add . --dry-run
```

If you see any sensitive files, check your .gitignore!

## 📚 ADDITIONAL SECURITY

Consider also:
- Using Docker secrets for production deployments
- Setting up proper firewall rules
- Regular security updates
- Monitoring for unauthorized access
