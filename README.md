# DNS Proxy Server with Nix

A declarative, containerized DNS proxy server built with Nix. This server uses nginx for SNI-based HTTPS proxying and dnsmasq for custom DNS resolution, allowing you to bypass geographic restrictions for services like Twitch, ChatGPT, Gemini, and more.

## 🎯 Purpose

This project solves geo-blocking issues by:
1. **DNS Resolution**: Routes specific domains to your VPS IP
2. **SNI Proxying**: Forwards HTTPS traffic based on Server Name Indication (SNI)

This is particularly useful for:
- Unlocking Twitch quality settings
- Accessing ChatGPT, Gemini, Grok from restricted regions
- Bypassing IP-based geographic restrictions

## 📋 Prerequisites

- Nix with flakes enabled
- Docker (for running the container)
- A VPS with unrestricted internet access

## 🚀 Quick Start

### 1. Build the Docker Image

```bash
nix build .#dockerImage
```

### 2. Load into Docker

```bash
docker load < result
```

### 3. Run the Container

Replace `YOUR_VPS_IP` with your actual VPS public IP:

```bash
docker run -d \
  --name dns-proxy \
  --restart unless-stopped \
  -p 53:53/udp \
  -p 443:443 \
  -e PROXY_IP="YOUR_VPS_IP" \
  -e DOMAINS="usher.ttvnw.net,gql.twitch.tv,chatgpt.com,gemini.google.com,grok.com" \
  dns-proxy-server:latest
```

### 4. Configure Your Clients

**Option A: Set DNS Server**
Point your device/router DNS to your VPS IP.

**Option B: Edit Hosts File**
Add to `/etc/hosts` (Linux/Mac) or `C:\Windows\System32\drivers\etc\hosts` (Windows):
```
YOUR_VPS_IP usher.ttvnw.net
YOUR_VPS_IP gql.twitch.tv
YOUR_VPS_IP chatgpt.com
```

## 🧪 Testing

### Test DNS Resolution
```bash
# From your local machine (replace YOUR_VPS_IP)
dig @YOUR_VPS_IP usher.ttvnw.net +short

# Should return YOUR_VPS_IP
```

### Test Container Health
```bash
docker logs dns-proxy
docker exec dns-proxy ps aux
curl http://YOUR_VPS_IP:80/health
```

### Check Docker Health Status
```bash
docker inspect --format='{{.State.Health.Status}}' dns-proxy
```

## 🔧 Configuration

### Environment Variables

| Variable | Required | Default | Description |
|----------|----------|---------|-------------|
| `PROXY_IP` | **Yes** | None | Your VPS public IP address |
| `DOMAINS` | No | `usher.ttvnw.net,gql.twitch.tv,...` | Comma-separated list of domains to proxy |

### Adding More Domains

```bash
docker run -d \
  --name dns-proxy \
  -p 53:53/udp \
  -p 443:443 \
  -e PROXY_IP="1.2.3.4" \
  -e DOMAINS="example.com,another-site.org,third-domain.net" \
  dns-proxy-server:latest
```

## 🔒 Security Considerations

### ⚠️ Important Security Notes

1. **Firewall Configuration**: Restrict port 53/udp to trusted IPs only
   ```bash
   # Example using ufw
   ufw allow from TRUSTED_IP to any port 53 proto udp
   ufw deny 53/udp
   ```

2. **Rate Limiting**: Built-in rate limiting (30 queries/second per IP) prevents DNS amplification attacks

3. **Non-root User**: The container runs services as the `dnsproxy` user (not root)

4. **No Privileged Mode**: Uses Linux capabilities instead of `--privileged` flag

### Recommended Firewall Rules

```bash
# Allow HTTPS proxy from anywhere
iptables -A INPUT -p tcp --dport 443 -j ACCEPT

# Allow DNS only from your home IP
iptables -A INPUT -p udp --dport 53 -s YOUR_HOME_IP -j ACCEPT
iptables -A INPUT -p udp --dport 53 -j DROP
```

## 📊 Monitoring

### View Logs
```bash
# Real-time logs
docker logs -f dns-proxy

# nginx access logs
docker exec dns-proxy tail -f /var/log/nginx/stream-access.log

# dnsmasq query logs
docker exec dns-proxy tail -f /var/log/dnsmasq.log
```

### Check Service Status
```bash
docker exec dns-proxy ps aux
```

## 🛠️ Development

### Enter Development Shell
```bash
nix develop
```

### Test Locally (without Docker)
```bash
export PROXY_IP="1.2.3.4"
export DOMAINS="example.com"
nix run
```

### Format Code
```bash
nix fmt
```

## 🐛 Troubleshooting

### Container Won't Start

Check logs:
```bash
docker logs dns-proxy
```

Common issues:
- `PROXY_IP not set`: You must provide `-e PROXY_IP="your.ip.here"`
- Port already in use: Stop conflicting services on ports 53, 443
- Permission denied: Ensure Docker has necessary permissions

### DNS Not Resolving

```bash
# Test from container itself
docker exec dns-proxy dig @localhost usher.ttvnw.net +short

# Check if dnsmasq is running
docker exec dns-proxy ps aux | grep dnsmasq

# View dnsmasq logs
docker exec dns-proxy cat /var/log/dnsmasq.log
```

### nginx Not Proxying

```bash
# Check nginx is running
docker exec dns-proxy ps aux | grep nginx

# View nginx errors
docker exec dns-proxy cat /var/log/nginx/error.log

# Test nginx config
docker exec dns-proxy nginx -t
```

## 📚 How It Works

1. **Client makes DNS request** → dnsmasq resolves configured domains to `PROXY_IP`
2. **Client connects to PROXY_IP:443** → nginx reads SNI from TLS handshake
3. **nginx proxies to actual server** → Connection forwarded to real destination
4. **Traffic flows through VPS** → Appears to come from VPS location

## 🔄 Updating

```bash
# Rebuild image
nix build .#dockerImage

# Stop old container
docker stop dns-proxy
docker rm dns-proxy

# Load and run new image
docker load < result
docker run -d --name dns-proxy ... dns-proxy-server:latest
```

## 📄 License

[Your chosen license]

## 🙏 Credits

Based on the tutorial for SNI proxy setup with nginx and dnsmasq.

## ⚠️ Disclaimer

This tool is for educational purposes and legitimate use cases (e.g., accessing services while traveling). Ensure compliance with service terms and local laws.