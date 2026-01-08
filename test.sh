#!/bin/sh

GREEN="\033[1;32m"
RED="\033[1;31m"
NC="\033[0m"

echo -e "${GREEN}===== Доступность сайтов =====${NC}"

SITES=$(cat <<'EOF'
gosuslugi.ru
esia.gosuslugi.ru
nalog.ru
lkfl2.nalog.ru
rutube.ru
youtube.com
instagram.com
rutor.info
ntc.party
rutracker.org
epidemz.net.co
nnmclub.to
openwrt.org
sxyprn.net
pornhub.com
discord.com
x.com
filmix.my
flightradar24.com
cdn77.com
play.google.com
genderize.io
EOF
)

# Очистка и массив сайтов через while read
sites_clean=$(echo "$SITES" | grep -v '^#' | grep -v '^\s*$')
total=$(echo "$sites_clean" | wc -l)
half=$(( (total + 1) / 2 ))
mapfile -t sites_array < <(echo "$sites_clean")

# Функция проверки
check_site() {
    site="$1"
    # GET-запрос с User-Agent (как браузер), проверка HTTP 200-399
    if curl -s --user-agent "Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36" \
            --connect-timeout 5 --max-time 8 --location \
            -w "%{http_code}" "https://$site" | grep -q "^2[0-9][0-9]$" >/dev/null 2>&1; then
        echo "[${GREEN}OK${NC}]"
    else
        echo "[${RED}FAIL${NC}]"
    fi
}

# Цикл вывода в две колонки
idx=0
while [ $idx -lt $half ]; do
    left="${sites_array[$idx]}"
    right_idx=$((idx + half))
    right="${sites_array[$right_idx]:-}"

    left_pad=$(printf "%-25s" "$left")
    left_color=$(check_site "$left")

    if [ -n "$right" ]; then
        right_pad=$(printf "%-25s" "$right")
        right_color=$(check_site "$right")
        echo -e "$left_color$left_pad $right_color$right_pad"
    else
        echo -e "$left_color$left_pad"
    fi

    idx=$((idx + 1))
done
