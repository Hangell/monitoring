# Simple Makefile for Monitoring HUD
PREFIX ?= $(HOME)
BIN_DIR := $(PREFIX)/bin
BIN := $(BIN_DIR)/monitoring

all: build

build:
	mkdir -p $(BIN_DIR)
	gcc main.c -o $(BIN) `pkg-config --cflags --libs gtk+-3.0`

run: build
	$(BIN) &

install: build autostart

autostart:
	mkdir -p $(HOME)/.config/autostart
	printf "%s\n" \
"[Desktop Entry]" \
"Type=Application" \
"Name=Monitoring HUD" \
"Comment=Transparent CPU/RAM overlay at top right" \
"Exec=$(BIN)" \
"Icon=utilities-system-monitor" \
"Terminal=false" \
"X-GNOME-Autostart-enabled=true" \
"X-GNOME-Autostart-Delay=5" \
"OnlyShowIn=X-Cinnamon;GNOME;XFCE;" \
	> $(HOME)/.config/autostart/monitoring.desktop
	chmod +x $(HOME)/.config/autostart/monitoring.desktop

uninstall:
	pkill -f "$(BIN)" || true
	rm -f $(BIN) $(HOME)/.config/autostart/monitoring.desktop
