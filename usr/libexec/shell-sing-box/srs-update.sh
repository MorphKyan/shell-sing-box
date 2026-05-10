#!/bin/sh

. /usr/libexec/shell-sing-box/common.sh

extract_srs_entries() {
    awk '
        /"type"[[:space:]]*:[[:space:]]*"remote"/ { remote=1; url=""; path="" }
        remote && /"url"[[:space:]]*:/ {
            line=$0
            sub(/^.*"url"[[:space:]]*:[[:space:]]*"/, "", line)
            sub(/".*$/, "", line)
            url=line
        }
        remote && /"path"[[:space:]]*:/ {
            line=$0
            sub(/^.*"path"[[:space:]]*:[[:space:]]*"/, "", line)
            sub(/".*$/, "", line)
            path=line
        }
        remote && /\}/ {
            if (url ~ /\.srs([?#].*)?$/) print url "|" path
            remote=0
        }
    ' "$CONFIG_RUNTIME_DIR"/*.json 2>/dev/null
}

safe_name() {
    name=${1%%\?*}
    name=${name##*/}
    [ -n "$name" ] || name=ruleset.srs
    printf '%s\n' "$name"
}

download_srs() {
    url=$1
    path=$2
    [ -n "$url" ] || return 0
    [ -n "$path" ] || path="$RULESET_DIR/$(safe_name "$url")"
    case "$path" in
        /*) ;;
        *) path="$BASE_DIR/$path" ;;
    esac

    mkdir -p "$(dirname "$path")"
    mirror=$(mirror_url "$url")
    proxied="${GITHUB_PROXY_PREFIX}${url}"

    if download "$path" "$mirror"; then
        log "updated SRS: $path"
        return 0
    fi

    if [ "$proxied" != "$mirror" ] && [ "$proxied" != "$url" ] && download "$path" "$proxied"; then
        log "updated SRS from GitHub proxy: $path"
        return 0
    fi

    if download "$path" "$url"; then
        log "updated SRS from origin: $path"
        return 0
    fi

    if [ -s "$path" ]; then
        log "SRS download failed, using cached file: $path"
        return 0
    fi

    log "SRS download failed and no cache exists: $url"
    return 1
}

main() {
    mkdirs
    rc=0
    entry_file="$RUNTIME_DIR/srs.entries"
    extract_srs_entries > "$entry_file"
    [ -s "$entry_file" ] || {
        log "no remote SRS rule_set found"
        rm -f "$entry_file"
        return 0
    }
    while IFS='|' read -r url path; do
        download_srs "$url" "$path" || rc=1
    done < "$entry_file"
    rm -f "$entry_file"
    return "$rc"
}

main "$@"
