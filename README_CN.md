# shell-sing-box for ImmortalWrt

这是一个面向 ImmortalWrt/OpenWrt ARM 路由器的轻量 sing-box 系统层，用来替代 ShellCrash 的“系统接管”部分。它不负责订阅转换，你仍然使用自己的订阅生成器输出 sing-box 配置。

## 功能范围

- 只支持 sing-box。
- 只使用 nftables，不支持 iptables。
- 使用 `procd` 管理服务。
- 固定透明代理模式：TCP redir + sing-box tun。
- 不支持 tproxy。
- 支持 fake-ip + CN SRS 规则直连混合 DNS。
- 支持 fake-ip 缓存。
- 支持 fake-ip filter。
- 支持自动下载和更新 `.srs` 规则集。
- 支持下载和配置 Zashboard 面板。
- 默认阻止 WAN 访问透明代理端口和 API 端口。

## 默认配置

- 服务：`/etc/init.d/shell-sing-box`
- sing-box 运行时内核：`/tmp/shell-sing-box/bin/sing-box`
- 订阅生成器输出：`/etc/sing-box/generated/config.json`
- 运行时配置目录：`/tmp/shell-sing-box/config`
- TCP redir 入站端口：`9998`
- DNS 劫持入站端口：`1053`
- Clash API / Zashboard 端口：`9999`
- nftables 表：`table inet singbox`
- SRS 缓存目录：`/etc/sing-box/ruleset`
- 面板目录：`/etc/sing-box/ui`
- TUN 接口：`sbtun0`
- fake-ip IPv4 地址段：`28.0.0.0/8`

## 安装

支持类似 ShellCrash 的命令安装方式：

```sh
export url='https://testingcf.jsdelivr.net/gh/<owner>/<repo>@<branch>/shell-sing-box' \
  && sh -c "$(curl -kfsSL $url/install.sh)"
```

如果设备没有 `curl`，使用 `wget`：

```sh
export url='https://testingcf.jsdelivr.net/gh/<owner>/<repo>@<branch>/shell-sing-box' \
  && wget --no-check-certificate -q -O /tmp/shell-sing-box-install.sh "$url/install.sh" \
  && sh /tmp/shell-sing-box-install.sh
```

如果你的仓库根目录就是 `shell-sing-box`，则 `url` 末尾不需要加 `/shell-sing-box`。

GitHub raw 安装命令，适合 jsDelivr 缓存还没刷新时使用：

```sh
export url='https://raw.githubusercontent.com/MorphKyan/shell-sing-box/main' \
  && sh -c "$(curl -kfsSL $url/install.sh)"
```

GitHub raw + `wget`：

```sh
export url='https://raw.githubusercontent.com/MorphKyan/shell-sing-box/main' \
  && wget --no-check-certificate -q -O /tmp/shell-sing-box-install.sh "$url/install.sh" \
  && sh /tmp/shell-sing-box-install.sh
```

把整个 `shell-sing-box` 目录复制到路由器，然后执行：

```sh
chmod +x install.sh
./install.sh
```

安装脚本会：

- 只安装缺失的硬依赖，不安装非必要包。
- 不通过 `opkg` 安装 sing-box。
- 从本项目 `update` 分支下载预打包 sing-box 内核，并解压到 `/tmp/shell-sing-box/bin/sing-box`。
- 复制服务、脚本和默认配置。
- 启用 `/etc/init.d/shell-sing-box`。

这遵循 ShellCrash 的思路：少安装东西，能用系统已有工具就不额外安装。安装脚本不会主动安装 `curl`、`libcurl`、`libnghttp2`、`unzip`、证书包等非必要组件。

硬依赖：

- `nft`
- `ip`
- `wget` 或 `curl`
- TUN 内核支持

如果缺失且系统存在 `opkg`，只会尝试安装对应最小包：

```text
nftables ip-full wget-ssl kmod-tun
```

脚本默认认为固件已有 BusyBox 基础工具，例如 `sh`、`tar`、`gzip`、`awk`、`sed`、`grep`、`find`。

然后把你的订阅生成器输出放到：

```sh
/etc/sing-box/generated/config.json
```

启动服务：

```sh
/etc/init.d/shell-sing-box start
```

## 国内镜像源优先

默认配置优先使用国内可访问性更好的镜像或代理：

- sing-box core：优先本项目 `update` 分支的 GitHub raw 镜像包
- SRS：优先 `https://testingcf.jsdelivr.net/gh/...`
- Zashboard：优先 jsDelivr 镜像

core 默认只下载项目内包；如果需要回退到上游 release，需要手动设置 `CORE_ALLOW_RELEASE_FALLBACK=1`。

相关配置在：

```sh
/etc/sing-box/custom.env
```

主要字段：

```sh
CORE_VERSION=v1.13.11
CORE_ARCH=auto
CORE_REPO_BASE=https://testingcf.jsdelivr.net/gh/MorphKyan/shell-sing-box
CORE_REPO_RAW_BASE=https://ghproxy.net/https://raw.githubusercontent.com/MorphKyan/shell-sing-box
CORE_REPO_ORIGIN_RAW_BASE=https://raw.githubusercontent.com/MorphKyan/shell-sing-box
CORE_REPO_BRANCH=update
CORE_REPO_PATH=bin/sing-box
GITHUB_PROXY_PREFIX=https://gh.llkk.cc/
CORE_DOWNLOAD_PREFIX=https://gh.llkk.cc/
CORE_ALLOW_RELEASE_FALLBACK=0
MIRROR_PREFIX=https://testingcf.jsdelivr.net/gh/
```

## sing-box 内核

默认固定到当前预打包的稳定版：

```sh
CORE_VERSION=v1.13.11
```

这和 ShellCrash 的预打包方式一致：配置里的版本必须能在 `update` 分支 `bin/sing-box/` 目录找到对应压缩包。你也可以设为 `latest`，但需要同步上传对应版本的包，否则默认不会回退到上游 release。

如果你想固定版本，例如：

```sh
CORE_VERSION=v1.12.0
```

架构默认自动识别：

```sh
CORE_ARCH=auto
```

普通 Linux 会根据 `uname -m` 映射到 sing-box release 包名，例如 `arm64`、`armv7`、`armv6`、`armv5`。

在 OpenWrt/ImmortalWrt 上会读取 `/etc/openwrt_release` 里的 `DISTRIB_ARCH`，例如你的 `aarch64_cortex-a53` 设备会使用从官方 OpenWrt ipk 提取出来的包：

```text
sing-box-1.13.11-openwrt-aarch64_cortex-a53.tar.gz
```

core 下载方式改成 ShellCrash 风格：把内核压缩包预先放到本项目 `update` 分支的 `bin/` 目录，安装时只下载项目内文件。

默认下载优先级：

1. GitHub raw 镜像项目内包：
   `https://ghproxy.net/https://raw.githubusercontent.com/MorphKyan/shell-sing-box/update/bin/sing-box/<asset>`
2. jsDelivr 项目内包：
   `https://testingcf.jsdelivr.net/gh/MorphKyan/shell-sing-box@update/bin/sing-box/<asset>`
3. GitHub raw 项目内包：
   `https://raw.githubusercontent.com/MorphKyan/shell-sing-box/update/bin/sing-box/<asset>`
4. 只有显式设置 `CORE_ALLOW_RELEASE_FALLBACK=1` 时，才回退到上游 release

```text
https://ghproxy.net/https://raw.githubusercontent.com/MorphKyan/shell-sing-box/update/bin/sing-box/sing-box-1.13.11-openwrt-aarch64_cortex-a53.tar.gz
```

jsDelivr 项目内包也会作为后备源尝试：

```text
https://testingcf.jsdelivr.net/gh/MorphKyan/shell-sing-box@update/bin/sing-box/sing-box-1.13.11-openwrt-aarch64_cortex-a53.tar.gz
```

也就是说，默认不再实时下载 GitHub Release 附件。要更新内核，从官方 OpenWrt `.ipk` 里提取 `/usr/bin/sing-box`，重新打成 tar.gz 后上传到 `update` 分支的 `bin/sing-box/` 目录即可。下载后会解压到 `/tmp/shell-sing-box/bin/sing-box`，并用 `sing-box version` 检查安装后的二进制。

注意：官方 OpenWrt sing-box 解压后超过 60MB，很多路由器 overlay 放不下，所以默认把运行时二进制放在 tmpfs。重启后如果 tmpfs 被清空，`prepare.sh` 会在启动前重新下载并解压。

手动更新 core：

```sh
/usr/libexec/shell-sing-box/core-install.sh
/etc/init.d/shell-sing-box restart
```

或者：

```sh
/usr/libexec/shell-sing-box/task.sh update-core
```

## GitHub Actions 编译内核

仓库包含 `.github/workflows/build-core.yml`，用于编译精简 sing-box core。

当前构建标签：

```text
with_quic,with_utls,with_clash_api,badlinkname,tfogo_checklinkname0
```

保留 QUIC/uTLS/Clash API，去掉 gVisor、WireGuard、Tailscale、NaiveProxy、ACME、DHCP 等非必要功能。手动运行 workflow 时可以选择是否发布到 `update` 分支。

workflow 会注入 `github.com/sagernet/sing-box/constant.Version`，所以 `sing-box version` 会显示选择的版本号，而不是 `unknown`。

## 配置生成方式

你的订阅生成器负责输出主配置：

```sh
/etc/sing-box/generated/config.json
```

`shell-sing-box` 启动时会复制它到运行时目录：

```sh
/tmp/shell-sing-box/config/00-generated.json
```

然后自动追加系统配置片段：

- DNS / fake-ip 配置
- TCP redirect 入站：`9998`
- DNS 入站：`1053`
- TUN 入站：`sbtun0`
- Clash API：`9999`
- fake-ip cache
- 必要的 `DIRECT` / `GLOBAL` 出站补齐
- CN SRS 规则补齐

最后执行：

```sh
sing-box check -D /etc/sing-box -C /tmp/shell-sing-box/config
```

校验成功后才启动服务并写入 nftables 规则。

## DNS 与 fake-ip

默认 DNS 模式是 fake-ip + CN SRS 直连混合：

- CN rule-set 命中：走 `dns_direct`
- 非 CN：返回 fake-ip，并由透明代理处理
- fake-ip 缓存开启
- reverse mapping 开启

默认 DNS：

```sh
DNS_DIRECT=223.5.5.5
DNS_PROXY=https://cloudflare-dns.com/dns-query
DNS_RESOLVER=223.5.5.5
```

fake-ip filter 文件：

```sh
/etc/sing-box/fake_ip_filter.list
```

可以写入不希望返回 fake-ip 的域名，例如：

```text
*.lan
*.local
time.android.com
pool.ntp.org
```

## SRS 下载与更新

系统会扫描运行时 sing-box 配置里的 remote `.srs` rule-set。

如果 rule-set 已经有 `path`，就下载到该路径。

如果没有 `path`，启动时会在运行时配置里自动注入：

```sh
/etc/sing-box/ruleset/<文件名>.srs
```

建议你的生成器输出类似：

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

手动更新 SRS：

```sh
/usr/libexec/shell-sing-box/task.sh update-srs
```

示例 cron：

```sh
0 4 * * * /usr/libexec/shell-sing-box/task.sh update-srs
```

如果下载失败但本地已有缓存，服务会继续使用旧缓存，不会因为网络问题直接中断启动。

## Zashboard

安装或刷新 Zashboard：

```sh
/usr/libexec/shell-sing-box/task.sh update-dashboard
```

面板解压会优先使用系统已有的 `unzip` 或 `busybox unzip`。如果两者都没有，可以手动把 Zashboard 放到 `/etc/sing-box/ui`，或者自行安装 `unzip`。

访问地址：

```text
http://<路由器LAN IP>:9999/ui
```

API 配置：

```sh
API_PORT=9999
API_SECRET=
```

如果你设置了 `API_SECRET`，面板连接时也需要填写对应 secret。

## nftables 透明代理

启动后会创建独立表：

```sh
table inet singbox
```

规则行为：

- LAN TCP 流量 redirect 到 `9998`
- LAN UDP 流量打 mark 后走 `sbtun0`
- LAN DNS `tcp/udp 53` redirect 到 `1053`
- 排除保留地址和局域网本地地址
- 排除 sing-box 自身 mark，避免回环
- 允许 LAN 访问 API
- 阻止 WAN 访问 `9998`、`9999`、`1053`

停止服务时会删除整张 `table inet singbox`，并清理策略路由。

## 常用命令

启动：

```sh
/etc/init.d/shell-sing-box start
```

停止：

```sh
/etc/init.d/shell-sing-box stop
```

重启：

```sh
/etc/init.d/shell-sing-box restart
```

开机自启：

```sh
/etc/init.d/shell-sing-box enable
```

检查配置：

```sh
/usr/libexec/shell-sing-box/task.sh check
```

更新 SRS：

```sh
/usr/libexec/shell-sing-box/task.sh update-srs
```

更新 core：

```sh
/usr/libexec/shell-sing-box/task.sh update-core
```

安装/更新 Zashboard：

```sh
/usr/libexec/shell-sing-box/task.sh update-dashboard
```

## 目录结构

```text
/etc/sing-box/
  custom.env
  fake_ip_filter.list
  generated/config.json
  ruleset/
  ui/
  bin/sing-box

/tmp/shell-sing-box/
  config/

/usr/libexec/shell-sing-box/
  common.sh
  core-install.sh
  dashboard.sh
  firewall.sh
  generate-system-config.sh
  prepare.sh
  srs-update.sh
  task.sh
```

## 注意事项

- 这个项目不支持 mihomo/clash 内核。
- 不支持 tproxy。
- 不维护 iptables 后端。
- 不暴露 mixed HTTP/SOCKS 代理端口。
- IPv6 默认关闭，可通过 `ENABLE_IPV6=1` 开启实验性支持。
- 如果你的生成器已经定义了同名 DNS、入站或 experimental 配置，可能需要调整生成器输出，避免和系统层追加配置冲突。
