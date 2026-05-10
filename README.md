# shell-sing-box for ImmortalWrt

Lightweight sing-box-only system layer for ImmortalWrt/OpenWrt ARM routers.
It replaces the ShellCrash system takeover layer, not your subscription
generator.

## Defaults

- Service: `/etc/init.d/shell-sing-box`
- sing-box binary: `/etc/sing-box/bin/sing-box`
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

If your repository root is the `shell-sing-box` directory itself, omit the
trailing `/shell-sing-box` in `url`.

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

## Configuration

Edit `/etc/sing-box/custom.env`.

Important settings:

- `CORE_VERSION=latest`
- `CORE_ARCH=auto`
- `GITHUB_PROXY_PREFIX=https://gh.llkk.cc/`
- `CORE_DOWNLOAD_PREFIX=https://gh.llkk.cc/`
- `REDIR_PORT=9998`
- `API_PORT=9999`
- `DNS_PORT=1053`
- `API_SECRET=`
- `DNS_DIRECT=223.5.5.5`
- `DNS_PROXY=https://cloudflare-dns.com/dns-query`
- `DNS_RESOLVER=223.5.5.5`
- `MIRROR_PREFIX=https://testingcf.jsdelivr.net/gh/`

Edit `/etc/sing-box/fake_ip_filter.list` for fake-ip exclusions.

## sing-box Core

The installer does not use `opkg install sing-box`. It downloads the latest
stable upstream sing-box release into:

```sh
/etc/sing-box/bin/sing-box
```

Domestic mirror/proxy sources are preferred. The default core download path is:

```text
https://gh.llkk.cc/https://github.com/SagerNet/sing-box/releases/download/...
```

If the proxy fails, the installer falls back to the original GitHub URL.

`CORE_VERSION=latest` follows GitHub's latest non-prerelease release. To pin a
version, set for example:

```sh
CORE_VERSION=v1.12.0
```

`CORE_ARCH=auto` maps `uname -m` to sing-box release assets such as `arm64` or
`armv7`. Override it if your device needs a specific ARM build.

Manual core update:

```sh
/usr/libexec/shell-sing-box/core-install.sh
/etc/init.d/shell-sing-box restart
```

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
