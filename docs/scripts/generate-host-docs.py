#!/usr/bin/env python3
"""Generate per-host mkdocs pages from the flake.

For each host registered in `.#all-hosts`, this script runs `nix eval --json`
against the host's evaluated NixOS configuration to extract:

  - hostname, domain, time zone
  - system architecture
  - kernel version, bootloader
  - open firewall ports (TCP, UDP, ranges)
  - installed packages (names only)
  - enabled services (every `services.*.enable = true`)
  - desktop environment / display manager
  - non-system users

…and writes the result to `docs/hosts/<host>.md`. Re-running the script
overwrites those files; everything else under `docs/` is left alone.

Designed to be invoked via `nix run .#docs-generate-hosts`.
"""
from __future__ import annotations

import hashlib
import json
import os
import re
import shutil
import subprocess
import sys
from pathlib import Path
from typing import Any

sys.path.insert(0, str(Path(__file__).resolve().parent))
import diagram  # noqa: E402  (local module, needs the sys.path line above)

REPO_ROOT = Path(__file__).resolve().parent.parent.parent
HOSTS_DIR = REPO_ROOT / "docs" / "hosts"

# Footer credit lives in mkdocs.yml `copyright:` (rendered site-wide by
# Material's footer), so generated pages don't repeat it inline.

# --- Package categorisation -----------------------------------------------
#
# Map well-known package names to a human-readable category. The category
# string is rendered verbatim as a section heading on each host page.
# Anything not matched here falls through to PACKAGE_PREFIX_RULES, then
# finally to "Uncategorised". This is intentionally not exhaustive — extend
# as new packages enter the fleet.
# Package categorisation lives in taxonomy.py, which derives categories from
# where the flake actually declares each package. This module used to carry a
# ~200-line hand-maintained keyword table instead; it had drifted to the point
# of having buckets for KDE, GNOME and XFCE — none of which this fleet runs —
# and none for services/ or locale/, which it does.
from taxonomy import categorise_packages, category_note  # noqa: E402


NIX_FLAGS = [
    "--extra-experimental-features", "nix-command",
    "--extra-experimental-features", "flakes",
    "--accept-flake-config",
]

def nix_eval(attr: str, apply: str | None = None, optional: bool = False) -> Any:
    """Evaluate a flake attribute and return the parsed JSON.

    Returns None if the attribute is missing (always silent for that case).
    If `optional=True`, also returns None on any other eval error — used
    when probing options that may not exist or that may abort due to broken
    `mkRenamedOptionModule` definitions in nixpkgs (which `tryEval` cannot
    catch since they use `builtins.abort`).
    """
    cmd = ["nix", *NIX_FLAGS, "eval", "--json", attr]
    if apply is not None:
        cmd += ["--apply", apply]
    try:
        out = subprocess.run(
            cmd, cwd=REPO_ROOT, check=True, capture_output=True, text=True,
        )
    except subprocess.CalledProcessError as e:
        if "does not provide attribute" in e.stderr or (
            "attribute" in e.stderr and "missing" in e.stderr
        ):
            return None
        if optional:
            return None
        sys.stderr.write(e.stderr)
        raise
    return json.loads(out.stdout)


def get_hosts() -> list[str]:
    hosts = nix_eval(".#all-hosts")
    if not isinstance(hosts, list):
        raise RuntimeError(f"Unexpected shape for .#all-hosts: {hosts!r}")
    return sorted(hosts)


def host_attr(host: str, path: str) -> str:
    return f".#nixosConfigurations.{host}.config.{path}"


def load_catalogue() -> dict[str, dict[str, Any]]:
    """Per-package metadata (description, homepage, version) from
    docs/references/software.json — the artefact generate-software-catalogue.py
    writes, which regenerateDocs (flake.nix) runs BEFORE this script so the
    lookups here are fresh. Missing or unreadable = empty: the host pages
    then render with "—" descriptions rather than failing the docs build."""
    try:
        return json.loads((REPO_ROOT / "docs" / "references" / "software.json").read_text())
    except (FileNotFoundError, json.JSONDecodeError):
        return {}


def escape_cell(text: str) -> str:
    """Make a string safe inside a markdown table cell (same contract as the
    catalogue's escape_cell; that script imports THIS module via importlib —
    see its _load_host_docs — so shared helpers belong here, not there)."""
    return text.replace("|", "\\|").replace("\n", " ").strip()


def fmt_table(headers: list[str], rows: list[list[str]]) -> str:
    # Avoid bare emphasis on its own line (trips markdownlint MD036).
    if not rows:
        return "None.\n"
    sep = "| " + " | ".join(headers) + " |\n"
    sep += "| " + " | ".join("---" for _ in headers) + " |\n"
    for row in rows:
        sep += "| " + " | ".join(row) + " |\n"
    return sep


def fmt_inline_list(items: list[str]) -> str:
    if not items:
        return "None."
    return ", ".join(f"`{x}`" for x in items)


#: Where a host's evaluated facts are kept between runs. Gitignored: it is
#: derived data, and a stale entry is worse than no entry.
CACHE_DIR = REPO_ROOT / ".cache" / "docs-host-facts"

#: Bumped when the SHAPE of the facts changes. Without it, a generator that
#: learns to collect a new field would keep reading old entries that do not
#: have it, and the pages would silently lose a section.
# v2: facts gained serviceDescriptions (and the services eval changed
# shape) — old cache entries would render every service as "—".
CACHE_VERSION = 2

#: Directories whose contents can change what a host evaluates to. A host's
#: own directory is added per host, so editing hosts/atoll/ does not throw
#: away the other eight entries.
SHARED_INPUTS = (
    "flake.nix",
    "flake.lock",
    "config.nix",
    "software",
    "profiles",
    "users",
    "modules",
    "lib",
    "overlays",
)


def _cache_key(host: str) -> str:
    """A hash of everything that could change this host's evaluation.

    Deliberately coarse. Knowing exactly which files nix reads would require
    evaluating, which is the thing being avoided — so this hashes every input
    that plausibly matters and accepts that an unrelated edit under software/
    costs a re-evaluation. It is still the difference between minutes and
    nothing on the common case of running the docs twice.
    """
    digest = hashlib.sha256()
    digest.update(f"v{CACHE_VERSION}\n".encode())

    paths: list[Path] = []
    for entry in (*SHARED_INPUTS, f"hosts/{host}"):
        target = REPO_ROOT / entry
        if target.is_dir():
            paths += sorted(target.rglob("*.nix"))
            paths += sorted(target.rglob("*.json"))
        elif target.is_file():
            paths.append(target)

    for path in sorted(paths):
        digest.update(str(path.relative_to(REPO_ROOT)).encode())
        try:
            digest.update(path.read_bytes())
        except OSError:
            digest.update(b"<unreadable>")
    return digest.hexdigest()[:32]


def collect_host_facts(host: str) -> dict[str, Any]:
    """Every fact one host page needs, from cache when the inputs are unchanged.

    A page costs roughly two dozen `nix eval` invocations, each a cold start
    of the whole module system. Nine hosts is a couple of hundred, which is
    why a docs build took minutes even when nothing had changed.
    """
    if os.environ.get("DOCS_NO_CACHE"):
        return _collect_host_facts_uncached(host)

    key = _cache_key(host)
    entry = CACHE_DIR / f"{host}-{key}.json"
    if entry.exists():
        try:
            facts = json.loads(entry.read_text())
            print(f"    {host}: cached", file=sys.stderr)
            return facts
        except ValueError:
            entry.unlink(missing_ok=True)

    facts = _collect_host_facts_uncached(host)

    CACHE_DIR.mkdir(parents=True, exist_ok=True)
    # Drop this host's older entries: they can never be hit again, and a
    # cache that only grows is a cache nobody trusts.
    for stale in CACHE_DIR.glob(f"{host}-*.json"):
        stale.unlink(missing_ok=True)
    entry.write_text(json.dumps(facts, indent=1, sort_keys=True))
    return facts


def _collect_host_facts_uncached(host: str) -> dict[str, Any]:
    """Run every nix eval needed for one host page."""
    facts: dict[str, Any] = {"host": host}

    # Identity
    facts["hostName"] = nix_eval(host_attr(host, "networking.hostName")) or host
    facts["domain"] = nix_eval(host_attr(host, "networking.domain"))
    facts["system"] = nix_eval(host_attr(host, "nixpkgs.hostPlatform.system"))
    facts["timeZone"] = nix_eval(host_attr(host, "time.timeZone"))

    # Kernel
    facts["kernelVersion"] = nix_eval(
        host_attr(host, "boot.kernelPackages.kernel.version")
    )

    # Bootloader
    if nix_eval(host_attr(host, "boot.loader.systemd-boot.enable")):
        facts["bootloader"] = "systemd-boot"
    elif nix_eval(host_attr(host, "boot.loader.grub.enable")):
        facts["bootloader"] = "GRUB"
    else:
        facts["bootloader"] = "(unspecified)"

    # Firewall
    facts["firewallEnabled"] = nix_eval(
        host_attr(host, "networking.firewall.enable")
    )
    facts["tcpPorts"] = nix_eval(
        host_attr(host, "networking.firewall.allowedTCPPorts")
    ) or []
    facts["udpPorts"] = nix_eval(
        host_attr(host, "networking.firewall.allowedUDPPorts")
    ) or []
    facts["tcpRanges"] = nix_eval(
        host_attr(host, "networking.firewall.allowedTCPPortRanges")
    ) or []
    facts["udpRanges"] = nix_eval(
        host_attr(host, "networking.firewall.allowedUDPPortRanges")
    ) or []

    # System packages — names only, deduplicated, sorted. tryEval guards
    # against entries that aren't conventional derivations (paths, wrapped
    # derivations missing pname/name, etc.) so one weird package doesn't
    # break the whole list.
    packages = nix_eval(
        host_attr(host, "environment.systemPackages"),
        apply=(
            "ps: builtins.map (p: "
            "  let r = builtins.tryEval ("
            "    if builtins.isAttrs p then (p.pname or p.name or \"unknown\")"
            "    else builtins.toString p"
            "  ); in if r.success then r.value else \"unknown\""
            ") ps"
        ),
    ) or []
    facts["packages"] = sorted(set(packages))

    # Services that start at boot — taken from `systemd.services` (the merged
    # unit list systemd will actually run) rather than `services.*.enable`.
    # Two reasons:
    #   1. systemd.services has ~30–100 entries per host; services.* has ~600,
    #      so this is one eval per host instead of hundreds.
    #   2. nixpkgs ships several broken `mkRenamedOptionModule` entries under
    #      services.* (e.g. services.frp → services.frp.instances) that
    #      `builtins.abort` when touched. `tryEval` can't catch `abort`, so
    #      iterating services.* atomically loses the whole list to one bad
    #      entry. systemd.services has no such issue.
    # Name AND unit description in one pass, so the report can say what
    # each service is for (same idea as the package descriptions, but the
    # source here is the unit's own Description= — nixpkgs modules set it
    # on nearly everything).
    enabled = nix_eval(
        host_attr(host, "systemd.services"),
        apply=(
            "svcs: builtins.concatMap (n: "
            "  let r = builtins.tryEval ("
            "    let s = svcs.${n}; wb = s.wantedBy or []; in "
            "    if builtins.any (t: t == \"multi-user.target\" "
            "                       || t == \"default.target\""
            "                       || t == \"graphical.target\") wb "
            "    then [ { name = n; description = s.description or \"\"; } ] "
            "    else [ ]"
            "  ); in if r.success then r.value else [ ]"
            ") (builtins.attrNames svcs)"
        ),
    ) or []
    facts["services"] = sorted(e["name"] for e in enabled)
    facts["serviceDescriptions"] = {e["name"]: e["description"] for e in enabled}

    # Systemd timers that are wanted at boot — useful for scheduled jobs.
    timers = nix_eval(
        host_attr(host, "systemd.timers"),
        apply=(
            "ts: builtins.filter (n: "
            "  let r = builtins.tryEval ("
            "    let wb = ts.${n}.wantedBy or []; in "
            "    builtins.any (t: t == \"timers.target\") wb"
            "  ); in r.success && r.value"
            ") (builtins.attrNames ts)"
        ),
    ) or []
    facts["timers"] = sorted(timers)

    # Desktop environment / display manager
    de_candidates = [
        ("COSMIC", "services.desktopManager.cosmic.enable"),
        ("KDE Plasma 6", "services.desktopManager.plasma6.enable"),
        ("GNOME", "services.xserver.desktopManager.gnome.enable"),
        ("Pantheon", "services.xserver.desktopManager.pantheon.enable"),
        ("XFCE", "services.xserver.desktopManager.xfce.enable"),
        ("Cinnamon", "services.xserver.desktopManager.cinnamon.enable"),
        ("MATE", "services.xserver.desktopManager.mate.enable"),
        ("Sway", "programs.sway.enable"),
        ("Hyprland", "programs.hyprland.enable"),
    ]
    facts["desktops"] = [
        name for name, path in de_candidates if nix_eval(host_attr(host, path))
    ]

    dm_candidates = [
        ("cosmic-greeter", "services.displayManager.cosmic-greeter.enable"),
        ("SDDM", "services.displayManager.sddm.enable"),
        ("GDM", "services.xserver.displayManager.gdm.enable"),
        ("LightDM", "services.xserver.displayManager.lightdm.enable"),
        ("greetd", "services.greetd.enable"),
    ]
    facts["displayManagers"] = [
        name for name, path in dm_candidates if nix_eval(host_attr(host, path))
    ]

    # Users — keep only normal (human) users. Done in one nix eval so we
    # don't pay per-user round-trip cost.
    real_users = nix_eval(
        host_attr(host, "users.users"),
        apply=(
            "us: builtins.map (n: "
            "  let u = us.${n}; in {"
            "    name = n;"
            "    uid = if u ? uid && u.uid != null then u.uid else 0;"
            "    description = if u ? description then u.description else \"\";"
            "    shell = if u ? shell && u.shell != null && u.shell ? executable"
            "            then u.shell.executable else \"\";"
            "  }"
            ") (builtins.filter (n:"
            "  let r = builtins.tryEval ("
            "    us.${n} ? isNormalUser && us.${n}.isNormalUser == true"
            "  ); in r.success && r.value"
            ") (builtins.attrNames us))"
        ),
    ) or []
    facts["users"] = real_users

    # Misc highlight flags
    facts["tailscale"] = nix_eval(host_attr(host, "services.tailscale.enable")) is True
    facts["zfs"] = nix_eval(host_attr(host, "boot.supportedFilesystems")) or []
    facts["sshd"] = nix_eval(host_attr(host, "services.openssh.enable")) is True

    # Storage topology — declared filesystems plus any additionally
    # imported ZFS pools. One nix eval for the filesystems table.
    facts["fileSystems"] = nix_eval(
        host_attr(host, "fileSystems"),
        apply=(
            "fss: builtins.map (m: {"
            "  mountpoint = m;"
            "  device = if fss.${m} ? device && fss.${m}.device != null"
            "           then fss.${m}.device else \"\";"
            "  fsType = if fss.${m} ? fsType then fss.${m}.fsType else \"\";"
            "}) (builtins.attrNames fss)"
        ),
        optional=True,
    ) or []
    facts["extraPools"] = nix_eval(
        host_attr(host, "boot.zfs.extraPools"), optional=True
    ) or []
    facts["zpools"] = sorted(
        {
            fs["device"].split("/")[0]
            for fs in facts["fileSystems"]
            if fs["fsType"] == "zfs" and fs["device"] and not fs["device"].startswith("/")
        }
        | set(facts["extraPools"])
    )

    return facts


# --- Mermaid diagram renderers --------------------------------------------

def render_network_diagram(facts: dict[str, Any]) -> str:
    """Mermaid diagram showing how this host connects to the outside world.

    Edges are derived from firewall rules (inbound from Internet), the
    Tailscale flag (mesh peering), and the global assumption that outbound
    traffic is unrestricted.
    """
    h = facts["host"]
    tcp = facts["tcpPorts"]
    udp = facts["udpPorts"]
    has_inbound = bool(tcp or udp or facts["tcpRanges"] or facts["udpRanges"])
    tailscale = facts["tailscale"]
    sshd = facts["sshd"]

    lines = ["graph LR"]
    # Mermaid 10 only interprets **bold** inside labels when the label is
    # wrapped in backticks (markdown strings). Plain text is safer for
    # cross-renderer compatibility.
    lines.append(f'    HOST["{h}<br/>{facts.get("system") or "x86_64-linux"}"]')

    if has_inbound:
        port_summary_parts = []
        if tcp:
            port_summary_parts.append(f"TCP: {', '.join(str(p) for p in tcp)}")
        if udp:
            port_summary_parts.append(f"UDP: {', '.join(str(p) for p in udp)}")
        if facts["tcpRanges"]:
            port_summary_parts.append(
                "TCP ranges: " + ", ".join(
                    f"{r.get('from')}–{r.get('to')}" for r in facts["tcpRanges"]
                )
            )
        port_summary = "<br/>".join(port_summary_parts) or "open"
        lines.append('    INET[("Internet")]')
        lines.append(f'    INET -- "{port_summary}" --> HOST')
    else:
        lines.append('    INET[("Internet")]')
        lines.append('    INET -. "no inbound ports" .- HOST')

    lines.append('    HOST -- outbound --> INET')

    if tailscale:
        lines.append('    TS{{"Tailscale mesh"}}')
        lines.append('    HOST <==> TS')
        lines.append('    OTHER["Other Kartoza hosts"]')
        lines.append('    TS <==> OTHER')
        if sshd:
            lines.append('    TS -- "ssh:22" --> HOST')

    # Styling — Kartoza palette (blue primary, amber highlight, charcoal text).
    # Match docs/stylesheets/kartoza-tokens.css.
    lines.append('    classDef host fill:#FCF3E0,stroke:#DF9E2F,stroke-width:2px,color:#383939')
    lines.append('    classDef inet fill:#F5F5F2,stroke:#8A8B8B,color:#383939')
    lines.append('    classDef mesh fill:#EAF3F8,stroke:#569FC6,stroke-width:2px,color:#383939')
    lines.append('    classDef other fill:#F5F5F2,stroke:#D1D1D1,color:#383939')
    lines.append('    class HOST host')
    lines.append('    class INET inet')
    if tailscale:
        lines.append('    class TS mesh')
        lines.append('    class OTHER other')

    return diagram.render(
        "\n".join(lines),
        slug=f"host-{h}-network",
        alt=f"{h} network exposure",
    )


def render_deployment_diagram(facts: dict[str, Any]) -> str:
    """Mermaid diagram showing the software stack on this host (UML-ish)."""
    h = facts["host"]
    arch = facts.get("system") or "x86_64-linux"
    kernel = facts.get("kernelVersion") or "unknown"
    bootloader = facts.get("bootloader", "")
    desktops = facts.get("desktops") or []
    dms = facts.get("displayManagers") or []
    services_count = len(facts.get("services") or [])
    timers_count = len(facts.get("timers") or [])
    packages_count = len(facts.get("packages") or [])

    has_desktop = bool(desktops)

    lines = ["graph TD"]
    # No backticks inside labels — Mermaid 10 treats them as the start of a
    # markdown-string literal, which trips the parser if the closing tick
    # isn't where it expects.
    lines.append(f'    HW["Hardware<br/>{arch}"]')
    lines.append(f'    BOOT["Bootloader<br/>{bootloader}"]')
    lines.append(f'    KERN["Linux kernel<br/>{kernel}"]')
    lines.append(f'    SD["systemd<br/>{services_count} services, {timers_count} timers"]')
    lines.append(f'    HW --> BOOT --> KERN --> SD')

    if has_desktop:
        lines.append(f'    DM["Display manager<br/>{", ".join(dms) if dms else "none"}"]')
        lines.append(f'    DE["Desktop env<br/>{", ".join(desktops)}"]')
        lines.append(f'    APPS["Applications<br/>{packages_count} packages"]')
        lines.append('    SD --> DM --> DE --> APPS')
    else:
        lines.append(f'    SVC["Services<br/>{packages_count} declared packages"]')
        lines.append('    SD --> SVC')

    # Style — Kartoza palette: cloud surfaces, blue/amber accents on charcoal.
    lines.append('    classDef hw fill:#F5F5F2,stroke:#8A8B8B,color:#383939')
    lines.append('    classDef sys fill:#EAF3F8,stroke:#569FC6,color:#383939')
    lines.append('    classDef de fill:#FCF3E0,stroke:#DF9E2F,color:#383939')
    lines.append('    class HW,BOOT hw')
    lines.append('    class KERN,SD sys')
    if has_desktop:
        lines.append('    class DM,DE,APPS de')
    else:
        lines.append('    class SVC sys')

    return diagram.render(
        "\n".join(lines),
        slug=f"host-{h}-deployment",
        alt=f"{h} module composition",
    )


def render_fleet_diagram(all_facts: dict[str, dict[str, Any]]) -> str:
    """Fleet-wide mermaid diagram for the hosts index page.

    Shows every host as a node, partitioned into 'server' vs 'desktop' by
    presence of a desktop environment, connected via the Tailscale mesh,
    with Internet edges drawn to any host with inbound firewall ports.
    """
    lines = ["graph LR"]
    lines.append('    INET[("Internet")]')
    lines.append('    TS{{"Tailscale mesh"}}')

    servers: list[str] = []
    desktops: list[str] = []
    public: list[str] = []

    for host, f in sorted(all_facts.items()):
        node_id = host.replace("-", "_")
        is_desktop = bool(f.get("desktops"))
        (desktops if is_desktop else servers).append(node_id)
        lines.append(f'    {node_id}["{host}"]')
        if f.get("tailscale"):
            lines.append(f'    {node_id} <--> TS')
        has_inbound = (
            bool(f.get("tcpPorts")) or bool(f.get("udpPorts"))
            or bool(f.get("tcpRanges")) or bool(f.get("udpRanges"))
        )
        if has_inbound:
            public.append(node_id)
            lines.append(f'    INET --> {node_id}')

    # Kartoza palette: amber=server, blue=desktop, cloud=Internet,
    # blue-strong=Tailscale mesh.
    lines.append('    classDef server fill:#FCF3E0,stroke:#DF9E2F,stroke-width:2px,color:#383939')
    lines.append('    classDef desktop fill:#EAF3F8,stroke:#569FC6,stroke-width:2px,color:#383939')
    lines.append('    classDef inet fill:#F5F5F2,stroke:#8A8B8B,color:#383939')
    lines.append('    classDef mesh fill:#EAF3F8,stroke:#569FC6,stroke-width:2px,color:#383939')
    if servers:
        lines.append(f'    class {",".join(servers)} server')
    if desktops:
        lines.append(f'    class {",".join(desktops)} desktop')
    lines.append('    class INET inet')
    lines.append('    class TS mesh')

    return diagram.render(
        "\n".join(lines),
        slug="fleet",
        alt="Fleet overview",
    )


def lint_clean(md: str) -> str:
    """Normalise a generated page to what the pre-commit hooks enforce —
    markdownlint's blank-lines-around-headings (MD022) and the
    end-of-file-fixer's single trailing newline.

    Without this the docs commands are not idempotent: the hooks rewrite
    each page AT COMMIT time, the next regeneration reverts their fixes,
    and `git status` is dirty again after every docs build even though
    nothing real changed. Emitting hook-clean output makes regeneration
    byte-identical to the committed page.

    Fenced code blocks are left alone: a `# comment` inside one is not a
    heading, however much it looks like one.
    """
    src = md.splitlines()
    out: list[str] = []
    in_fence = False
    for line in src:
        if line.lstrip().startswith("```"):
            in_fence = not in_fence
        is_heading = not in_fence and re.match(r"#{1,6} ", line)
        if is_heading and out and out[-1].strip():
            out.append("")
        out.append(line)
        if is_heading:
            out.append("")
    # Collapse any doubled blanks the insertion created, then exactly one
    # trailing newline.
    text = re.sub(r"\n{3,}", "\n\n", "\n".join(out))
    return text.rstrip("\n") + "\n"


def render_host_page(facts: dict[str, Any]) -> str:
    h = facts["host"]
    lines: list[str] = []
    lines.append("<!-- SPDX-FileCopyrightText: Tim Sutton -->\n")
    lines.append("<!-- SPDX-License-Identifier: MIT -->\n\n")
    lines.append(f'<span class="kz-eyebrow">HOST · {h.upper()}</span>\n\n')
    lines.append(f"# {h}\n")
    lines.append(
        "_This page is generated by `nix run .#docs-generate-hosts`. Do not "
        "hand-edit — your changes will be overwritten._\n"
    )

    # ---- Hand-authored companion pages (docs/hosts/<host>-*.md) ----
    companions = sorted(HOSTS_DIR.glob(f"{h}-*.md"))
    if companions:
        lines.append("\n## See also\n")
        lines.append(
            "_Hand-authored deep-dives for this host:_\n\n"
        )
        for companion in companions:
            title = companion.stem
            for line in companion.read_text().splitlines():
                if line.startswith("# "):
                    title = line[2:].strip()
                    break
            lines.append(f"- [{title}]({companion.name})\n")

    # ---- Network interactions ----
    lines.append("\n## Network interactions\n")
    lines.append(
        "_How this host connects to the Internet, the Tailscale mesh, and "
        "the rest of the Kartoza fleet — derived from firewall rules and "
        "`services.tailscale.enable`._\n\n"
    )
    lines.append(render_network_diagram(facts))

    # ---- Deployment stack ----
    lines.append("\n## Deployment stack\n")
    lines.append(
        "_Layered view of the software stack on this host — from hardware "
        "up through systemd, the display manager, and desktop applications._\n\n"
    )
    lines.append(render_deployment_diagram(facts))

    # ---- Identity ----
    lines.append("\n## Identity\n")
    ident_rows = [
        ["Hostname", f"`{facts['hostName']}`"],
        ["Domain", f"`{facts['domain']}`" if facts["domain"] else "_(none)_"],
        ["System", f"`{facts['system']}`" if facts["system"] else "_(unknown)_"],
        ["Time zone", f"`{facts['timeZone']}`" if facts["timeZone"] else "_(unset)_"],
    ]
    lines.append(fmt_table(["Field", "Value"], ident_rows))

    # ---- Boot / kernel ----
    lines.append("\n## Boot & kernel\n")
    boot_rows = [
        ["Kernel", f"`{facts['kernelVersion']}`" if facts["kernelVersion"] else "_(unknown)_"],
        ["Bootloader", facts["bootloader"]],
        ["Filesystems", fmt_inline_list(facts["zfs"])],
    ]
    lines.append(fmt_table(["Field", "Value"], boot_rows))

    # ---- Storage topology ----
    lines.append("\n## Storage topology\n")
    lines.append(
        "_Declared filesystems and ZFS pools — from `config.fileSystems` "
        "and `boot.zfs.extraPools`._\n"
    )
    if facts["zpools"]:
        lines.append("\n**ZFS pools:** " + fmt_inline_list(facts["zpools"]) + "\n")
    if facts["extraPools"]:
        lines.append(
            "\nAdditionally imported at boot (no automatic key request): "
            + fmt_inline_list(facts["extraPools"])
            + "\n"
        )
    fs_rows = [
        [f"`{fs['mountpoint']}`", f"`{fs['device']}`" if fs["device"] else "", f"`{fs['fsType']}`"]
        for fs in sorted(facts["fileSystems"], key=lambda f: f["mountpoint"])
    ]
    lines.append("\n" + fmt_table(["Mountpoint", "Device", "Type"], fs_rows))

    # ---- Firewall ----
    lines.append("\n## Firewall\n")
    if facts["firewallEnabled"] is False:
        lines.append(
            "!!! warning \"Firewall disabled\"\n"
            "    `networking.firewall.enable = false` for this host.\n"
        )
    elif facts["firewallEnabled"] is None:
        lines.append("_Firewall state unspecified._\n")
    else:
        lines.append("Firewall is **enabled**.\n")

    lines.append("\n### Open TCP ports\n")
    lines.append(fmt_inline_list([str(p) for p in facts["tcpPorts"]]) + "\n")
    if facts["tcpRanges"]:
        lines.append("\n### Open TCP port ranges\n")
        rows = [[str(r.get("from", "")), str(r.get("to", ""))] for r in facts["tcpRanges"]]
        lines.append(fmt_table(["From", "To"], rows))

    lines.append("\n### Open UDP ports\n")
    lines.append(fmt_inline_list([str(p) for p in facts["udpPorts"]]) + "\n")
    if facts["udpRanges"]:
        lines.append("\n### Open UDP port ranges\n")
        rows = [[str(r.get("from", "")), str(r.get("to", ""))] for r in facts["udpRanges"]]
        lines.append(fmt_table(["From", "To"], rows))

    # ---- Desktop ----
    lines.append("\n## Desktop environment\n")
    if facts["desktops"]:
        lines.append(fmt_inline_list(facts["desktops"]) + "\n")
    else:
        lines.append("_No graphical desktop enabled — headless / server host._\n")
    if facts["displayManagers"]:
        lines.append("\n**Display manager:** " + fmt_inline_list(facts["displayManagers"]) + "\n")

    # ---- Services ----
    lines.append("\n## Services started at boot\n")
    lines.append(
        "_Taken from `config.systemd.services` filtered to units wanted by "
        "`multi-user.target`, `default.target`, or `graphical.target`, with "
        "each unit's own `Description=`._\n\n"
    )
    if facts["services"]:
        descriptions = facts.get("serviceDescriptions") or {}
        rows = [
            [f"`{escape_cell(s)}`", escape_cell(descriptions.get(s, "")) or "—"]
            for s in facts["services"]
        ]
        lines.append(fmt_table(["Service", "Description"], rows))
    else:
        lines.append("_No boot-time systemd services configured._\n")

    if facts.get("timers"):
        lines.append("\n## Scheduled timers\n")
        lines.append(
            "_Systemd timers wanted by `timers.target` — scheduled jobs that "
            "fire on this host._\n\n"
        )
        ts = facts["timers"]
        cols = 3
        rows = []
        for i in range(0, len(ts), cols):
            chunk = ts[i:i + cols]
            chunk += [""] * (cols - len(chunk))
            rows.append([f"`{c}`" if c else "" for c in chunk])
        lines.append(fmt_table([""] * cols, rows))

    # Highlight a few specific flags
    extras = []
    if facts["sshd"]:
        extras.append("OpenSSH server enabled (`services.openssh.enable`).")
    if facts["tailscale"]:
        extras.append("Tailscale daemon enabled (`services.tailscale.enable`).")
    if extras:
        lines.append("\n!!! info \"Highlights\"\n")
        for e in extras:
            lines.append(f"    - {e}\n")

    # ---- Users ----
    lines.append("\n## Users\n")
    if facts["users"]:
        rows = [
            [u["name"], str(u["uid"] or ""), u["description"] or "", f"`{u['shell']}`" if u["shell"] else ""]
            for u in facts["users"]
        ]
        lines.append(fmt_table(["Name", "UID", "Description", "Shell"], rows))
    else:
        lines.append("_No non-system users configured._\n")

    # ---- Packages ----
    # One subsection per taxonomy group, each a Package | Description table.
    # This section USED to be name-only grids inside collapsible admonitions
    # ("click to expand") — which is exactly wrong for the per-host PDF
    # handbook: print cannot click, so every package list rendered collapsed
    # and the report showed none of the software the host is configured to
    # have. Plain headings and tables read equally well on the site and on
    # paper, and the descriptions come along for free from the catalogue.
    lines.append("\n## Installed software\n")
    pkgs = facts["packages"]
    lines.append(
        # _x_, not *x* — markdownlint's MD049 fix rewrites asterisk emphasis
        # to underscores here (verified against what the hook actually does
        # to this very line; the previous comment claimed the opposite).
        f"_{len(pkgs)} packages declared in `environment.systemPackages`, "
        "grouped by where the flake declares them. Descriptions come from "
        "the exact nixpkgs revision the flake pins, via the "
        "[software catalogue](../references/software.md)._\n\n"
    )
    if pkgs:
        catalogue = load_catalogue()
        for cat, plist in categorise_packages(pkgs).items():
            lines.append(f"\n### {cat} ({len(plist)})\n")
            note = category_note(cat)
            if note:
                lines.append(f"_{note}_\n\n")
            rows = [
                [
                    f"`{escape_cell(p)}`",
                    escape_cell(catalogue.get(p, {}).get("description", "")) or "—",
                ]
                for p in plist
            ]
            lines.append(fmt_table(["Package", "Description"], rows))

    return "".join(lines)


def render_index_page(all_facts: dict[str, dict[str, Any]]) -> str:
    """Regenerate docs/hosts/index.md with the fleet diagram + role table."""
    lines: list[str] = []
    lines.append("<!-- SPDX-FileCopyrightText: Tim Sutton -->\n")
    lines.append("<!-- SPDX-License-Identifier: MIT -->\n\n")
    lines.append('<span class="kz-eyebrow">FLEET</span>\n\n')
    lines.append("# Hosts\n")
    lines.append(
        "_This page is generated by `nix run .#docs-generate-hosts`. Do not "
        "hand-edit — your changes will be overwritten._\n\n"
    )
    lines.append(
        "Each linked page below describes exactly what is deployed on a "
        "given machine: hostname, architecture, kernel, bootloader, open "
        "firewall ports, installed packages, enabled services, desktop "
        "environment, and users.\n"
    )
    lines.append("\n## Fleet overview\n")
    lines.append(
        "_Network topology across the Kartoza fleet — Tailscale-meshed hosts "
        "and any hosts with inbound Internet ports._\n\n"
    )
    lines.append(render_fleet_diagram(all_facts))

    # Role table — server vs desktop, with a public/tailscale summary.
    lines.append("\n## Fleet at a glance\n\n")
    rows: list[list[str]] = []
    for host in sorted(all_facts):
        f = all_facts[host]
        is_desktop = bool(f.get("desktops"))
        role = "Desktop / laptop" if is_desktop else "Server"
        de = ", ".join(f.get("desktops") or []) or "—"
        ts = "✅" if f.get("tailscale") else "—"
        n_ports = (
            len(f.get("tcpPorts") or [])
            + len(f.get("udpPorts") or [])
            + len(f.get("tcpRanges") or [])
            + len(f.get("udpRanges") or [])
        )
        public = f"{n_ports} port{'s' if n_ports != 1 else ''}" if n_ports else "—"
        rows.append([
            f"[{host}]({host}.md)",
            role,
            de,
            ts,
            public,
        ])
    lines.append(fmt_table(
        ["Host", "Role", "Desktop env", "Tailscale", "Inbound firewall"], rows,
    ))

    return "".join(lines)


def main() -> int:
    if shutil.which("nix") is None:
        sys.stderr.write("nix not found in PATH\n")
        return 1

    HOSTS_DIR.mkdir(parents=True, exist_ok=True)

    hosts = get_hosts()
    print(f"Generating pages for {len(hosts)} hosts: {', '.join(hosts)}", flush=True)

    # Collect facts for every host first, then render. This keeps render-side
    # bugs from leaving the docs half-written, and gives render_fleet_diagram
    # the global view it needs.
    all_facts: dict[str, dict[str, Any]] = {}
    for host in hosts:
        print(f"  • {host} …", end="", flush=True)
        try:
            all_facts[host] = collect_host_facts(host)
        except subprocess.CalledProcessError:
            print(" FAILED")
            raise
        print(" ok")

    for host, facts in all_facts.items():
        (HOSTS_DIR / f"{host}.md").write_text(lint_clean(render_host_page(facts)))

    (HOSTS_DIR / "index.md").write_text(lint_clean(render_index_page(all_facts)))

    # Prune pages for hosts that no longer exist. Generating without pruning
    # leaves an orphan page behind whenever a host is retired: it stays in the
    # site, keeps its nav entry working, and quietly describes a machine that
    # is gone. Companion pages (<host>-keyboard.md and friends) go with it.
    keep = set(hosts)
    for page in sorted(HOSTS_DIR.glob("*.md")):
        if page.name == "index.md":
            continue
        owner = page.stem.split("-")[0]
        if page.stem in keep or owner in keep:
            continue
        print(f"  removing stale page: {page.relative_to(REPO_ROOT)}", flush=True)
        page.unlink()

    print(
        f"Wrote {len(hosts)} host pages + index.md to "
        f"{HOSTS_DIR.relative_to(REPO_ROOT)}/"
    )
    return 0


if __name__ == "__main__":
    sys.exit(main())
