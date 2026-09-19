{ config, pkgs, ... }:

{

  ##
  ## Blocky ad blocker and DNS resolver
  ## See https://0xerr0r.github.io/blocky/latest/configuration/
  ##

  environment.systemPackages = with pkgs; [
    blocky
  ];

  services.blocky = {
    enable = true;
    settings = {
      # Localhost-only. systemd-resolved is the system stub
      # (127.0.0.53) and forwards all global queries here;
      # tailnet queries are routed by resolved to 100.100.100.100
      # via tailscale's split DNS. This host does not serve DNS
      # to the tailnet.
      ports = {
        dns = "127.0.0.1:53";
      };

      # Force outbound connections to IPv4 only. On hosts with broken or absent
      # IPv6 routing, DoH/list downloads silently fail when the upstream
      # resolves to an AAAA record and the connect attempt hits an unreachable
      # IPv6 route. Set to "dual" if a host has working IPv6.
      connectIPVersion = "v4";

      # Upstream DNS servers. Quad9 is used (not Cloudflare) so the
      # block-doh firewall module can blanket-block 1.1.1.1 / 8.8.8.8 / etc.
      # without breaking blocky's own egress. Quad9 also filters known
      # malicious domains at the resolver level (a free bonus on top of
      # blocky's blocklists).
      upstreams = {
        groups = {
          default = [
            "https://dns.quad9.net/dns-query"
          ];
        };
      };

      # Bootstrap DNS for resolving DoH/DoT upstream addresses
      bootstrapDns = [
        {
          upstream = "https://dns.quad9.net/dns-query";
          ips = [
            "9.9.9.9"
            "149.112.112.112"
          ];
        }
      ];

      # Ad, tracker, malware and phishing blocking.
      # HaGeZi Multi PRO is the curated combined list (ads + trackers + fake +
      # mobile telemetry + light malware); StevenBlack is a complementary
      # well-known hosts list; Phishing Army Extended is dedicated to phishing
      # domains. Together they score ~95%+ on adblock test pages.
      blocking = {
        # NXDOMAIN (not the default ZEROIP) so blocked queries report a
        # clean failed lookup. Required for Mozilla's DoH canary signal
        # via use-application-dns.net to work — Firefox treats NXDOMAIN
        # on that name as "DoH disabled by network policy" and falls back
        # to the system resolver (= blocky on 127.0.0.1).
        blockType = "NXDOMAIN";

        # The default 5-second download timeout truncates large blocklists
        # (HaGeZi pro.plus, StevenBlack, blocklistproject porn) mid-fetch,
        # causing blocky to load only a fraction of the entries. 60s is
        # plenty for multi-MB lists on a slow link.
        loading.downloads.timeout = "60s";
        loading.downloads.attempts = 5;

        denylists = {
          ads = [
            "https://raw.githubusercontent.com/hagezi/dns-blocklists/main/hosts/pro.plus.txt"
            "https://raw.githubusercontent.com/StevenBlack/hosts/master/hosts"
          ];
          phishing = [
            "https://phishing.army/download/phishing_army_blocklist_extended.txt"
          ];
          adult = [ "https://blocklistproject.github.io/Lists/porn.txt" ];
          # Firefox DoH canary — Mozilla's documented opt-out signal.
          # Returning NXDOMAIN for this name makes Firefox disable its
          # default Cloudflare DoH and use the system resolver instead.
          # Inline (block scalar) so blocky treats it as content, not a URL.
          doh-canary = [
            ''
              use-application-dns.net
            ''
          ];
        };
        clientGroupsBlock = {
          default = [
            "ads"
            "phishing"
            "doh-canary"
          ];
          kids-ipad = [
            "ads"
            "phishing"
            "adult"
            "doh-canary"
          ];
        };
      };
    };
  };

  # systemd-resolved is the local stub on 127.0.0.53. It routes
  # all global lookups (Domains=~.) to blocky at 127.0.0.1 so
  # blocklists stay in the path, while tailscale registers
  # ~<tailnet>.ts.net (and any Split-DNS domains) plus the search
  # domain against tailscale0 — those take precedence over ~.
  # for tailnet queries, so short names + MagicDNS resolve without
  # bypassing blocky for anything else.
  services.resolved = {
    enable = true;
    settings.Resolve = {
      DNS = "127.0.0.1";
      Domains = "~.";
    };
  };
  networking.networkmanager.dns = "systemd-resolved";

  # Let tailscale push its DNS config into resolved.
  services.tailscale.extraUpFlags = [ "--accept-dns=true" ];

  # A corporate/site-to-site VPN that registers its own DNS with a routing
  # domain of `~.` (all queries) will displace blocky as the global resolver
  # and silently kill ad-blocking. If a deployment adds one, scope its
  # routing domain down to just that VPN's internal suffix with a
  # NetworkManager dispatcher script (fires after NM finishes setting up DNS
  # for the connection, so there's no race).
}
