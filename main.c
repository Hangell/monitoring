#include <gtk/gtk.h>
#include <stdio.h>

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

static double get_mem_percent() {
    FILE* fp = fopen("/proc/meminfo", "r");
    if (!fp) return 0.0;
    long total=0, available=0;
    char key[64]; long val; char kb[8];
    while (fscanf(fp, "%63s %ld %7s\n", key, &val, kb) == 3) {
        if (strcmp(key, "MemTotal:") == 0) total = val;
        else if (strcmp(key, "MemAvailable:") == 0) available = val;
        if (total && available) break;
    }
    fclose(fp);
    if (!total) return 0.0;
    return 100.0 * (double)(total - available) / (double)total;
}

// ---------- UI ----------
typedef struct {
    GtkWidget *window;
    GtkWidget *label;
    int margin;
} UiCtx;

static void position_top_right_primary(UiCtx *ctx) {
    GdkDisplay *display = gdk_display_get_default();
    if (!display) return;
    GdkMonitor *mon = gdk_display_get_primary_monitor(display);
    if (!mon) return;

    // tamanho do label já alocado
    GtkAllocation a; gtk_widget_get_allocation(ctx->window, &a);

    GdkRectangle r; gdk_monitor_get_geometry(mon, &r);
    int x = r.x + r.width  - a.width  - ctx->margin;
    int y = r.y + ctx->margin;

    gtk_window_move(GTK_WINDOW(ctx->window), x, y);
}

static gboolean on_size_allocate(GtkWidget *w, GdkRectangle *alloc, gpointer user_data) {
    position_top_right_primary((UiCtx*)user_data);
    return FALSE;
}

static gboolean update_stats(gpointer user_data) {
    UiCtx *ctx = (UiCtx*)user_data;
    char text[128];
    g_snprintf(text, sizeof(text), "💻 CPU: %.1f%%\n🧠 RAM: %.1f%%",
               get_cpu_usage(), get_mem_percent());
    gtk_label_set_text(GTK_LABEL(ctx->label), text);
    // continua chamando
    return TRUE; 
}

int main(int argc, char *argv[]) {
    gtk_init(&argc, &argv);

    UiCtx ui = {0};
    ui.margin = 10;

    ui.window = gtk_window_new(GTK_WINDOW_TOPLEVEL);
    gtk_window_set_type_hint(GTK_WINDOW(ui.window), GDK_WINDOW_TYPE_HINT_DOCK); // janela tipo dock (acima das apps)
    gtk_window_stick(GTK_WINDOW(ui.window));        // fica em todas as workspaces
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

    // RGBA (transparência verdadeira, se disponível)
    GdkScreen *screen = gdk_screen_get_default();
    if (screen) {
        GdkVisual *visual = gdk_screen_get_rgba_visual(screen);
        if (visual) gtk_widget_set_visual(ui.window, visual);
    }

    // CSS: fonte e cores (substitui gtk_widget_override_font)
    GtkCssProvider *prov = gtk_css_provider_new();
    const char *css =
        "window { background-color: rgba(0,0,0,0.0); }"
        "label { font: 11pt \"FiraCode Nerd Font\", Monospace; color: #FFFFFF; }";
    gtk_css_provider_load_from_data(prov, css, -1, NULL);
    gtk_style_context_add_provider_for_screen(screen,
        GTK_STYLE_PROVIDER(prov), GTK_STYLE_PROVIDER_PRIORITY_APPLICATION);
    g_object_unref(prov);

    // Conteúdo
    GtkWidget *box = gtk_box_new(GTK_ORIENTATION_VERTICAL, 6);
    gtk_container_add(GTK_CONTAINER(ui.window), box);

    ui.label = gtk_label_new("Carregando...");
    gtk_label_set_justify(GTK_LABEL(ui.label), GTK_JUSTIFY_LEFT);
    gtk_box_pack_start(GTK_BOX(box), ui.label, TRUE, TRUE, 0);

    // Reposiciona no canto direito quando a janela mudar de tamanho/for exibida
    g_signal_connect(ui.window, "size-allocate", G_CALLBACK(on_size_allocate), &ui);

    // Timer de atualização (1s)
    g_timeout_add(1000, update_stats, &ui);
    update_stats(&ui);

    gtk_widget_show_all(ui.window);
    gtk_main();
    return 0;
}
