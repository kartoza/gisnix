"""app.py's Button focus/press styling — a blue bevel that inverts
between focus and Textual's own "-active" press-tracking class (its
stock press-flash mechanism, unchanged; only the colours are ours), so
a button visibly "sinks in" for the ~0.2s a press is held. Verified once
against a bare Textual Button (textual's own -active toggling is
out of scope here — that's framework behaviour, not this app's code) and
covered here as a CSS-resolution regression: change the rule, this test
should tell you whether it still means what it's supposed to."""

from __future__ import annotations

import asyncio

from installer.app import InstallerApp


def _run(coro):
    return asyncio.run(coro)


def test_focused_button_gets_a_light_top_dark_bottom_bevel():
    async def body():
        app = InstallerApp()
        async with app.run_test() as pilot:
            await pilot.pause()
            btn = app.screen.query_one("#wizard-next")
            btn.focus()
            await pilot.pause()
            top = btn.styles.border_top[1]
            bottom = btn.styles.border_bottom[1]
            # "light" top, "dark" bottom: top should be strictly brighter
            # (higher R+G+B) than bottom — that asymmetry is the entire
            # raised-bevel illusion.
            assert (top.r + top.g + top.b) > (bottom.r + bottom.g + bottom.b)

    _run(body())


def test_pressed_button_inverts_the_bevel():
    """Same button, with Textual's own "-active" class applied (what a
    real Enter/click briefly adds) — the bevel must flip, dark-on-top
    now, or a press doesn't read as sinking in versus just re-lighting."""

    async def body():
        app = InstallerApp()
        async with app.run_test() as pilot:
            await pilot.pause()
            btn = app.screen.query_one("#wizard-next")
            btn.focus()
            await pilot.pause()
            focused_top = btn.styles.border_top[1]

            btn.add_class("-active")
            await pilot.pause()
            pressed_top = btn.styles.border_top[1]
            pressed_bottom = btn.styles.border_bottom[1]

            assert (pressed_bottom.r + pressed_bottom.g + pressed_bottom.b) > (
                pressed_top.r + pressed_top.g + pressed_top.b
            )
            # And it's a real change from the focused (unpressed) state,
            # not the same bevel redrawn.
            assert pressed_top != focused_top

    _run(body())
