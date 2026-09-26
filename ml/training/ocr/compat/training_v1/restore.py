"""Route the archived training kernel's offline restore to the current verifier."""

import runpy
from pathlib import Path

if __name__ == "__main__":
    runpy.run_path(str(Path(__file__).resolve().parents[2] / "restore.py"), run_name="__main__")
