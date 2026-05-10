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
- sing-box 内核：`/etc/sing-box/bin/sing-box`
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

如果你的仓库根目录就是 `shell-sing-box`，则 `url` 末尾不需要加 `/shell-sing-box`。

把整个 `shell-sing-box` 目录复制到路由器，然后执行：

```sh
chmod +x install.sh
./install.sh
```

安装脚本会：

- 安装基础依赖：`nftables`、`kmod-tun`、证书、`curl`、`unzip` 等。
- 不通过 `opkg` 安装 sing-box。
- 从官方最新稳定版 release 下载 sing-box 内核到 `/etc/sing-box/bin/sing-box`。
- 复制服务、脚本和默认配置。
- 启用 `/etc/init.d/shell-sing-box`。

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

- sing-box core：优先 `https://gh.llkk.cc/https://github.com/...`
- SRS：优先 `https://testingcf.jsdelivr.net/gh/...`
- Zashboard：优先 jsDelivr 镜像

如果镜像失败，会自动 fallback 到 GitHub 原始地址。

相关配置在：

```sh
/etc/sing-box/custom.env
```

主要字段：

```sh
CORE_VERSION=latest
CORE_ARCH=auto
GITHUB_PROXY_PREFIX=https://gh.llkk.cc/
CORE_DOWNLOAD_PREFIX=https://gh.llkk.cc/
MIRROR_PREFIX=https://testingcf.jsdelivr.net/gh/
```

## sing-box 内核

默认使用最新稳定版：

```sh
CORE_VERSION=latest
```

如果你想固定版本，例如：

```sh
CORE_VERSION=v1.12.0
```

架构默认自动识别：

```sh
CORE_ARCH=auto
```

会根据 `uname -m` 映射到 sing-box release 包名，例如 `arm64`、`armv7`、`armv6`、`armv5`。

手动更新 core：

```sh
/usr/libexec/shell-sing-box/core-install.sh
/etc/init.d/shell-sing-box restart
```

或者：

```sh
/usr/libexec/shell-sing-box/task.sh update-core
```

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
