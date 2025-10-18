{ pkgs, packages, configs, scripts }:

let
  setupScript = pkgs.writeShellScriptBin "setup-container" ''
    #!/bin/sh
    set -e
    
    echo "=== Container runtime setup ==="
    

    mkdir -p /var/log/nginx /var/log /run /var/cache/nginx /tmp
    

    touch /var/log/dnsmasq.log
    

    chmod 755 /var/log /var/log/nginx /run /var/empty
    chmod 644 /var/log/dnsmasq.log
    chmod 1777 /tmp
    chmod 755 /var/cache/nginx
    

    if getent passwd dnsproxy >/dev/null 2>&1; then
      echo "✓ dnsproxy user found"
      chown -R dnsproxy:dnsproxy /var/log/nginx /var/log/dnsmasq.log /var/cache/nginx 2>/dev/null || true
      echo "✓ Set ownership to dnsproxy user"
    else
      echo "⚠ dnsproxy user not found, running as root"
    fi
    
    echo "=== Setup complete ==="
  '';

  runtimeEnv = pkgs.buildEnv {
    name = "dns-proxy-runtime";
    paths = packages.runtime ++ [
      scripts.start
      setupScript
    ];
    pathsToLink = [ "/bin" "/sbin" ];
  };

  image = pkgs.dockerTools.buildLayeredImage {
    name = "dns-proxy-server";
    tag = "latest";

    contents = [ runtimeEnv ];

    extraCommands = ''
      mkdir -p etc/nginx
      mkdir -p var/log/nginx
      mkdir -p var/log
      mkdir -p run
      mkdir -p var/cache/nginx
      mkdir -p var/empty
      mkdir -p tmp
      
      chmod 1777 tmp
      chmod 755 var/log var/log/nginx run var/empty var/cache/nginx
      
      cp ${configs.nginx} etc/nginx/nginx.conf
      

      touch var/log/dnsmasq.log
      chmod 666 var/log/dnsmasq.log
      
      mkdir -p etc

      cat > etc/passwd << 'EOF'
root:x:0:0:root:/root:/bin/sh
nobody:x:65534:65534:Nobody:/:/bin/false
dnsproxy:x:999:999:DNS Proxy User:/var/empty:/bin/false
EOF

      cat > etc/group << 'EOF'
root:x:0:
nogroup:x:65534:
nobody:x:65534:
dnsproxy:x:999:
EOF

      cat > etc/shadow << 'EOF'
root:!:1::::::
nobody:!:1::::::
dnsproxy:!:1::::::
EOF

      cat > etc/gshadow << 'EOF'
root:!::
nogroup:!::
nobody:!::
dnsproxy:!::
EOF
      
      chmod 644 etc/passwd etc/group
      chmod 600 etc/shadow etc/gshadow
      

      chown -R 999:999 var/log/nginx var/cache/nginx || true
      chown 999:999 var/log/dnsmasq.log || true
    '';

    config = {
      Cmd = [ "${pkgs.bash}/bin/bash" "-c" "${setupScript}/bin/setup-container && exec ${scripts.start}/bin/start-proxy" ];

      ExposedPorts = {
        "53/tcp" = { };
        "53/udp" = { };
        "443/tcp" = { };
        "80/tcp" = { };
      };

      Env = [
        "DOMAINS=usher.ttvnw.net,gql.twitch.tv,chatgpt.com,gemini.google.com,grok.com"
        "PATH=/bin:/sbin:/usr/bin:/usr/sbin"
      ];

      Healthcheck = {
        Test = [ "CMD-SHELL" "${pkgs.curl}/bin/curl -f http://localhost:80/health || exit 1" ];
        Interval = 30000000000;
        Timeout = 10000000000;
        Retries = 3;
        StartPeriod = 10000000000;
      };

      WorkingDir = "/";

      Labels = {
        "org.opencontainers.image.title" = "DNS Proxy Server";
        "org.opencontainers.image.description" = "SNI proxy with custom DNS for bypassing geographic restrictions";
        "org.opencontainers.image.source" = "https://github.com/yourusername/dns-proxy-nix";
        "maintainer" = "your-email@example.com";
      };
    };

    maxLayers = 100;
  };

in
{
  inherit image;
}
