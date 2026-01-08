#!/bin/sh
# rdX Zapret Installer
# for Rooted Dumb Xiaomi routers

##############################################################################
# КОНФИГ
##############################################################################

GITHUB_OWNER="commensal"
GITHUB_REPO="rdx-zapret"
GITHUB_BRANCH="main"

MY_REPO_TAR="https://github.com/${GITHUB_OWNER}/${GITHUB_REPO}/archive/refs/heads/${GITHUB_BRANCH}.tar.gz"
MY_REPO_RAW_BASE="https://raw.githubusercontent.com/${GITHUB_OWNER}/${GITHUB_REPO}/${GITHUB_BRANCH}"
MY_REPO_API_BASE="https://api.github.com/repos/${GITHUB_OWNER}/${GITHUB_REPO}/contents"

INSTALL_PATH="/data/zapret"

RED='\033[1;31m'
GREEN='\033[1;32m'
YELLOW='\033[1;33m'
BLUE='\033[1;34m'
PURPLE='\033[1;35m'
CYAN='\033[1;36m'
WHITE='\033[1;37m'
NC='\033[0m'

DEBUG_MODE=false
TEST_MODE=false

##############################################################################
# ПАРСИНГ АРГУМЕНТОВ
##############################################################################
for arg in "$@"; do
    case "$arg" in
        -debug|--debug) DEBUG_MODE=true ;;
        -test|--test) TEST_MODE=true; DEBUG_MODE=true ;;
        -h|--help)
            echo "Использование: $0 [опции]"
            echo "Опции:"
            echo "  -debug   Включить режим отладки (подробный вывод)"
            echo "  -test    Тестовый режим: установка в /tmp, без запуска zapret"
            exit 0
            ;;
    esac
done

##############################################################################
# ЛОГГЕР
##############################################################################
print_header() {
    echo ""
    echo -e "${CYAN}╔══════════════════════════════════════════╗${NC}"
    echo -e "${CYAN}║         rdX Zapret Installer             ║${NC}"
    echo -e "${CYAN}║     for Rooted Dumb Xiaomi routers       ║${NC}"
    echo -e "${CYAN}╚══════════════════════════════════════════╝${NC}"
    echo ""
}
print_success() { echo -e "${GREEN}[✓]${NC} $1"; }
print_error()   { echo -e "${RED}[✗]${NC} $1"; }
print_info()    { echo -e "${BLUE}[i]${NC} $1"; }
print_warning() { echo -e "${YELLOW}[!]${NC} $1"; }
debug() {
    if [ "$DEBUG_MODE" = "true" ]; then
        echo -e "${PURPLE}[DEBUG]${NC} $1" >&2
    fi
}

check_curl() {
    if ! command -v curl >/dev/null 2>&1; then
        print_error "curl не найден!"
        exit 1
    fi
}
check_tar() {
    if ! command -v tar >/dev/null 2>&1; then
        print_error "tar не найден!"
        exit 1
    fi
}

##############################################################################
# УПРАВЛЕНИЕ СЕРВИСОМ ZAPRET
##############################################################################
stop_zapret_service() {
    print_info "Попытка остановить сервис zapret..."

    if command -v service >/dev/null 2>&1; then
        debug "Останавливаем через service zapret stop"
        if service zapret stop 2>/dev/null; then
            print_success "Сервис zapret остановлен (service)"
            return 0
        fi
    fi

    if [ -x /etc/init.d/zapret ]; then
        debug "Останавливаем /etc/init.d/zapret stop"
        if /etc/init.d/zapret stop 2>/dev/null; then
            print_success "Сервис zapret остановлен (/etc/init.d)"
            return 0
        fi
    fi

    print_warning "Не удалось остановить сервис zapret (возможно, он не установлен или не запущен)"
    return 1
}

start_zapret_service() {
    print_info "Попытка запустить/перезапустить сервис zapret..."

    if command -v service >/dev/null 2>&1; then
        debug "Перезапуск через service zapret restart"
        if service zapret restart 2>/dev/null; then
            print_success "Zapret перезапущен (service)"
            return 0
        fi
    fi

    if [ -x /etc/init.d/zapret ]; then
        debug "Перезапуск /etc/init.d/zapret restart"
        if /etc/init.d/zapret restart 2>/dev/null; then
            print_success "Zapret перезапущен (/etc/init.d)"
            return 0
        fi
    fi

    print_warning "Не удалось перезапустить zapret (возможно, еще не установлен сервис)"
    return 1
}

is_zapret_running() {
    # Проверяем процессы nfqws или tpws (игнорируем grep)
    if pgrep -f "nfqws" >/dev/null 2>&1 || pgrep -f "tpws" >/dev/null 2>&1; then
        return 0
    fi
    return 1
}



##############################################################################
# ZAPRET (bol-van/zapret)
##############################################################################
get_latest_version() {
    debug "Запрашиваем последнюю версию Zapret..."

    local version
    version=$(curl -s -H "User-Agent: Mozilla/5.0" \
        "https://github.com/bol-van/zapret/releases" 2>/dev/null | \
        grep -o 'releases/tag/v[0-9][0-9.]*' | \
        head -1 | cut -d'/' -f3)

    if [ -n "$version" ]; then
        debug "Получена версия: $version"
        echo "$version"
        return 0
    fi

    echo "v72.6"
    return 1
}

download_release() {
    local version="$1"
    local target_file="$2"

    debug "Пробуем скачать Zapret $version"

    local main_url="https://github.com/bol-van/zapret/releases/download/$version/zapret-$version-openwrt-embedded.tar.gz"
    debug "Основной URL: $main_url"

    if curl -L -H "User-Agent: Mozilla/5.0" \
        -o "$target_file" \
        "$main_url" 2>/dev/null; then
        if [ -f "$target_file" ]; then
            local size
            size=$(wc -c < "$target_file" 2>/dev/null || echo "0")
            if [ "$size" -gt 1000000 ]; then
                debug "Файл скачан, размер: $size байт"
                return 0
            fi
            rm -f "$target_file"
        fi
    fi

    local alt_url="https://github.com/bol-van/zapret/releases/download/$version/openwrt_embedded.zip"
    debug "Пробуем запасной URL: $alt_url"

    if curl -L -H "User-Agent: Mozilla/5.0" \
        -o "$target_file" \
        "$alt_url" 2>/dev/null; then
        if [ -f "$target_file" ]; then
            local size
            size=$(wc -c < "$target_file" 2>/dev/null || echo "0")
            if [ "$size" -gt 1000000 ]; then
                debug "Файл скачан, размер: $size байт"
                return 0
            fi
        fi
    fi

    print_error "Не удалось скачать релиз Zapret"
    return 1
}

##############################################################################
# МОЙ РЕПО: TARBALL + API FALLBACK
##############################################################################
download_my_repo_tar() {
    local target_dir="$1"

    print_info "Скачивание всех файлов из ${GITHUB_OWNER}/${GITHUB_REPO} (tar.gz ветки ${GITHUB_BRANCH})..."
    mkdir -p "$target_dir"

    local tmp_tar="/tmp/${GITHUB_REPO}-${GITHUB_BRANCH}.tar.gz"
    if ! curl -L -H "User-Agent: Mozilla/5.0" \
        -o "$tmp_tar" \
        "$MY_REPO_TAR" 2>/dev/null; then
        print_error "Не удалось скачать архив репозитория"
        return 1
    fi

    local tmp_dir="/tmp/${GITHUB_REPO}_extract_$$"
    mkdir -p "$tmp_dir"

    if ! tar -xzf "$tmp_tar" -C "$tmp_dir" 2>/dev/null; then
        print_error "Ошибка распаковки архива репозитория"
        rm -f "$tmp_tar"
        rm -rf "$tmp_dir"
        return 1
    fi

    local repo_root
    repo_root=$(find "$tmp_dir" -mindepth 1 -maxdepth 1 -type d | head -1)
    if [ -z "$repo_root" ]; then
        print_error "Не найдена корневая папка в архиве репозитория"
        rm -f "$tmp_tar"
        rm -rf "$tmp_dir"
        return 1
    fi

    debug "Корневая папка моего репо: $repo_root"

    cp -rf "$repo_root"/* "$target_dir"/ 2>/dev/null

    rm -f "$tmp_tar"
    rm -rf "$tmp_dir"

    print_success "Все файлы моего репозитория скопированы (tar)"
    return 0
}

download_single_file_raw() {
    local path="$1"
    local out="$2"

    local url="${MY_REPO_RAW_BASE}/${path}"
    debug "Скачиваем файл raw: $url -> $out"

    if curl -L -H "User-Agent: Mozilla/5.0" \
        -o "$out" \
        "$url" 2>/dev/null; then
        return 0
    fi
    return 1
}

download_repo_dir_recursive() {
    local api_path="$1"
    local local_root="$2"

    local url="$MY_REPO_API_BASE"
    [ -n "$api_path" ] && url="$url/$api_path"

    debug "Запрашиваем список содержимого: $url"

    local json
    json=$(curl -s -H "User-Agent: Mozilla/5.0" \
        -H "Accept: application/vnd.github+json" \
        "$url" 2>/dev/null)

    if [ -z "$json" ]; then
        print_error "Не удалось получить список файлов по API: $url"
        return 1
    fi

    echo "$json" | while IFS= read -r line; do
        case "$line" in
            *'"type"'* )
                type=$(printf '%s' "$line" | sed -n 's/.*"type"[[:space:]]*:[[:space:]]*"\([^"]*\)".*/\1/p')
                ;;
            *'"name"'* )
                name=$(printf '%s' "$line" | sed -n 's/.*"name"[[:space:]]*:[[:space:]]*"\([^"]*\)".*/\1/p')
                ;;
            *'"path"'* )
                path=$(printf '%s' "$line" | sed -n 's/.*"path"[[:space:]]*:[[:space:]]*"\([^"]*\)".*/\1/p')

                if [ "$type" = "dir" ]; then
                    debug "Найдена директория: $path"
                    mkdir -p "$local_root/$path"
                    download_repo_dir_recursive "$path" "$local_root"
                elif [ "$type" = "file" ]; then
                    debug "Найден файл: $path"
                    mkdir -p "$(dirname "$local_root/$path")"
                    if download_single_file_raw "$path" "$local_root/$path"; then
                        print_success "Файл $path скачан"
                        case "$path" in
                            *.sh) chmod +x "$local_root/$path" 2>/dev/null ;;
                        esac
                    else
                        print_error "Ошибка скачивания файла $path"
                    fi
                fi
                ;;
        esac
    done

    return 0
}

download_my_repo_via_api() {
    local target_dir="$1"
    print_info "Скачивание всех файлов моего репозитория через GitHub API (по одному)..."
    mkdir -p "$target_dir"
    download_repo_dir_recursive "" "$target_dir"
    print_success "Попытка загрузить все файлы моего репозитория завершена (API)"
}

download_my_files() {
    local target_dir="$1"

    if ! download_my_repo_tar "$target_dir"; then
        print_warning "Не удалось скачать/распаковать tar с моим репо, fallback на GitHub API + raw"
        download_my_repo_via_api "$target_dir"
    fi
}

##############################################################################
# ПОЛНОЕ УДАЛЕНИЕ ZAPRET
##############################################################################
full_uninstall_zapret() {
    print_header
    print_warning "Полное удаление zapret..."

    stop_zapret_service

    if [ -f "$INSTALL_PATH/uninstall_easy.sh" ]; then
        print_info "Запуск uninstall_easy.sh..."
        sh "$INSTALL_PATH/uninstall_easy.sh"
    else
        print_warning "uninstall_easy.sh не найден, пропускаем"
    fi

    if [ -f "/data/etc/crontabs/root" ]; then
        print_info "Очистка crontab от записей zapret..."
        sed -i '/zapret/d' /data/etc/crontabs/root 2>/dev/null || true
    fi

    if [ -f "/data/etc/crontabs/patches/zapret_patch.sh" ]; then
        print_info "Удаление /data/etc/crontabs/patches/zapret_patch.sh..."
        rm -f /data/etc/crontabs/patches/zapret_patch.sh 2>/dev/null || true
    fi

    if [ -x /etc/init.d/cron ]; then
        print_info "Перезапуск cron..."
        /etc/init.d/cron restart 2>/dev/null || true
    fi

    if [ -d "$INSTALL_PATH" ]; then
        print_info "Удаление каталога $INSTALL_PATH..."
        rm -rf "$INSTALL_PATH" 2>/dev/null || true
    fi

    print_success "Zapret полностью удалён (насколько это возможно скриптом)"
    echo ""
    read -p "Нажмите Enter для продолжения..."
	exit 0
}

##############################################################################
# УСТАНОВКА
##############################################################################
install_zapret_core() {
    local actual_path="$1"

    print_info "Получение информации о последней версии Zapret..."
    local version
    version=$(get_latest_version)

    if [ -n "$version" ]; then
        print_success "Найдена версия: $version"
    else
        print_error "Не удалось получить версию Zapret"
        return 1
    fi

    local archive="/tmp/zapret_$version.tar.gz"
    if download_release "$version" "$archive"; then
        print_success "Релиз Zapret скачан"

        local temp_dir="/tmp/zapret_extract_$$"
        mkdir -p "$temp_dir"

        print_info "Распаковка архива Zapret..."
        if tar -xzf "$archive" -C "$temp_dir" 2>/dev/null; then
            print_success "Архив Zapret распакован"

            local source_dir=""
            if [ -d "$temp_dir/zapret" ]; then
                source_dir="$temp_dir/zapret"
            elif [ -d "$temp_dir/zapret-$version" ]; then
                source_dir="$temp_dir/zapret-$version"
            else
                source_dir="$temp_dir"
            fi

            debug "Корневая папка Zapret: $source_dir"

            mkdir -p "$actual_path"

            print_info "Копирование файлов Zapret..."
            for item in "$source_dir"/*; do
                if [ -e "$item" ] && [ "$(basename "$item")" != "binaries" ]; then
                    cp -rf "$item" "$actual_path/" 2>/dev/null
                fi
            done

            print_info "Копирование бинарников linux-arm..."
            if [ -d "$source_dir/binaries/linux-arm" ]; then
                mkdir -p "$actual_path/binaries/linux-arm"
                cp -rf "$source_dir/binaries/linux-arm"/* "$actual_path/binaries/linux-arm/" 2>/dev/null
                print_success "Бинарники linux-arm скопированы"
            else
                print_warning "Папка binaries/linux-arm не найдена в архиве Zapret"
            fi

            download_my_files "$actual_path"

            print_info "Установка прав доступа..."
            chmod -R 755 "$actual_path" 2>/dev/null
            find "$actual_path" -name "*.sh" -exec chmod +x {} \; 2>/dev/null
            print_success "Права установлены"

            if [ "$TEST_MODE" = "false" ]; then
                print_info "Замена путей /opt/ -> /data/ в файлах zapret..."
                find "$INSTALL_PATH" -type f -exec sed -i 's|/opt/|/data/|g' {} \; 2>/dev/null
            fi

            if [ "$TEST_MODE" = "true" ]; then
                print_info "Тестовый режим: zapret не запускается, изменения ограничены $actual_path"
            else
                if [ -f "$actual_path/install_easy.sh" ]; then
                    print_info "Запуск install_easy.sh..."
                    "$actual_path/install_easy.sh"
                else
                    print_error "install_easy.sh не найден"
                fi

                if [ -f "$actual_path/install_patch.sh" ]; then
                    print_info "Запуск install_patch.sh..."
                    "$actual_path/install_patch.sh"
                else
                    print_error "install_patch.sh не найден"
                fi

                print_success "Zapret установлен!"
            fi

            rm -rf "$temp_dir"
            rm -f "$archive"
        else
            print_error "Ошибка при распаковке архива Zapret"
        fi
    else
        print_error "Ошибка при скачивании архива Zapret"
    fi
}

install_zapret() {
    local force_reinstall="$1"

    print_header

    local actual_path="$INSTALL_PATH"
    if [ "$TEST_MODE" = "true" ]; then
        actual_path="/tmp/zapret_test"
        print_info "Тестовый режим: установка в $actual_path (рабочая система не трогаем)"
    fi

    if [ "$force_reinstall" = "true" ]; then
        if [ "$TEST_MODE" = "true" ]; then
            print_info "Тестовый режим: проверка переустановки"
        else
            print_warning "Принудительная переустановка Zapret"
        fi

        # используем логіку полного удаления
        full_uninstall_zapret
    else
        print_info "Начало установки..."
    fi

    install_zapret_core "$actual_path"

    echo ""
    read -p "Нажмите Enter для продолжения..."
}

##############################################################################
# ОБНОВЛЕНИЕ
##############################################################################
update_zapret() {
    print_header
    print_info "Проверка обновлений Zapret..."

    local current_version=""
    if [ -f "$INSTALL_PATH/binaries/linux-arm/nfqws" ]; then
        current_version=$("$INSTALL_PATH/binaries/linux-arm/nfqws" -version 2>&1 | \
            grep -o "v[0-9][0-9.]*" | head -1)
    fi

    local latest_version
    latest_version=$(get_latest_version)

    if [ -z "$current_version" ]; then
        print_warning "Текущая версия не определена"
    else
        echo "Текущая версия: $current_version"
    fi

    if [ -n "$latest_version" ]; then
        echo "Последняя версия: $latest_version"
    fi

    if [ "$current_version" = "$latest_version" ] && [ -n "$current_version" ]; then
        print_success "Установлена последняя версия!"
        echo ""
        read -p "Нажмите Enter для продолжения..."
        return
    fi

    echo ""

    while true; do
        read -p "Обновить? (Y/n): " choice
        case "$choice" in
            [Yy]*|"" )
                if [ "$TEST_MODE" = "true" ]; then
                    print_info "Тестовый режим: проверка обновления (без реальных изменений)"
                else
                    local archive="/tmp/zapret_update_$latest_version.tar.gz"

                    stop_zapret_service

                    if download_release "$latest_version" "$archive"; then
                        print_success "Релиз Zapret скачан"

                        local temp_dir="/tmp/zapret_update_temp_$$"
                        mkdir -p "$temp_dir"

                        if tar -xzf "$archive" -C "$temp_dir" 2>/dev/null; then
                            local found=false
                            for dir in "$temp_dir/zapret/binaries/linux-arm" \
                                       "$temp_dir/zapret-$latest_version/binaries/linux-arm" \
                                       "$temp_dir/binaries/linux-arm"; do
                                if [ -d "$dir" ]; then
                                    mkdir -p "$INSTALL_PATH/binaries/linux-arm"
                                    cp -rf "$dir"/* "$INSTALL_PATH/binaries/linux-arm/"
                                    print_success "Бинарники linux-arm обновлены"
                                    found=true
                                    break
                                fi
                            done

                            if [ "$found" = "false" ]; then
                                print_error "Бинарники linux-arm не найдены в архиве обновления"
                            fi

                            start_zapret_service

                            rm -rf "$temp_dir"
                            rm -f "$archive"

                            print_success "Обновление завершено!"
                        fi
                    fi
                fi
                break
                ;;
            [Nn]* )
                print_info "Обновление отменено"
                break
                ;;
            * )
                echo "Введите Y или N"
                ;;
        esac
    done

    echo ""
    read -p "Нажмите Enter для продолжения..."
}

##############################################################################
# ТЕСТ ОБХОДА
##############################################################################
test_bypass() {
    print_header
    print_info "Протестировать работу обхода (не точно)..."

    if [ -f "$INSTALL_PATH/test.sh" ]; then
        "$INSTALL_PATH/test.sh"
    else
        print_error "Тестовый скрипт test.sh не найден"
    fi

    echo ""
    read -p "Нажмите Enter для продолжения..."
}

##############################################################################
# МЕНЮ
##############################################################################
show_menu() {
    while true; do
        print_header

        if [ "$DEBUG_MODE" = "true" ]; then
            if [ "$TEST_MODE" = "true" ]; then
                echo -e "${YELLOW}[ТЕСТОВЫЙ РЕЖИМ]${NC}"
            else
                echo -e "${PURPLE}[ОТЛАДКА]${NC}"
            fi
            echo ""
        fi

        if [ -d "$INSTALL_PATH" ] && [ -n "$(ls -A "$INSTALL_PATH" 2>/dev/null)" ]; then
            if is_zapret_running; then
                echo -e "${YELLOW}Zapret установлен${GREEN} и работает!${NC}"
                echo -e "${GREEN}1. Остановить zapret (вкл/выкл)${NC}"
            else
                echo -e "${YELLOW}Zapret установлен,${RED} но остановлен.${NC}"
                echo -e "${GREEN}1. Запустить zapret (вкл/выкл)${NC}"
            fi
            echo ""
            echo "3. Проверить обновление"
            echo -e "${YELLOW}5. Принудительно переустановить${NC}"
            echo -e "${RED}6. Полностью удалить zapret${NC}"
            echo ""
            echo -e "${GREEN}0. Выйти${NC} (или Enter)"
            echo ""

            echo -n "Выберите опцию [1,3,5,6,0]: "
            read choice

            case "$choice" in
                1)
                    if is_zapret_running; then
                        stop_zapret_service
                    else
                        start_zapret_service
                    fi
                    ;;
                3) update_zapret ;;
                5) install_zapret "true" ;;
                6) full_uninstall_zapret ;;
                0|"")
                    echo ""
                    print_info "Выход..."
                    echo ""
                    exit 0
                    ;;
                *)
                    print_error "Неверный выбор"
                    echo ""
                    read -p "Нажмите Enter для продолжения..."
                    ;;
            esac
        else
            echo -e "${GREEN}Zapret не установлен. Начинаем установку...${NC}"
            echo ""
            install_zapret "false"
            continue
        fi
    done
}



##############################################################################
# MAIN
##############################################################################
main() {
    if [ "$DEBUG_MODE" = "true" ]; then
        if [ "$TEST_MODE" = "true" ]; then
            echo -e "${YELLOW}Запуск в тестовом режиме${NC}"
        else
            echo -e "${PURPLE}Запуск в режиме отладки${NC}"
        fi
        echo ""
    fi

    check_curl
    check_tar

    if [ "$TEST_MODE" = "false" ] && [ "$(id -u)" -ne 0 ]; then
        print_error "Требуются права root!"
        exit 1
    fi

    show_menu
}

main
