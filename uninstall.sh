#!/usr/bin/env bash
set -euo pipefail

BIN_PATH="${HOME}/bin/monitoring"
DESKTOP_PATH="${HOME}/.config/autostart/monitoring.desktop"

echo "[*] Stopping running instances..."
pkill -f "${BIN_PATH}" || true

echo "[*] Removing files..."
rm -f "${BIN_PATH}" "${DESKTOP_PATH}"

echo "[✓] Uninstalled."
