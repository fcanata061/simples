#!/bin/bash
set -euo pipefail
source config.sh

# Cores
RED='\033[0;31m'; GREEN='\033[0;32m'; YELLOW='\033[1;33m'; BLUE='\033[0;34m'; NC='\033[0m'

mkdir -p "$WORK" "$LOGS" "$REPO" "$INSTALL"
touch "$DB"

spinner() {
    local pid=$1
    local log_file=$2
    local delay=0.1
    local spinstr='|/-\'
    while kill -0 "$pid" 2>/dev/null; do
        local temp=${spinstr#?}
        printf " [%c] \r" "$spinstr"
        spinstr=$temp${spinstr%"$temp"}
        sleep $delay
    done
    printf "\r"
}

run_logged() {
    local desc=$1
    local cmd=$2
    local log_file="$LOGS/${desc// /_}.log"
    echo -ne "${BLUE}==>${NC} $desc... "
    bash -c "$cmd" &> "$log_file" &
    local pid=$!
    spinner $pid "$log_file"
    wait $pid
    echo -e "${GREEN}OK${NC} ($desc)"
}

sync_repo() {
    if [ ! -d "$REPO/.git" ]; then
        echo -e "${YELLOW}Clonando repo em $REPO${NC}"
        git clone <URL_DO_SEU_REPO> "$REPO"
    else
        echo -e "${YELLOW}Atualizando repo em $REPO${NC}"
        git -C "$REPO" fetch --all
        git -C "$REPO" reset --hard origin/main
    fi
}

register_package() {
    local name=$1
    local version=$2
    local files=$3
    echo "$name|$version|$(date '+%Y-%m-%d %H:%M:%S')|$files" >> "$DB"
}

unregister_package() {
    local name=$1
    grep -v "^$name|" "$DB" > "$DB.tmp" && mv "$DB.tmp" "$DB"
}

list_installed() {
    if [ ! -s "$DB" ]; then
        echo "Nenhum pacote instalado."
    else
        cat "$DB"
    fi
}

search_package() {
    local term=$1
    grep -i "$term" recipes/*.sh
}

info_package() {
    local name=$1
    grep "^$name|" "$DB" || echo "Pacote não instalado."
}

remove_package() {
    local name=$1
    local line=$(grep "^$name|" "$DB" || true)
    if [ -z "$line" ]; then
        echo "Pacote não instalado."
        return
    fi
    local files=$(echo "$line" | cut -d'|' -f4)
    for f in $files; do
        rm -rf "$INSTALL/$f"
    done
    unregister_package "$name"
    echo "Pacote $name removido."
}

# Verifica argumentos
if [ $# -lt 2 ]; then
    echo -e "${RED}Uso: $0 <recipe> <fase|all|sync|remove|search|info>${NC}"
    exit 1
fi

RECIPE="$1"
PHASE="$2"

if [ "$PHASE" != "sync" ] && [ "$PHASE" != "remove" ] && [ "$PHASE" != "search" ] && [ "$PHASE" != "info" ]; then
    if [ ! -f "recipes/$RECIPE" ]; then
        echo -e "${RED}Recipe $RECIPE não encontrado!${NC}"
        exit 1
    fi
    source "recipes/$RECIPE"
fi

case "$PHASE" in
    sync) sync_repo ;;
    fetch) fetch ;;
    extract) extract ;;
    patch) patch_sources ;;
    build) build ;;
    package) package ;;
    all) fetch; extract; patch_sources; build; package ;;
    remove) remove_package "$RECIPE" ;;
    search) search_package "$RECIPE" ;;
    info) info_package "$RECIPE" ;;
    *) echo -e "${RED}Fase inválida${NC}" ; exit 1 ;;
esac
