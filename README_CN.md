# shell-sing-box for ImmortalWrt

这是一个面向 ImmortalWrt/OpenWrt ARM 路由器的轻量 sing-box 系统层，用来替代 ShellCrash 的“系统接管”部分。它不负责订阅转换，你仍然需要使用自己的订阅生成器输出 sing-box 配置。

## 功能范围

- 只支持 sing-box。
- 只使用 nftables，不支持 iptables。
- 使用 `procd` 管理服务。
- 固定透明代理模式：TCP redir + sing-box tun。
- 不支持 tproxy。
- 支持 fake-ip + CN SRS 规则直连混合 DNS。
- 支持 fake-ip 缓存与 filter。
- 支持自动下载和更新 `.srs` 规则集。
- 支持下载和配置 Zashboard 面板。
- 默认阻止 WAN 访问透明代理端口和 API 端口。
- 提供 `ssb` 交互式命令行管理工具。

## 安装

支持一键命令安装：

```sh
export url='https://testingcf.jsdelivr.net/gh/MorphKyan/shell-sing-box@main' \
  && sh -c "$(curl -kfsSL $url/install.sh)"
```

如果设备没有 `curl`，使用 `wget`：

```sh
export url='https://testingcf.jsdelivr.net/gh/MorphKyan/shell-sing-box@1.0.0' \
  && wget --no-check-certificate -q -O /tmp/shell-sing-box-install.sh "$url/install.sh" \
  && sh /tmp/shell-sing-box-install.sh
```

如果 jsDelivr 缓存未刷新，可以换用 GitHub Raw 源：

```sh
export url='https://raw.githubusercontent.com/MorphKyan/shell-sing-box/main' \
  && sh -c "$(curl -kfsSL $url/install.sh)"
```

GitHub Raw + `wget`：

```sh
export url='https://raw.githubusercontent.com/MorphKyan/shell-sing-box/main' \
  && wget --no-check-certificate -q -O /tmp/shell-sing-box-install.sh "$url/install.sh" \
  && sh /tmp/shell-sing-box-install.sh
```

GitHub Mirror + `curl`：
```sh
export url='https://ghproxy.net/https://raw.githubusercontent.com/MorphKyan/shell-sing-box/main' \
  && sh -c "$(curl -kfsSL $url/install.sh)"
```

GitHub Mirror + `wget`：
```sh
export url='https://ghproxy.net/https://raw.githubusercontent.com/MorphKyan/shell-sing-box/main' \
  && wget --no-check-certificate -q -O /tmp/shell-sing-box-install.sh "$url/install.sh" \
  && sh /tmp/shell-sing-box-install.sh
```

*注：安装脚本遵循最小化安装原则，只安装必要的硬依赖（`nft`, `ip`, `wget/curl`, `kmod-tun`）。*

安装完成后，请将你的订阅生成器输出配置放入：`/etc/sing-box/generated/config.json`

## 常用命令

我们提供了一个与 ShellCrash 类似的交互式管理面板 `ssb`，你可以在终端输入 `ssb` 快速打开配置面板，进行启动、停止、配置订阅、安装面板、设置定时任务等操作：

```sh
ssb
```

也可以使用带参数的 `ssb` 命令快速执行对应操作：

```sh
ssb start    # 启动服务
ssb stop     # 停止服务
ssb restart  # 重启服务
ssb update   # 更新订阅
```

系统服务同样支持传统的 `init.d` 脚本命令：`/etc/init.d/shell-sing-box start|stop|restart|enable`

## 默认配置与目录结构

- 服务：`/etc/init.d/shell-sing-box`
- 交互工具：`/usr/sbin/ssb`
- sing-box 运行时内核：`/etc/sing-box/bin/sing-box`
- 运行时配置目录：`/tmp/shell-sing-box/config`
- 订阅生成器主配置：`/etc/sing-box/generated/config.json`
- 自定义环境变量：`/etc/sing-box/custom.env`
- SRS 缓存目录：`/etc/sing-box/ruleset`
- Zashboard 面板目录：`/etc/sing-box/ui`
- TCP redir 入站端口：`9998`
- DNS 劫持入站端口：`1053`
- Clash API / Zashboard 端口：`9999`
- nftables 表：`table inet singbox`
- TUN 接口：`sbtun0`
- fake-ip IPv4 地址段：`28.0.0.0/8`
- fake-ip filter 列表：`/etc/sing-box/fake_ip_filter.list`

## 运行机制与核心功能

### 配置生成
`shell-sing-box` 启动时会将主配置复制到运行时目录，并自动追加系统配置片段（如 DNS、入站、Clash API、fake-ip 等），随后自动验证配置，校验成功才会写入 nftables 规则启动服务。
*注意：如果生成器配置已存在同名 DNS 或入站定义，可能会与系统层追加配置冲突。*

### 内核与镜像下载
系统默认优先使用国内可访问性较好的镜像源（如 jsDelivr, ghproxy）。你可以在 `/etc/sing-box/custom.env` 中自定义版本及镜像配置（如 `CORE_VERSION`、`CORE_ARCH` 等）。
- **内核版本**：自动识别系统架构并优先下载本项目 `update` 分支预打包的精简核心（默认固定为当前预打包稳定版）。项目默认使用 GitHub Actions 编译精简内核，移除了 gVisor、WireGuard 等非必要功能，以适配路由器存储限制。你可以在 `ssb` 菜单中更新内核。
- **SRS 规则集**：系统会自动扫描配置中的 remote `.srs`，自动下载至本地进行缓存。如果下载失败将继续使用已有旧缓存。
- **Zashboard 面板**：可通过 `ssb` 安装。安装后访问地址为：`http://<路由器LAN IP>:9999/ui`。

### DNS 与 fake-ip
默认 DNS 模式为 fake-ip + CN SRS 直连混合。命中 CN rule-set 的流量直连，其余流量透明代理。默认开启 fake-ip 缓存及逆向解析。如果不希望特定域名返回 fake-ip，可以将其加入 `/etc/sing-box/fake_ip_filter.list`（如 `*.lan`, `pool.ntp.org`）。

### nftables 透明代理
服务启动时会创建 `table inet singbox` 独立表，实现局域网 TCP 流量重定向至 9998，UDP 流量标记后路由至 `sbtun0`，DNS 劫持至 1053。默认放行局域网访问 API，但阻止 WAN 访问代理和 API 端口。停止服务时自动删除该表并清理策略路由。

## 注意事项

- 本项目不支持 mihomo/clash 内核。
- 不支持 tproxy 模式和 iptables 后端。
- 不暴露 mixed HTTP/SOCKS 代理端口。
- IPv6 默认关闭，可通过 `ENABLE_IPV6=1` 开启实验性支持。
