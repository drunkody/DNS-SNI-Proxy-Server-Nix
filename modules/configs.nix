{ pkgs }:

let
  nginxConf = pkgs.writeText "nginx.conf" ''
    daemon off;
    worker_processes auto;
    pid /run/nginx.pid;
    error_log /var/log/nginx/error.log warn;

    events {
        worker_connections 1024;
        use epoll;
    }

    stream {
        log_format proxy '$remote_addr [$time_local] '
                         '$protocol $status $bytes_sent $bytes_received '
                         '$session_time "$ssl_preread_server_name"';

        access_log /var/log/nginx/stream-access.log proxy;
        error_log /var/log/nginx/stream-error.log warn;

        server {
            resolver 1.1.1.1 ipv6=off;
            listen 443;
            ssl_preread on;
            proxy_pass $ssl_preread_server_name:443;
            proxy_connect_timeout 10s;
            proxy_timeout 30s;
            proxy_socket_keepalive on;
        }
    }

    http {
        default_type application/octet-stream;
        access_log /var/log/nginx/http-access.log;
        sendfile on;
        tcp_nopush on;
        tcp_nodelay on;
        keepalive_timeout 65;

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
  nginx = nginxConf;
}
