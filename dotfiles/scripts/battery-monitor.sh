#!/usr/bin/env bash
# Battery monitor with tiered warnings
# - 10%: Alert user (critical battery warning, bypasses DND)
# - 5%: Suspend the laptop
# - 3%: Shutdown the laptop

set -euo pipefail

# Thresholds
WARN_THRESHOLD=10
SUSPEND_THRESHOLD=5
SHUTDOWN_THRESHOLD=3

# Track if we've already warned at each level
warned_10=false
warned_5=false

get_battery_percentage() {
    local bat_path="/sys/class/power_supply/BAT0"
    if [[ -d "$bat_path" ]]; then
        cat "$bat_path/capacity" 2>/dev/null || echo "100"
    else
        # Try BAT1 as fallback
        bat_path="/sys/class/power_supply/BAT1"
        if [[ -d "$bat_path" ]]; then
            cat "$bat_path/capacity" 2>/dev/null || echo "100"
        else
            echo "100"
        fi
    fi
}

is_charging() {
    local status
    for bat_path in /sys/class/power_supply/BAT*; do
        if [[ -f "$bat_path/status" ]]; then
            status=$(cat "$bat_path/status" 2>/dev/null)
            if [[ "$status" == "Charging" || "$status" == "Full" ]]; then
                return 0
            fi
        fi
    done
    return 1
}

while true; do
    percentage=$(get_battery_percentage)

    # Skip checks if charging
    if is_charging; then
        warned_10=false
        warned_5=false
        sleep 60
        continue
    fi

    # Shutdown at 3%
    if [[ "$percentage" -le "$SHUTDOWN_THRESHOLD" ]]; then
        notify-send -u critical "Battery Critical" "Battery at ${percentage}%! Shutting down NOW to protect battery."
        sleep 5
        systemctl poweroff
    # Suspend at 5%
    elif [[ "$percentage" -le "$SUSPEND_THRESHOLD" ]]; then
        if [[ "$warned_5" == false ]]; then
            notify-send -u critical "Battery Critical" "Battery at ${percentage}%! Suspending in 30 seconds..."
            warned_5=true
            sleep 30
            # Check again in case user plugged in
            if ! is_charging; then
                systemctl suspend
            fi
        fi
    # Warn at 10%
    elif [[ "$percentage" -le "$WARN_THRESHOLD" ]]; then
        if [[ "$warned_10" == false ]]; then
            notify-send -u critical "Low Battery Warning" "Battery at ${percentage}%! Please connect charger."
            warned_10=true
        fi
    else
        # Reset warnings when battery is above thresholds
        warned_10=false
        warned_5=false
    fi

    # Check every 60 seconds
    sleep 60
done
