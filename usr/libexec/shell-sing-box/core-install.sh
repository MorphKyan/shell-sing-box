#!/bin/sh

. /usr/libexec/shell-sing-box/common.sh

CORE_VERSION=${CORE_VERSION:-latest}
CORE_ARCH=${CORE_ARCH:-auto}
CORE_DOWNLOAD_PREFIX=${CORE_DOWNLOAD_PREFIX:-${GITHUB_PROXY_PREFIX:-https://gh.llkk.cc/}}
CORE_RELEASE_BASE=${CORE_RELEASE_BASE:-https://github.com/SagerNet/sing-box/releases/download}

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

latest_version() {
    if [ "$CORE_VERSION" != "latest" ]; then
        printf '%s\n' "$CORE_VERSION"
        return 0
    fi

    tmp="$RUNTIME_DIR/latest.headers"
    mkdir -p "$RUNTIME_DIR"
    rm -f "$tmp"

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
    asset="sing-box-${plain_ver}-linux-${arch}.tar.gz"
    origin="${CORE_RELEASE_BASE}/${ver}/${asset}"
    proxied="${CORE_DOWNLOAD_PREFIX}${origin}"
    out="$RUNTIME_DIR/$asset"

    rm -f "$out"
    if [ -n "$CORE_DOWNLOAD_PREFIX" ] && download "$out" "$proxied"; then
        printf '%s\n' "$out"
        return 0
    fi

    if download "$out" "$origin"; then
        printf '%s\n' "$out"
        return 0
    fi

    printf '%s\n' "ERROR: failed to download sing-box core: $origin" >&2
    return 1
}

install_core() {
    ver=$(latest_version) || exit 1
    arch=$(detect_arch)
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
