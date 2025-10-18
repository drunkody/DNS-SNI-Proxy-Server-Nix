{ pkgs }:

let
  startScript = pkgs.writeScriptBin "start-proxy" ''
    #!${pkgs.bash}/bin/bash
    set -euo pipefail  # Exit on error, undefined vars, pipe failures

    # ============================================================================
    # DNS Proxy Server Startup Script
    # ============================================================================

    # Read environment variables with defaults
    : ''${PROXY_IP:?"ERROR: PROXY_IP environment variable must be set. Example: export PROXY_IP=\"1.2.3.4\""}
    : ''${DOMAINS:="usher.ttvnw.net,gql.twitch.tv,chatgpt.com,gemini.google.com,grok.com"}

    echo "╔═══════════════════════════════════════════════════════╗"
    echo "║         DNS Proxy Server Initializing                ║"
    echo "╚═══════════════════════════════════════════════════════╝"
    echo ""
    echo "📍 Proxy Server IP: $PROXY_IP"
    echo "🌐 Domains to Proxy: $DOMAINS"
    echo ""

    # Define paths for configuration files
    DNSMASQ_CONF="/etc/dnsmasq.conf"
    NGINX_CONF="/etc/nginx/nginx.conf"
    DNSMASQ_LOG="/var/log/dnsmasq.log"

    # ============================================================================
    # Generate dnsmasq Configuration
    # ============================================================================
    echo "⚙️  Generating dnsmasq configuration..."

    # Create the base configuration
    cat > "$DNSMASQ_CONF" <<EOF
# This file is generated dynamically at container startup

# Listen on all interfaces
listen-address=0.0.0.0
port=53

# Don't read /etc/resolv.conf or /etc/hosts
no-resolv
no-hosts

# Upstream DNS servers (Cloudflare)
server=1.1.1.1
server=1.0.0.1

# Cache settings
cache-size=10000

# Logging
log-queries
log-facility=$DNSMASQ_LOG

# Security settings
bogus-priv            # Don't forward private IP ranges to upstream
bind-interfaces       # Bind to specific interfaces for security
domain-needed         # Don't forward plain names
no-poll               # Don't poll /etc/resolv.conf for changes

# Rate limiting (prevent DNS amplification attacks)
dns-ratelimit=30      # Max 30 queries per second per IP
EOF

    # Parse the DOMAINS variable and add 'address' rules
    echo "📝 Adding domain routing rules..."
    IFS=',' read -ra DOMAIN_ARRAY <<< "$DOMAINS"
    for domain in "''${DOMAIN_ARRAY[@]}"; do
      # Trim whitespace
      domain=$(echo "$domain" | xargs)
      if [ -n "$domain" ]; then
        echo "   → $domain -> $PROXY_IP"
        echo "address=/$domain/$PROXY_IP" >> "$DNSMASQ_CONF"
      fi
    done
    echo ""

    # ============================================================================
    # Prepare Log Files and Directories
    # ============================================================================
    echo "📁 Preparing log directories..."
    mkdir -p /var/log/nginx
    touch "$DNSMASQ_LOG"
    chown dnsproxy:dnsproxy /var/log/nginx /var/log/dnsmasq.log
    chmod 644 "$DNSMASQ_LOG"

    # ============================================================================
    # Validate Configurations
    # ============================================================================
    echo "✅ Validating configurations..."

    if ! ${pkgs.dnsmasq}/sbin/dnsmasq --test -C "$DNSMASQ_CONF"; then
      echo "❌ ERROR: dnsmasq configuration is invalid!"
      exit 1
    fi
    echo "   ✓ dnsmasq configuration is valid"

    if ! ${pkgs.nginx}/bin/nginx -t -c "$NGINX_CONF" 2>&1 | grep -q "successful"; then
      echo "❌ ERROR: nginx configuration is invalid!"
      ${pkgs.nginx}/bin/nginx -t -c "$NGINX_CONF"
      exit 1
    fi
    echo "   ✓ nginx configuration is valid"
    echo ""

    # ============================================================================
    # Setup Signal Handling for Graceful Shutdown
    # ============================================================================
    NGINX_PID=""
    DNSMASQ_PID=""

    cleanup() {
      echo ""
      echo "🛑 Shutting down services gracefully..."

      if [ -n "$NGINX_PID" ]; then
        echo "   Stopping nginx (PID: $NGINX_PID)..."
        ${pkgs.nginx}/bin/nginx -s quit 2>/dev/null || kill "$NGINX_PID" 2>/dev/null || true
      fi

      if [ -n "$DNSMASQ_PID" ]; then
        echo "   Stopping dnsmasq (PID: $DNSMASQ_PID)..."
        kill -TERM "$DNSMASQ_PID" 2>/dev/null || true
      fi

      echo "✅ Shutdown complete"
      exit 0
    }

    trap cleanup SIGTERM SIGINT SIGQUIT

    # ============================================================================
    # Start Services
    # ============================================================================
    echo "🚀 Starting nginx..."
    ${pkgs.nginx}/bin/nginx -c "$NGINX_CONF" &
    NGINX_PID=$!

    # Wait a moment for nginx to start
    sleep 1

    # Check if nginx is still running
    if ! kill -0 "$NGINX_PID" 2>/dev/null; then
      echo "❌ ERROR: nginx failed to start!"
      cat /var/log/nginx/error.log 2>/dev/null || true
      exit 1
    fi
    echo "   ✓ nginx started successfully (PID: $NGINX_PID)"

    echo "🚀 Starting dnsmasq..."
    ${pkgs.dnsmasq}/sbin/dnsmasq --no-daemon -C "$DNSMASQ_CONF" &
    DNSMASQ_PID=$!

    # Wait a moment for dnsmasq to start
    sleep 1

    # Check if dnsmasq is still running
    if ! kill -0 "$DNSMASQ_PID" 2>/dev/null; then
      echo "❌ ERROR: dnsmasq failed to start!"
      cat "$DNSMASQ_LOG" 2>/dev/null || true
      exit 1
    fi
    echo "   ✓ dnsmasq started successfully (PID: $DNSMASQ_PID)"
    echo ""

    # ============================================================================
    # Self-Test
    # ============================================================================
    echo "🧪 Running self-tests..."
    sleep 2  # Give services time to fully initialize

    # Test nginx health endpoint
    if ${pkgs.curl}/bin/curl -sf http://localhost:80/health > /dev/null; then
      echo "   ✓ nginx health check passed"
    else
      echo "   ⚠️  nginx health check failed (non-critical)"
    fi

    # Test DNS resolution for first domain
    if [ ''${#DOMAIN_ARRAY[@]} -gt 0 ]; then
      FIRST_DOMAIN="''${DOMAIN_ARRAY[0]}"
      FIRST_DOMAIN=$(echo "$FIRST_DOMAIN" | xargs)

      RESOLVED_IP=$(${pkgs.bind}/bin/dig @localhost "$FIRST_DOMAIN" +short 2>/dev/null | head -n1)

      if [ "$RESOLVED_IP" = "$PROXY_IP" ]; then
        echo "   ✓ DNS resolution test passed ($FIRST_DOMAIN -> $RESOLVED_IP)"
      else
        echo "   ⚠️  DNS resolution test failed (expected $PROXY_IP, got $RESOLVED_IP)"
      fi
    fi
    echo ""

    # ============================================================================
    # Monitor Services
    # ============================================================================
    echo "✅ All services started successfully!"
    echo "📊 Monitoring services (logs will appear below)..."
    echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
    echo ""

    # Monitor both processes and restart if either dies
    while true; do
      if ! kill -0 "$NGINX_PID" 2>/dev/null; then
        echo "❌ CRITICAL: nginx process died! Attempting restart..."
        ${pkgs.nginx}/bin/nginx -c "$NGINX_CONF" &
        NGINX_PID=$!
        sleep 2
        if ! kill -0 "$NGINX_PID" 2>/dev/null; then
          echo "❌ FATAL: nginx restart failed!"
          cleanup
          exit 1
        fi
        echo "✅ nginx restarted successfully"
      fi

      if ! kill -0 "$DNSMASQ_PID" 2>/dev/null; then
        echo "❌ CRITICAL: dnsmasq process died! Attempting restart..."
        ${pkgs.dnsmasq}/sbin/dnsmasq --no-daemon -C "$DNSMASQ_CONF" &
        DNSMASQ_PID=$!
        sleep 2
        if ! kill -0 "$DNSMASQ_PID" 2>/dev/null; then
          echo "❌ FATAL: dnsmasq restart failed!"
          cleanup
          exit 1
        fi
        echo "✅ dnsmasq restarted successfully"
      fi

      sleep 5
    done
  '';
in
{
  start = startScript;
}