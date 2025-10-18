{ pkgs }:

{
  # Packages required inside the container at runtime
  runtime = with pkgs; [
    bash          # For the startup script
    coreutils     # For basic shell utilities (cat, echo, mkdir, etc.)
    nginx         # The SNI proxy server
    dnsmasq       # The DNS server
    curl          # For health checks and debugging
    bind          # Provides 'dig' for DNS testing
    iproute2      # Network utilities (ip, ss)
    procps        # Process monitoring (ps, top, kill)
    gnugrep       # For log parsing
    gawk          # For text processing
  ];
}