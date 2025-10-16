
# 🖥️ Monitoring HUD (GTK3)

![Build](https://img.shields.io/badge/build-gcc%20success-brightgreen)
![GTK](https://img.shields.io/badge/GTK-3.24%2B-blue)
![Linux](https://img.shields.io/badge/Linux%20Mint-20%20|%2021%20|%2022-success)
![Ubuntu](https://img.shields.io/badge/Ubuntu-20.04%2B-orange)
![License](https://img.shields.io/badge/license-MIT-lightgrey)

Um monitor de **CPU** e **RAM** minimalista, transparente e flutuante, escrito em **C com GTK3**, feito para Linux (testado no **Linux Mint 22.2 Cinnamon**).

Exibe em tempo real o uso do processador e da memória no **canto superior direito** da tela principal — sem terminal, sem janelas visíveis e com inicialização automática.

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

## 🚀 Instalação automática (recomendada)

Execute este comando no terminal:

```bash
bash -c "$(curl -fsSL https://raw.githubusercontent.com/Hangell/monitoring/main/install.sh)"
```

O script irá:
- Instalar dependências (`build-essential`, `libgtk-3-dev`);
- Compilar o binário em `~/bin/monitoring`;
- Criar o atalho de inicialização em `~/.config/autostart/`;
- Executar o HUD automaticamente.

✅ Após isso, ele abrirá sozinho sempre que você iniciar o sistema.

---

## 🧩 Requisitos (para compilação manual)

Se quiser compilar manualmente:

```bash
sudo apt install build-essential libgtk-3-dev pkg-config
```

---

## 🧱 Compilação manual

```bash
git clone https://github.com/Hangell/monitoring.git
cd monitoring
gcc main.c -o monitoring `pkg-config --cflags --libs gtk+-3.0`
```

---

## ▶️ Execução manual

```bash
./monitoring &
```

A janela aparecerá automaticamente no **topo direito do monitor principal**, mostrando CPU e RAM atualizados a cada segundo.

---

## 🧹 Desinstalar

```bash
bash -c "$(curl -fsSL https://raw.githubusercontent.com/Hangell/monitoring/main/uninstall.sh)"
```

Remove o binário, o autostart e encerra processos ativos do HUD.

---

## 🎨 Personalização

| Configuração | Onde alterar | Valor padrão |
|---------------|---------------|---------------|
| Opacidade da janela | `gtk_widget_set_opacity(ui.window, 0.85);` | `0.85` |
| Margem da tela | `ui.margin = 10;` | `10 px` |
| Fonte e cor do texto | bloco CSS (`label { ... }`) | `FiraCode Nerd Font`, branco |
| Intervalo de atualização | `g_timeout_add(1000, update_stats, &ui);` | `1000 ms` |

---

## 🧠 Como funciona

- Lê `/proc/stat` e `/proc/meminfo` diretamente;
- Atualiza a cada segundo via `g_timeout_add`;
- Usa `GTK_WINDOW_TYPE_HINT_DOCK` para manter-se **sempre sobreposto**;
- Não consome foco nem interfere em janelas abertas;
- Mantém o uso mínimo de recursos (<15 MB RAM e <0.5% CPU).

---

## 🧰 Próximas melhorias

- [ ] Mostrar uso da **GPU** (NVIDIA/AMD)
- [ ] Exibir **temperatura da CPU**
- [ ] Alternância automática Dark/Light Theme
- [ ] Barras animadas de uso

---

## 📜 Licença

MIT © 2025 **Rangel Hangell**  
Feito com 💙 e C puro no Linux Mint.

---