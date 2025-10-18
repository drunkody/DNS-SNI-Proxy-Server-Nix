{ pkgs }:

{
  runtime = with pkgs; [
    bash        
    coreutils    
    nginx       
    dnsmasq      
    curl          
    bind          
    iproute2      
    procps        
    gnugrep       
    gawk
    findutils  
  ];
}