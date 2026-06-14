#!/usr/bin/env bash
#
# bootstrap.sh — generate BlindSpot.xcodeproj from source and open it in Xcode.
#
# Usage:
#   ./bootstrap.sh
#
# What it does:
#   1. Ensures XcodeGen is installed (via Homebrew).
#   2. Generates BlindSpot.xcodeproj from project.yml.
#   3. Opens the project in Xcode.
#
set -euo pipefail

cd "$(dirname "$0")"

# 1. Make sure XcodeGen is available.
if ! command -v xcodegen >/dev/null 2>&1; then
  echo "→ XcodeGen not found."
  if command -v brew >/dev/null 2>&1; then
    echo "→ Installing XcodeGen via Homebrew…"
    brew install xcodegen
  else
    echo "✗ Homebrew not found. Install it first:"
    echo '    /bin/bash -c "$(curl -fsSL https://raw.githubusercontent.com/Homebrew/install/HEAD/install.sh)"'
    echo "  Then re-run ./bootstrap.sh"
    exit 1
  fi
fi

# 2. Generate the Xcode project from project.yml.
echo "→ Generating BlindSpot.xcodeproj…"
xcodegen generate

# 3. Open it.
echo "→ Opening in Xcode…"
open BlindSpot.xcodeproj

echo "✓ Done. In Xcode: select your iPhone, set your signing Team in"
echo "  'Signing & Capabilities', then press ⌘R to run on device."
