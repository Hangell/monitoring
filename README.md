
# 🖥️ Monitoring HUD (GTK3)

![Build](https://img.shields.io/badge/build-gcc%20success-brightgreen)
![GTK](https://img.shields.io/badge/GTK-3.24%2B-blue)
![Linux](https://img.shields.io/badge/Linux%20Mint-20%20|%2021%20|%2022-success)
![Ubuntu](https://img.shields.io/badge/Ubuntu-20.04%2B-orange)

Um monitor de **CPU** e **RAM** minimalista, transparente e flutuante, escrito em **C com GTK3**, feito para Linux (testado no **Linux Mint 22.2 Cinnamon**).

Exibe em tempo real o uso do processador e da memória no **canto superior direito** da tela principal — sem terminal e sem janelas visíveis.

---

## ⚙️ Compatibilidade

| Distribuição | Versão mínima | Status |
|---------------|----------------|--------|
| Linux Mint | 20 (Ulyana) | ✅ Suportado |
| Ubuntu | 20.04 (Focal Fossa) | ✅ Suportado |
| Debian | 11 (Bullseye) | ⚠️ Precisa GTK3 ≥ 3.24 |
| Fedora | 37+ | ⚠️ Testar dependências |
| Arch / Manjaro | Rolling | ✅ Suportado |

---

## 📸 Preview

*(Exemplo visual, janela transparente com CPU/RAM no canto superior direito)*

---

## 🧩 Requisitos

- **GTK3** (já vem no Mint, mas instale se necessário)
  ```bash
  sudo apt install libgtk-3-dev
  ```

- Compilador **GCC**
  ```bash
  sudo apt install build-essential
  ```

---

## 🧱 Compilação

```bash
git clone https://github.com/seuusuario/monitoring-hud.git
cd monitoring-hud
gcc main.c -o monitoring `pkg-config --cflags --libs gtk+-3.0`
```

---

## 🚀 Execução

```bash
./monitoring &
```

A janela aparecerá automaticamente no **topo direito do monitor principal**, mostrando CPU e RAM atualizados a cada segundo.

---

## 🎨 Personalização

| Configuração | Onde alterar | Valor padrão |
|----------------|---------------|---------------|
| Opacidade da janela | `gtk_widget_set_opacity(ui.window, 0.85);` | `0.85` |
| Margem da tela | `ui.margin = 10;` | `10 px` |
| Fonte e cor do texto | bloco CSS (`label { ... }`) | `FiraCode Nerd Font`, branco |
| Intervalo de atualização | `g_timeout_add(1000, update_stats, &ui);` | `1000 ms` |

---

## 🧠 Como funciona

- Lê `/proc/stat` e `/proc/meminfo` diretamente.
- Atualiza a cada segundo via `g_timeout_add`.
- Cria uma janela GTK sem bordas, transparente e flutuante.
- Posiciona automaticamente no **canto superior direito**.

---

## 🧰 Próximas melhorias

- [ ] Mostrar uso da **GPU** (NVIDIA/AMD)
- [ ] Exibir **temperatura da CPU**
- [ ] Modo dark/light automático
- [ ] Mostrar barras animadas de uso

---

## 📜 Licença

MIT © 2025 Rangel Hangell  
Feito com 💙 e C puro no Linux Mint.

---