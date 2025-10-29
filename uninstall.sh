#!/usr/bin/env bash
set -euo pipefail

# Configurações
USER_HOME="${HOME}"
BIN_DIR="${USER_HOME}/.local/bin"
BIN_PATH="${BIN_DIR}/monitoring"
DESKTOP_PATH="${USER_HOME}/.config/autostart/monitoring.desktop"
LOCK_FILE="/tmp/monitoring_hud.lock"

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

# Verificar se o programa está instalado
check_installation() {
    local installed=false
    
    if [[ -f "$BIN_PATH" ]]; then
        log_info "Binário encontrado: $BIN_PATH"
        installed=true
    fi
    
    if [[ -f "$DESKTOP_PATH" ]]; then
        log_info "Arquivo de autostart encontrado: $DESKTOP_PATH"
        installed=true
    fi
    
    if ! $installed; then
        log_warning "Nenhuma instalação do Monitoring HUD foi encontrada."
        echo
        echo "Locais verificados:"
        echo "  • $BIN_PATH"
        echo "  • $DESKTOP_PATH"
        return 1
    fi
    
    return 0
}

# Parar instâncias em execução
stop_instances() {
    log_info "Parando instâncias em execução..."
    
    local pids=()
    
    # Encontra PIDs do processo
    while IFS= read -r pid; do
        pids+=("$pid")
    done < <(pgrep -f "monitoring" 2>/dev/null || true)
    
    if [[ ${#pids[@]} -eq 0 ]]; then
        log_info "Nenhuma instância em execução encontrada."
        return 0
    fi
    
    log_info "Encontradas ${#pids[@]} instância(s) em execução: ${pids[*]}"
    
    # Envia SIGTERM
    if kill "${pids[@]}" 2>/dev/null; then
        log_info "Sinal de término enviado aos processos..."
        
        # Aguarda um pouco para processos finalizarem
        local wait_time=3
        local count=0
        while [[ $count -lt $wait_time ]] && pgrep -f "monitoring" >/dev/null; do
            sleep 1
            ((count++))
        done
        
        # Se ainda estiver rodando, força com SIGKILL
        if pgrep -f "monitoring" >/dev/null; then
            log_warning "Processos ainda em execução, forçando término..."
            kill -9 "${pids[@]}" 2>/dev/null || true
            sleep 1
        fi
    fi
    
    # Verifica se ainda há processos
    if pgrep -f "monitoring" >/dev/null; then
        log_error "Não foi possível parar todas as instâncias."
        return 1
    else
        log_success "Todas as instâncias foram paradas."
    fi
    
    return 0
}

# Remover arquivos de lock
remove_lock_files() {
    log_info "Removendo arquivos de lock..."
    
    local lock_files=(
        "$LOCK_FILE"
        "/tmp/monitoring_hud.*"
    )
    
    for pattern in "${lock_files[@]}"; do
        if ls $pattern >/dev/null 2>&1; then
            rm -f $pattern
            log_info "Removido: $pattern"
        fi
    done
}

# Remover arquivos de instalação
remove_installation_files() {
    log_info "Removendo arquivos de instalação..."
    
    local files_removed=0
    local dirs_to_check=()
    
    # Lista de arquivos para remover
    local files=(
        "$BIN_PATH"
        "$DESKTOP_PATH"
        "${USER_HOME}/bin/monitoring"  # Localização antiga
    )
    
    # Lista de diretórios para verificar se ficaram vazios
    local dirs=(
        "$BIN_DIR"
        "${USER_HOME}/bin"
        "${USER_HOME}/.config/autostart"
    )
    
    # Remove arquivos
    for file in "${files[@]}"; do
        if [[ -f "$file" ]]; then
            if rm -f "$file"; then
                log_success "Removido: $file"
                ((files_removed++))
            else
                log_error "Falha ao remover: $file"
            fi
        fi
    done
    
    # Verifica diretórios vazios
    for dir in "${dirs[@]}"; do
        if [[ -d "$dir" ]] && [[ -z "$(ls -A "$dir" 2>/dev/null)" ]]; then
            log_info "Diretório vazio: $dir"
            # Não remove automaticamente por segurança
        fi
    done
    
    if [[ $files_removed -eq 0 ]]; then
        log_warning "Nenhum arquivo de instalação foi encontrado para remover."
    fi
    
    return $files_removed
}

# Verificar dependências removidas
check_remaining_dependencies() {
    log_info "Verificando dependências..."
    
    local deps=("gtk+-3.0" "gcc")
    local found_deps=()
    
    # Verifica pacotes development
    for dep in "${deps[@]}"; do
        if pkg-config --exists "$dep" 2>/dev/null; then
            found_deps+=("$dep")
        fi
    done
    
    if [[ ${#found_deps[@]} -gt 0 ]]; then
        log_warning "Dependências de desenvolvimento ainda instaladas:"
        for dep in "${found_deps[@]}"; do
            echo "  • $dep"
        done
        echo
        echo "Estas dependências podem ser removidas com:"
        echo "  sudo apt remove --auto-remove libgtk-3-dev build-essential"
    else
        log_success "Nenhuma dependência específica encontrada."
    fi
}

# Mostrar resumo da desinstalação
show_uninstall_summary() {
    echo
    echo -e "${GREEN}╔══════════════════════════════════════════════════════════════╗${NC}"
    echo -e "${GREEN}║                  DESINSTALAÇÃO CONCLUÍDA                    ║${NC}"
    echo -e "${GREEN}╚══════════════════════════════════════════════════════════════╝${NC}"
    echo
    echo -e "${BLUE}📋 Resumo:${NC}"
    echo -e "   • Instâncias do programa: ${GREEN}Paradas${NC}"
    echo -e "   • Arquivos de lock:        ${GREEN}Removidos${NC}"
    echo -e "   • Arquivos de instalação:  ${GREEN}Removidos${NC}"
    echo
    echo -e "${YELLOW}📍 Arquivos removidos:${NC}"
    [[ -f "$BIN_PATH" ]] || echo -e "   • ${BIN_PATH}"
    [[ -f "$DESKTOP_PATH" ]] || echo -e "   • ${DESKTOP_PATH}"
    [[ -f "${USER_HOME}/bin/monitoring" ]] || echo -e "   • ${USER_HOME}/bin/monitoring (localização antiga)"
    echo
    echo -e "${GREEN}✅ Monitoring HUD foi completamente removido do sistema${NC}"
}

# Confirmar desinstalação
confirm_uninstall() {
    echo -e "${YELLOW}╔══════════════════════════════════════════════════════════════╗${NC}"
    echo -e "${YELLOW}║                   DESINSTALAR MONITORING HUD                ║${NC}"
    echo -e "${YELLOW}╚══════════════════════════════════════════════════════════════╝${NC}"
    echo
    echo -e "Esta ação irá:"
    echo -e "  • Parar todas as instâncias do Monitoring HUD"
    echo -e "  • Remover o binário: ${BIN_PATH}"
    echo -e "  • Remover o autostart: ${DESKTOP_PATH}"
    echo -e "  • Limpar arquivos temporários"
    echo
    echo -e "${RED}⚠️  Esta operação não pode ser desfeita!${NC}"
    echo
    
    read -p "Tem certeza que deseja continuar? (s/N): " -n 1 -r
    echo
    if [[ ! $REPLY =~ ^[Ss]$ ]]; then
        echo -e "${GREEN}Desinstalação cancelada.${NC}"
        exit 0
    fi
    echo
}

# Função principal
main() {
    confirm_uninstall
    
    if ! check_installation; then
        log_error "Não é possível desinstalar - instalação não encontrada."
        exit 1
    fi
    
    stop_instances
    remove_lock_files
    remove_installation_files
    
    echo
    check_remaining_dependencies
    show_uninstall_summary
}

# Executar desinstalação
main "$@"