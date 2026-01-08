#!/bin/sh

VERSION="v0.1 080126"
TITLE="rdX Zapret Installer"
GITHUBOWNER="commensal"
GITHUBREPO="rdx-zapret"
GITHUBBRANCH="main"
MYREPOTAR="https://github.com/${GITHUBOWNER}/${GITHUBREPO}/archive/refs/heads/${GITHUBBRANCH}.tar.gz"
MYREPORAWBASE="https://raw.githubusercontent.com/${GITHUBOWNER}/${GITHUBREPO}/${GITHUBBRANCH}"
MYREPOAPIBASE="https://api.github.com/repos/${GITHUBOWNER}/${GITHUBREPO}/contents"
INSTALLPATH="data/zapret"

RED='\033[31;1m'
GREEN='\033[32;1m'
YELLOW='\033[33;1m'
BLUE='\033[34;1m'
PURPLE='\033[35;1m'
CYAN='\033[36;1m'
WHITE='\033[37;1m'
NC='\033[0m'

DEBUGMODE=false
TESTMODE=false

printheader() {
    local version=${VERSION}
    local titlelen=42
    local title="rdX Zapret Installer ${version}"
    local titlelength=${#title}
    local spaces=$((titlelen - titlelength))
    local padding=$(printf "%*s" $spaces "")
    echo
    echo -e "${CYAN}╦${NC}"
    echo -e "${CYAN}║${NC}${title}${padding}${NC}║${NC}"
    echo -e "${CYAN}║ for Rooted Dumb Xiaomi routers${NC}║${NC}"
    echo -e "${CYAN}╩${NC}"
    echo
}

printsuccess() {
    echo -e "${GREEN}[✓]${NC} $1"
}

printerror() {
    echo -e "${RED}[✗]${NC} $1"
}

printinfo() {
    echo -e "${BLUE}[i]${NC} $1"
}

printwarning() {
    echo -e "${YELLOW}[!]${NC} $1"
}

debug() {
    if [ "$DEBUGMODE" = true ]; then
        echo -e "${PURPLE}[DEBUG]${NC} $1" >&2
    fi
}

checkcurl() {
    if ! command -v curl >/dev/null 2>&1; then
        printerror "curl не найден!"
        exit 1
    fi
}

checktar() {
    if ! command -v tar >/dev/null 2>&1; then
        printerror "tar не найден!"
        exit 1
    fi
}

stopzapretservice() {
    printinfo "zapret останавливается..."
    if command -v service >/dev/null 2>&1; then
        debug "service zapret stop"
        if service zapret stop 2>/dev/null; then
            printsuccess "zapret service остановлен"
            return 0
        fi
    fi
    if [ -x /etc/init.d/zapret ]; then
        debug "/etc/init.d/zapret stop"
        if /etc/init.d/zapret stop 2>/dev/null; then
            printsuccess "zapret /etc/init.d остановлен"
            return 0
        fi
    fi
    printwarning "zapret не удалось остановить"
    return 1
}

startzapretservice() {
    printinfo "zapret запускается..."
    if command -v service >/dev/null 2>&1; then
        debug "service zapret restart"
        if service zapret restart 2>/dev/null; then
            printsuccess "Zapret service запущен"
            return 0
        fi
    fi
    if [ -x /etc/init.d/zapret ]; then
        debug "/etc/init.d/zapret restart"
        if /etc/init.d/zapret restart 2>/dev/null; then
            printsuccess "Zapret /etc/init.d запущен"
            return 0
        fi
    fi
    printwarning "zapret не удалось запустить"
    return 1
}

iszapretrunning() {
    if pgrep -f nfqws >/dev/null 2>&1 || pgrep -f tpws >/dev/null 2>&1; then
        return 0
    fi
    return 1
}

getlatestversion() {
    debug "Проверка версии Zapret..."
    local version=$(curl -s -H "User-Agent: Mozilla/5.0" https://github.com/bol-van/zapret/releases 2>/dev/null | grep -o 'releases/tag/v[0-9].*' | head -1 | cut -d- -f3)
    if [ -n "$version" ]; then
        debug "Найдена версия: $version"
        echo $version
        return 0
    fi
    debug "Fallback версия Zapret bol-van/zapret..."
    echo "v7.2.6"
    return 1
}

downloadrelease() {
    local version=$1
    local targetfile=$2
    debug "Скачивание Zapret версии ${version}..."
    local mainurl="https://github.com/bol-van/zapret/releases/download/${version}/zapret-${version}-openwrt-embedded.tar.gz"
    debug "URL: $mainurl"
    if curl -L -H "User-Agent: Mozilla/5.0" -o "$targetfile" "$mainurl" 2>/dev/null; then
        if [ -f "$targetfile" ]; then
            local size=$(wc -c < "$targetfile" 2>/dev/null)
            echo "0"
            if [ "$size" -gt 1000000 ]; then
                debug "Файл скачан, размер: $size"
                return 0
            fi
            rm -f "$targetfile"
        fi
    fi
    local alturl="https://github.com/bol-van/zapret/releases/download/${version}/openwrtembedded.zip"
    debug "URL: $alturl"
    if curl -L -H "User-Agent: Mozilla/5.0" -o "$targetfile" "$alturl" 2>/dev/null; then
        if [ -f "$targetfile" ]; then
            local size=$(wc -c < "$targetfile" 2>/dev/null)
            echo "0"
            if [ "$size" -gt 1000000 ]; then
                debug "Файл скачан, размер: $size"
                return 0
            fi
        fi
    fi
    printerror "Не удалось скачать Zapret"
    return 1
}

downloadmyrepotar() {
    local targetdir=$1
    printinfo "${GITHUBOWNER}/${GITHUBREPO} tar.gz (${GITHUBBRANCH})..."
    mkdir -p "$targetdir"
    local tmptar="tmp${GITHUBREPO}-${GITHUBBRANCH}.tar.gz"
    if ! curl -L -H "User-Agent: Mozilla/5.0" -o "$tmptar" "$MYREPOTAR" 2>/dev/null; then
        printerror "Ошибка скачивания"
        return 1
    fi
    local tmpdir="tmp${GITHUBREPO}extract"
    mkdir -p "$tmpdir"
    if ! tar -xzf "$tmptar" -C "$tmpdir" 2>/dev/null; then
        printerror "Ошибка распаковки"
        rm -f "$tmptar"
        rm -rf "$tmpdir"
        return 1
    fi
    local reporoot=$(find "$tmpdir" -mindepth 1 -maxdepth 1 -type d | head -1)
    if [ -z "$reporoot" ]; then
        printerror "Репозиторий не найден"
        rm -f "$tmptar"
        rm -rf "$tmpdir"
        return 1
    fi
    debug "Репозиторий: $reporoot"
    cp -rf "$reporoot"/* "$targetdir" 2>/dev/null
    rm -f "$tmptar"
    rm -rf "$tmpdir"
    printsuccess "tar.gz скачан"
    return 0
}

downloadsinglefileraw() {
    local path=$1
    local out=$2
    local url="${MYREPORAWBASE}/${path}"
    debug "raw: $url -> $out"
    if curl -L -H "User-Agent: Mozilla/5.0" -o "$out" "$url" 2>/dev/null; then
        return 0
    fi
    return 1
}

downloadrepodirrecursive() {
    local apipath=$1
    local localroot=$2
    local url="${MYREPOAPIBASE}${apipath}"
    debug "API: $url"
    local json=$(curl -s -H "User-Agent: Mozilla/5.0" -H "Accept: application/vnd.github.v3+json" "$url" 2>/dev/null)
    if [ -z "$json" ]; then
        printerror "API недоступен: $url"
        return 1
    fi
    echo "$json" | while IFS= read -r line; do
        case $line in
            *"\"type\"":\"dir\""*|*"type":"dir"*)
                local path=$(printf '%s\n' "$line" | sed -n 's/.*"path":"\([^"]*\)".*/\1/p')
                debug "Каталог: $path"
                mkdir -p "${localroot}${path}"
                downloadrepodirrecursive "$path" "$localroot" ;;
            *"\"type\"":\"file\""*|*"type":"file"*)
                local path=$(printf '%s\n' "$line" | sed -n 's/.*"path":"\([^"]*\)".*/\1/p')
                debug "Файл: $path"
                mkdir -p "$(dirname ${localroot}${path})"
                if downloadsinglefileraw "$path" "${localroot}${path}"; then
                    printsuccess "$path"
                    case "$path" in *.sh) chmod +x "${localroot}${path}" 2>/dev/null ;; esac
                else
                    printerror "$path"
                fi ;;
        esac
    done
    return 0
}

downloadmyrepoviaapi() {
    local targetdir=$1
    printinfo "Скачивание через GitHub API..."
    mkdir -p "$targetdir"
    downloadrepodirrecursive "" "$targetdir/"
    printsuccess "API скачивание завершено"
}

downloadmyfiles() {
    local targetdir=$1
    if ! downloadmyrepotar "$targetdir"; then
        printwarning "tar.gz не удался, fallback на GitHub API/raw"
        downloadmyrepoviaapi "$targetdir"
    fi
}

fulluninstallzapret() {
    printheader
    printwarning "Полное удаление zapret..."
    stopzapretservice
    if [ -f "$INSTALLPATH/uninstalleasy.sh" ]; then
        printinfo "uninstalleasy.sh..."
        sh "$INSTALLPATH/uninstalleasy.sh"
    else
        printwarning "uninstalleasy.sh не найден,"
    fi
    if [ -f /data/etc/crontabs/root ]; then
        printinfo "crontab zapret..."
        sed -i '/zapret/d' /data/etc/crontabs/root 2>/dev/null || true
    fi
    if [ -f /data/etc/crontabs/patches/zapretpatch.sh ]; then
        printinfo "/data/etc/crontabs/patches/zapretpatch.sh..."
        rm -f /data/etc/crontabs/patches/zapretpatch.sh 2>/dev/null || true
    fi
    if [ -x /etc/init.d/cron ]; then
        printinfo "cron..."
        /etc/init.d/cron restart 2>/dev/null || true
    fi
    if [ -d "$INSTALLPATH" ]; then
        printinfo "$INSTALLPATH..."
        rm -rf "$INSTALLPATH" 2>/dev/null || true
    fi
    printsuccess "Zapret удален"
    echo
    read -p "Нажмите Enter для выхода..."
    exit 0
}

installzapretcore() {
    local actualpath=$1
    printinfo "Установка Zapret..."
    local version=$(getlatestversion)
    if [ -n "$version" ]; then
        printsuccess "Версия: $version"
    else
        printerror "Не удалось получить версию Zapret"
        return 1
    fi
    local archive="tmpzapret-${version}.tar.gz"
    if downloadrelease "$version" "$archive"; then
        printsuccess "Архив скачан"
        local tempdir="tmpzapretextract"
        mkdir -p "$tempdir"
        printinfo "Распаковка Zapret..."
        if tar -xzf "$archive" -C "$tempdir" 2>/dev/null; then
            printsuccess "Zapret распакован"
            local sourcedir
            if [ -d "$tempdir/zapret" ]; then sourcedir="$tempdir/zapret"
            elif [ -d "$tempdir/zapret-${version}" ]; then sourcedir="$tempdir/zapret-${version}"
            else sourcedir="$tempdir"
            fi
            debug "Zapret: $sourcedir"
            mkdir -p "$actualpath"
            printinfo "Копирование Zapret..."
            for item in "$sourcedir"/*; do
                if [ -e "$item" ] && [[ "$(basename "$item")" != "binaries" ]]; then
                    cp -rf "$item" "$actualpath" 2>/dev/null
                fi
            done
            printinfo "linux-arm..."
            if [ -d "$sourcedir/binaries/linux-arm" ]; then
                mkdir -p "$actualpath/binaries/linux-arm"
                cp -rf "$sourcedir/binaries/linux-arm" "$actualpath/binaries/linux-arm" 2>/dev/null
                printsuccess "linux-arm скопирован"
            else
                printwarning "binaries/linux-arm не найден в Zapret"
            fi
            downloadmyfiles "$actualpath"
            printinfo "Права доступа..."
            chmod -R 755 "$actualpath" 2>/dev/null
            find "$actualpath" -name "*.sh" -exec chmod +x {} \; 2>/dev/null
            printsuccess "Установка завершена"
            if [ "$TESTMODE" = true ]; then
                printinfo "zapret установлен в: $actualpath"
            else
                printinfo "Замена /opt -> /data..."
                find "$INSTALLPATH" -type f -exec sed -i 's|/opt/|/data/|g' {} \; 2>/dev/null
                printinfo "rdx-zapret installeasy.sh патч..."
                if [ -f "$actualpath/installeasy.sh" ]; then
                    awk '
                    /installopenwrt/{found=1; print; next}
                    found && /selectfwtype/{print "0"; next}
                    found && /selectipv6/{print "0"; next}
                    found && /checkprerequisitesopenwrt/{print "0"; next}
                    found && /askconfig/{print "0"; next}
                    found && /askconfigtmpdir/{print "0"; next}
                    found && /askconfigoffload/{print "0"; next}
                    found{print; next}
                    {print}
                    END{found=0}' "$actualpath/installeasy.sh" > "$actualpath/installeasy.sh.tmp" &&
                    mv "$actualpath/installeasy.sh.tmp" "$actualpath/installeasy.sh"
                    printsuccess "installeasy.sh пропатчен"
                fi
                printinfo "rdx-zapret uninstalleasy.sh..."
                if [ -f "$actualpath/uninstalleasy.sh" ]; then
                    sed -i 's/.removeextrapkgsopenwrt//g' "$actualpath/uninstalleasy.sh" 2>/dev/null
                    printsuccess "rdx-zapret uninstalleasy.sh пропатчен"
                fi
                if [ -f "$actualpath/installeasy.sh" ]; then
                    printinfo "installeasy.sh..."
                    sh "$actualpath/installeasy.sh"
                else
                    printerror "installeasy.sh не найден"
                fi
                if [ -f "$actualpath/installpatch.sh" ]; then
                    printinfo "installpatch.sh..."
                    sh "$actualpath/installpatch.sh"
                else
                    printerror "installpatch.sh не найден"
                fi
                printsuccess "Zapret установлен! 🎉"
            fi
        else
            printerror "Ошибка распаковки архива"
        fi
        rm -rf "$tempdir"
        rm -f "$archive"
    else
        printerror "Ошибка скачивания архива Zapret"
    fi
}

installzapret() {
    local forcereinstall=$1
    printheader
    local actualpath="$INSTALLPATH"
    if [ "$TESTMODE" = true ]; then
        actualpath="tmp/zaprettest"
        printinfo "Тестовая установка в: $actualpath"
    fi
    if [ "$forcereinstall" = true ]; then
        if [ "$TESTMODE" = true ]; then
            printinfo "Переустановка..."
        else
            printwarning "Переустановка Zapret"
        fi
        fulluninstallzapret
    else
        printinfo "Проверка установки..."
    fi
    installzapretcore "$actualpath"
    echo
    read -p "Нажмите Enter для продолжения..."
}

updatezapret() {
    printheader
    printinfo "Проверка обновлений Zapret..."
    local currentversion
    if [ -f "$INSTALLPATH/binaries/linux-arm/nfqws" ]; then
        currentversion=$("$INSTALLPATH/binaries/linux-arm/nfqws" -version 2>&1 | grep -o 'v[0-9].*' | head -1)
    fi
    local latestversion=$(getlatestversion)
    if [ -z "$currentversion" ]; then
        printwarning "Текущая версия не определена"
    else
        echo "Текущая: $currentversion"
    fi
    if [ -n "$latestversion" ]; then
        echo "Последняя: $latestversion"
    fi
    if [ "$currentversion" = "$latestversion" ] && [ -n "$currentversion" ]; then
        printsuccess "Актуальная версия!"
        echo
        read -p "Нажмите Enter..."
        return
    fi
    echo
    while true; do
        read -p "Обновить? (Y/n): " choice
        case $choice in
            [Yy]*)
                if [ "$TESTMODE" = true ]; then
                    printinfo "Тестовый режим"
                else
                    local archive="tmpzapretupdate-${latestversion}.tar.gz"
                    stopzapretservice
                    if downloadrelease "$latestversion" "$archive"; then
                        printsuccess "Архив скачан"
                        local tempdir="tmpzapretupdatetemp"
                        mkdir -p "$tempdir"
                        if tar -xzf "$archive" -C "$tempdir" 2>/dev/null; then
                            local found=false
                            for dir in "$tempdir/zapret/binaries/linux-arm" \
                                       "$tempdir/zapret-${latestversion}/binaries/linux-arm" \
                                       "$tempdir/binaries/linux-arm"; do
                                if [ -d "$dir" ]; then
                                    mkdir -p "$INSTALLPATH/binaries/linux-arm"
                                    cp -rf "$dir"/* "$INSTALLPATH/binaries/linux-arm/"
                                    printsuccess "linux-arm обновлен"
                                    found=true
                                    break
                                fi
                            done
                            if [ "$found" = false ]; then
                                printerror "linux-arm не найден"
                            fi
                            startzapretservice
                            rm -rf "$tempdir"
                            rm -f "$archive"
                            printsuccess "Обновление завершено! 🎉"
                        fi
                    fi
                fi
                break ;;
            [Nn]*)
                printinfo "Обновление отменено"
                break ;;
            *)
                echo "Y/N"
                ;;
        esac
    done
    echo
    read -p "Нажмите Enter..."
}

showmenu() {
    while true; do
        printheader
        if [ "$DEBUGMODE" = true ]; then
            if [ "$TESTMODE" = true ]; then
                echo -e "${YELLOW}[ТЕСТ]${NC}"
            else
                echo -e "${PURPLE}[DEBUG]${NC}"
            fi
            echo
        fi
        if [ -d "$INSTALLPATH" ] && [ -n "$(ls -A "$INSTALLPATH" 2>/dev/null)" ]; then
            if iszapretrunning; then
                echo -e "${YELLOW}Zapret${GREEN} запущен!${NC}"
                echo -e "${RED}1.${NC} zapret остановить"
            else
                echo -e "${YELLOW}Zapret${RED} остановлен.${NC}"
                echo -e "${GREEN}1.${NC} zapret запустить"
            fi
            echo
            echo -e "${GREEN}3.${NC} Обновить"
            echo -e "${YELLOW}5.${NC} Переустановить"
            echo -e "${RED}6.${NC} Полное удаление zapret"
            echo
            echo -e "${GREEN}0.${NC} Выход (Enter)"
            echo
            echo -n "Выберите (1,3,5,6,0): "
            read choice
            case $choice in
                1)
                    if iszapretrunning; then
                        stopzapretservice
                    else
                        startzapretservice
                    fi ;;
                3) updatezapret ;;
                5) installzapret true ;;
                6) fulluninstallzapret ;;
                0|"")
                    echo
                    printinfo "До свидания!"
                    echo
                    exit 0 ;;
                *)
                    printerror "Неверный пункт"
                    echo
                    read -p "Нажмите Enter..."
                    ;;
            esac
        else
            echo -e "${GREEN}Zapret не установлен. Установка...${NC}"
            echo
            installzapret false
            continue
        fi
    done
}

main() {
    if [ "$DEBUGMODE" = true ]; then
        if [ "$TESTMODE" = true ]; then
            echo -e "${YELLOW}[ТЕСТ]${NC}"
        else
            echo -e "${PURPLE}[DEBUG]${NC}"
        fi
        echo
    fi
    checkcurl
    checktar
    if [ "$TESTMODE" = false ] && id -u -ne 0; then
        printerror "Требуются права root!"
        exit 1
    fi
    showmenu
}

for arg in "$@"; do
    case $arg in
        -debug|--debug) DEBUGMODE=true ;;
        -test|--test) TESTMODE=true; DEBUGMODE=true ;;
        -h|--help)
            echo "0"
            echo
            echo "-debug  - Режим отладки"
            echo "-test   - Тестовый режим, zapret"
            echo
            exit 0 ;;
    esac
done

printheader
main
