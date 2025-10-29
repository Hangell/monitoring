#!/usr/bin/env bash
set -euo pipefail

USER_HOME="${HOME}"
BIN_DIR="${USER_HOME}/.local/bin"
SRC_DIR="$(mktemp -d)"
AUTOSTART_DIR="${USER_HOME}/.config/autostart"
BIN_PATH="${BIN_DIR}/monitoring"
DESKTOP_PATH="${AUTOSTART_DIR}/monitoring.desktop"

# Cores para output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

# Funções de log
log_info() { echo -e "${BLUE}[*]${NC} $1"; }
log_success() { echo -e "${GREEN}[✓]${NC} $1"; }
log_warning() { echo -e "${YELLOW}[!]${NC} $1"; }
log_error() { echo -e "${RED}[✗]${NC} $1"; }

# Verificar se estamos no Wayland (não suportado)
check_wayland() {
    if [[ "${XDG_SESSION_TYPE:-}" == "wayland" ]]; then
        log_warning "Wayland detectado. Este aplicativo pode não funcionar corretamente no Wayland."
        log_warning "Recomendado usar X11 para melhor compatibilidade."
        read -p "Continuar mesmo assim? (s/N): " -n 1 -r
        echo
        if [[ ! $REPLY =~ ^[Ss]$ ]]; then
            exit 1
        fi
    fi
}

# Verificar dependências
check_dependencies() {
    local deps=("gcc" "pkg-config")
    local missing=()
    
    for dep in "${deps[@]}"; do
        if ! command -v "$dep" >/dev/null 2>&1; then
            missing+=("$dep")
        fi
    done
    
    if [[ ${#missing[@]} -gt 0 ]]; then
        log_info "Instalando dependências (requer sudo)..."
        sudo apt update
        sudo apt install -y build-essential libgtk-3-dev pkg-config
    fi
    
    # Verificar bibliotecas GTK
    if ! pkg-config --exists gtk+-3.0; then
        log_error "GTK+3 não encontrado após instalação. Abortando."
        exit 1
    fi
}

# Criar diretórios necessários
create_directories() {
    log_info "Criando diretórios..."
    mkdir -p "${BIN_DIR}" "${AUTOSTART_DIR}"
}

# Escrever código fonte completo
write_source_code() {
    log_info "Escrevendo código fonte..."
    cat > "${SRC_DIR}/main.c" <<'EOF'
#include <gtk/gtk.h>
#include <stdio.h>
#include <string.h>
#include <unistd.h>
#include <signal.h>
#include <sys/types.h>
#include <dirent.h>
#include <glob.h>
#include <stdlib.h>
#include <errno.h>
#include <math.h>

// ================== Config ==================
#define LOCK_FILE "/tmp/monitoring_hud.lock"
// ============================================

// ---------- Util ----------
static gboolean read_long_from_file(const char *path, long *out) {
    FILE *f = fopen(path, "r");
    if (!f) {
        return FALSE;
    }
    long v;
    int ok = (fscanf(f, "%ld", &v) == 1);
    fclose(f);
    if (!ok) return FALSE;
    *out = v;
    return TRUE;
}

static gboolean read_str_from_file(const char *path, char *buf, size_t bufsz) {
    FILE *f = fopen(path, "r");
    if (!f) return FALSE;
    if (!fgets(buf, (int)bufsz, f)) { fclose(f); return FALSE; }
    fclose(f);
    // strip \n
    size_t n = strlen(buf);
    if (n && buf[n-1] == '\n') buf[n-1] = '\0';
    return TRUE;
}

// ---------- Leitura de CPU/RAM ----------
static double get_cpu_usage() {
    static long prev_total = 0, prev_idle = 0;
    FILE* fp = fopen("/proc/stat", "r");
    if (!fp) return 0.0;
    char lbl[5];
    long user, nice, system, idle, iowait, irq, softirq;
    if (fscanf(fp, "%4s %ld %ld %ld %ld %ld %ld %ld",
               lbl, &user, &nice, &system, &idle, &iowait, &irq, &softirq) != 8) {
        fclose(fp); return 0.0;
    }
    fclose(fp);
    long total = user + nice + system + idle + iowait + irq + softirq;
    long diff_total = total - prev_total;
    long diff_idle  = idle  - prev_idle;
    double usage = (diff_total > 0) ? 100.0 * (diff_total - diff_idle) / diff_total : 0.0;
    prev_total = total; prev_idle = idle;
    return usage;
}

// Lê MemTotal/MemAvailable em kB
static gboolean get_mem_kb(long *total_kb, long *avail_kb) {
    FILE* fp = fopen("/proc/meminfo", "r");
    if (!fp) return FALSE;
    long total=0, available=0;
    char key[64]; long val; char kb[8];
    while (fscanf(fp, "%63s %ld %7s\n", key, &val, kb) == 3) {
        if (strcmp(key, "MemTotal:") == 0) total = val;
        else if (strcmp(key, "MemAvailable:") == 0) available = val;
        if (total && available) break;
    }
    fclose(fp);
    if (!total) return FALSE;
    if (total_kb) *total_kb = total;
    if (avail_kb) *avail_kb = available;
    return TRUE;
}

static double get_mem_percent() {
    long total=0, avail=0;
    if (!get_mem_kb(&total, &avail) || !total) return 0.0;
    return 100.0 * (double)(total - avail) / (double)total;
}

// ---------- Temperatura CPU (°C) ----------
static double get_cpu_temp_celsius() {
    glob_t g = {0};
    double best = -1.0;
    if (glob("/sys/class/thermal/thermal_zone*/type", 0, NULL, &g) == 0) {
        for (size_t i = 0; i < g.gl_pathc; i++) {
            char type[128];
            if (!read_str_from_file(g.gl_pathv[i], type, sizeof(type))) continue;

            char temp_path[256];
            strcpy(temp_path, g.gl_pathv[i]);
            char *p = strrchr(temp_path, '/');
            if (!p) continue;
            strcpy(p, "/temp");

            long millic = 0;
            if (read_long_from_file(temp_path, &millic)) {
                double c = (millic > 1000) ? (millic / 1000.0) : (double)millic;
                if (best < 0 ||
                    strcasestr(type, "x86_pkg_temp") ||
                    strcasestr(type, "package") ||
                    strcasestr(type, "cpu")) {
                    best = c;
                }
            }
        }
    }
    globfree(&g);

    if (best < 0) {
        if (glob("/sys/class/hwmon/hwmon*/temp*_input", 0, NULL, &g) == 0) {
            for (size_t i = 0; i < g.gl_pathc; i++) {
                long millic = 0;
                if (read_long_from_file(g.gl_pathv[i], &millic)) {
                    double c = (millic > 1000) ? (millic / 1000.0) : (double)millic;
                    if (c > best) best = c;
                }
            }
        }
        globfree(&g);
    }
    return best; // -1.0 se indisponível
}

// ---------- GPU: uso (%) e temperatura (°C) ----------
static gboolean get_gpu_nvidia(double *util, double *temp) {
    FILE *p = popen("nvidia-smi --query-gpu=utilization.gpu,temperature.gpu "
                    "--format=csv,noheader,nounits 2>/dev/null", "r");
    if (!p) return FALSE;
    
    char line[256];
    if (!fgets(line, sizeof(line), p)) {
        pclose(p);
        return FALSE;
    }
    
    pclose(p);
    
    // Tenta diferentes formatos de parsing
    double u = -1, t = -1;
    int ok = (sscanf(line, "%lf , %lf", &u, &t) == 2) ||
             (sscanf(line, "%lf %lf", &u, &t) == 2) ||
             (sscanf(line, "%lf%% , %lfC", &u, &t) == 2) ||
             (sscanf(line, "%lf %% , %lf C", &u, &t) == 2);
    
    if (!ok) return FALSE;
    
    // Valida os valores
    if (u < 0 || u > 100 || t < 0 || t > 120) return FALSE;
    
    if (util) *util = u;
    if (temp) *temp = t;
    return TRUE;
}

static gboolean get_gpu_amd(double *util, double *temp) {
    glob_t g = {0};
    gboolean found_util = FALSE, found_temp = FALSE;
    double u = -1, t = -1;

    // Busca uso da GPU AMD
    if (glob("/sys/class/drm/card*/device/gpu_busy_percent", 0, NULL, &g) == 0) {
        for (size_t i = 0; i < g.gl_pathc; i++) {
            long v = 0;
            if (read_long_from_file(g.gl_pathv[i], &v) && v >= 0 && v <= 100) {
                u = (double)v;
                found_util = TRUE;
                break;
            }
        }
        globfree(&g);
    }

    // Busca temperatura AMD
    g.gl_pathc = 0;
    if (glob("/sys/class/drm/card*/device/hwmon/hwmon*/temp1_input", 0, NULL, &g) == 0) {
        for (size_t i = 0; i < g.gl_pathc; i++) {
            long millic = 0;
            if (read_long_from_file(g.gl_pathv[i], &millic)) {
                t = millic / 1000.0;
                found_temp = TRUE;
                break;
            }
        }
        globfree(&g);
    }

    // Também tenta caminhos alternativos para temperatura AMD
    if (!found_temp) {
        g.gl_pathc = 0;
        if (glob("/sys/class/drm/card*/device/hwmon/hwmon*/temp2_input", 0, NULL, &g) == 0) {
            for (size_t i = 0; i < g.gl_pathc; i++) {
                long millic = 0;
                if (read_long_from_file(g.gl_pathv[i], &millic)) {
                    t = millic / 1000.0;
                    found_temp = TRUE;
                    break;
                }
            }
            globfree(&g);
        }
    }

    if (util) *util = u;
    if (temp) *temp = t;
    
    return found_util || found_temp;
}

// Nova função para detectar GPU Intel
static gboolean get_gpu_intel(double *util, double *temp) {
    glob_t g = {0};
    gboolean found = FALSE;
    double u = -1, t = -1;

    // Uso da GPU Intel (pode não estar disponível)
    if (glob("/sys/class/drm/card*/device/gt/gt*/freq0_cur_freq", 0, NULL, &g) == 0) {
        // Para Intel, não temos uso percentual fácil, mas podemos detectar a presença
        found = TRUE;
        globfree(&g);
    }

    // Temperatura Intel
    g.gl_pathc = 0;
    if (glob("/sys/class/drm/card*/device/hwmon/hwmon*/temp1_input", 0, NULL, &g) == 0) {
        for (size_t i = 0; i < g.gl_pathc; i++) {
            long millic = 0;
            if (read_long_from_file(g.gl_pathv[i], &millic)) {
                t = millic / 1000.0;
                found = TRUE;
                break;
            }
        }
        globfree(&g);
    }

    if (util) *util = u; // Intel geralmente não fornece uso percentual via sysfs
    if (temp) *temp = t;
    
    return found;
}

static gboolean get_gpu_usage_and_temp(double *util, double *temp) {
    static gboolean first_run = TRUE;
    
    // Tenta NVIDIA primeiro (mais confiável)
    if (get_gpu_nvidia(util, temp)) {
        if (first_run) {
            printf("GPU detectada: NVIDIA\n");
            first_run = FALSE;
        }
        return TRUE;
    }
    
    // Tenta AMD
    if (get_gpu_amd(util, temp)) {
        if (first_run) {
            printf("GPU detectada: AMD\n");
            first_run = FALSE;
        }
        return TRUE;
    }
    
    // Tenta Intel
    if (get_gpu_intel(util, temp)) {
        if (first_run) {
            printf("GPU detectada: Intel\n");
            first_run = FALSE;
        }
        return TRUE;
    }
    
    return FALSE;
}

// ---------- Lock / instância única ----------
static pid_t read_running_pid() {
    FILE *f = fopen(LOCK_FILE, "r");
    if (!f) return -1;
    long pid = -1;
    if (fscanf(f, "%ld", &pid) != 1) pid = -1;
    fclose(f);
    return (pid_t)pid;
}

static gboolean pid_alive(pid_t pid) {
    if (pid <= 1) return FALSE;
    return kill(pid, 0) == 0;
}

static gboolean write_lockfile() {
    FILE *f = fopen(LOCK_FILE, "w");
    if (!f) return FALSE;
    fprintf(f, "%ld\n", (long)getpid());
    fclose(f);
    return TRUE;
}

static void remove_lockfile() { unlink(LOCK_FILE); }

static gboolean kill_running() {
    pid_t pid = read_running_pid();
    if (pid_alive(pid)) {
        if (kill(pid, SIGTERM) == 0) return TRUE;
    }
    return FALSE;
}

// ---------- UI ----------
typedef struct {
    GtkWidget *window;
    GtkWidget *event_box; // para captar clique
    GtkWidget *label;
    int margin_top;
    int margin_right;
    gboolean click_through;
    gboolean ram_show_bytes; // toggle RAM: % <-> GB
} UiCtx;

// Declaração antecipada da função update_stats
static gboolean update_stats(gpointer user_data);

static void position_top_right_primary(UiCtx *ctx) {
    GdkDisplay *display = gdk_display_get_default();
    if (!display) return;
    GdkMonitor *mon = gdk_display_get_primary_monitor(display);
    if (!mon) return;

    GtkAllocation a; gtk_widget_get_allocation(ctx->window, &a);

#if GTK_CHECK_VERSION(3,22,0)
    GdkRectangle wa;
    gdk_monitor_get_workarea(mon, &wa);
    int x = wa.x + wa.width  - a.width  - ctx->margin_right;
    int y = wa.y + ctx->margin_top;
#else
    GdkRectangle r; gdk_monitor_get_geometry(mon, &r);
    int x = r.x + r.width  - a.width  - ctx->margin_right;
    int y = r.y + ctx->margin_top;
#endif
    gtk_window_move(GTK_WINDOW(ctx->window), x, y);
}

static gboolean on_size_allocate(GtkWidget *w, GdkRectangle *alloc, gpointer user_data) {
    position_top_right_primary((UiCtx*)user_data);
    return FALSE;
}

static void on_realize(GtkWidget *w, gpointer user_data) {
#if GTK_CHECK_VERSION(3,8,0)
    UiCtx *ctx = (UiCtx*)user_data;
    if (ctx->click_through) {
        GdkWindow *gw = gtk_widget_get_window(w);
        if (gw) gdk_window_set_pass_through(gw, TRUE);
    }
#endif
}

static gboolean on_click(GtkWidget *widget, GdkEventButton *event, gpointer user_data) {
    if (event->type == GDK_BUTTON_PRESS && event->button == 1) {
        UiCtx *ctx = (UiCtx*)user_data;
        ctx->ram_show_bytes = !ctx->ram_show_bytes;
        // Força atualização imediata chamando update_stats
        update_stats(ctx);
    }
    return FALSE; // Não propaga o evento
}

static gboolean update_stats(gpointer user_data) {
    UiCtx *ctx = (UiCtx*)user_data;
    if (!ctx || !ctx->label) return TRUE;

    double cpu = get_cpu_usage();
    double ram_pct = get_mem_percent();
    long total_kb = 0, avail_kb = 0;
    get_mem_kb(&total_kb, &avail_kb);
    long used_kb = (total_kb > 0) ? (total_kb - avail_kb) : 0;

    double cpu_temp = get_cpu_temp_celsius();
    double gpu_util = -1, gpu_temp = -1;
    gboolean has_gpu = get_gpu_usage_and_temp(&gpu_util, &gpu_temp);

    char left1[64], right1[64], left2[64], right2[64];
    char text[256];

    g_snprintf(left1, sizeof(left1), "💻 CPU: %.1f%%", cpu);

    if (ctx->ram_show_bytes && total_kb > 0) {
        double used_gb = used_kb / (1024.0 * 1024.0);
        double total_gb = total_kb / (1024.0 * 1024.0);
        g_snprintf(left2, sizeof(left2), "🧠 RAM: %.1f/%.1f GB", used_gb, total_gb);
    } else {
        g_snprintf(left2, sizeof(left2), "🧠 RAM: %.1f%%", ram_pct);
    }

    // Mostra segunda coluna apenas se temos ambos GPU e temperatura
    gboolean show_right_col = (has_gpu && gpu_util >= 0 && cpu_temp >= 0);

    if (show_right_col) {
        g_snprintf(right1, sizeof(right1), "🌡 TMP: %.0f°C", cpu_temp);
        g_snprintf(right2, sizeof(right2), "🎮 GPU: %.0f%%", gpu_util);
        g_snprintf(text, sizeof(text), "%-18s   %-14s\n%-18s   %-14s",
                   left1, right1, left2, right2);
    } else {
        // Mostra apenas temperatura da CPU se disponível
        if (cpu_temp >= 0) {
            g_snprintf(right1, sizeof(right1), "🌡 TMP: %.0f°C", cpu_temp);
            g_snprintf(text, sizeof(text), "%-18s   %-14s\n%s",
                       left1, right1, left2);
        } else {
            g_snprintf(text, sizeof(text), "%s\n%s", left1, left2);
        }
    }

    gtk_label_set_text(GTK_LABEL(ctx->label), text);
    return TRUE;
}

int main(int argc, char *argv[]) {
    gboolean flag_kill = FALSE, flag_restart = FALSE, flag_click_through = FALSE;
    for (int i = 1; i < argc; i++) {
        if (!strcmp(argv[i], "--kill")) flag_kill = TRUE;
        else if (!strcmp(argv[i], "--restart")) flag_restart = TRUE;
        else if (!strcmp(argv[i], "--click-through")) flag_click_through = TRUE;
    }

    if (flag_kill) {
        if (kill_running())
            fprintf(stdout, "monitoring: processo antigo finalizado.\n");
        else
            fprintf(stdout, "monitoring: nenhum processo ativo encontrado.\n");
        return 0;
    }

    pid_t old = read_running_pid();
    if (pid_alive(old)) {
        if (flag_restart) { kill_running(); usleep(250 * 1000); }
        else {
            fprintf(stderr, "monitoring já está em execução (pid %ld). Use --kill ou --restart.\n", (long)old);
            return 1;
        }
    }
    if (!write_lockfile()) { fprintf(stderr, "monitoring: não foi possível criar lockfile.\n"); return 1; }

    atexit(remove_lockfile);
    signal(SIGTERM, (void (*)(int))exit);
    signal(SIGINT,  (void (*)(int))exit);

    gtk_init(&argc, &argv);

    UiCtx ui = {0};
    ui.margin_top = 5;
    ui.margin_right = 100;
    ui.click_through = flag_click_through;
    ui.ram_show_bytes = FALSE;

    ui.window = gtk_window_new(GTK_WINDOW_TOPLEVEL);
    gtk_window_set_type_hint(GTK_WINDOW(ui.window), GDK_WINDOW_TYPE_HINT_DOCK);
    gtk_window_stick(GTK_WINDOW(ui.window));
    gtk_window_set_accept_focus(GTK_WINDOW(ui.window), FALSE);
    gtk_window_set_focus_on_map(GTK_WINDOW(ui.window), FALSE);
    gtk_widget_set_can_focus(ui.window, FALSE);
    gtk_window_set_title(GTK_WINDOW(ui.window), "Monitoring HUD");
    gtk_window_set_decorated(GTK_WINDOW(ui.window), FALSE);
    gtk_window_set_keep_above(GTK_WINDOW(ui.window), TRUE);
    gtk_window_set_resizable(GTK_WINDOW(ui.window), FALSE);
    gtk_window_set_skip_taskbar_hint(GTK_WINDOW(ui.window), TRUE);
    gtk_window_set_skip_pager_hint(GTK_WINDOW(ui.window), TRUE);
    gtk_widget_set_app_paintable(ui.window, TRUE);
    gtk_widget_set_opacity(ui.window, 0.85);

    GdkScreen *screen = gdk_screen_get_default();
    if (screen) {
        GdkVisual *visual = gdk_screen_get_rgba_visual(screen);
        if (visual) gtk_widget_set_visual(ui.window, visual);
    }

    GtkCssProvider *prov = gtk_css_provider_new();
    const char *css =
        "window { background-color: rgba(0,0,0,0.0); }"
        "label { font: 11pt \"FiraCode Nerd Font\", Monospace; color: #FFFFFF; }";
    gtk_css_provider_load_from_data(prov, css, -1, NULL);
    gtk_style_context_add_provider_for_screen(screen,
        GTK_STYLE_PROVIDER(prov), GTK_STYLE_PROVIDER_PRIORITY_APPLICATION);
    g_object_unref(prov);

    GtkWidget *box = gtk_box_new(GTK_ORIENTATION_VERTICAL, 6);
    gtk_container_add(GTK_CONTAINER(ui.window), box);

    // EventBox para capturar clique e alternar RAM
    ui.event_box = gtk_event_box_new();
    gtk_box_pack_start(GTK_BOX(box), ui.event_box, TRUE, TRUE, 0);
    gtk_widget_add_events(ui.event_box, GDK_BUTTON_PRESS_MASK);
    g_signal_connect(ui.event_box, "button-press-event", G_CALLBACK(on_click), &ui);

    ui.label = gtk_label_new("Carregando...");
    gtk_label_set_justify(GTK_LABEL(ui.label), GTK_JUSTIFY_LEFT);
    gtk_label_set_xalign(GTK_LABEL(ui.label), 0.0);
    gtk_label_set_yalign(GTK_LABEL(ui.label), 0.5);
    gtk_container_add(GTK_CONTAINER(ui.event_box), ui.label);

    g_signal_connect(ui.window, "size-allocate", G_CALLBACK(on_size_allocate), &ui);
    g_signal_connect(ui.window, "realize", G_CALLBACK(on_realize), &ui);

    g_timeout_add(1000, update_stats, &ui);
    update_stats(&ui);

    gtk_widget_show_all(ui.window);
    gtk_main();
    return 0;
}
EOF
}

# Compilar o programa
compile_program() {
    log_info "Compilando programa..."
    if gcc "${SRC_DIR}/main.c" -o "${BIN_PATH}" $(pkg-config --cflags --libs gtk+-3.0); then
        log_success "Compilação concluída com sucesso"
    else
        log_error "Falha na compilação"
        exit 1
    fi
    
    chmod +x "${BIN_PATH}"
}

# Criar entrada de autostart
create_autostart() {
    log_info "Criando entrada de autostart..."
    cat > "${DESKTOP_PATH}" <<EOF
[Desktop Entry]
Type=Application
Name=Monitoring HUD
Comment=Transparent CPU/RAM/GPU/Temperature overlay at top right
Exec=${BIN_PATH}
Icon=utilities-system-monitor
Terminal=false
X-GNOME-Autostart-enabled=true
X-GNOME-Autostart-Delay=5
OnlyShowIn=XFCE;GNOME;X-Cinnamon;MATE;
EOF

    chmod +x "${DESKTOP_PATH}"
}

# Iniciar o programa
start_program() {
    log_info "Iniciando o programa..."
    # Mata instâncias anteriores
    if pgrep -f "monitoring" > /dev/null; then
        log_info "Parando instâncias anteriores..."
        pkill -f "monitoring" || true
        sleep 1
    fi
    
    # Inicia nova instância
    nohup "${BIN_PATH}" >/dev/null 2>&1 &
    sleep 2
    
    # Verifica se está rodando
    if pgrep -f "monitoring" > /dev/null; then
        log_success "Programa iniciado com sucesso"
    else
        log_warning "Programa pode não ter iniciado corretamente"
    fi
}

# Mostrar informações finais
show_summary() {
    log_success "Instalação concluída!"
    echo
    echo -e "${GREEN}╔══════════════════════════════════════════════════════════════╗${NC}"
    echo -e "${GREEN}║                     MONITORING HUD INSTALADO                 ║${NC}"
    echo -e "${GREEN}╚══════════════════════════════════════════════════════════════╝${NC}"
    echo
    echo -e "${BLUE}📁 Binário:${NC}          ${BIN_PATH}"
    echo -e "${BLUE}🚀 Autostart:${NC}        ${DESKTOP_PATH}"
    echo
    echo -e "${YELLOW}🛠️  Funcionalidades:${NC}"
    echo -e "   • Monitoramento de CPU e RAM"
    echo -e "   • Temperatura da CPU"
    echo -e "   • Uso e temperatura da GPU (NVIDIA/AMD/Intel)"
    echo -e "   • Clique para alternar entre % e GB da RAM"
    echo -e "   • Interface transparente e sempre visível"
    echo
    echo -e "${YELLOW}🎮 Comandos úteis:${NC}"
    echo -e "   ${BIN_PATH} --kill       # Parar o programa"
    echo -e "   ${BIN_PATH} --restart    # Reiniciar o programa"  
    echo -e "   ${BIN_PATH} --click-through # Modo click-through"
    echo
    echo -e "${GREEN}✅ O programa iniciará automaticamente no próximo login${NC}"
}

# Limpeza
cleanup() {
    log_info "Limpando arquivos temporários..."
    rm -rf "${SRC_DIR}"
}

# Função principal
main() {
    echo -e "${BLUE}╔══════════════════════════════════════════════════════════════╗${NC}"
    echo -e "${BLUE}║                   INSTALADOR MONITORING HUD                 ║${NC}"
    echo -e "${BLUE}╚══════════════════════════════════════════════════════════════╝${NC}"
    echo
    
    check_wayland
    check_dependencies
    create_directories
    write_source_code
    compile_program
    create_autostart
    start_program
    show_summary
    cleanup
}

# Executar instalação
main "$@"