{ lib, ... }:

##
## Block outbound DNS-over-HTTPS (DoH) and DNS-over-TLS (DoT) to the
## major public resolvers commonly hard-coded into browsers and apps.
## With these endpoints unreachable, clients fall back to the system
## resolver (blocky on 127.0.0.1), so the local blocklists actually
## see those queries.
##
## Quad9 (9.9.9.9 / 149.112.112.112) is intentionally NOT blocked
## because blocky uses it as its upstream — see services/blocky.nix.
## If you change blocky's upstream, update the exemption here.
##

let
  # Public DoH/DoT endpoints to block. Each entry blocks both TCP/443 (DoH)
  # and TCP+UDP/853 (DoT, DoT-over-UDP). CIDR notation is accepted.
  endpointsV4 = [
    # Cloudflare (Firefox's default DoH provider)
    "1.1.1.1"
    "1.0.0.1"
    "1.1.1.2"
    "1.0.0.2"
    "1.1.1.3"
    "1.0.0.3"
    # Google Public DNS
    "8.8.8.8"
    "8.8.4.4"
    # OpenDNS / Cisco Umbrella
    "208.67.222.222"
    "208.67.220.220"
    # AdGuard DNS public
    "94.140.14.14"
    "94.140.15.15"
    # NextDNS anycast ranges (Firefox alternate provider)
    "45.90.28.0/24"
    "45.90.30.0/24"
  ];
  endpointsV6 = [
    "2606:4700:4700::1111"
    "2606:4700:4700::1001"
    "2001:4860:4860::8888"
    "2001:4860:4860::8844"
    "2620:119:35::35"
    "2620:119:53::53"
  ];

  mkReject4 = ip: ''
    iptables  -D OUTPUT -d ${ip} -p tcp --dport 443 -j REJECT 2>/dev/null || true
    iptables  -D OUTPUT -d ${ip} -p tcp --dport 853 -j REJECT 2>/dev/null || true
    iptables  -D OUTPUT -d ${ip} -p udp --dport 853 -j REJECT 2>/dev/null || true
    iptables  -A OUTPUT -d ${ip} -p tcp --dport 443 -j REJECT --reject-with icmp-net-unreachable
    iptables  -A OUTPUT -d ${ip} -p tcp --dport 853 -j REJECT --reject-with icmp-net-unreachable
    iptables  -A OUTPUT -d ${ip} -p udp --dport 853 -j REJECT --reject-with icmp-port-unreachable
  '';
  mkReject6 = ip: ''
    ip6tables -D OUTPUT -d ${ip} -p tcp --dport 443 -j REJECT 2>/dev/null || true
    ip6tables -D OUTPUT -d ${ip} -p tcp --dport 853 -j REJECT 2>/dev/null || true
    ip6tables -D OUTPUT -d ${ip} -p udp --dport 853 -j REJECT 2>/dev/null || true
    ip6tables -A OUTPUT -d ${ip} -p tcp --dport 443 -j REJECT --reject-with icmp6-addr-unreachable
    ip6tables -A OUTPUT -d ${ip} -p tcp --dport 853 -j REJECT --reject-with icmp6-addr-unreachable
    ip6tables -A OUTPUT -d ${ip} -p udp --dport 853 -j REJECT --reject-with icmp6-port-unreachable
  '';
  mkClean4 = ip: ''
    iptables  -D OUTPUT -d ${ip} -p tcp --dport 443 -j REJECT --reject-with icmp-net-unreachable 2>/dev/null || true
    iptables  -D OUTPUT -d ${ip} -p tcp --dport 853 -j REJECT --reject-with icmp-net-unreachable 2>/dev/null || true
    iptables  -D OUTPUT -d ${ip} -p udp --dport 853 -j REJECT --reject-with icmp-port-unreachable 2>/dev/null || true
  '';
  mkClean6 = ip: ''
    ip6tables -D OUTPUT -d ${ip} -p tcp --dport 443 -j REJECT --reject-with icmp6-addr-unreachable 2>/dev/null || true
    ip6tables -D OUTPUT -d ${ip} -p tcp --dport 853 -j REJECT --reject-with icmp6-addr-unreachable 2>/dev/null || true
    ip6tables -D OUTPUT -d ${ip} -p udp --dport 853 -j REJECT --reject-with icmp6-port-unreachable 2>/dev/null || true
  '';
in
{
  networking.firewall.extraCommands = ''
    ${lib.concatMapStrings mkReject4 endpointsV4}
    ${lib.concatMapStrings mkReject6 endpointsV6}
  '';

  networking.firewall.extraStopCommands = ''
    ${lib.concatMapStrings mkClean4 endpointsV4}
    ${lib.concatMapStrings mkClean6 endpointsV6}
  '';
}
