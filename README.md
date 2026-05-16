# shell-sing-box for ImmortalWrt

Lightweight sing-box-only system layer for ImmortalWrt/OpenWrt ARM routers.
It replaces the ShellCrash system takeover layer, not your subscription
generator.

## Defaults

- Service: `/etc/init.d/shell-sing-box`
- sing-box runtime binary: `/tmp/shell-sing-box/bin/sing-box`
- Generated config input: `/etc/sing-box/generated/config.json`
- Runtime config directory: `/tmp/shell-sing-box/config`
- TCP transparent redirect inbound: `9998`
- DNS hijack inbound: `1053`
- Clash API / Zashboard: `9999`
- nftables table: `inet singbox`
- Rule-set cache: `/etc/sing-box/ruleset`
- UI directory: `/etc/sing-box/ui`
- TUN interface: `sbtun0`
- fake-ip range: `28.0.0.0/8`

## Install

Remote install, ShellCrash-style:

```sh
export url='https://testingcf.jsdelivr.net/gh/<owner>/<repo>@<branch>/shell-sing-box' \
  && sh -c "$(curl -kfsSL $url/install.sh)"
```

If `curl` is not available, use `wget`:

```sh
export url='https://testingcf.jsdelivr.net/gh/<owner>/<repo>@<branch>/shell-sing-box' \
  && wget --no-check-certificate -q -O /tmp/shell-sing-box-install.sh "$url/install.sh" \
  && sh /tmp/shell-sing-box-install.sh
```

If your repository root is the `shell-sing-box` directory itself, omit the
trailing `/shell-sing-box` in `url`.

GitHub raw install, useful when CDN cache is stale:

```sh
export url='https://raw.githubusercontent.com/MorphKyan/shell-sing-box/main' \
  && sh -c "$(curl -kfsSL $url/install.sh)"
```

GitHub raw with `wget`:

```sh
export url='https://raw.githubusercontent.com/MorphKyan/shell-sing-box/main' \
  && wget --no-check-certificate -q -O /tmp/shell-sing-box-install.sh "$url/install.sh" \
  && sh /tmp/shell-sing-box-install.sh
```

Copy this directory to the router and run:

```sh
chmod +x install.sh
./install.sh
```

Then put your generator output at:

```sh
/etc/sing-box/generated/config.json
```

Start the service:

```sh
/etc/init.d/shell-sing-box start
```

## Management CLI

We provide an interactive `ssb` management interface similar to ShellCrash. Simply run:

```sh
ssb
```

to start/stop the service, configure subscriptions, install dashboards, and set cron jobs interactively.

You can also use direct commands:

```sh
ssb start    # Start service
ssb stop     # Stop service
ssb restart  # Restart service
ssb update   # Update subscription
ssb upgrade  # Upgrade Shell-Sing-Box and sing-box core
```

## Configuration

Edit `/etc/sing-box/custom.env`.

Important settings:

- `CORE_VERSION=v1.13.11`
- `CORE_ARCH=auto`
- `CORE_REPO_BASE=https://testingcf.jsdelivr.net/gh/MorphKyan/shell-sing-box`
- `CORE_REPO_RAW_BASE=https://ghproxy.net/https://raw.githubusercontent.com/MorphKyan/shell-sing-box`
- `CORE_REPO_ORIGIN_RAW_BASE=https://raw.githubusercontent.com/MorphKyan/shell-sing-box`
- `CORE_REPO_BRANCH=update`
- `CORE_REPO_PATH=bin/sing-box`
- `GITHUB_PROXY_PREFIX=https://gh.llkk.cc/`
- `CORE_DOWNLOAD_PREFIX=https://gh.llkk.cc/`
- `CORE_ALLOW_RELEASE_FALLBACK=0`
- `SHELL_SING_BOX_REPO_BASE=https://testingcf.jsdelivr.net/gh/MorphKyan/shell-sing-box`
- `SHELL_SING_BOX_CHANNEL=latest`
- `REDIR_PORT=9998`
- `API_PORT=9999`
- `DNS_PORT=1053`
- `API_SECRET=`
- `DNS_DIRECT=223.5.5.5`
- `DNS_PROXY=https://cloudflare-dns.com/dns-query`
- `DNS_RESOLVER=223.5.5.5`
- `MIRROR_PREFIX=https://testingcf.jsdelivr.net/gh/`

Edit `/etc/sing-box/fake_ip_filter.list` for fake-ip exclusions.

`ssb upgrade` downloads the latest Shell-Sing-Box release from jsDelivr by
default, updates program files and sing-box core, and preserves existing
`/etc/sing-box/custom.env` and `/etc/sing-box/fake_ip_filter.list`. New default
copies are written as `.default` files when user config already exists.

## sing-box Core

The installer does not use `opkg install sing-box`. By default it follows the
ShellCrash packaging style: sing-box archives are prepacked in this project's
`update` branch and extracted into tmpfs:

```sh
/tmp/shell-sing-box/bin/sing-box
```

This avoids filling small OpenWrt overlay partitions with the 60MB+ uncompressed
binary. If tmpfs is cleared after reboot, `prepare.sh` downloads and extracts the
core again before starting sing-box.

Default core download order:

1. GitHub raw mirror package:
   `https://ghproxy.net/https://raw.githubusercontent.com/MorphKyan/shell-sing-box/update/bin/sing-box/<asset>`
2. jsDelivr project package:
   `https://testingcf.jsdelivr.net/gh/MorphKyan/shell-sing-box@update/bin/sing-box/<asset>`
3. GitHub raw project package:
   `https://raw.githubusercontent.com/MorphKyan/shell-sing-box/update/bin/sing-box/<asset>`
4. Optional upstream release fallback, only when `CORE_ALLOW_RELEASE_FALLBACK=1`

For OpenWrt/ImmortalWrt, the installer reads `DISTRIB_ARCH` from
`/etc/openwrt_release` and selects pre-extracted OpenWrt assets like:

```text
sing-box-1.13.11-openwrt-aarch64_cortex-a53.tar.gz
```

The primary package URL is:

```text
https://ghproxy.net/https://raw.githubusercontent.com/MorphKyan/shell-sing-box/update/bin/sing-box/sing-box-1.13.11-openwrt-aarch64_cortex-a53.tar.gz
```

The jsDelivr package URL is also configured as a fallback:

```text
https://testingcf.jsdelivr.net/gh/MorphKyan/shell-sing-box@update/bin/sing-box/sing-box-1.13.11-openwrt-aarch64_cortex-a53.tar.gz
```

If you explicitly enable upstream fallback, the proxy URL is:

```text
https://gh.llkk.cc/https://github.com/SagerNet/sing-box/releases/download/...
```

The default does not fetch GitHub Release assets. To update the packaged core,
extract `/usr/bin/sing-box` from the official OpenWrt `.ipk`, package it as a
tar.gz archive, and upload it to the `update` branch under `bin/sing-box/`. The
downloaded archive is extracted and the installed binary is checked with
`sing-box version`.

The installer keeps a ShellCrash-style minimal footprint: it only installs
missing hard requirements, and does not install convenience packages such as
`curl`, `libcurl`, `libnghttp2`, `unzip`, or certificate bundles.

Hard requirements are:

- `nft`
- `ip`
- `wget` or `curl`
- TUN kernel support

If these are missing and `opkg` exists, the installer only tries to install the
corresponding minimal packages:

```text
nftables ip-full wget-ssl kmod-tun
```

It assumes the base firmware already has `sh`, `tar`, `gzip`, `awk`, `sed`,
`grep`, `find`, and other BusyBox basics.

The default `CORE_VERSION` is pinned to the packaged core version:

```sh
CORE_VERSION=v1.13.11
```

This matches the ShellCrash-style prepacked archive under the `update` branch.
You may set `CORE_VERSION=latest`, but then the matching archive must also
exist under `bin/sing-box/`, otherwise startup will fail unless upstream release
fallback is explicitly enabled.

`CORE_ARCH=auto` maps `uname -m` to sing-box release assets such as `arm64` or
`armv7`. Override it if your device needs a specific ARM build.

Manual core update:

```sh
/usr/libexec/shell-sing-box/core-install.sh
/etc/init.d/shell-sing-box restart
```

## GitHub Actions Core Build

`.github/workflows/build-core.yml` builds the slim sing-box core.

Current build tags:

```text
with_quic,with_utls,with_clash_api,badlinkname,tfogo_checklinkname0
```

This keeps QUIC, uTLS, and Clash API while excluding heavier features such as
gVisor, WireGuard, Tailscale, NaiveProxy, ACME, and DHCP. Manual workflow runs
can optionally publish the packaged core to the `update` branch.

The workflow injects `github.com/sagernet/sing-box/constant.Version`, so
`sing-box version` reports the selected release instead of `unknown`.

## SRS behavior

The service scans remote `.srs` rule sets in the runtime sing-box config and
downloads them before starting. If a rule-set has a `path`, the file is cached
there. If not, startup injects a runtime-only local path under
`/etc/sing-box/ruleset` by filename.

For GitHub-hosted SRS URLs, the updater tries the domestic mirror first:

```text
https://testingcf.jsdelivr.net/gh/<owner>/<repo>@<branch>/<path>
```

If that fails, it tries the GitHub proxy prefix, then the original URL.

The generator should preferably emit rule sets with explicit local paths, for
example:

```json
{
  "type": "remote",
  "tag": "cn",
  "format": "binary",
  "path": "/etc/sing-box/ruleset/cn.srs",
  "url": "https://raw.githubusercontent.com/DustinWin/ruleset_geodata/sing-box-ruleset/cn.srs",
  "download_detour": "DIRECT"
}
```

Manual update:

```sh
/usr/libexec/shell-sing-box/task.sh update-srs
```

Example cron:

```sh
0 4 * * * /usr/libexec/shell-sing-box/task.sh update-srs
```

## Zashboard

Install or refresh Zashboard:

```sh
/usr/libexec/shell-sing-box/task.sh update-dashboard
```

Dashboard extraction uses existing `unzip` or `busybox unzip`. If neither is
available, install a dashboard manually into `/etc/sing-box/ui`, or install
`unzip` yourself.

Open:

```text
http://<router-lan-ip>:9999/ui
```

WAN access to `9998`, `9999`, and `1053` is rejected by the custom nft table.

## Design Notes

This implementation intentionally does not support tproxy, iptables, mihomo, or
manual mixed proxy exposure. It uses nftables because current ImmortalWrt uses
fw4/nftables, and an independent `inet singbox` table is easy to install and
remove without touching the main firewall configuration.
