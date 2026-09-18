import os
import sys

if "--mock" in sys.argv:
    os.environ["GISNIX_INSTALLER_MOCK"] = "1"
    sys.argv.remove("--mock")

from .app import main  # noqa: E402 — must follow the env var above

if __name__ == "__main__":
    main()
