#!/bin/sh

. /usr/libexec/shell-sing-box/common.sh

ZASHBOARD_URL=${ZASHBOARD_URL:-https://ghproxy.net/https://github.com/Zephyruso/zashboard/releases/latest/download/dist.zip}
ZASHBOARD_ORIGIN_URL=${ZASHBOARD_ORIGIN_URL:-https://github.com/Zephyruso/zashboard/releases/latest/download/dist.zip}

install_dashboard() {
    mkdirs
    tmp="$RUNTIME_DIR/zashboard.zip"
    mkdir -p "$RUNTIME_DIR"

    if [ -s "$UI_DIR/index.html" ]; then
        log "Zashboard already installed: $UI_DIR"
        return 0
    fi

    download "$tmp" "$ZASHBOARD_URL" || download "$tmp" "$ZASHBOARD_ORIGIN_URL" || die "failed to download Zashboard: $ZASHBOARD_URL"
    rm -rf "$UI_DIR"
    mkdir -p "$UI_DIR"
    if busybox unzip -oq "$tmp" -d "$UI_DIR" 2>/dev/null; then
        :
    elif unzip -oq "$tmp" -d "$UI_DIR" 2>/dev/null; then
        :
    else
        die "failed to extract Zashboard archive (busybox unzip not available)"
    fi

    if [ ! -s "$UI_DIR/index.html" ]; then
        first_index=$(find "$UI_DIR" -name index.html | head -n 1)
        [ -n "$first_index" ] || die "Zashboard archive has no index.html"
        inner_dir=$(dirname "$first_index")
        if [ "$inner_dir" != "$UI_DIR" ]; then
            tmp_ui="$RUNTIME_DIR/ui.$$"
            mkdir -p "$tmp_ui"
            cp -R "$inner_dir"/. "$tmp_ui"/
            rm -rf "$UI_DIR"
            mv "$tmp_ui" "$UI_DIR"
        fi
    fi

    rm -f "$tmp"
    log "Zashboard installed: $UI_DIR"
}

uninstall_dashboard() {
    if [ -d "$UI_DIR" ]; then
        rm -rf "$UI_DIR"
        log "Zashboard uninstalled: $UI_DIR"
    else
        log "Zashboard not installed, nothing to do"
    fi
}

case "$1" in
    install|"") install_dashboard ;;
    uninstall) uninstall_dashboard ;;
    *) die "unknown dashboard command: $1" ;;
esac
