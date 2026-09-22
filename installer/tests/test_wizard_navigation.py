"""Regression coverage for the wizard's own plumbing — screen
construction/mounting and step-order bookkeeping — not any individual
screen's business logic (that's each screen's own test module).

Exists because of a real incident: 0.14.0 shipped a per-screen step
counter whose wiring in InstallerApp._make() called screen.set_step()
unconditionally on every step name in the wizard's order, including
"installing" and "done" — plain Screen subclasses, not WizardScreen,
with no such method. It crashed every real (non-mock) install right at
the transition into the Installing screen. Nothing before this suite had
ever exercised actually pushing every registered screen; --mock testing
during development never reached that far down the flow.
"""

from __future__ import annotations

import asyncio
import importlib
import pkgutil
from unittest.mock import patch

import pytest

import installer.screens as screens_pkg
from installer.app import InstallerApp
from installer.screens.base import WizardScreen


def _run(coro):
    return asyncio.run(coro)


def _all_screen_classes() -> list[type]:
    """Every Screen subclass defined in installer.screens.* — walked by
    module rather than via InstallerApp's registry, so a screen added to
    a module but never wired into the registry still gets caught by the
    CSS-override check below (the registry-driven tests below are the
    ones actually exercising real navigation)."""
    classes = []
    for _, name, _ in pkgutil.iter_modules(screens_pkg.__path__):
        module = importlib.import_module(f"installer.screens.{name}")
        for attr in vars(module).values():
            if isinstance(attr, type) and issubclass(attr, WizardScreen) and attr is not WizardScreen:
                classes.append(attr)
    return classes


def test_no_wizard_screen_overrides_css():
    """Screen.CSS is a plain class attribute — Textual does not merge it
    across a Python subclass chain, so a WizardScreen subclass defining
    its own class-level CSS silently REPLACES WizardScreen's (card
    border, title row, step badge, docked button bar) instead of adding
    to it. This bit NetworkScreen once already (confirmed against a live
    screenshot: card border, title row, and the docked button bar all
    vanished). Style widget instances directly instead — see network.py
    and user.py's own comments on this exact trap."""
    offenders = [cls.__name__ for cls in _all_screen_classes() if "CSS" in vars(cls)]
    assert not offenders, f"WizardScreen subclasses overriding CSS instead of merging: {offenders}"


@pytest.mark.parametrize("has_existing,use_existing", [(False, False), (True, False), (True, True)])
def test_every_step_in_the_order_mounts_without_crashing(has_existing, use_existing):
    """Construct AND push every step name _current_order() can produce,
    for the three reachable (has_existing_hosts, use_existing_host)
    combinations. This is the test that would have caught 0.14.0's
    crash directly: run against that commit, it fails on "installing"
    with `AttributeError: 'InstallingScreen' object has no attribute
    'set_step'` — the exact error from the bare-metal bug report."""

    async def body():
        with patch(
            "installer.app.existing_hosts", return_value=(["fake-host"] if has_existing else [])
        ):
            app = InstallerApp()
            async with app.run_test() as pilot:
                app.state.use_existing_host = use_existing
                for step in app._current_order():
                    screen = app._make(step)
                    await app.push_screen(screen)
                    await pilot.pause()
                    await app.pop_screen()

    _run(body())


@pytest.mark.parametrize("has_existing,use_existing", [(False, False), (True, False), (True, True)])
def test_step_badge_numbering_is_contiguous(has_existing, use_existing):
    """set_step()'s (index, total) across every WizardScreen in the
    order must be exactly 1..N with no gaps or repeats, and must match
    the order's own length — a screen skipped in the order (e.g.
    host_mode with no existing profiles) but not accounted for in the
    numbering would show as a visible jump like "Step 2 of 10" then
    "Step 4 of 10". installing/done carry no badge at all (plain Screen,
    not WizardScreen) and are excluded, by design."""

    async def body():
        with patch(
            "installer.app.existing_hosts", return_value=(["fake-host"] if has_existing else [])
        ):
            app = InstallerApp()
            async with app.run_test():
                app.state.use_existing_host = use_existing
                order = app._current_order()
                indices = []
                totals = set()
                for step in order:
                    screen = app._make(step)
                    idx = getattr(screen, "_step_index", None)
                    if idx is None:
                        continue
                    indices.append(idx)
                    totals.add(screen._step_total)
                assert indices == list(range(1, len(indices) + 1)), indices
                assert totals == {len(order)}, (totals, len(order))

    _run(body())


def test_host_mode_skipped_when_no_existing_hosts():
    with patch("installer.app.existing_hosts", return_value=[]):
        app = InstallerApp.__new__(InstallerApp)
        InstallerApp.__init__(app)
        assert "host_mode" not in app._current_order()


def test_host_mode_shown_when_existing_hosts_present():
    with patch("installer.app.existing_hosts", return_value=["some-host"]):
        app = InstallerApp.__new__(InstallerApp)
        InstallerApp.__init__(app)
        assert "host_mode" in app._current_order()


def test_order_lists_have_no_duplicate_steps():
    assert len(InstallerApp._ORDER_NEW) == len(set(InstallerApp._ORDER_NEW))
    assert len(InstallerApp._ORDER_EXISTING) == len(set(InstallerApp._ORDER_EXISTING))


def test_every_order_step_is_in_the_screen_registry():
    """_make()'s registry dict must have an entry for every step name
    either order list can produce — a typo'd or renamed step in one but
    not the other is a KeyError waiting for whoever reaches that step."""
    app = InstallerApp.__new__(InstallerApp)
    with patch("installer.app.existing_hosts", return_value=["some-host"]):
        InstallerApp.__init__(app)

    async def body():
        async with app.run_test():
            for step in set(InstallerApp._ORDER_NEW) | set(InstallerApp._ORDER_EXISTING):
                app._make(step)  # raises KeyError if the registry is missing an entry

    _run(body())
