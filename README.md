# it-rammanager

## Python Qt6 App

This refactors the original `base/ram_manager.sh` TUI into a PyQt6 desktop app that:
- Lists top RAM-consuming processes (top 10)
- Allows selecting processes to terminate
- Tries SIGTERM, then SIGKILL if needed
- Shows before/after RAM summary

### Requirements

- Python 3.10+
- macOS (developed for macOS)

Install dependencies:

```bash
python3 -m venv .venv
source .venv/bin/activate
pip install -r requirements.txt
```

### Run

```bash
python qt_app/main.py
```

If some processes fail to terminate due to permissions, run the app from a terminal with elevated privileges where appropriate.

### Build macOS .app

This uses PyInstaller to create a standalone `.app` bundle.

```bash
chmod +x scripts/build_macos.sh
scripts/build_macos.sh
```

The bundle will be at `dist/IT RAM Manager.app`.
