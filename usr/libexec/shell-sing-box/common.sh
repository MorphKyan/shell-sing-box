#!/bin/sh

ENV_FILE=${ENV_FILE:-/etc/sing-box/custom.env}
[ -f "$ENV_FILE" ] && . "$ENV_FILE"

BASE_DIR=${BASE_DIR:-/etc/sing-box}
RUNTIME_DIR=${RUNTIME_DIR:-/tmp/shell-sing-box}
CONFIG_SOURCE_FILE=${CONFIG_SOURCE_FILE:-$BASE_DIR/generated/config.json}
CONFIG_RUNTIME_DIR=${CONFIG_RUNTIME_DIR:-$RUNTIME_DIR/config}
RULESET_DIR=${RULESET_DIR:-$BASE_DIR/ruleset}
UI_DIR=${UI_DIR:-$BASE_DIR/ui}
SING_BOX_BIN=${SING_BOX_BIN:-/etc/sing-box/bin/sing-box}
REDIR_PORT=${REDIR_PORT:-9998}
API_PORT=${API_PORT:-9999}
DNS_PORT=${DNS_PORT:-1053}
TUN_NAME=${TUN_NAME:-sbtun0}
TUN_INET4=${TUN_INET4:-28.0.0.1/30}
TUN_INET6=${TUN_INET6:-fc00::1/126}
FAKEIP_INET4=${FAKEIP_INET4:-28.0.0.0/8}
FAKEIP_INET6=${FAKEIP_INET6:-fc00::/16}
NFT_TABLE=${NFT_TABLE:-singbox}
FW_MARK=${FW_MARK:-0x2026}
ROUTE_TABLE=${ROUTE_TABLE:-2026}
DNS_DIRECT=${DNS_DIRECT:-223.5.5.5}
DNS_PROXY=${DNS_PROXY:-https://cloudflare-dns.com/dns-query}
DNS_RESOLVER=${DNS_RESOLVER:-223.5.5.5}
CN_RULESET_TAG=${CN_RULESET_TAG:-cn}
MIRROR_PREFIX=${MIRROR_PREFIX:-https://testingcf.jsdelivr.net/gh/}
GITHUB_PROXY_PREFIX=${GITHUB_PROXY_PREFIX:-https://gh.llkk.cc/}
ENABLE_IPV6=${ENABLE_IPV6:-0}

log() {
    logger -t shell-sing-box "$*"
    printf '%s\n' "$*" >&2
}

die() {
    log "ERROR: $*"
    exit 1
}

need_cmd() {
    command -v "$1" >/dev/null 2>&1 || die "missing command: $1"
}

mkdirs() {
    mkdir -p "$BASE_DIR" "$RUNTIME_DIR" "$CONFIG_RUNTIME_DIR" "$RULESET_DIR" "$UI_DIR"
}

download() {
    out=$1
    url=$2
    tmp="${out}.tmp.$$"
    mkdir -p "$(dirname "$out")" || return 1
    rm -f "$tmp"
    if command -v wget >/dev/null 2>&1; then
        wget --no-check-certificate -T 10 -q -O "$tmp" "$url" || { rm -f "$tmp"; return 1; }
    elif command -v curl >/dev/null 2>&1; then
        curl -L -kfsS --connect-timeout 10 -o "$tmp" "$url" || { rm -f "$tmp"; return 1; }
    else
        return 1
    fi
    [ -s "$tmp" ] && mv -f "$tmp" "$out" && return 0
    rm -f "$tmp"
    return 1
}

mirror_url() {
    url=$1
    case "$url" in
        https://raw.githubusercontent.com/*)
            path=${url#https://raw.githubusercontent.com/}
            owner_repo=$(printf '%s' "$path" | cut -d/ -f1,2)
            branch=$(printf '%s' "$path" | cut -d/ -f3)
            rest=$(printf '%s' "$path" | cut -d/ -f4-)
            printf '%s%s@%s/%s\n' "$MIRROR_PREFIX" "$owner_repo" "$branch" "$rest"
            ;;
        https://github.com/*/raw/*)
            path=${url#https://github.com/}
            owner_repo=$(printf '%s' "$path" | cut -d/ -f1,2)
            branch=$(printf '%s' "$path" | cut -d/ -f4)
            rest=$(printf '%s' "$path" | cut -d/ -f5-)
            printf '%s%s@%s/%s\n' "$MIRROR_PREFIX" "$owner_repo" "$branch" "$rest"
            ;;
        *)
            case "$url" in
                https://github.com/*|https://raw.githubusercontent.com/*)
                    printf '%s%s\n' "$GITHUB_PROXY_PREFIX" "$url"
                    ;;
                *)
                    printf '%s\n' "$url"
                    ;;
            esac
            ;;
    esac
}

json_escape() {
    sed 's/\\/\\\\/g; s/"/\\"/g' "$1"
}

csv_to_json_array() {
    printf '%s' "$1" | awk -F',' '{
        for (i=1; i<=NF; i++) {
            gsub(/^[ \t]+|[ \t]+$/, "", $i)
            if ($i != "") {
                if (n++) printf ", "
                printf "\"%s\"", $i
            }
        }
    }'
}

lan_ipv4_list() {
    ip -4 route show scope link 2>/dev/null |
        grep -Ev '(^default| wan|ppp|tun|utun|sbtun|docker|podman|virbr|vnet|vmbr|veth|wg|tailscale|zt)' |
        awk '{print $1}' |
        grep -E '/[0-9]+$' |
        tr '\n' ' ' |
        sed 's/[[:space:]]*$//'
}

lan_ipv6_list() {
    ip -6 route show 2>/dev/null |
        grep -Ev '(^default|unreachable|fe80::/| wan|ppp|tun|utun|sbtun|docker|podman|virbr|vnet|vmbr|veth|wg|tailscale|zt)' |
        awk '{print $1}' |
        grep -E '/[0-9]+$' |
        tr '\n' ' ' |
        sed 's/[[:space:]]*$//'
}
