{ pkgs }:

let
  # Create a static nginx.conf file
  # The dnsmasq.conf will be generated dynamically by the startup script
  nginxConf = pkgs.writeText "nginx.conf" ''
    # Run nginx in foreground mode (required for Docker containers)
    daemon off;

    # Run as non-privileged user for security
    user dnsproxy;

    # Automatically determine optimal number of worker processes
    worker_processes auto;

    # PID file location
    pid /run/nginx.pid;

    # Error log configuration
    error_log /var/log/nginx/error.log warn;

    # Standard events block
    events {
        worker_connections 1024;
        use epoll;  # Efficient connection processing on Linux
    }

    # Stream block for SNI proxying (the main functionality)
    stream {
        # Custom log format showing SNI information
        log_format proxy '$remote_addr [$time_local] '
                         '$protocol $status $bytes_sent $bytes_received '
                         '$session_time "$ssl_preread_server_name"';

        access_log /var/log/nginx/stream-access.log proxy;
        error_log /var/log/nginx/stream-error.log warn;

        server {
            # Use Cloudflare's DNS resolver (disable IPv6 for simplicity)
            resolver 1.1.1.1 ipv6=off;

            # Listen on port 443 for HTTPS traffic
            listen 443;

            # Enable SSL preread to extract SNI without terminating SSL
            ssl_preread on;

            # Proxy to the server name from SNI on port 443
            proxy_pass $ssl_preread_server_name:443;

            # Connection timeout settings
            proxy_connect_timeout 10s;
            proxy_timeout 30s;

            # Enable TCP proxy protocol optimizations
            proxy_socket_keepalive on;
        }
    }

    # Minimal HTTP block for health checks
    http {
        # Basic MIME types
        default_type application/octet-stream;

        # Logging
        access_log /var/log/nginx/http-access.log;

        # Performance optimizations
        sendfile on;
        tcp_nopush on;
        tcp_nodelay on;
        keepalive_timeout 65;

        # Health check endpoint
        server {
            listen 80;
            server_name localhost;

            location /health {
                access_log off;
                return 200 'DNS Proxy Server is running\n';
                add_header Content-Type text/plain;
            }

            location / {
                return 200 'nginx SNI proxy component is active\n';
                add_header Content-Type text/plain;
            }
        }
    }
  '';

in
{
  # Expose the generated config file
  nginx = nginxConf;
}