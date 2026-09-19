#!/usr/bin/env bash
# Show fish aliases in a formatted table
# This script parses fish aliases and displays them nicely

echo ""
echo "Fish Shell Aliases"
echo "=================="
echo ""

# Get aliases from fish and format them
fish -c 'alias' 2>/dev/null | while IFS= read -r line; do
    # Parse "alias name 'command'" format
    if [[ "$line" =~ ^alias[[:space:]]+([^[:space:]]+)[[:space:]]+\'(.*)\'$ ]]; then
        name="${BASH_REMATCH[1]}"
        cmd="${BASH_REMATCH[2]}"
        printf "  %-20s -> %s\n" "$name" "$cmd"
    elif [[ "$line" =~ ^alias[[:space:]]+([^[:space:]]+)[[:space:]]+(.*)$ ]]; then
        name="${BASH_REMATCH[1]}"
        cmd="${BASH_REMATCH[2]}"
        printf "  %-20s -> %s\n" "$name" "$cmd"
    fi
done | sort

echo ""
