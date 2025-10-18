{ pkgs, packages, configs, scripts }:

let
  image = pkgs.dockerTools.buildImage {
    name = "dns-proxy-server";
    tag = "latest";

    # Add all runtime packages to the container's Nix store
    contents = packages.runtime;

    # Configure the Docker image metadata and runtime behavior
    config = {
      # Set the default command to run when the container starts
      Cmd = [ "${scripts.start}/bin/start-proxy" ];

      # Expose the standard ports for DNS and the HTTPS proxy
      ExposedPorts = {
        "53/tcp" = { };
        "53/udp" = { };
        "443/tcp" = { };
        "80/tcp" = { };  # For health checks
      };

      # Set default environment variables (can be overridden with `docker run -e`)
      Env = [
        # PROXY_IP is intentionally not set - user MUST provide it
        "DOMAINS=usher.ttvnw.net,gql.twitch.tv,chatgpt.com,gemini.google.com,grok.com"
      ];

      # Health check configuration
      Healthcheck = {
        Test = [ "CMD-SHELL" "${pkgs.curl}/bin/curl -f http://localhost:80/health || exit 1" ];
        Interval = 30000000000; # 30 seconds in nanoseconds
        Timeout = 10000000000; # 10 seconds
        Retries = 3;
        StartPeriod = 10000000000; # 10 seconds grace period
      };

      # Working directory
      WorkingDir = "/";

      # Labels for metadata
      Labels = {
        "org.opencontainers.image.title" = "DNS Proxy Server";
        "org.opencontainers.image.description" = "SNI proxy with custom DNS for bypassing geographic restrictions";
        "org.opencontainers.image.source" = "https://github.com/yourusername/dns-proxy-nix";
        "maintainer" = "your-email@example.com";
      };
    };

    # Commands to set up the container filesystem during the image build
    runAsRoot = ''
      #!${pkgs.bash}/bin/bash
      set -e

      echo "Setting up container filesystem..."

      # Create a non-privileged user and group for security
      groupadd -r dnsproxy || true
      useradd -r -g dnsproxy -s /sbin/nologin -c "DNS Proxy User" dnsproxy || true

      # Create directory structure for logs, configs, and runtime files
      mkdir -p /etc/nginx
      mkdir -p /var/log/nginx
      mkdir -p /var/log
      mkdir -p /run
      mkdir -p /var/cache/nginx
      mkdir -p /tmp

      # Create log files
      touch /var/log/dnsmasq.log

      # Copy the static Nginx config from the Nix store into the image
      cp ${configs.nginx} /etc/nginx/nginx.conf

      # Set appropriate ownership and permissions
      chown -R dnsproxy:dnsproxy /var/log/nginx /var/log/dnsmasq.log /var/cache/nginx
      chmod 755 /var/log /var/log/nginx
      chmod 644 /var/log/dnsmasq.log
      chmod 755 /run
      chmod 1777 /tmp  # Sticky bit for tmp

      # Nginx needs to bind to privileged ports (53, 443)
      # Grant capabilities to nginx binary
      ${pkgs.libcap}/bin/setcap 'cap_net_bind_service=+ep' ${pkgs.nginx}/bin/nginx || true
      ${pkgs.libcap}/bin/setcap 'cap_net_bind_service=+ep' ${pkgs.dnsmasq}/sbin/dnsmasq || true

      echo "Container setup complete!"
    '';
  };

in
{
  # Expose the final image derivation
  inherit image;
}