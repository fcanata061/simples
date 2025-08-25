#!/bin/bash
set -euo pipefail
source config.sh

# ----------------- Cores -----------------
RED='\033[0;31m'; GREEN='\033[0;32m'; YELLOW='\033[1;33m'
BLUE='\033[0;34m'; CYAN='\033[0;36m'; NC='\033[0m'

# ----------------- Spinner -----------------
spinner() {
    local pid=$1
    local delay=0.1
    local spinstr='|/-\'
    while kill -0 "$pid" 2>/dev/null; do
        local temp=${spinstr#?}
        printf " ${CYAN}[%c]${NC} \r" "$spinstr"
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
    local status=$?
    if [ $status -eq 0 ]; then
        echo -e "${GREEN}OK${NC} ($desc)"
    else
        echo -e "${RED}FALHA${NC} ($desc) - Veja log: $log_file"
        exit 1
    fi
}

# ----------------- Diretórios -----------------
mkdir -p "$WORK" "$LOGS" "$REPO" "$INSTALL"
touch "$DB"

# ----------------- Funções de registro -----------------
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
    [ -s "$DB" ] && cat "$DB" || echo "Nenhum pacote instalado."
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
    [ -z "$line" ] && { echo "Pacote não instalado."; return; }
    local files=$(echo "$line" | cut -d'|' -f4)
    for f in $files; do
        rm -rf "$INSTALL/$f"
    done
    unregister_package "$name"
    echo -e "${YELLOW}Pacote $name removido.${NC}"
}

# ----------------- Sincronização do repo -----------------
sync_repo() {
    if [ ! -d "$REPO/.git" ]; then
        echo -e "${BLUE}Clonando repositório...${NC}"
        git clone <URL_DO_SEU_REPO> "$REPO"
    else
        echo -e "${BLUE}Atualizando repositório...${NC}"
        git -C "$REPO" fetch --all
        git -C "$REPO" reset --hard origin/main
    fi
}

# ----------------- Validação de argumentos -----------------
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

SRC_DIR="$WORK/$NAME-$VERSION"
DESTDIR="$INSTALL/$NAME-$VERSION"

# ----------------- Funções padrão -----------------
default_fetch() {
    mkdir -p "$WORK"
    for url in "${SRC_URLS[@]}"; do
        if curl -L --fail -o "$WORK/$(basename $url)" "$url"; then
            echo -e "${GREEN}Download bem-sucedido: $url${NC}"
            return
        fi
    done
    echo -e "${RED}Falha em todos os downloads!${NC}"
    exit 1
}

default_extract() {
    mkdir -p "$SRC_DIR"
    local archive=$(ls "$WORK" | grep "$NAME" | head -n1)
    case "$archive" in
        *.tar.gz) tar -xzf "$WORK/$archive" -C "$SRC_DIR" --strip-components=1 ;;
        *.tar.bz2) tar -xjf "$WORK/$archive" -C "$SRC_DIR" --strip-components=1 ;;
        *.tar.xz) tar -xJf "$WORK/$archive" -C "$SRC_DIR" --strip-components=1 ;;
        *.zip) unzip "$WORK/$archive" -d "$SRC_DIR" ;;
        *) echo -e "${RED}Formato desconhecido!${NC}" ; exit 1 ;;
    esac
    echo -e "${GREEN}Extração concluída.${NC}"
}

default_patch() {
    local patch_dir="$REPO/base/$NAME/patch"
    [ -d "$patch_dir" ] || return
    cd "$SRC_DIR"
    for p in $(ls "$patch_dir"/*.patch 2>/dev/null | sort); do
        echo -e "${YELLOW}Aplicando patch $p${NC}"
        patch -p1 < "$p"
    done
}

default_build() {
    cd "$SRC_DIR"
    mkdir -p build && cd build
    ../configure --prefix=/usr &> "$LOGS/${NAME}_configure.log"
    make -j"$PARALLEL" &> "$LOGS/${NAME}_make.log"
    if make -q check 2>/dev/null; then
        echo -e "${YELLOW}Executando testes...${NC}"
        make -k check -j"$PARALLEL" &> "$LOGS/${NAME}_test.log"
    fi
    if [ "$USE_FAKEROOT" -eq 1 ]; then
        fakeroot make DESTDIR="$DESTDIR" install &> "$LOGS/${NAME}_install.log"
    else
        make DESTDIR="$DESTDIR" install &> "$LOGS/${NAME}_install.log"
    fi
}

default_package() {
    tar -czf "$WORK/${NAME}-${VERSION}.tar.gz" -C "$DESTDIR" .
    register_package "$NAME" "$VERSION" "$NAME-$VERSION"
    echo -e "${GREEN}Pacote $NAME gerado: $WORK/${NAME}-${VERSION}.tar.gz${NC}"
}

# ----------------- Execução das fases -----------------
case "$PHASE" in
    sync) sync_repo ;;
    fetch) run_logged "fetch $NAME" "${fetch:-default_fetch}" ;;
    extract) run_logged "extract $NAME" "${extract:-default_extract}" ;;
    patch) run_logged "patch $NAME" "${patch_sources:-default_patch}" ;;
    build) run_logged "build $NAME" "${build:-default_build}" ;;
    package) run_logged "package $NAME" "${package:-default_package}" ;;
    all)
        run_logged "fetch $NAME" "${fetch:-default_fetch}"
        run_logged "extract $NAME" "${extract:-default_extract}"
        run_logged "patch $NAME" "${patch_sources:-default_patch}"
        run_logged "build $NAME" "${build:-default_build}"
        run_logged "package $NAME" "${package:-default_package}"
        ;;
    remove) remove_package "$RECIPE" ;;
    search) search_package "$RECIPE" ;;
    info) info_package "$RECIPE" ;;
    *) echo -e "${RED}Fase inválida${NC}" ; exit 1 ;;
esac
