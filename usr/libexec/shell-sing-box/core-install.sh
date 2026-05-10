#!/bin/sh

. /usr/libexec/shell-sing-box/common.sh

CORE_VERSION=${CORE_VERSION:-latest}
CORE_ARCH=${CORE_ARCH:-auto}
CORE_REPO_BASE=${CORE_REPO_BASE:-https://testingcf.jsdelivr.net/gh/MorphKyan/shell-sing-box}
CORE_REPO_RAW_BASE=${CORE_REPO_RAW_BASE:-https://ghproxy.net/https://raw.githubusercontent.com/MorphKyan/shell-sing-box}
CORE_REPO_ORIGIN_RAW_BASE=${CORE_REPO_ORIGIN_RAW_BASE:-https://raw.githubusercontent.com/MorphKyan/shell-sing-box}
CORE_REPO_BRANCH=${CORE_REPO_BRANCH:-update}
CORE_REPO_PATH=${CORE_REPO_PATH:-bin/sing-box}
CORE_DOWNLOAD_PREFIX=${CORE_DOWNLOAD_PREFIX:-${GITHUB_PROXY_PREFIX:-https://gh.llkk.cc/}}
CORE_RELEASE_BASE=${CORE_RELEASE_BASE:-https://github.com/SagerNet/sing-box/releases/download}
CORE_ALLOW_RELEASE_FALLBACK=${CORE_ALLOW_RELEASE_FALLBACK:-0}

detect_arch() {
    if [ "$CORE_ARCH" != "auto" ] && [ -n "$CORE_ARCH" ]; then
        printf '%s\n' "$CORE_ARCH"
        return 0
    fi

    case "$(uname -m)" in
        aarch64|arm64) printf '%s\n' arm64 ;;
        armv7l|armv7*) printf '%s\n' armv7 ;;
        armv6l|armv6*) printf '%s\n' armv6 ;;
        armv5l|armv5*) printf '%s\n' armv5 ;;
        x86_64|amd64) printf '%s\n' amd64 ;;
        mipsle) printf '%s\n' mipsle ;;
        mips) printf '%s\n' mips ;;
        *)
            die "unsupported arch: $(uname -m). Set CORE_ARCH manually in $ENV_FILE"
            ;;
    esac
}

detect_asset_arch() {
    if [ -f /etc/openwrt_release ]; then
        owrt_arch=$(sed -n "s/^DISTRIB_ARCH='\([^']*\)'.*/\1/p" /etc/openwrt_release | head -n 1)
        [ -n "$owrt_arch" ] && printf 'openwrt-%s\n' "$owrt_arch" && return 0
    fi
    detect_arch
}

asset_name() {
    ver=$1
    arch=$2
    plain_ver=${ver#v}
    case "$arch" in
        openwrt-*) printf 'sing-box-%s-%s.tar.gz\n' "$plain_ver" "$arch" ;;
        *) printf 'sing-box-%s-linux-%s.tar.gz\n' "$plain_ver" "$arch" ;;
    esac
}

latest_version() {
    if [ "$CORE_VERSION" != "latest" ]; then
        printf '%s\n' "$CORE_VERSION"
        return 0
    fi

    tmp="$RUNTIME_DIR/latest.headers"
    api_json="$RUNTIME_DIR/latest.json"
    mkdir -p "$RUNTIME_DIR"
    rm -f "$tmp" "$api_json"

    if download "$api_json" "https://api.github.com/repos/SagerNet/sing-box/releases/latest"; then
        ver=$(grep '"tag_name"' "$api_json" | head -n 1 | sed 's/.*"tag_name"[[:space:]]*:[[:space:]]*"//;s/".*//')
        case "$ver" in
            v[0-9]*) printf '%s\n' "$ver"; return 0 ;;
        esac
    fi

    latest_url=https://github.com/SagerNet/sing-box/releases/latest
    proxied_latest="${CORE_DOWNLOAD_PREFIX}${latest_url}"

    if command -v curl >/dev/null 2>&1; then
        final_url=$(curl -kfsSLI -o /dev/null -w '%{url_effective}' "$proxied_latest" 2>/dev/null)
        [ -n "$final_url" ] || final_url=$(curl -kfsSLI -o /dev/null -w '%{url_effective}' "$latest_url" 2>/dev/null)
    elif command -v wget >/dev/null 2>&1; then
        wget --spider --server-response "$proxied_latest" >"$tmp" 2>&1 || true
        final_url=$(awk '/Location: / {u=$2} END {print u}' "$tmp" | tr -d '\r')
        if [ -z "$final_url" ]; then
            wget --spider --server-response "$latest_url" >"$tmp" 2>&1 || true
            final_url=$(awk '/Location: / {u=$2} END {print u}' "$tmp" | tr -d '\r')
        fi
    else
        die "missing curl/wget"
    fi

    ver=$(printf '%s\n' "$final_url" | sed -n 's#.*/tag/\(v[0-9][^/?#]*\).*#\1#p')
    [ -n "$ver" ] || ver=${final_url##*/}
    case "$ver" in
        v[0-9]*) printf '%s\n' "$ver" ;;
        *)
            printf '%s\n' "ERROR: failed to resolve latest stable sing-box version from: $final_url" >&2
            return 1
            ;;
    esac
}

download_core() {
    ver=$1
    arch=$2
    plain_ver=${ver#v}
    asset=$(asset_name "$ver" "$arch")
    repo_path=${CORE_REPO_PATH%/}
    repo_base=${CORE_REPO_BASE%/}
    repo_raw_base=${CORE_REPO_RAW_BASE%/}
    repo_origin_raw_base=${CORE_REPO_ORIGIN_RAW_BASE%/}
    repo_url="${repo_base}@${CORE_REPO_BRANCH}/${repo_path}/${asset}"
    repo_raw_url="${repo_raw_base}/${CORE_REPO_BRANCH}/${repo_path}/${asset}"
    repo_origin_raw_url="${repo_origin_raw_base}/${CORE_REPO_BRANCH}/${repo_path}/${asset}"
    origin="${CORE_RELEASE_BASE}/${ver}/${asset}"
    proxied="${CORE_DOWNLOAD_PREFIX}${origin}"
    out="$RUNTIME_DIR/$asset"

    try_archive() {
        url=$1
        rm -f "$out"
        if download "$out" "$url"; then
            printf '%s\n' "$out"
            return 0
        fi
        rm -f "$out"
        return 1
    }

    rm -f "$out"
    if [ -n "$CORE_REPO_RAW_BASE" ] && try_archive "$repo_raw_url"; then
        return 0
    fi

    if [ -n "$CORE_REPO_BASE" ] && try_archive "$repo_url"; then
        return 0
    fi

    if [ -n "$CORE_REPO_ORIGIN_RAW_BASE" ] && try_archive "$repo_origin_raw_url"; then
        return 0
    fi

    if [ "$CORE_ALLOW_RELEASE_FALLBACK" = "1" ]; then
        if [ -n "$CORE_DOWNLOAD_PREFIX" ] && try_archive "$proxied"; then
            return 0
        fi
        if try_archive "$origin"; then
            return 0
        fi
    fi

    printf '%s\n' "ERROR: failed to download sing-box core: $repo_raw_url" >&2
    printf '%s\n' "ERROR: put $asset under ${CORE_REPO_PATH%/} on branch $CORE_REPO_BRANCH, or set CORE_ALLOW_RELEASE_FALLBACK=1" >&2
    return 1
}

install_core() {
    ver=$(latest_version) || exit 1
    arch=$(detect_asset_arch)
    archive=$(download_core "$ver" "$arch") || exit 1
    tmpdir="$RUNTIME_DIR/core.$$"
    bindir=$(dirname "$SING_BOX_BIN")

    rm -rf "$tmpdir"
    mkdir -p "$tmpdir" "$bindir"
    tar -zxf "$archive" -C "$tmpdir" || die "failed to extract $archive"
    core=$(find "$tmpdir" -type f -name sing-box | head -n 1)
    [ -n "$core" ] || die "sing-box binary not found in archive"
    mv -f "$core" "$SING_BOX_BIN"
    chmod 755 "$SING_BOX_BIN"
    rm -rf "$tmpdir" "$archive"

    "$SING_BOX_BIN" version | head -n 1
    log "sing-box core installed: $SING_BOX_BIN ($ver linux-$arch)"
}

install_core "$@"
