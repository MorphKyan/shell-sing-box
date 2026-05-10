#!/bin/sh

. /usr/libexec/shell-sing-box/common.sh

main() {
    need_cmd "$SING_BOX_BIN"
    need_cmd ip
    need_cmd nft
    mkdirs
    /usr/libexec/shell-sing-box/generate-system-config.sh
    [ "$UPDATE_SRS_ON_START" = "1" ] && /usr/libexec/shell-sing-box/srs-update.sh || true
    [ "$UPDATE_DASHBOARD_ON_START" = "1" ] && /usr/libexec/shell-sing-box/dashboard.sh install || true
    "$SING_BOX_BIN" check -D "$BASE_DIR" -C "$CONFIG_RUNTIME_DIR"
}

main "$@"
