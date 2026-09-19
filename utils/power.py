#!/usr/bin/env python3
"""Why is this machine hot, and what is it spending its watts on?

A read-only profiler. It reads sysfs and /proc, samples over a short interval,
and reports what it found — temperatures, clocks, power draw, what is running
and what the machine has been told about how hard to work. Then it says which
of those look like they are costing heat, and prints the Nix that would change
each one.

READING CHANGES NOTHING. Every finding ends in a suggestion you apply
yourself, because the right answer depends on what the machine is for: a
laptop on a train and a build host want opposite settings, and a tool that
guessed would be wrong half the time.

Two flags do write, both temporary by construction and both explicit:
--full-charge/--charge-limit for the battery ceiling, and --low/--normal for
the machine's own power knobs. Neither edits configuration and neither
survives a reboot, which is what makes them safe to reach for. Neither stops
anything you are running.

WHY sysfs AND NOT A LIBRARY

Portability, in the sense that matters here. Every fact below comes from a
file that exists on any Linux with the relevant hardware — no vendor tools, no
root, no daemon to be running. A machine missing a sensor simply reports one
fewer line rather than failing, which is what makes this usable on a host you
have never seen.

Run from anywhere:  gisnix power
"""

from __future__ import annotations

import argparse
import json
import os
import re
import sys
import time
from pathlib import Path

GREEN = "\033[38;2;88;150;50m"
YELLOW = "\033[38;2;240;230;74m"
BLUE = "\033[38;2;147;176;35m"
RED = "\033[38;2;200;70;60m"
DIM = "\033[2m"
BOLD = "\033[1m"
NC = "\033[0m"

#: Above this, a CPU package sensor is worth remarking on. Not a hardware
#: limit — silicon is happy well past it — but the point where a laptop is
#: audibly working and its battery is paying for it.
WARM_C = 70.0
HOT_C = 85.0


def read(path: str | Path, default: str = "") -> str:
    try:
        return Path(path).read_text().strip()
    except (OSError, UnicodeDecodeError):
        return default


def read_int(path: str | Path, default: int | None = None) -> int | None:
    raw = read(path)
    try:
        return int(raw)
    except ValueError:
        return default


def glob(pattern: str) -> list[Path]:
    root, _, rest = pattern.partition("/*")
    try:
        return sorted(Path(root).glob("*" + rest))
    except OSError:
        return []


# ── what the machine is ───────────────────────────────────────────────────


def machine() -> dict:
    return {
        "model": read("/sys/class/dmi/id/product_name") or "unknown",
        "vendor": read("/sys/class/dmi/id/sys_vendor"),
        "kernel": read("/proc/sys/kernel/osrelease"),
        "cpu": next(
            (
                line.split(":", 1)[1].strip()
                for line in read("/proc/cpuinfo").splitlines()
                if line.startswith("model name")
            ),
            "unknown",
        ),
        "cores": os.cpu_count() or 0,
    }


# ── temperatures ──────────────────────────────────────────────────────────


def temperatures() -> list[dict]:
    """Every hwmon sensor, with its chip and label."""
    out = []
    for chip in sorted(Path("/sys/class/hwmon").glob("hwmon*")):
        name = read(chip / "name") or chip.name
        for entry in sorted(chip.glob("temp*_input")):
            value = read_int(entry)
            if value is None:
                continue
            stem = entry.name.replace("_input", "")
            out.append(
                {
                    "chip": name,
                    "label": read(chip / f"{stem}_label") or stem,
                    "celsius": value / 1000.0,
                    "max": (read_int(chip / f"{stem}_max") or 0) / 1000.0 or None,
                    "critical": (read_int(chip / f"{stem}_crit") or 0) / 1000.0 or None,
                }
            )
    return out


def fans() -> list[dict]:
    out = []
    for chip in sorted(Path("/sys/class/hwmon").glob("hwmon*")):
        name = read(chip / "name") or chip.name
        for entry in sorted(chip.glob("fan*_input")):
            rpm = read_int(entry)
            if rpm is None:
                continue
            out.append({"chip": name, "label": entry.name, "rpm": rpm})
    return out


# ── clocks and policy ─────────────────────────────────────────────────────


def cpufreq() -> dict:
    base = Path("/sys/devices/system/cpu/cpu0/cpufreq")
    policies = sorted(Path("/sys/devices/system/cpu/cpufreq").glob("policy*"))

    current = []
    for policy in policies:
        khz = read_int(policy / "scaling_cur_freq")
        if khz:
            current.append(khz / 1000.0)

    # amd-pstate and intel_pstate spell "do not turbo" differently.
    boost = read("/sys/devices/system/cpu/cpufreq/boost")
    no_turbo = read("/sys/devices/system/cpu/intel_pstate/no_turbo")
    if boost:
        boosting = boost == "1"
    elif no_turbo:
        boosting = no_turbo == "0"
    else:
        boosting = None

    return {
        "driver": read(base / "scaling_driver") or "unknown",
        "governor": read(base / "scaling_governor") or "unknown",
        "governors_available": read(base / "scaling_available_governors").split(),
        "epp": read(base / "energy_performance_preference"),
        "epp_available": read(base / "energy_performance_available_preferences").split(),
        "min_khz": read_int(base / "cpuinfo_min_freq"),
        "max_khz": read_int(base / "cpuinfo_max_freq"),
        "scaling_max_khz": read_int(base / "scaling_max_freq"),
        "scaling_min_khz": read_int(base / "scaling_min_freq"),
        "boost": boosting,
        "current_mhz": current,
    }


def managers() -> dict:
    """Which power manager is actually running.

    This decides whether a suggestion is useful or inert. `services.tlp.settings`
    does nothing at all unless `services.tlp.enable` is also true — a trap this
    repository was already in — and TLP and power-profiles-daemon fight each
    other if both are up, because both write the same sysfs knobs.
    """
    import subprocess

    def active(unit: str) -> bool | None:
        try:
            done = subprocess.run(
                ["systemctl", "is-active", "--quiet", unit],
                capture_output=True,
                timeout=5,
            )
            return done.returncode == 0
        except (OSError, subprocess.SubprocessError):
            return None

    return {
        "tlp": active("tlp.service"),
        "power_profiles_daemon": active("power-profiles-daemon.service"),
        "thermald": active("thermald.service"),
    }


def platform_profile() -> dict:
    return {
        "active": read("/sys/firmware/acpi/platform_profile"),
        "choices": read("/sys/firmware/acpi/platform_profile_choices").split(),
    }


# ── power draw ────────────────────────────────────────────────────────────


def battery() -> dict | None:
    for supply in sorted(Path("/sys/class/power_supply").glob("*")):
        if read(supply / "type") != "Battery":
            continue
        power_uw = read_int(supply / "power_now")
        if power_uw is None:
            current_ua = read_int(supply / "current_now")
            voltage_uv = read_int(supply / "voltage_now")
            if current_ua and voltage_uv:
                power_uw = abs(current_ua * voltage_uv) // 1_000_000
        return {
            "name": supply.name,
            "status": read(supply / "status"),
            "percent": read_int(supply / "capacity"),
            "watts": round(abs(power_uw) / 1_000_000, 2) if power_uw else None,
            "health": read(supply / "health"),
            "charge_start": read_int(supply / "charge_control_start_threshold"),
            "charge_stop": read_int(supply / "charge_control_end_threshold"),
        }
    return None


def rapl_watts(seconds: float) -> list[dict]:
    """Package power from the RAPL energy counters, sampled over `seconds`.

    The counters are microjoules and they wrap, so this reads twice and
    divides. A negative delta means a wrap and is reported as unknown rather
    than as a wild number.
    """
    domains = sorted(Path("/sys/class/powercap").glob("intel-rapl:*"))
    if not domains:
        return []

    def sample() -> dict[str, int]:
        got = {}
        for d in domains:
            value = read_int(d / "energy_uj")
            if value is not None:
                got[d.name] = value
        return got

    first = sample()
    time.sleep(seconds)
    second = sample()

    out = []
    for domain in domains:
        name = domain.name
        if name not in first or name not in second:
            continue
        delta = second[name] - first[name]
        out.append(
            {
                "domain": read(domain / "name") or name,
                "watts": round(delta / 1_000_000 / seconds, 2) if delta >= 0 else None,
            }
        )
    return out


# ── what is actually running ──────────────────────────────────────────────


def busiest(seconds: float, limit: int = 8) -> list[dict]:
    """Processes by CPU time consumed during the sample, not since boot.

    `ps` sorted by %cpu reports an average over the process's whole lifetime,
    which is why a long-running idle process outranks the one currently
    spinning a core. Sampling twice answers the question actually being asked:
    what is using the processor NOW.
    """
    ticks = os.sysconf("SC_CLK_TCK")

    def sample() -> dict[int, tuple[str, int]]:
        got = {}
        for entry in Path("/proc").iterdir():
            if not entry.name.isdigit():
                continue
            stat = read(entry / "stat")
            if not stat:
                continue
            # comm can contain spaces and brackets; everything after the
            # closing bracket is positional.
            close = stat.rfind(")")
            if close < 0:
                continue
            name = stat[stat.find("(") + 1 : close]
            fields = stat[close + 2 :].split()
            if len(fields) < 13:
                continue
            got[int(entry.name)] = (name, int(fields[11]) + int(fields[12]))
        return got

    first = sample()
    time.sleep(seconds)
    second = sample()

    rows = []
    for pid, (name, later) in second.items():
        if pid not in first:
            continue
        used = later - first[pid][1]
        if used <= 0:
            continue
        rows.append(
            {
                "pid": pid,
                "name": name,
                "cpu_percent": round(used / ticks / seconds * 100, 1),
            }
        )
    rows.sort(key=lambda r: -r["cpu_percent"])
    return rows[:limit]


# ── findings ──────────────────────────────────────────────────────────────


def _ec_advice() -> str:
    """How to read the real limit on THIS machine, not a generic incantation."""
    tool = ec_tool()
    if tool is None:
        return (
            "no EC tool is installed here. On a Framework, add framework-tool "
            "to see and set it"
        )
    name = Path(tool[0]).name
    if name == "framework_tool":
        return (
            "ask the embedded controller instead of the kernel:\n"
            "    framework_tool --charge-limit          # read it\n"
            "    gisnix power --full-charge                 # lift it for a trip"
        )
    return (
        "ask the embedded controller instead of the kernel:\n"
        f"    {name} chargecontrol\n"
        "    gisnix power --full-charge                 # lift it for a trip"
    )


def _tlp_or(data: dict, with_tlp: str, without_tlp: str) -> str:
    """The suggestion that will actually take effect on this machine.

    Recommending `services.tlp.settings.*` to a host where TLP is not enabled
    is advice that looks applied and does nothing — the exact trap this
    repository was already in, with charge thresholds set in a tlp.nix that
    never turned TLP on.
    """
    if data.get("managers", {}).get("tlp"):
        return with_tlp
    return without_tlp


def verdict(data: dict) -> dict:
    """Is this machine actually hot right now, and how hard is it working?

    Worth stating before any advice. The first version of this tool listed
    suggestions whatever the readings, so a laptop idling at 47°C with clocks
    averaging a third of its ceiling was told to cap its clocks. Advice with
    no problem attached is how a tool trains people to ignore it.
    """
    package = [
        temp["celsius"]
        for temp in data["temperatures"]
        if temp["chip"] in {"k10temp", "coretemp", "zenpower"}
        or temp["label"] in {"Tctl", "Tdie", "Package id 0"}
    ]
    hottest = max((t["celsius"] for t in data["temperatures"]), default=0.0)
    cpu_c = max(package) if package else hottest

    clocks = data["cpufreq"].get("current_mhz") or []
    mean_mhz = sum(clocks) / len(clocks) if clocks else 0.0
    max_khz = data["cpufreq"].get("max_khz") or 0
    load = (mean_mhz * 1000 / max_khz) if max_khz else 0.0

    if cpu_c >= HOT_C:
        level, summary = "hot", f"Yes — the processor is at {cpu_c:.0f}°C."
    elif cpu_c >= WARM_C:
        level, summary = "warm", f"Warm — the processor is at {cpu_c:.0f}°C."
    else:
        level, summary = "cool", f"No — the processor is at {cpu_c:.0f}°C."

    fan_note = ""
    if data["fans"]:
        rpm = max(f["rpm"] for f in data["fans"])
        fan_note = f" Fans at {rpm} rpm."

    return {
        "level": level,
        "cpu_celsius": cpu_c,
        "clock_fraction": round(load, 2),
        "summary": summary,
        "evidence": (
            f"Clocks are averaging {mean_mhz:.0f} MHz, "
            f"{load * 100:.0f}% of the {max_khz / 1_000_000:.2f} GHz ceiling."
            f"{fan_note}"
            + (
                " Nothing here suggests a thermal problem, so treat the entries"
                " below as efficiency notes rather than fixes."
                if level == "cool"
                else ""
            )
        ),
    }


def findings(data: dict) -> list[dict]:
    """Things that plausibly cost heat, each with what to do about it.

    Every entry says what was observed, why it matters and the change that
    would address it. None of them are applied: a laptop on a train and a
    build host want opposite settings.
    """
    out: list[dict] = []
    freq = data["cpufreq"]
    batt = data.get("battery")
    on_battery = bool(batt and batt.get("status") == "Discharging")
    mgr = data.get("managers", {})

    if mgr.get("tlp") and mgr.get("power_profiles_daemon"):
        out.append(
            {
                "level": "hot",
                "what": "TLP and power-profiles-daemon are both running",
                "why": "they write the same sysfs knobs and undo each other. Which "
                "settings survive depends on which wrote last, so the machine's "
                "behaviour is not what either configuration says",
                "do": "pick one. power-profiles-daemon integrates with the desktop's "
                "power menu; TLP has far more knobs:\n"
                "    services.tlp.enable = false;   # or\n"
                "    services.power-profiles-daemon.enable = false;",
            }
        )

    if mgr.get("tlp") is False:
        out.append(
            {
                "level": "info",
                "what": "TLP is not running, so any services.tlp.settings are inert",
                "why": "`services.tlp.settings` does nothing on its own — NixOS needs "
                "`services.tlp.enable = true` as well. Settings written without it look "
                "applied and are not",
                "do": "either enable it, or move the settings to whatever is actually "
                "managing power here",
            }
        )

    hottest = max(
        (t for t in data["temperatures"] if t["celsius"]),
        key=lambda t: t["celsius"],
        default=None,
    )
    if hottest and hottest["celsius"] >= HOT_C:
        out.append(
            {
                "level": "hot",
                "what": f"{hottest['label']} ({hottest['chip']}) is at {hottest['celsius']:.0f}°C",
                "why": "sustained temperatures this high mean the fans are working and "
                "the package is close to throttling itself",
                "do": "the entries below are the usual causes; start with the governor",
            }
        )

    if freq["governor"] == "performance":
        out.append(
            {
                "level": "hot" if on_battery else "warm",
                "what": f"the CPU governor is `performance`"
                + (" while on battery" if on_battery else ""),
                "why": "performance holds clocks high rather than letting them fall when "
                "there is nothing to do, which is heat spent on idle",
                "do": 'powerManagement.cpuFreqGovernor = "powersave";\n'
                "    On amd-pstate and intel_pstate `powersave` is not slow — it still "
                "reaches full clocks under load. It simply stops holding them there.",
            }
        )

    if freq["epp"] in {"performance", "balance_performance"}:
        out.append(
            {
                "level": "warm",
                "what": f"the energy/performance preference is `{freq['epp']}`",
                "why": "EPP biases the hardware's own decisions. `performance` tells it "
                "to favour speed over watts on every one of them",
                "do": _tlp_or(
                    data,
                    'services.tlp.settings.CPU_ENERGY_PERF_POLICY_ON_BAT = "power";',
                    "powerprofilesctl set power-saver   # sets EPP for you",
                ),
            }
        )

    if freq["boost"] and on_battery:
        out.append(
            {
                "level": "warm",
                "what": "turbo/boost is enabled on battery",
                "why": "the last few hundred MHz cost disproportionately more power than "
                "they return in speed — the top of the curve is the expensive part",
                "do": _tlp_or(
                    data,
                    'services.tlp.settings.CPU_BOOST_ON_BAT = "0";',
                    "echo 0 | sudo tee /sys/devices/system/cpu/cpufreq/boost"
                    "   # amd-pstate; intel_pstate uses intel_pstate/no_turbo",
                ),
            }
        )

    scaling_max = freq.get("scaling_max_khz")
    hardware_max = freq.get("max_khz")
    # Only worth raising when the machine is actually hot or actually
    # clocking high. Telling a laptop idling at 47°C and a third of its
    # ceiling to cap its clocks is advice with no problem attached.
    warm_enough = data["verdict"]["level"] != "cool"
    busy_enough = data["verdict"]["clock_fraction"] >= 0.6
    if scaling_max and hardware_max and scaling_max >= hardware_max and (
        warm_enough or busy_enough
    ):
        out.append(
            {
                "level": "info",
                "what": f"no frequency ceiling: scaling_max is the hardware maximum "
                f"({hardware_max / 1_000_000:.2f} GHz)",
                "why": "capping the top clock is the bluntest way to cut heat, and on a "
                "laptop that is mostly idle it costs very little in practice",
                "do": _tlp_or(
                    data,
                    f"services.tlp.settings.CPU_SCALING_MAX_FREQ_ON_BAT = "
                    f"{int(hardware_max * 0.8)};",
                    f"echo {int(hardware_max * 0.8)} | sudo tee "
                    "/sys/devices/system/cpu/cpu*/cpufreq/scaling_max_freq"
                    "   # not persistent; wrap it in a systemd oneshot to keep it",
                ),
            }
        )

    profile = data["platform_profile"]
    if profile["active"] and profile["active"] not in {"low-power", "quiet", "balanced"}:
        out.append(
            {
                "level": "warm",
                "what": f"the ACPI platform profile is `{profile['active']}`",
                "why": "this is the firmware's own power budget, above anything Linux "
                "sets. A `performance` profile raises the sustained power limit the "
                "whole machine works to",
                "do": "choose a cooler one from "
                f"{', '.join(profile['choices']) or 'the available list'}:\n"
                "    powerprofilesctl set power-saver   (power-profiles-daemon)",
            }
        )

    hot_procs = [p for p in data["processes"] if p["cpu_percent"] >= 25]
    if hot_procs:
        names = ", ".join(f"{p['name']} ({p['cpu_percent']}%)" for p in hot_procs[:3])
        out.append(
            {
                "level": "info",
                "what": f"something is using the processor right now: {names}",
                "why": "no power setting will cool a machine that has work to do. This "
                "is worth ruling out before changing anything",
                "do": "if that is unexpected, deal with the process rather than the "
                "governor",
            }
        )

    if batt and batt.get("charge_stop") == 100:
        out.append(
            {
                "level": "info",
                "what": "the battery charges to 100%",
                "why": "not a heat problem, but holding a lithium cell at full charge "
                "ages it faster than stopping short",
                "do": _tlp_or(
                    data,
                    'services.tlp.settings.STOP_CHARGE_THRESH_BAT0 = "80";',
                    "on a Framework the EC owns this, and it persists across reboots:\n"
                    "    ectool fwchargelimit 80",
                ),
            }
        )
    elif batt and batt.get("charge_stop") is None:
        out.append(
            {
                "level": "info",
                "what": "the kernel does not report a charge limit for this battery",
                "why": "that does NOT mean there is none. An embedded controller can "
                "hold one the kernel never sees — a Framework set with "
                "`ectool fwchargelimit` is limited without exposing "
                "charge_control_end_threshold at all",
                "do": _ec_advice(),
            }
        )

    return out


# ── the one thing this tool writes ────────────────────────────────────────


def is_framework() -> bool:
    return "framework" in read("/sys/class/dmi/id/sys_vendor").lower()


#: Ways to reach an embedded controller, in the order they are tried.
#:
#: `framework_tool` is the Rust tool from framework-system and is what
#: hosts/abyss actually installs; `ectool` is the Framework fork of the
#: ChromeOS EC tool and is what its systemd unit reaches by store path. The
#: first version of this looked only for `ectool`, found nothing on a
#: Framework 16 that had framework_tool right there on PATH, and reported that
#: the machine was not a Framework.
EC_TOOLS = [
    ("framework_tool", lambda binary, n: [binary, "--charge-limit", str(n)]),
    ("ectool", lambda binary, n: [binary, "fwchargelimit", str(n)]),
    ("fw-ectool", lambda binary, n: [binary, "fwchargelimit", str(n)]),
]


def ec_tool():
    """(path, argv builder) for the first EC tool on PATH, or None."""
    import shutil

    for name, build in EC_TOOLS:
        found = shutil.which(name)
        if found:
            return found, (lambda n, f=found, b=build: b(f, n))
    return None


def batteries_with_threshold() -> list[Path]:
    return [
        supply
        for supply in sorted(Path("/sys/class/power_supply").glob("*"))
        if (supply / "charge_control_end_threshold").exists()
    ]


def set_charge_limit(percent: int) -> int:
    """Raise or lower the charge ceiling until the configuration reasserts it.

    THE ONE WRITE IN THIS TOOL, and only behind an explicit flag. It exists
    for the case a declarative limit gets wrong: you are travelling tomorrow
    and want the full battery, once, without editing the configuration and
    rebuilding.

    Deliberately NOT persistent. `kartoza.power.chargeLimit` reapplies at boot
    and on resume, so the machine returns to its declared state by itself —
    which is the property that makes this safe to use casually. If you want
    100% permanently, change the option, not this.
    """
    import shutil
    import subprocess

    def run(argv: list[str]) -> bool:
        if os.geteuid() != 0:
            if shutil.which("sudo") is None:
                print(f"  {RED}✗{NC} need root and sudo is not available", file=sys.stderr)
                return False
            argv = ["sudo", *argv]
        print(f"  {DIM}$ {' '.join(argv)}{NC}")
        try:
            done = subprocess.run(argv, capture_output=True, text=True)
        except OSError as exc:
            print(f"  {RED}✗{NC} {exc}", file=sys.stderr)
            return False
        if done.returncode != 0:
            print(f"  {RED}✗{NC} {done.stderr.strip() or 'failed'}", file=sys.stderr)
            return False
        return True

    print()
    print(f"  {BOLD}Charge limit → {percent}%{NC}")

    # On a Framework the embedded controller owns this, and on some models the
    # sysfs threshold does not persist — which is why hosts/abyss sets its
    # limit through the EC rather than sysfs.
    tool = ec_tool()
    if tool:
        binary, argv = tool
        if not run(argv(percent)):
            return 1
        print(f"  {GREEN}✓{NC} set at the embedded controller via {Path(binary).name}")
    else:
        targets = batteries_with_threshold()
        if not targets:
            looked = ", ".join(name for name, _ in EC_TOOLS)
            print(
                f"  {RED}✗{NC} nothing here can set a charge limit.",
                file=sys.stderr,
            )
            print(
                f"      no battery exposes charge_control_end_threshold, and none of"
                f"\n      {looked} is on PATH"
                + (
                    "\n      This IS a Framework, so installing framework-tool would"
                    "\n      give it one."
                    if is_framework()
                    else ""
                ),
                file=sys.stderr,
            )
            return 1
        for battery in targets:
            threshold = battery / "charge_control_end_threshold"
            if os.geteuid() == 0:
                try:
                    threshold.write_text(f"{percent}\n")
                except OSError as exc:
                    print(f"  {RED}✗{NC} {exc}", file=sys.stderr)
                    return 1
                print(f"  {DIM}$ echo {percent} > {threshold}{NC}")
            elif not run(["sh", "-c", f"echo {percent} > {threshold}"]):
                return 1
        print(f"  {GREEN}✓{NC} set on {', '.join(b.name for b in targets)}")

    print()
    print(f"  {DIM}Not permanent. kartoza.power.chargeLimit reapplies at boot and{NC}")
    print(f"  {DIM}on resume, so the machine returns to its declared state by itself.{NC}")
    print(f"  {DIM}For a permanent change, set that option instead.{NC}")
    print()
    return 0


# ── presentation ──────────────────────────────────────────────────────────


#: A sensor's own max/crit is used to scale its bar, but some report nonsense
#: — several NVMe controllers advertise 32767°C. A ceiling outside this range
#: is ignored in favour of a sane default, because a bar scaled to 32767
#: renders every real temperature as empty. That is exactly what happened:
#: an NVMe at 54.9°C drew a completely empty bar beside a wifi chip at 54.0°C
#: drawing a half-full one.
PLAUSIBLE_CEILING = (40.0, 130.0)


# ── low-power mode ────────────────────────────────────────────────────────

#: Where the pre-low-power values are parked. /run is tmpfs BY DESIGN: a
#: reboot loses the file, and a reboot has also already undone every write
#: below, so the two facts stay true together. There is no state to go stale.
RESTORE = Path("/run/gisnix-power-restore.json")


def _write_sysfs(path: str | Path, value: str) -> bool:
    """Write one sysfs file, via sudo when we are not root. False if it did not take."""
    import shutil
    import subprocess

    path = Path(path)
    if not path.exists():
        return False
    if os.geteuid() == 0:
        try:
            path.write_text(value)
            return True
        except OSError as exc:
            print(f"  {RED}✗{NC} {path}: {exc}", file=sys.stderr)
            return False
    if shutil.which("sudo") is None:
        print(f"  {RED}✗{NC} need root and sudo is not available", file=sys.stderr)
        return False
    done = subprocess.run(
        ["sudo", "tee", str(path)], input=value, capture_output=True, text=True
    )
    if done.returncode != 0:
        print(f"  {RED}✗{NC} {path}: {done.stderr.strip() or 'failed'}", file=sys.stderr)
        return False
    return True


def _ppd(*argv: str) -> str | None:
    """Talk to power-profiles-daemon. None if it is not here or refused."""
    import shutil
    import subprocess

    if shutil.which("powerprofilesctl") is None:
        return None
    try:
        done = subprocess.run(
            ["powerprofilesctl", *argv], capture_output=True, text=True, timeout=5
        )
    except (OSError, subprocess.SubprocessError):
        return None
    return done.stdout.strip() if done.returncode == 0 else None


def _cpu_epp_paths() -> list[Path]:
    return glob("/sys/devices/system/cpu/cpu*/cpufreq/energy_performance_preference")


def _snapshot() -> dict:
    """Everything --low is about to change, as it is right now."""
    epp = _cpu_epp_paths()
    return {
        "profile": _ppd("get"),
        "boost": read("/sys/devices/system/cpu/cpufreq/boost", ""),
        "no_turbo": read("/sys/devices/system/cpu/intel_pstate/no_turbo", ""),
        "aspm": (read("/sys/module/pcie_aspm/parameters/policy", "") or "").strip(),
        "epp": {str(p): read(p, "") for p in epp},
    }


def _aspm_current(raw: str) -> str:
    """ASPM policy reads as a list with the active one in brackets."""
    found = re.search(r"\[(\w+)\]", raw or "")
    return found.group(1) if found else ""


def low_power(on: bool) -> int:
    """Turn the machine's own power knobs down, reversibly.

    THE SECOND WRITE IN THIS TOOL, and like the charge limit it is temporary
    by construction: everything here is a runtime knob that a reboot returns
    to what the configuration declares. Nothing is edited, nothing persists.

    IT DOES NOT STOP ANYTHING YOU ARE RUNNING. A container, a VM, a model or
    a build may well be the largest number on this machine, but which of those
    is disposable is not something a tool can know, and killing the wrong one
    costs more than the battery it saves. The report says what is expensive;
    closing it stays your call.
    """
    if on:
        if RESTORE.exists():
            print(f"  {YELLOW}!{NC} already in low-power mode — `gisnix power --normal` to come back")
            return 0
        before = _snapshot()
        print()
        print(f"  {BOLD}Low power{NC} {DIM}— reversible; a reboot also undoes it{NC}")

        applied: list[str] = []

        # The one lever COSMIC's own slider reflects, so the desktop does not
        # disagree with the machine. On amd_pstate this already moves the
        # governor and EPP; the explicit EPP write below is for the case it
        # does not.
        if _ppd("set", "power-saver") is not None:
            applied.append("power-profiles-daemon → power-saver")

        for path in _cpu_epp_paths():
            _write_sysfs(path, "power")
        if _cpu_epp_paths():
            applied.append("CPU energy-performance preference → power")

        # Boost is the big one for HEAT specifically: it is what lets the
        # package spike to its ceiling for a few seconds of work, which on a
        # fanless-ish laptop is most of the noise and much of the drain.
        if _write_sysfs("/sys/devices/system/cpu/cpufreq/boost", "0"):
            applied.append("CPU boost → off")
        elif _write_sysfs("/sys/devices/system/cpu/intel_pstate/no_turbo", "1"):
            applied.append("CPU turbo → off")

        # powersave, not powersupersave: the deeper state has a history of
        # wedging NVMe on some controllers, and a laptop that does not resume
        # has saved no power at all.
        if _write_sysfs("/sys/module/pcie_aspm/parameters/policy", "powersave"):
            applied.append("PCIe ASPM → powersave")

        try:
            RESTORE.parent.mkdir(parents=True, exist_ok=True)
            payload = json.dumps(before, indent=2)
            if os.geteuid() == 0:
                RESTORE.write_text(payload)
            else:
                import subprocess

                subprocess.run(
                    ["sudo", "tee", str(RESTORE)], input=payload,
                    capture_output=True, text=True,
                )
        except OSError as exc:
            print(f"  {YELLOW}!{NC} could not record previous values ({exc});")
            print(f"    {DIM}a reboot still restores everything{NC}")

        if not applied:
            print(f"  {RED}✗{NC} nothing here exposes a power knob this tool can turn.")
            return 1
        for line in applied:
            print(f"  {GREEN}✓{NC} {line}")
        print()
        print(f"  {DIM}Not touched, because only you know what is disposable:{NC}")
        print(f"  {DIM}screen brightness (the biggest single draw on a 16in panel),{NC}")
        print(f"  {DIM}Wi-Fi/Bluetooth, and anything you have running. `gisnix power`{NC}")
        print(f"  {DIM}lists what is costing watts.{NC}")
        return 0

    # ── back to normal ────────────────────────────────────────────────────
    if not RESTORE.exists():
        print(f"  {DIM}Not in low-power mode — nothing to restore.{NC}")
        print(f"  {DIM}(A reboot clears it too, which is why there is no state to go stale.){NC}")
        return 0
    try:
        before = json.loads(RESTORE.read_text())
    except (OSError, ValueError) as exc:
        print(f"  {RED}✗{NC} cannot read {RESTORE}: {exc}", file=sys.stderr)
        print(f"      {DIM}reboot to restore, or set the profile by hand{NC}", file=sys.stderr)
        return 1

    print()
    print(f"  {BOLD}Normal power{NC}")
    if before.get("profile"):
        if _ppd("set", before["profile"]) is not None:
            print(f"  {GREEN}✓{NC} power-profiles-daemon → {before['profile']}")
    for path, value in (before.get("epp") or {}).items():
        if value:
            _write_sysfs(path, value)
    if before.get("epp"):
        print(f"  {GREEN}✓{NC} CPU energy-performance preference restored")
    if before.get("boost") and _write_sysfs("/sys/devices/system/cpu/cpufreq/boost", before["boost"]):
        print(f"  {GREEN}✓{NC} CPU boost → {'on' if before['boost'] == '1' else before['boost']}")
    if before.get("no_turbo"):
        _write_sysfs("/sys/devices/system/cpu/intel_pstate/no_turbo", before["no_turbo"])
    was = _aspm_current(before.get("aspm", ""))
    if was and _write_sysfs("/sys/module/pcie_aspm/parameters/policy", was):
        print(f"  {GREEN}✓{NC} PCIe ASPM → {was}")

    import shutil
    import subprocess

    if os.geteuid() == 0:
        try:
            RESTORE.unlink()
        except OSError:
            pass
    elif shutil.which("sudo"):
        subprocess.run(["sudo", "rm", "-f", str(RESTORE)], capture_output=True)
    return 0


def bar(value: float, ceiling: float, width: int = 24) -> str:
    if not ceiling or not PLAUSIBLE_CEILING[0] <= ceiling <= PLAUSIBLE_CEILING[1]:
        ceiling = 100.0
    filled = max(0, min(width, round(value / ceiling * width))) if ceiling else 0
    colour = RED if value >= HOT_C else (YELLOW if value >= WARM_C else GREEN)
    return f"{colour}{'█' * filled}{DIM}{'░' * (width - filled)}{NC}"


def report(data: dict) -> None:
    m = data["machine"]
    print()
    print(f"  {BOLD}{m['vendor']} {m['model']}{NC}")
    print(f"  {DIM}{m['cpu'].strip()} · {m['cores']} threads · kernel {m['kernel']}{NC}")

    temps = sorted(data["temperatures"], key=lambda t: -t["celsius"])
    if temps:
        print(f"\n  {BOLD}Temperatures{NC}")
        for t in temps[:10]:
            ceiling = t["critical"] or t["max"] or 100.0
            print(
                f"    {t['label'][:22]:<22} {t['celsius']:5.1f}°C  {bar(t['celsius'], ceiling)}"
                f"  {DIM}{t['chip']}{NC}"
            )
    else:
        print(f"\n  {DIM}No hwmon temperature sensors readable.{NC}")

    if data["fans"]:
        speeds = ", ".join(f"{f['rpm']} rpm" for f in data["fans"])
        print(f"    {DIM}fans: {speeds}{NC}")

    f = data["cpufreq"]
    print(f"\n  {BOLD}Clocks and policy{NC}")
    print(f"    driver          {f['driver']}")
    print(f"    governor        {f['governor']}  {DIM}of {' '.join(f['governors_available']) or '?'}{NC}")
    if f["epp"]:
        print(f"    EPP             {f['epp']}  {DIM}of {' '.join(f['epp_available'])}{NC}")
    if f["boost"] is not None:
        print(f"    boost/turbo     {'on' if f['boost'] else 'off'}")
    if f["current_mhz"]:
        now = f["current_mhz"]
        print(
            f"    current         {min(now):.0f}–{max(now):.0f} MHz  "
            f"{DIM}mean {sum(now) / len(now):.0f}{NC}"
        )
    if f["max_khz"]:
        cap = f.get("scaling_max_khz") or f["max_khz"]
        note = "" if cap >= f["max_khz"] else f"  {YELLOW}capped{NC}"
        print(f"    ceiling         {cap / 1_000_000:.2f} GHz of {f['max_khz'] / 1_000_000:.2f} GHz{note}")

    p = data["platform_profile"]
    if p["active"]:
        print(f"    platform        {p['active']}  {DIM}of {' '.join(p['choices'])}{NC}")

    mgr = data.get("managers", {})
    running = [name.replace("_", "-") for name, on in mgr.items() if on]
    if any(v is not None for v in mgr.values()):
        print(f"    managed by      {', '.join(running) or 'nothing — sysfs defaults'}")

    b = data.get("battery")
    if b:
        print(f"\n  {BOLD}Power{NC}")
        draw = f"{b['watts']} W" if b["watts"] else "unknown"
        print(f"    battery         {b['percent']}%  {b['status']}  drawing {draw}")
        if b["charge_stop"]:
            print(f"    charge limit    {b['charge_start'] or '?'}–{b['charge_stop']}%")
        else:
            tool = ec_tool()
            via = (
                f"{Path(tool[0]).name} can set one"
                if tool
                else "and nothing here can set one"
            )
            print(f"    charge limit    {DIM}not visible to the kernel; {via}{NC}")
    for domain in data["rapl"]:
        if domain["watts"] is not None:
            print(f"    {domain['domain'][:15]:<15} {domain['watts']} W")

    if data["processes"]:
        print(f"\n  {BOLD}Using the processor{NC} {DIM}(sampled, not since boot){NC}")
        for proc in data["processes"]:
            print(f"    {proc['cpu_percent']:5.1f}%  {proc['name'][:30]:<30} {DIM}{proc['pid']}{NC}")

    verdict = data["verdict"]
    print(f"\n  {BOLD}Is it hot?{NC}")
    mark = {"hot": RED, "warm": YELLOW}.get(verdict["level"], GREEN)
    print(f"    {mark}{verdict['summary']}{NC}")
    for line in wrap(verdict["evidence"], 68):
        print(f"    {DIM}{line}{NC}")

    found = data["findings"]
    print(f"\n  {BOLD}What is costing heat{NC}")
    if not found:
        print(f"    {GREEN}Nothing obvious.{NC} Clocks, governor and profile all look "
              "reasonable for a machine trying to stay cool.")
    for item in found:
        mark = {"hot": f"{RED}●{NC}", "warm": f"{YELLOW}●{NC}"}.get(item["level"], f"{BLUE}●{NC}")
        print(f"\n    {mark} {BOLD}{item['what']}{NC}")
        for line in wrap(item["why"], 68):
            print(f"      {DIM}{line}{NC}")
        for line in item["do"].split("\n"):
            print(f"      {GREEN}{line}{NC}" if line.strip() else "")
    print()
    print(f"  {DIM}Nothing was changed. Everything above is a suggestion.{NC}")
    print()


def wrap(text: str, width: int) -> list[str]:
    import textwrap

    return textwrap.wrap(" ".join(text.split()), width=width)


def collect(seconds: float) -> dict:
    # The two sampled readings share one interval rather than taking one each.
    processes = busiest(seconds)
    data = {
        "machine": machine(),
        "temperatures": temperatures(),
        "fans": fans(),
        "cpufreq": cpufreq(),
        "platform_profile": platform_profile(),
        "battery": battery(),
        "managers": managers(),
        "rapl": rapl_watts(0.2),
        "processes": processes,
    }
    data["verdict"] = verdict(data)
    data["findings"] = findings(data)
    return data


def main(argv: list[str]) -> int:
    parser = argparse.ArgumentParser(
        prog="gisnix power",
        description="Profile this machine's heat and power, and suggest what to change.",
        formatter_class=argparse.RawDescriptionHelpFormatter,
        epilog="""
Reads sysfs and /proc. Needs no root and works on any Linux — a machine
missing a sensor reports one fewer line rather than failing.

It writes only behind an explicit flag, and never permanently: the charge
ceiling (--full-charge/--charge-limit) and the power knobs (--low/--normal).
A reboot undoes both, because the declared configuration reasserts itself.
Neither stops a service, a container or a VM - what is disposable is yours
to decide, and the report tells you what is costing watts.

examples:
  gisnix power                 # profile now
  gisnix power --low           # travelling: turn the machine's knobs down
  gisnix power --normal        # put them back
  gisnix power --full-charge   # travelling tomorrow: charge to 100% this once
  gisnix power --seconds 5     # sample the processor for longer
  gisnix power --json          # machine-readable, for graphing over time
  gisnix power --watch         # refresh until interrupted
""",
    )
    parser.add_argument(
        "-s", "--seconds", type=float, default=1.0,
        help="how long to sample processor use for (default 1)",
    )
    parser.add_argument("--json", action="store_true", help="emit JSON instead of a report")
    parser.add_argument(
        "--full-charge",
        action="store_true",
        help="charge to 100%% for this trip. Needs root. NOT permanent: the "
        "declared limit reapplies at the next boot or resume",
    )
    parser.add_argument(
        "--charge-limit",
        type=int,
        metavar="PERCENT",
        help="set the charge ceiling now, temporarily, the same way as "
        "--full-charge",
    )
    parser.add_argument(
        "--low",
        action="store_true",
        help="turn the machine's power knobs down for travel. Needs root. "
        "NOT permanent: a reboot restores them, and it stops nothing you are running",
    )
    parser.add_argument(
        "--normal",
        action="store_true",
        help="undo --low, restoring the values it recorded",
    )
    parser.add_argument("--watch", action="store_true", help="refresh until interrupted")
    args = parser.parse_args(argv)

    if args.low and args.normal:
        print("power: --low and --normal are opposites; pick one.", file=sys.stderr)
        return 1
    if args.low or args.normal:
        return low_power(args.low)

    if args.full_charge or args.charge_limit is not None:
        percent = 100 if args.full_charge else args.charge_limit
        if not 50 <= percent <= 100:
            print("power: a charge limit outside 50-100% is not sensible.", file=sys.stderr)
            return 1
        return set_charge_limit(percent)

    if not Path("/sys/class/hwmon").exists():
        print("power: /sys is not readable here, so nothing can be measured.", file=sys.stderr)
        return 1

    try:
        while True:
            data = collect(args.seconds)
            if args.json:
                print(json.dumps(data, indent=2))
                return 0
            if args.watch:
                print("\033[2J\033[H", end="")
            report(data)
            if not args.watch:
                return 0
    except KeyboardInterrupt:
        return 0


if __name__ == "__main__":
    raise SystemExit(main(sys.argv[1:]))
