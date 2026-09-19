"""
Kartoza custom tab bar for kitty terminal.

Matches the starship powerline prompt style:
- Flat left edge on first tab
- Angled separators between tabs
- Rounded right cap on last tab
- Right-aligned clock with rounded left cap and flat right edge
- Kartoza brand colors: stop-red for active tab, grey/blue alternating for inactive
"""

import datetime

from kitty.fast_data_types import Screen
from kitty.tab_bar import (
    DrawData,
    ExtraData,
    TabBarData,
    as_rgb,
    draw_title,
)
from kitty.utils import color_as_int

# Kartoza brand colors
KARTOZA_ORANGE = 0xDF9E2F
KARTOZA_BLUE = 0x569FC6
KARTOZA_GREY = 0x8A8B8B
KARTOZA_TEAL = 0x06969A
KARTOZA_RED = 0xCC0403
KARTOZA_DARK = 0x0D181E
KARTOZA_LIGHT = 0xC3C7D1

# Powerline glyphs matching starship config
LEFT_CAP = "\ue0b6"     #  rounded left
RIGHT_CAP = "\ue0b4"    #  rounded right
SEPARATOR = "\ue0b0"    #  angled separator


def _c(rgb: int) -> int:
    return as_rgb(rgb)


def _tab_bg(tab: TabBarData, index: int = 0) -> int:
    if tab.is_active:
        return KARTOZA_RED
    # Alternate between grey and blue for inactive tabs
    return KARTOZA_GREY if index % 2 == 0 else KARTOZA_BLUE


def draw_tab(
    draw_data: DrawData,
    screen: Screen,
    tab: TabBarData,
    before: int,
    max_tab_length: int,
    index: int,
    is_last: bool,
    extra_data: ExtraData,
) -> int:
    default_bg = as_rgb(color_as_int(draw_data.default_bg))
    tab_bg = _tab_bg(tab, index)
    tab_fg = KARTOZA_LIGHT

    # Determine next tab background for separator coloring
    if extra_data.next_tab:
        next_bg = _tab_bg(extra_data.next_tab, index + 1)
    else:
        next_bg = None

    # --- Tab content ---
    screen.cursor.bg = _c(tab_bg)
    screen.cursor.fg = _c(tab_fg)

    # Icon
    if tab.is_active:
        screen.draw(" ⚙️  ")
    else:
        screen.draw(" 💻 ")

    # Bell / activity
    if tab.needs_attention:
        screen.cursor.fg = _c(KARTOZA_RED)
        screen.draw("🔔 ")
        screen.cursor.fg = _c(tab_fg)
    elif tab.has_activity_since_last_focus:
        screen.cursor.fg = _c(KARTOZA_TEAL)
        screen.draw("● ")
        screen.cursor.fg = _c(tab_fg)

    # Title
    draw_title(draw_data, screen, tab, index, max_tab_length)

    # Truncate if overflowing
    extra = screen.cursor.x + 2 - before - max_tab_length
    if extra > 0 and extra + 1 < screen.cursor.x:
        screen.cursor.x -= extra + 1
        screen.draw("…")

    # Window count badge
    if tab.num_window_groups > 1:
        screen.cursor.fg = _c(KARTOZA_TEAL)
        screen.draw(f" [{tab.num_window_groups}]")
        screen.cursor.fg = _c(tab_fg)

    screen.draw(" ")

    # --- Separator / right cap ---
    if next_bg is not None:
        # Angled separator into next tab
        screen.cursor.fg = _c(tab_bg)
        screen.cursor.bg = _c(next_bg)
        screen.draw(SEPARATOR)
    else:
        # Last tab: rounded right cap
        screen.cursor.fg = _c(tab_bg)
        screen.cursor.bg = default_bg
        screen.draw(RIGHT_CAP)

    end = screen.cursor.x

    # --- Right-aligned clock on the far right (like starship ♥ time) ---
    if is_last:
        now = datetime.datetime.now().strftime("%H:%M")
        clock_text = f" ♥ {now} "
        clock_width = len(clock_text) + 1  # +1 for left cap only
        remaining = screen.columns - screen.cursor.x - clock_width

        if remaining > 2:
            # Fill gap
            screen.cursor.bg = default_bg
            screen.cursor.fg = default_bg
            screen.draw(" " * remaining)

            # Draw clock: rounded left cap, flat right edge
            screen.cursor.fg = _c(KARTOZA_ORANGE)
            screen.cursor.bg = default_bg
            screen.draw(LEFT_CAP)

            screen.cursor.bg = _c(KARTOZA_ORANGE)
            screen.cursor.fg = _c(KARTOZA_LIGHT)
            screen.draw(clock_text)

    return end
