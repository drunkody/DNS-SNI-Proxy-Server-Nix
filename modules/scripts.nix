{ pkgs }:

let
  startScript = pkgs.writeScriptBin "start-proxy" ''
    #!${pkgs.bash}/bin/bash
    set -euo pipefail

    : ''${PROXY_IP:?"ERROR: PROXY_IP environment variable must be set. Example: export PROXY_IP=\"1.2.3.4\""}
    : ''${DOMAINS:="usher.ttvnw.net,gql.twitch.tv,chatgpt.com,gemini.google.com,grok.com"}

    echo ""
    echo "📡 Proxy Server IP: $PROXY_IP"
    echo "🌐 Domains to Proxy: $DOMAINS"
    echo ""

    DNSMASQ_CONF="/etc/dnsmasq.conf"
    NGINX_CONF="/etc/nginx/nginx.conf"
    DNSMASQ_LOG="/var/log/dnsmasq.log"

    echo "⚙️  Generating dnsmasq configuration..."


    DNSMASQ_USER="root"
    if getent passwd dnsproxy >/dev/null 2>&1; then
      DNSMASQ_USER="dnsproxy"
    fi

    cat > "$DNSMASQ_CONF" <<EOF
listen-address=0.0.0.0
port=53

user=$DNSMASQ_USER
group=$DNSMASQ_USER

no-resolv
no-hosts

server=1.1.1.1
server=1.0.0.1

cache-size=10000

log-queries
log-facility=$DNSMASQ_LOG

bogus-priv
bind-interfaces
domain-needed
no-poll
EOF

    echo "📝 Adding domain routing rules..."
    IFS=',' read -ra DOMAIN_ARRAY <<< "$DOMAINS"
    for domain in "''${DOMAIN_ARRAY[@]}"; do
      domain=$(echo "$domain" | xargs)
      if [ -n "$domain" ]; then
        echo "   → $domain -> $PROXY_IP"
        echo "address=/$domain/$PROXY_IP" >> "$DNSMASQ_CONF"
      fi
    done
    echo ""

    echo "🔍 Validating configurations..."

    if ! dnsmasq --test -C "$DNSMASQ_CONF"; then
      echo "❌ ERROR: dnsmasq configuration is invalid!"
      echo "Configuration file contents:"
      cat -n "$DNSMASQ_CONF"
      exit 1
    fi
    echo "✓ dnsmasq configuration is valid"

    if ! nginx -t -c "$NGINX_CONF" 2>&1 | grep -q "successful"; then
      echo "❌ ERROR: nginx configuration is invalid!"
      nginx -t -c "$NGINX_CONF"
      exit 1
    fi
    echo "✓ nginx configuration is valid"
    echo ""

    NGINX_PID=""
    DNSMASQ_PID=""

    cleanup() {
      echo ""
      echo "🛑 Shutting down services gracefully..."

      if [ -n "$NGINX_PID" ]; then
        echo "   Stopping nginx (PID: $NGINX_PID)..."
        nginx -s quit 2>/dev/null || kill "$NGINX_PID" 2>/dev/null || true
      fi

      if [ -n "$DNSMASQ_PID" ]; then
        echo "   Stopping dnsmasq (PID: $DNSMASQ_PID)..."
        kill -TERM "$DNSMASQ_PID" 2>/dev/null || true
      fi

      echo "✅ Shutdown complete"
      exit 0
    }

    trap cleanup SIGTERM SIGINT SIGQUIT

    echo "🚀 Starting nginx..."
    nginx -c "$NGINX_CONF" &
    NGINX_PID=$!

    sleep 1

    if ! kill -0 "$NGINX_PID" 2>/dev/null; then
      echo "❌ ERROR: nginx failed to start!"
      cat /var/log/nginx/error.log 2>/dev/null || true
      exit 1
    fi
    echo "✓ nginx started successfully (PID: $NGINX_PID)"

    echo "🚀 Starting dnsmasq..."
    dnsmasq --no-daemon -C "$DNSMASQ_CONF" &
    DNSMASQ_PID=$!

    sleep 1

    if ! kill -0 "$DNSMASQ_PID" 2>/dev/null; then
      echo "❌ ERROR: dnsmasq failed to start!"
      cat "$DNSMASQ_LOG" 2>/dev/null || true
      exit 1
    fi
    echo "✓ dnsmasq started successfully (PID: $DNSMASQ_PID)"
    echo ""

    echo "🧪 Running self-tests..."
    sleep 2

    if curl -sf http://localhost:80/health > /dev/null; then
      echo "✓ nginx health check passed"
    else
      echo "⚠️  nginx health check failed (non-critical)"
    fi

    if [ ''${#DOMAIN_ARRAY[@]} -gt 0 ]; then
      FIRST_DOMAIN="''${DOMAIN_ARRAY[0]}"
      FIRST_DOMAIN=$(echo "$FIRST_DOMAIN" | xargs)

      RESOLVED_IP=$(dig @localhost "$FIRST_DOMAIN" +short 2>/dev/null | head -n1)

      if [ "$RESOLVED_IP" = "$PROXY_IP" ]; then
        echo "✓ DNS resolution test passed ($FIRST_DOMAIN -> $RESOLVED_IP)"
      else
        echo "⚠️  DNS resolution test failed (expected $PROXY_IP, got $RESOLVED_IP)"
      fi
    fi
    echo ""

    echo "✅ All services started successfully!"
    echo "📊 Monitoring services (logs will appear below)..."
    echo ""

    while true; do
      if ! kill -0 "$NGINX_PID" 2>/dev/null; then
        echo "⚠️  CRITICAL: nginx process died! Attempting restart..."
        nginx -c "$NGINX_CONF" &
        NGINX_PID=$!
        sleep 2
        if ! kill -0 "$NGINX_PID" 2>/dev/null; then
          echo "❌ FATAL: nginx restart failed!"
          cleanup
          exit 1
        fi
        echo "✓ nginx restarted successfully"
      fi

      if ! kill -0 "$DNSMASQ_PID" 2>/dev/null; then
        echo "⚠️  CRITICAL: dnsmasq process died! Attempting restart..."
        dnsmasq --no-daemon -C "$DNSMASQ_CONF" &
        DNSMASQ_PID=$!
        sleep 2
        if ! kill -0 "$DNSMASQ_PID" 2>/dev/null; then
          echo "❌ FATAL: dnsmasq restart failed!"
          cleanup
          exit 1
        fi
        echo "✓ dnsmasq restarted successfully"
      fi

      sleep 5
    done
  '';
in
{
  start = startScript;
}
