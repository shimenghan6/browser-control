#!/bin/bash
set -e
echo "============================================="
echo "  browser-control - One-Click Install"
echo "============================================="

command -v node >/dev/null 2>&1 || { echo "[ERROR] Node.js not found."; exit 1; }
echo "[OK] Node.js"

command -v python3 >/dev/null 2>&1 || { echo "[ERROR] Python not found."; exit 1; }
echo "[OK] Python"

echo "[1/3] Installing Node.js packages..."
npm install -g agent-browser chrome-devtools-mcp

echo "[2/3] Installing Python packages..."
pip install nodriver cloakbrowser

echo "[3/3] Configuring agent-browser..."
echo '{ "headed": true }' > ~/agent-browser.json

echo ""
echo "============================================="
echo "  Done. Use with Claude Code: /browser-control"
echo "============================================="
