"""Forces --mock before any installer module is imported anywhere in this
suite, so nothing here touches a real disk, curl's out to the network, or
shells out for real ISO-only operations (setfont, mkpasswd's real hashing
path, disko/nixos-install). Must run before the first `import installer...`
in any test module — conftest.py is collected first, which is what makes
that guarantee hold."""

import os

os.environ.setdefault("GISNIX_INSTALLER_MOCK", "1")
