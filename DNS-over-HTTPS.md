# 🎯 Better Solution: DNS-over-HTTPS (DoH) with Cloudflare Workers

You're right! Cloud IDE is **blocking external connections**. Let's use **serverless-dns** instead - it works over HTTPS so no firewall issues.

---

## **⚡ Quick Setup: Cloudflare Workers (Free Tier)**

### **Step 1: Clone & Deploy serverless-dns**

```bash
# On your local machine or Cloud IDE:
git clone https://github.com/serverless-dns/serverless-dns.git
cd serverless-dns

# Install Wrangler CLI
npm install -g wrangler

# Login to Cloudflare
wrangler login

# Deploy to Cloudflare Workers
npm install
npm run build
wrangler deploy
```

---

### **Step 2: Configure Custom Domain Routing**

Create a custom configuration file to route your domains to `34.91.220.15`:

**`src/plugins/custom-routes.js`**:
```javascript
// Custom DNS routing for specific domains
const CUSTOM_ROUTES = {
  "usher.ttvnw.net": "34.91.220.15",
  "gql.twitch.tv": "34.91.220.15", 
  "chatgpt.com": "34.91.220.15"
};

export function customResolve(domain) {
  // Check if domain matches our custom routes
  for (const [route, ip] of Object.entries(CUSTOM_ROUTES)) {
    if (domain === route || domain.endsWith('.' + route)) {
      return ip;
    }
  }
  return null; // Use default DNS
}
```

---

### **Step 3: Modify Main Worker**

Edit `src/core/doh.js` to include your custom routing:

```javascript
import { customResolve } from '../plugins/custom-routes.js';

// In the DNS resolution handler, add:
async function handleDnsQuery(request) {
  const dnsQuery = await extractDnsQuery(request);
  const domain = extractDomain(dnsQuery);
  
  // Check custom routes first
  const customIP = customResolve(domain);
  if (customIP) {
    return createDnsResponse(domain, customIP);
  }
  
  // Otherwise, use normal DNS resolution
  return normalDnsResolution(dnsQuery);
}
```

---

## **🚀 Easier Alternative: Use Existing RethinkDNS + Custom Rules**

Instead of self-hosting, use RethinkDNS with custom configuration:

### **Step 1: Create Custom Blocklist**

1. Go to https://rethinkdns.com/configure
2. Click "Create Configuration"
3. Add your custom DNS overrides (note: this might not support custom IPs directly)

---

## **💡 BEST Solution for Your Use Case: Cloudflare Workers with Custom Code**

Create a simple DoH proxy:

**`worker.js`**:
```javascript
// Cloudflare Worker for DNS-over-HTTPS with custom routing
const CUSTOM_DNS_ROUTES = {
  "usher.ttvnw.net": "34.91.220.15",
  "gql.twitch.tv": "34.91.220.15",
  "chatgpt.com": "34.91.220.15"
};

addEventListener('fetch', event => {
  event.respondWith(handleRequest(event.request));
});

async function handleRequest(request) {
  // Handle DoH requests (GET and POST)
  if (request.url.includes('/dns-query')) {
    return handleDnsQuery(request);
  }
  
  // Health check
  return new Response('DNS-over-HTTPS Proxy Running', { status: 200 });
}

async function handleDnsQuery(request) {
  // Parse DNS query from request
  let dnsQuery;
  
  if (request.method === 'GET') {
    const url = new URL(request.url);
    const dnsParam = url.searchParams.get('dns');
    dnsQuery = Uint8Array.from(atob(dnsParam), c => c.charCodeAt(0));
  } else {
    dnsQuery = new Uint8Array(await request.arrayBuffer());
  }
  
  // Extract domain from DNS query
  const domain = extractDomain(dnsQuery);
  
  // Check if we have a custom route
  if (CUSTOM_DNS_ROUTES[domain]) {
    return createDnsResponse(domain, CUSTOM_DNS_ROUTES[domain]);
  }
  
  // Forward to Cloudflare DNS
  const response = await fetch('https://1.1.1.1/dns-query', {
    method: 'POST',
    headers: { 'Content-Type': 'application/dns-message' },
    body: dnsQuery
  });
  
  return new Response(response.body, {
    headers: { 'Content-Type': 'application/dns-message' }
  });
}

function extractDomain(dnsQuery) {
  // Simple DNS query parser (implement proper parsing)
  // This is a placeholder - use proper DNS library
  let offset = 12; // Skip header
  let domain = '';
  
  while (dnsQuery[offset] !== 0) {
    const length = dnsQuery[offset];
    offset++;
    domain += String.fromCharCode(...dnsQuery.slice(offset, offset + length)) + '.';
    offset += length;
  }
  
  return domain.slice(0, -1); // Remove trailing dot
}

function createDnsResponse(domain, ip) {
  // Create DNS A record response
  // This is simplified - implement proper DNS packet creation
  const parts = ip.split('.').map(Number);
  
  // Build DNS response (simplified)
  const response = new Uint8Array([
    // Header
    0x00, 0x00, 0x81, 0x80, 0x00, 0x01, 0x00, 0x01, 0x00, 0x00, 0x00, 0x00,
    // ... (complete DNS packet structure)
    ...parts // IP address bytes
  ]);
  
  return new Response(response, {
    headers: { 'Content-Type': 'application/dns-message' }
  });
}
```

---

## **⚡ FASTEST Solution: Use DNS-over-HTTPS Directly**

**Deploy this minimal worker:**

```bash
# Create new project
mkdir dns-proxy-worker && cd dns-proxy-worker

# Create wrangler.toml
cat > wrangler.toml << EOF
name = "dns-proxy"
main = "index.js"
compatibility_date = "2024-01-01"
EOF

# Create worker (use proper DNS library)
npm init -y
npm install dns-packet

# Create index.js
cat > index.js << 'EOF'
import dnsPacket from 'dns-packet';

const ROUTES = {
  "usher.ttvnw.net": "34.91.220.15",
  "gql.twitch.tv": "34.91.220.15",
  "chatgpt.com": "34.91.220.15"
};

export default {
  async fetch(request) {
    const url = new URL(request.url);
    
    if (url.pathname === '/dns-query') {
      return handleDns(request);
    }
    
    return new Response('DoH Proxy OK');
  }
};

async function handleDns(request) {
  let query;
  
  if (request.method === 'GET') {
    const dns = new URL(request.url).searchParams.get('dns');
    query = dnsPacket.decode(Buffer.from(dns, 'base64'));
  } else {
    query = dnsPacket.decode(Buffer.from(await request.arrayBuffer()));
  }
  
  const domain = query.questions[0].name;
  const customIP = ROUTES[domain];
  
  if (customIP) {
    const response = dnsPacket.encode({
      id: query.id,
      type: 'response',
      questions: query.questions,
      answers: [{
        type: 'A',
        name: domain,
        ttl: 300,
        data: customIP
      }]
    });
    
    return new Response(response, {
      headers: { 'Content-Type': 'application/dns-message' }
    });
  }
  
  // Forward to 1.1.1.1
  return fetch('https://1.1.1.1/dns-query', request);
}
EOF

# Deploy
wrangler deploy
```

---

## **📱 Then Configure Client**

After deploying, use your worker URL:

```bash
# Your DoH endpoint will be:
https://dns-proxy.YOUR_SUBDOMAIN.workers.dev/dns-query

# Test it:
curl "https://dns-proxy.YOUR_SUBDOMAIN.workers.dev/dns-query?dns=$(echo -n 'usher.ttvnw.net' | base64)"
```

**Configure in Firefox:**
```
Settings → Privacy & Security → DNS over HTTPS
Custom: https://dns-proxy.YOUR_SUBDOMAIN.workers.dev/dns-query
```

---

Would you like me to create a **ready-to-deploy Cloudflare Worker** with the complete code? 🚀
