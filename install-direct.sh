#!/bin/sh
# Podkop: отдельная секция прямой маршрутизации для Podkop.

LIST_URL='https://raw.githubusercontent.com/oxvay/routing-data/refs/heads/main/domains.txt'
SECTION='direct'
CONFIG='/etc/config/podkop'
BACKUP="/etc/config/podkop.backup-direct-$(date +%Y%m%d-%H%M%S)-$$"
TEMP_LIST="/tmp/podkop-direct-check-$$"

cleanup() {
    rm -f "$TEMP_LIST"
}
trap cleanup EXIT HUP INT TERM

if [ "$(id -u)" != 0 ]; then
    echo 'ОШИБКА: запусти скрипт от root.'
    exit 1
fi
if ! command -v uci >/dev/null 2>&1 || ! command -v wget >/dev/null 2>&1 ||
   [ ! -f "$CONFIG" ] || [ ! -x /etc/init.d/podkop ]; then
    echo 'ОШИБКА: Podkop, uci или wget не найдены.'
    exit 1
fi
if [ -n "$(uci changes podkop)" ]; then
    echo 'ОШИБКА: есть неприменённые изменения Podkop. Сначала примени или отмени их в LuCI.'
    exit 1
fi
if uci -q get "podkop.$SECTION" >/dev/null; then
    echo "ОШИБКА: секция $SECTION уже существует. Изменений нет."
    exit 1
fi

echo 'Проверяю доступность списка...'
if ! wget -q -T 20 -O "$TEMP_LIST" "$LIST_URL" || [ ! -s "$TEMP_LIST" ]; then
    echo 'ОШИБКА: список недоступен или пуст. Изменений нет.'
    exit 1
fi
if grep -qiE '<!doctype html|<html' "$TEMP_LIST"; then
    echo 'ОШИБКА: сервер вернул HTML вместо списка. Изменений нет.'
    exit 1
fi

umask 077
if ! cp -p "$CONFIG" "$BACKUP"; then
    echo 'ОШИБКА: не удалось сохранить резервную копию.'
    exit 1
fi

restore() {
    echo 'Восстанавливаю прежний конфиг Podkop...'
    uci -q revert podkop
    if cp -p "$BACKUP" "$CONFIG"; then
        if /etc/init.d/podkop restart; then
            echo "Конфиг восстановлен из $BACKUP"
        else
            echo "Конфиг восстановлен, но перезапуск завершился с ошибкой. Копия: $BACKUP"
        fi
    else
        echo "ОШИБКА восстановления. Резервная копия: $BACKUP"
    fi
}

if ! uci set "podkop.$SECTION=section" ||
   ! uci set "podkop.$SECTION.connection_type=exclusion" ||
   ! uci add_list "podkop.$SECTION.community_lists=russia_outside" ||
   ! uci add_list "podkop.$SECTION.remote_domain_lists=$LIST_URL" ||
   ! uci commit podkop; then
    echo 'ОШИБКА: не удалось сохранить настройки.'
    restore
    exit 1
fi

echo 'Применяю настройки Podkop...'
if ! /etc/init.d/podkop restart; then
    echo 'ОШИБКА: перезапуск Podkop завершился с ошибкой.'
    restore
    exit 1
fi

echo 'ГОТОВО: создана секция direct с Russia outside и списком доменов.'
echo "Резервная копия: $BACKUP"
echo 'Проверь работу нужных сайтов через роутер.'
