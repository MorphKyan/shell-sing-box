#!/bin/sh

. /usr/libexec/shell-sing-box/common.sh

case "$1" in
    update-srs)
        /usr/libexec/shell-sing-box/generate-system-config.sh &&
        /usr/libexec/shell-sing-box/srs-update.sh &&
        "$SING_BOX_BIN" check -D "$BASE_DIR" -C "$CONFIG_RUNTIME_DIR" &&
        /etc/init.d/shell-sing-box restart
        ;;
    update-dashboard)
        /usr/libexec/shell-sing-box/dashboard.sh install
        ;;
    update-core)
        /usr/libexec/shell-sing-box/core-install.sh &&
        /etc/init.d/shell-sing-box restart
        ;;
    check)
        /usr/libexec/shell-sing-box/prepare.sh
        ;;
    *)
        printf '%s\n' "usage: $0 {update-srs|update-dashboard|update-core|check}"
        exit 1
        ;;
esac
