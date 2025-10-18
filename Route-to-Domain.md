# 🎯 Route to Domain Instead of IP

Perfect! Let's configure DNS to route to **`subdomain.mirhost.com`** instead of IP addresses.

---

## **Option 1: DNS CNAME Records (Recommended)**

Update your DNS proxy to return **CNAME** records instead of **A** records:

### **Update Docker Container Config:**

```bash
# Stop current container
docker stop dns-proxy
docker rm dns-proxy

# Run with CNAME routing
docker run -d --name dns-proxy \
  -p 5353:53/udp \
  -p 5353:53/tcp \
  -p 8080:80 \
  -p 8443:443 \
  -e PROXY_DOMAIN="subdomain.mirhost.com" \
  -e DOMAINS="usher.ttvnw.net,gql.twitch.tv,chatgpt.com" \
  dns-proxy-server:latest
```

### **Update Dockerfile - Add CNAME Support:**

```dockerfile
FROM alpine:latest

RUN apk add --no-cache \
    dnsmasq \
    nginx \
    bash \
    curl \
    bind-tools

# Copy config generator script
COPY <<'EOF' /usr/local/bin/start.sh
#!/bin/bash
set -e

PROXY_DOMAIN="${PROXY_DOMAIN:-subdomain.mirhost.com}"
IFS=',' read -ra DOMAIN_LIST <<< "$DOMAINS"

echo "📡 Proxy Domain: $PROXY_DOMAIN"
echo "🌐 Domains to Proxy: $DOMAINS"

# Generate dnsmasq config with CNAME records
cat > /etc/dnsmasq.conf << DNSMASQ_EOF
# Upstream DNS servers
server=1.1.1.1
server=1.0.0.1

# Cache settings
cache-size=10000
no-negcache

# Custom CNAME routing
DNSMASQ_EOF

# Add CNAME records for each domain
for domain in "${DOMAIN_LIST[@]}"; do
  domain=$(echo "$domain" | xargs) # trim whitespace
  echo "cname=${domain},${PROXY_DOMAIN}" >> /etc/dnsmasq.conf
  echo "   → ${domain} -> ${PROXY_DOMAIN}"
done

# Start dnsmasq
dnsmasq --no-daemon &

# Start nginx
nginx -g 'daemon off;'
EOF

RUN chmod +x /usr/local/bin/start.sh

# Nginx config for proxy
COPY <<'NGINX_EOF' /etc/nginx/nginx.conf
events {
    worker_connections 1024;
}

http {
    server {
        listen 80;
        
        location /health {
            return 200 "DNS Proxy Running\n";
        }
        
        # Proxy all other requests
        location / {
            resolver 127.0.0.1:53;
            proxy_pass http://$http_host$request_uri;
            proxy_set_header Host $http_host;
            proxy_set_header X-Real-IP $remote_addr;
        }
    }
}
NGINX_EOF

EXPOSE 53/udp 53/tcp 80 443

CMD ["/usr/local/bin/start.sh"]
```

### **Build and Run:**

```bash
# Build new image
docker build -t dns-proxy-cname:latest .

# Run with your domain
docker run -d --name dns-proxy \
  -p 5353:53/udp \
  -p 5353:53/tcp \
  -p 8080:80 \
  -e PROXY_DOMAIN="subdomain.mirhost.com" \
  -e DOMAINS="usher.ttvnw.net,gql.twitch.tv,chatgpt.com" \
  dns-proxy-cname:latest
```

### **Test CNAME Resolution:**

```bash
# From Cloud IDE:
dig @localhost -p 5353 usher.ttvnw.net

# Expected output:
# ;; ANSWER SECTION:
# usher.ttvnw.net.  300  IN  CNAME  subdomain.mirhost.com.
# subdomain.mirhost.com. 300 IN A   xx.xx.xx.xx
```

---

## **Option 2: SNI Proxy (For HTTPS Traffic)**

Route HTTPS traffic based on domain name without decrypting:

### **Install SNI Proxy:**

```bash
# Update Dockerfile
FROM alpine:latest

RUN apk add --no-cache \
    dnsmasq \
    sniproxy \
    bash

COPY <<'EOF' /etc/sniproxy.conf
user daemon

listener 0.0.0.0:443 {
    protocol tls
    table routes
    
    access_log {
        filename /var/log/sniproxy/access.log
        priority notice
    }
}

table routes {
    # Route to your domain
    usher\.ttvnw\.net subdomain.mirhost.com:443
    gql\.twitch\.tv subdomain.mirhost.com:443
    chatgpt\.com subdomain.mirhost.com:443
    
    # Default: direct connection
    .* *:443
}
EOF

CMD ["sniproxy", "-f"]
```

---

## **Option 3: Cloudflare Worker with CNAME (DNS-over-HTTPS)**

Best solution for Cloud IDE! Works over HTTPS:

### **`worker.js`:**

```javascript
import dnsPacket from 'dns-packet';

const CNAME_ROUTES = {
  "usher.ttvnw.net": "subdomain.mirhost.com",
  "gql.twitch.tv": "subdomain.mirhost.com",
  "chatgpt.com": "subdomain.mirhost.com"
};

export default {
  async fetch(request) {
    const url = new URL(request.url);
    
    // Health check
    if (url.pathname === '/health') {
      return new Response('DoH Proxy with CNAME routing OK');
    }
    
    // DNS-over-HTTPS endpoint
    if (url.pathname === '/dns-query') {
      return handleDnsQuery(request);
    }
    
    return new Response('Use /dns-query for DNS queries', { status: 404 });
  }
};

async function handleDnsQuery(request) {
  try {
    // Parse DNS query
    let queryBuffer;
    
    if (request.method === 'GET') {
      const dnsParam = new URL(request.url).searchParams.get('dns');
      if (!dnsParam) {
        return new Response('Missing dns parameter', { status: 400 });
      }
      queryBuffer = base64ToBuffer(dnsParam);
    } else if (request.method === 'POST') {
      queryBuffer = await request.arrayBuffer();
    } else {
      return new Response('Method not allowed', { status: 405 });
    }
    
    const query = dnsPacket.decode(Buffer.from(queryBuffer));
    const question = query.questions[0];
    const domain = question.name;
    
    // Check if we have a CNAME route for this domain
    const cnameTarget = CNAME_ROUTES[domain];
    
    if (cnameTarget && question.type === 'A') {
      // First, resolve the CNAME target
      const targetIP = await resolveToIP(cnameTarget);
      
      // Build response with CNAME + A record
      const response = dnsPacket.encode({
        id: query.id,
        type: 'response',
        flags: dnsPacket.RECURSION_DESIRED | dnsPacket.RECURSION_AVAILABLE,
        questions: query.questions,
        answers: [
          {
            type: 'CNAME',
            class: 'IN',
            name: domain,
            ttl: 300,
            data: cnameTarget
          },
          {
            type: 'A',
            class: 'IN',
            name: cnameTarget,
            ttl: 300,
            data: targetIP
          }
        ]
      });
      
      return new Response(response, {
        headers: { 
          'Content-Type': 'application/dns-message',
          'Cache-Control': 'max-age=300'
        }
      });
    }
    
    // No custom route - forward to Cloudflare DNS
    const upstreamResponse = await fetch('https://1.1.1.1/dns-query', {
      method: 'POST',
      headers: {
        'Content-Type': 'application/dns-message',
        'Accept': 'application/dns-message'
      },
      body: queryBuffer
    });
    
    return new Response(upstreamResponse.body, {
      headers: { 'Content-Type': 'application/dns-message' }
    });
    
  } catch (error) {
    console.error('DNS query error:', error);
    return new Response('DNS query failed', { status: 500 });
  }
}

async function resolveToIP(domain) {
  // Query DNS for the target domain
  const query = dnsPacket.encode({
    type: 'query',
    id: Math.floor(Math.random() * 65535),
    flags: dnsPacket.RECURSION_DESIRED,
    questions: [{
      type: 'A',
      name: domain
    }]
  });
  
  const response = await fetch('https://1.1.1.1/dns-query', {
    method: 'POST',
    headers: { 'Content-Type': 'application/dns-message' },
    body: query
  });
  
  const decoded = dnsPacket.decode(Buffer.from(await response.arrayBuffer()));
  
  // Return first A record
  const aRecord = decoded.answers.find(a => a.type === 'A');
  return aRecord ? aRecord.data : '0.0.0.0';
}

function base64ToBuffer(base64) {
  // URL-safe base64 decode
  const base64Cleaned = base64.replace(/-/g, '+').replace(/_/g, '/');
  const binaryString = atob(base64Cleaned);
  const bytes = new Uint8Array(binaryString.length);
  for (let i = 0; i < binaryString.length; i++) {
    bytes[i] = binaryString.charCodeAt(i);
  }
  return bytes.buffer;
}
```

### **Deploy to Cloudflare Workers:**

```bash
# Install dependencies
npm init -y
npm install dns-packet

# Create wrangler.toml
cat > wrangler.toml << EOF
name = "dns-cname-proxy"
main = "worker.js"
compatibility_date = "2024-01-01"

[build]
command = "npm install"
EOF

# Deploy
npx wrangler deploy
```

### **Test Your DoH Endpoint:**

```bash
# Your worker URL:
# https://dns-cname-proxy.YOUR_SUBDOMAIN.workers.dev

# Test from local machine:
curl -H "accept: application/dns-json" \
  "https://dns-cname-proxy.YOUR_SUBDOMAIN.workers.dev/dns-query?name=usher.ttvnw.net&type=A"

# Should return:
# {
#   "Answer": [
#     { "name": "usher.ttvnw.net", "type": 5, "data": "subdomain.mirhost.com" },
#     { "name": "subdomain.mirhost.com", "type": 1, "data": "xx.xx.xx.xx" }
#   ]
# }
```

---

## **📱 Configure Clients:**

### **Firefox:**
```
Settings → Privacy & Security → DNS over HTTPS
Custom: https://dns-cname-proxy.YOUR_SUBDOMAIN.workers.dev/dns-query
```

### **Android (Private DNS):**
```
Settings → Network → Private DNS
DNS-over-TLS hostname: max.rethinkdns.com (if using RethinkDNS)
```

### **iOS:**
Install DoH profile from: https://dns.notjakob.com/tool.html

---

Which option do you prefer? **Cloudflare Worker** is easiest for Cloud IDE! 🚀
