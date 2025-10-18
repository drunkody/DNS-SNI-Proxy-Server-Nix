# 🔄 DNS CNAME Proxy Architecture

## **Mermaid Sequence Diagram:**

```mermaid
sequenceDiagram
    participant Client as 👤 Client Device
    participant Browser as 🌐 Browser
    participant DoH as ☁️ DoH Proxy<br/>(Cloudflare Worker)
    participant DNS as 🔍 Cloudflare DNS<br/>(1.1.1.1)
    participant ProxyServer as 🎯 subdomain.mirhost.com
    participant RealServer as 🎮 usher.ttvnw.net<br/>(Twitch Server)

    Note over Client,RealServer: 📡 DNS Resolution Phase

    Browser->>DoH: DNS Query: usher.ttvnw.net (A record)?
    activate DoH
    
    DoH->>DoH: Check CNAME_ROUTES table
    Note over DoH: Found: usher.ttvnw.net → subdomain.mirhost.com
    
    DoH->>DNS: Resolve subdomain.mirhost.com (A record)?
    activate DNS
    DNS-->>DoH: 34.91.220.15
    deactivate DNS
    
    DoH-->>Browser: CNAME: subdomain.mirhost.com<br/>A Record: 34.91.220.15
    deactivate DoH
    
    Note over Browser: Browser now knows:<br/>usher.ttvnw.net → subdomain.mirhost.com → 34.91.220.15

    Note over Client,RealServer: 🌐 HTTP/HTTPS Connection Phase

    Browser->>ProxyServer: CONNECT usher.ttvnw.net:443<br/>(to IP: 34.91.220.15)
    activate ProxyServer
    
    Note over ProxyServer: SNI Inspection:<br/>Host: usher.ttvnw.net
    
    ProxyServer->>RealServer: Forward TLS connection<br/>(Host: usher.ttvnw.net)
    activate RealServer
    
    RealServer-->>ProxyServer: TLS Handshake + Data
    ProxyServer-->>Browser: Encrypted Response
    deactivate RealServer
    deactivate ProxyServer
    
    Note over Client,RealServer: ✅ Client thinks it's talking to usher.ttvnw.net<br/>but traffic goes through subdomain.mirhost.com
```

---

## **Flow Diagram:**

```mermaid
graph TD
    A[👤 Client] -->|1. Visit usher.ttvnw.net| B{🌐 Browser DNS Lookup}
    
    B -->|2. Query via DoH| C[☁️ Cloudflare Worker<br/>DoH Proxy]
    
    C -->|3. Check routing table| D{Match found?}
    
    D -->|Yes: usher.ttvnw.net| E[📝 Return CNAME:<br/>subdomain.mirhost.com]
    D -->|No match| F[🔍 Forward to<br/>Cloudflare DNS 1.1.1.1]
    
    E -->|4. Resolve CNAME target| G[🔍 Query:<br/>subdomain.mirhost.com A?]
    G -->|5. Response| H[📍 IP: 34.91.220.15]
    
    H -->|6. DNS Response| B
    F -->|Standard DNS| B
    
    B -->|7. Connect to IP| I[🎯 subdomain.mirhost.com<br/>34.91.220.15]
    
    I -->|8. Check SNI Header| J{Which domain?}
    
    J -->|Host: usher.ttvnw.net| K[🎮 Proxy to Twitch]
    J -->|Host: gql.twitch.tv| L[💬 Proxy to Twitch API]
    J -->|Host: chatgpt.com| M[🤖 Proxy to OpenAI]
    
    K -->|9. Forward request| N[🌍 Real usher.ttvnw.net]
    L -->|9. Forward request| O[🌍 Real gql.twitch.tv]
    M -->|9. Forward request| P[🌍 Real chatgpt.com]
    
    N -->|10. Response| I
    O -->|10. Response| I
    P -->|10. Response| I
    
    I -->|11. Return data| A
    
    style C fill:#f9f,stroke:#333,stroke-width:4px
    style I fill:#bbf,stroke:#333,stroke-width:4px
    style D fill:#ffa,stroke:#333,stroke-width:2px
```

---

## **Architecture Overview:**

```mermaid
graph LR
    subgraph Client["👤 Client Side"]
        Browser[🌐 Browser<br/>Firefox/Chrome]
        DoHClient[📡 DoH Client]
    end
    
    subgraph CloudflareEdge["☁️ Cloudflare Network"]
        Worker[⚡ Cloudflare Worker<br/>DNS-over-HTTPS Proxy]
        CDN[🌍 Cloudflare CDN]
    end
    
    subgraph YourServer["🎯 Your Proxy Server<br/>subdomain.mirhost.com"]
        SNIProxy[🔀 SNI Proxy<br/>Port 443]
        DNSMasq[📝 dnsmasq<br/>Port 53]
        Nginx[🌐 nginx<br/>Port 80/443]
    end
    
    subgraph TargetServers["🎮 Target Services"]
        Twitch1[usher.ttvnw.net]
        Twitch2[gql.twitch.tv]
        ChatGPT[chatgpt.com]
    end
    
    Browser -->|DNS Query| DoHClient
    DoHClient -->|HTTPS POST| Worker
    Worker -->|CNAME Response:<br/>subdomain.mirhost.com| DoHClient
    DoHClient -->|IP: 34.91.220.15| Browser
    
    Browser -->|HTTPS Request<br/>SNI: usher.ttvnw.net| SNIProxy
    SNIProxy -->|Forward based on SNI| Twitch1
    SNIProxy -->|Forward based on SNI| Twitch2
    SNIProxy -->|Forward based on SNI| ChatGPT
    
    Twitch1 -->|Response| SNIProxy
    Twitch2 -->|Response| SNIProxy
    ChatGPT -->|Response| SNIProxy
    SNIProxy -->|Encrypted response| Browser
    
    style Worker fill:#ff9,stroke:#333,stroke-width:4px
    style SNIProxy fill:#9f9,stroke:#333,stroke-width:4px
    style Browser fill:#99f,stroke:#333,stroke-width:2px
```

---

## **Data Flow Diagram:**

```mermaid
flowchart TB
    Start([👤 User opens<br/>usher.ttvnw.net])
    
    Start --> DNS1{Browser cache<br/>has DNS?}
    DNS1 -->|No| DNS2[Query DoH Proxy]
    DNS1 -->|Yes| Connect
    
    DNS2 --> Check{Domain in<br/>CNAME_ROUTES?}
    
    Check -->|✅ Yes| CNAME[Return CNAME:<br/>subdomain.mirhost.com<br/>+ A: 34.91.220.15]
    Check -->|❌ No| Forward[Forward to<br/>Cloudflare DNS]
    
    CNAME --> Cache[Browser caches:<br/>usher.ttvnw.net = 34.91.220.15]
    Forward --> Cache
    
    Cache --> Connect[Connect to<br/>34.91.220.15:443]
    
    Connect --> TLS[TLS ClientHello<br/>SNI: usher.ttvnw.net]
    
    TLS --> Proxy[subdomain.mirhost.com<br/>receives connection]
    
    Proxy --> SNI{Read SNI<br/>header}
    
    SNI -->|usher.ttvnw.net| T1[Open connection to<br/>Real Twitch server]
    SNI -->|gql.twitch.tv| T2[Open connection to<br/>Real Twitch API]
    SNI -->|chatgpt.com| T3[Open connection to<br/>Real ChatGPT]
    
    T1 --> Tunnel[Tunnel encrypted<br/>data bidirectionally]
    T2 --> Tunnel
    T3 --> Tunnel
    
    Tunnel --> End([✅ User sees content<br/>thinks it's direct connection])
    
    style Check fill:#ffd,stroke:#333,stroke-width:3px
    style Proxy fill:#dfd,stroke:#333,stroke-width:3px
    style CNAME fill:#fdd,stroke:#333,stroke-width:2px
```

---

## **Network Packet Flow:**

```mermaid
sequenceDiagram
    autonumber
    
    participant C as 💻 Client<br/>192.168.1.100
    participant W as ☁️ Worker<br/>DoH Proxy
    participant P as 🎯 Proxy<br/>subdomain.mirhost.com<br/>34.91.220.15
    participant T as 🎮 Twitch<br/>usher.ttvnw.net<br/>151.101.2.167
    
    rect rgb(200, 220, 250)
        Note over C,W: Phase 1: DNS Resolution (over HTTPS)
        C->>W: POST /dns-query<br/>Query: usher.ttvnw.net A?
        W->>W: Lookup in CNAME table
        W->>C: Response:<br/>CNAME subdomain.mirhost.com<br/>A 34.91.220.15
    end
    
    rect rgb(220, 250, 220)
        Note over C,P: Phase 2: TCP Connection
        C->>P: SYN (to 34.91.220.15:443)
        P->>C: SYN-ACK
        C->>P: ACK
    end
    
    rect rgb(250, 220, 220)
        Note over C,T: Phase 3: TLS Handshake (SNI Routing)
        C->>P: ClientHello<br/>SNI: usher.ttvnw.net
        Note over P: Extract SNI header<br/>Route to real Twitch
        P->>T: TCP SYN to 151.101.2.167:443
        T->>P: SYN-ACK
        P->>T: Forward ClientHello<br/>SNI: usher.ttvnw.net
        T->>P: ServerHello + Certificate<br/>(*.ttvnw.net)
        P->>C: Forward TLS handshake
        C->>P: Encrypted data
        P->>T: Forward encrypted data
    end
    
    rect rgb(250, 250, 200)
        Note over C,T: Phase 4: Data Transfer
        T->>P: Video stream data
        P->>C: Proxy data to client
        Note over C: ✅ Browser shows:<br/>"Connected to usher.ttvnw.net"<br/>but routed via subdomain.mirhost.com
    end
```

---

## **Configuration Map:**

```mermaid
mindmap
  root((🎯 DNS CNAME<br/>Proxy System))
    [☁️ Cloudflare Worker]
      DoH Endpoint
        /dns-query
      CNAME Routes
        usher.ttvnw.net → subdomain.mirhost.com
        gql.twitch.tv → subdomain.mirhost.com
        chatgpt.com → subdomain.mirhost.com
      DNS Resolution
        Query Cloudflare 1.1.1.1
        Return CNAME + A record
    
    [🎯 subdomain.mirhost.com]
      IP: 34.91.220.15
      Services
        SNI Proxy :443
        Nginx :80
        dnsmasq :53
      Routing Logic
        Read SNI header
        Forward to real server
        Transparent proxy
    
    [👤 Client Configuration]
      Browser Settings
        DoH URL
        Firefox/Chrome
      DNS Client
        System DNS
        Private DNS Android
      Mobile Apps
        DoH Profile iOS
        
    [🎮 Target Servers]
      Twitch
        usher.ttvnw.net
        gql.twitch.tv
      OpenAI
        chatgpt.com
      Other
        Custom domains
```

---

## **How It Works - Simple Explanation:**

1. **Client asks**: "What's the IP of `usher.ttvnw.net`?"
2. **DoH Proxy responds**: "It's a CNAME to `subdomain.mirhost.com` which is `34.91.220.15`"
3. **Client connects** to `34.91.220.15` but sends SNI header: `usher.ttvnw.net`
4. **SNI Proxy reads** the SNI header and forwards to the real Twitch server
5. **Data flows** through your proxy transparently
6. **Client thinks** it's connected directly to Twitch!
