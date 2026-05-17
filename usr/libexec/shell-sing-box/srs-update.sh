#!/bin/sh

. /usr/libexec/shell-sing-box/common.sh

extract_srs_entries() {
    awk '
        function reset_pending() {
            pending_string = ""
            pending_depth = 0
        }

        function assign_string_value(depth, key, value) {
            if (key == "type") {
                obj_type[depth] = value
            } else if (key == "url") {
                obj_url[depth] = value
            } else if (key == "path") {
                obj_path[depth] = value
            }
        }

        function open_object() {
            if (obj_depth > 0 && expect_key[obj_depth] != "") {
                expect_key[obj_depth] = ""
            }
            obj_depth++
            obj_type[obj_depth] = ""
            obj_url[obj_depth] = ""
            obj_path[obj_depth] = ""
            expect_key[obj_depth] = ""
            reset_pending()
        }

        function close_object() {
            if (obj_depth < 1) {
                reset_pending()
                return
            }
            if (obj_type[obj_depth] == "remote" && obj_url[obj_depth] ~ /\.srs([?#].*)?$/) {
                print obj_url[obj_depth] "|" obj_path[obj_depth]
            }
            delete obj_type[obj_depth]
            delete obj_url[obj_depth]
            delete obj_path[obj_depth]
            delete expect_key[obj_depth]
            obj_depth--
            reset_pending()
        }

        function string_token(value) {
            if (obj_depth > 0 && expect_key[obj_depth] != "") {
                assign_string_value(obj_depth, expect_key[obj_depth], value)
                expect_key[obj_depth] = ""
                reset_pending()
            } else {
                pending_string = value
                pending_depth = obj_depth
            }
        }

        function punctuation_token(ch) {
            if (ch == "{") {
                open_object()
            } else if (ch == "}") {
                close_object()
            } else if (ch == ":") {
                if (obj_depth > 0 && pending_depth == obj_depth && pending_string != "") {
                    expect_key[obj_depth] = pending_string
                }
                reset_pending()
            } else {
                if (ch == "[" && obj_depth > 0 && expect_key[obj_depth] != "") {
                    expect_key[obj_depth] = ""
                }
                reset_pending()
            }
        }

        function scalar_token() {
            if (obj_depth > 0 && expect_key[obj_depth] != "") {
                expect_key[obj_depth] = ""
            }
            reset_pending()
        }

        {
            for (i = 1; i <= length($0); i++) {
                ch = substr($0, i, 1)
                if (in_string) {
                    if (escaped) {
                        string_value = string_value ch
                        escaped = 0
                    } else if (ch == "\\") {
                        escaped = 1
                    } else if (ch == "\"") {
                        in_string = 0
                        string_token(string_value)
                        string_value = ""
                    } else {
                        string_value = string_value ch
                    }
                    continue
                }

                if (ch ~ /[[:space:]]/) {
                    continue
                } else if (ch == "\"") {
                    in_string = 1
                    escaped = 0
                    string_value = ""
                } else if (ch == "{" || ch == "}" || ch == "[" || ch == "]" || ch == ":" || ch == ",") {
                    punctuation_token(ch)
                } else {
                    scalar_token()
                }
            }
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
    missing_only=0
    [ "$1" = "--missing-only" ] && missing_only=1

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
        [ -n "$url" ] || continue
        [ -n "$path" ] || path="$RULESET_DIR/$(safe_name "$url")"
        case "$path" in
            /*) ;;
            *) path="$BASE_DIR/$path" ;;
        esac
        if [ "$missing_only" = "1" ] && [ -s "$path" ]; then
            continue
        fi
        download_srs "$url" "$path" || rc=1
    done < "$entry_file"
    rm -f "$entry_file"
    return "$rc"
}

main "$@"
