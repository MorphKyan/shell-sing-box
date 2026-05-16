#!/bin/sh

. /usr/libexec/shell-sing-box/common.sh

ZASHBOARD_URL=${ZASHBOARD_URL:-https://ghproxy.net/https://github.com/Zephyruso/zashboard/releases/latest/download/dist.zip}
ZASHBOARD_ORIGIN_URL=${ZASHBOARD_ORIGIN_URL:-https://github.com/Zephyruso/zashboard/releases/latest/download/dist.zip}

install_dashboard() {
    mkdirs
    tmp="$RUNTIME_DIR/zashboard.zip"
    tmp_ui="$RUNTIME_DIR/ui.$$"
    mkdir -p "$RUNTIME_DIR"

    download "$tmp" "$ZASHBOARD_URL" || download "$tmp" "$ZASHBOARD_ORIGIN_URL" || die "failed to download Zashboard: $ZASHBOARD_URL"
    rm -rf "$tmp_ui"
    mkdir -p "$tmp_ui"
    if busybox unzip -oq "$tmp" -d "$tmp_ui" 2>/dev/null; then
        :
    elif unzip -oq "$tmp" -d "$tmp_ui" 2>/dev/null; then
        :
    else
        rm -rf "$tmp_ui"
        die "failed to extract Zashboard archive (busybox unzip not available)"
    fi

    if [ ! -s "$tmp_ui/index.html" ]; then
        first_index=$(find "$tmp_ui" -name index.html | head -n 1)
        if [ -z "$first_index" ]; then
            rm -rf "$tmp_ui"
            die "Zashboard archive has no index.html"
        fi
        inner_dir=$(dirname "$first_index")
        if [ "$inner_dir" != "$tmp_ui" ]; then
            normalized_ui="$RUNTIME_DIR/ui.normalized.$$"
            rm -rf "$normalized_ui"
            mkdir -p "$normalized_ui"
            cp -R "$inner_dir"/. "$normalized_ui"/
            rm -rf "$tmp_ui"
            mv "$normalized_ui" "$tmp_ui"
        fi
    fi

    rm -rf "$UI_DIR"
    mv "$tmp_ui" "$UI_DIR"
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
