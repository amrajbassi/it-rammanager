#!/bin/zsh

set -euo pipefail

ROOT_DIR="$(cd "$(dirname "$0")/.." && pwd)"
cd "$ROOT_DIR"

if [ ! -d .venv ]; then
  python3 -m venv .venv
fi
source .venv/bin/activate

pip install --upgrade pip
pip install -r requirements.txt
pip install pyinstaller

pyinstaller -y it-rammanager.spec

echo "\nBuild complete: dist/IT RAM Manager.app"


