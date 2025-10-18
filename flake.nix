{
  description = "A Nix flake for building a DNS proxy server container";

  inputs = {
    nixpkgs.url = "github:NixOS/nixpkgs/nixos-unstable";
    flake-utils.url = "github:numtide/flake-utils";
  };

  outputs = { self, nixpkgs, flake-utils }:
    flake-utils.lib.eachDefaultSystem (system:
      let
        pkgs = nixpkgs.legacyPackages.${system};

        # Import modules that define the build logic
        packages = import ./modules/packages.nix { inherit pkgs; };
        configs = import ./modules/configs.nix { inherit pkgs; };
        scripts = import ./modules/scripts.nix { inherit pkgs; };
        docker = import ./modules/docker.nix { inherit pkgs packages configs scripts; };
      in
      {
        # The primary output is the Docker image
        packages = {
          dockerImage = docker.image;
          default = docker.image; # Alias for convenience
        };

        # A development shell with tools for testing and building
        devShells.default = pkgs.mkShell {
          buildInputs = [
            pkgs.docker
            pkgs.dig
            pkgs.curl
          ];

          shellHook = ''
            echo "╔═══════════════════════════════════════════════════════╗"
            echo "║   DNS Proxy Development Environment                   ║"
            echo "╚═══════════════════════════════════════════════════════╝"
            echo ""
            echo "📦 Build the Docker image:"
            echo "   nix build .#dockerImage"
            echo ""
            echo "🚀 Load the image into Docker:"
            echo "   docker load < result"
            echo ""
            echo "🏃 Run the container:"
            echo "   docker run -d --name dns-proxy \\"
            echo "     -p 53:53/udp \\"
            echo "     -p 443:443 \\"
            echo "     -e PROXY_IP=\"\$(curl -s ifconfig.me)\" \\"
            echo "     -e DOMAINS=\"usher.ttvnw.net,gql.twitch.tv,chatgpt.com\" \\"
            echo "     dns-proxy-server:latest"
            echo ""
            echo "⚠️  IMPORTANT: Replace PROXY_IP with your actual VPS IP!"
            echo ""
            echo "🧪 Test DNS resolution:"
            echo "   dig @localhost usher.ttvnw.net +short"
            echo "   docker exec dns-proxy dig @localhost usher.ttvnw.net +short"
            echo ""
            echo "🔍 Check container health:"
            echo "   docker logs dns-proxy"
            echo "   docker exec dns-proxy ps aux"
            echo ""
            echo "🛑 Stop and remove:"
            echo "   docker stop dns-proxy && docker rm dns-proxy"
            echo ""
            echo "⚡ Quick test (after build):"
            echo "   docker load < result && \\"
            echo "   docker run --rm -e PROXY_IP=\"1.2.3.4\" dns-proxy-server:latest"
            echo ""
          '';
        };

        # A runnable app for testing the start script locally
        apps.default = {
          type = "app";
          program = "${scripts.start}/bin/start-proxy";
        };

        # Standard Nix code formatter
        formatter = pkgs.nixpkgs-fmt;
      }
    );
}