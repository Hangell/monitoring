#!/usr/bin/env bash
set -euo pipefail

# ===== Config =====
USER_HOME="${HOME}"
BIN_DIR="${USER_HOME}/bin"
AUTOSTART_DIR="${USER_HOME}/.config/autostart"
BIN_PATH="${BIN_DIR}/monitoring"
DESKTOP_PATH="${AUTOSTART_DIR}/monitoring.desktop"
SRC_FILE="${1:-./monitoring_hud.c}"   # passe o caminho do seu .c como argumento (ou deixe ./monitoring_hud.c)

# Temp dir com cleanup
SRC_DIR="$(mktemp -d)"
cleanup() { rm -rf "${SRC_DIR}"; }
trap cleanup EXIT

echo "[*] Preparando ambiente..."
mkdir -p "${BIN_DIR}" "${AUTOSTART_DIR}"

if ! command -v gcc >/dev/null 2>&1; then
  echo "[*] Instalando build tools (sudo)..."
  sudo apt update
  sudo apt install -y build-essential
fi

if ! pkg-config --exists gtk+-3.0; then
  echo "[*] Instalando GTK3 dev (sudo)..."
  sudo apt update
  sudo apt install -y libgtk-3-dev pkg-config
fi

# Verifica fonte
if [[ ! -f "${SRC_FILE}" ]]; then
  echo "[!] Fonte não encontrada: ${SRC_FILE}"
  exit 1
fi

echo "[*] Copiando fonte..."
cp -f "${SRC_FILE}" "${SRC_DIR}/main.c"

echo "[*] Compilando..."
# -O2 otimiza; -s remove símbolos; -lm por causa de math.h (round/floor, etc.)
gcc "${SRC_DIR}/main.c" -o "${BIN_PATH}" $(pkg-config --cflags --libs gtk+-3.0) -O2 -s -lm

echo "[*] Criando entrada de autostart..."
cat > "${DESKTOP_PATH}" <<EOF
[Desktop Entry]
Type=Application
Name=Monitoring HUD
Comment=Overlay transparente de CPU/RAM/TMP/GPU
Exec=${BIN_PATH} --click-through
Icon=utilities-system-monitor
Terminal=false
X-GNOME-Autostart-enabled=true
X-GNOME-Autostart-Delay=5
OnlyShowIn=X-Cinnamon;GNOME;XFCE;
EOF

chmod +x "${BIN_PATH}" "${DESKTOP_PATH}"

echo "[*] Iniciando agora..."
# Mata instância antiga (sua versão suporta --kill/--restart)
if "${BIN_PATH}" --kill >/dev/null 2>&1; then
  sleep 0.2
fi
nohup "${BIN_PATH}" >/dev/null 2>&1 &

echo "[✓] Instalado!"
echo "    Binário:   ${BIN_PATH}"
echo "    Autostart: ${DESKTOP_PATH}"
echo "    Ele iniciará automaticamente no próximo login."
