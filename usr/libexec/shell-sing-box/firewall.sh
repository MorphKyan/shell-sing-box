#!/bin/sh

. /usr/libexec/shell-sing-box/common.sh

RESERVE4="0.0.0.0/8, 10.0.0.0/8, 100.64.0.0/10, 127.0.0.0/8, 169.254.0.0/16, 172.16.0.0/12, 192.168.0.0/16, 224.0.0.0/4, 240.0.0.0/4"
RESERVE6="::/128, ::1/128, ::ffff:0:0/96, 64:ff9b::/96, 100::/64, 2001::/32, 2001:20::/28, 2001:db8::/32, 2002::/16, fc00::/7, fe80::/10, ff00::/8"

list4() {
    list=$(lan_ipv4_list)
    [ -n "$list" ] || list="192.168.0.0/16 10.0.0.0/8 172.16.0.0/12"
    printf '%s' "$list" | sed 's/[[:space:]][[:space:]]*/, /g'
}

list6() {
    list=$(lan_ipv6_list)
    [ -n "$list" ] || list="fe80::/10 fd00::/8"
    printf '%s' "$list" | sed 's/[[:space:]][[:space:]]*/, /g'
}

wait_tun() {
    i=0
    while [ "$i" -lt 20 ]; do
        ip link show "$TUN_NAME" >/dev/null 2>&1 && return 0
        sleep 1
        i=$((i + 1))
    done
    return 1
}

route_start() {
    if wait_tun; then
        ip route replace default dev "$TUN_NAME" table "$ROUTE_TABLE" 2>/dev/null || true
        ip rule add fwmark "$FW_MARK" table "$ROUTE_TABLE" priority "$ROUTE_TABLE" 2>/dev/null || true
        if [ "$ENABLE_IPV6" = "1" ]; then
            ip -6 route replace default dev "$TUN_NAME" table "$((ROUTE_TABLE + 1))" 2>/dev/null || true
            ip -6 rule add fwmark "$FW_MARK" table "$((ROUTE_TABLE + 1))" priority "$((ROUTE_TABLE + 1))" 2>/dev/null || true
        fi
        log "policy route installed for $TUN_NAME"
    else
        log "tun interface $TUN_NAME not found; UDP tun redirection skipped until restart"
    fi
}

route_stop() {
    while ip rule del fwmark "$FW_MARK" table "$ROUTE_TABLE" priority "$ROUTE_TABLE" 2>/dev/null; do :; done
    ip route flush table "$ROUTE_TABLE" 2>/dev/null || true
    while ip -6 rule del fwmark "$FW_MARK" table "$((ROUTE_TABLE + 1))" priority "$((ROUTE_TABLE + 1))" 2>/dev/null; do :; done
    ip -6 route flush table "$((ROUTE_TABLE + 1))" 2>/dev/null || true
}

nft_start() {
    lan4=$(list4)
    lan6=$(list6)

    nft delete table inet "$NFT_TABLE" 2>/dev/null || true
    nft add table inet "$NFT_TABLE"

    nft add chain inet "$NFT_TABLE" input "{ type filter hook input priority -100; policy accept; }"
    nft add chain inet "$NFT_TABLE" forward "{ type filter hook forward priority -100; policy accept; }"
    nft add chain inet "$NFT_TABLE" dns_hijack "{ type nat hook prerouting priority -100; policy accept; }"
    nft add chain inet "$NFT_TABLE" tcp_redir "{ type nat hook prerouting priority -100; policy accept; }"
    nft add chain inet "$NFT_TABLE" udp_tun "{ type filter hook prerouting priority -150; policy accept; }"

    nft add rule inet "$NFT_TABLE" input iifname lo accept
    nft add rule inet "$NFT_TABLE" input ip saddr "{ $lan4 }" accept
    [ "$ENABLE_IPV6" = "1" ] && nft add rule inet "$NFT_TABLE" input ip6 saddr "{ $lan6 }" accept
    nft add rule inet "$NFT_TABLE" input tcp dport "{ $REDIR_PORT, $API_PORT, $DNS_PORT }" reject
    nft add rule inet "$NFT_TABLE" input udp dport "{ $REDIR_PORT, $API_PORT, $DNS_PORT }" reject

    nft add rule inet "$NFT_TABLE" forward iifname "$TUN_NAME" accept
    nft add rule inet "$NFT_TABLE" forward oifname "$TUN_NAME" accept

    nft add rule inet "$NFT_TABLE" dns_hijack meta mark "$FW_MARK" return
    [ "$ENABLE_IPV6" != "1" ] && nft add rule inet "$NFT_TABLE" dns_hijack meta nfproto ipv6 return
    nft add rule inet "$NFT_TABLE" dns_hijack meta nfproto ipv4 ip saddr != "{ $lan4 }" return
    nft add rule inet "$NFT_TABLE" dns_hijack meta nfproto ipv4 udp dport 53 redirect to "$DNS_PORT"
    nft add rule inet "$NFT_TABLE" dns_hijack meta nfproto ipv4 tcp dport 53 redirect to "$DNS_PORT"
    [ "$ENABLE_IPV6" = "1" ] && {
        nft add rule inet "$NFT_TABLE" dns_hijack ip6 saddr != "{ $lan6 }" return
        nft add rule inet "$NFT_TABLE" dns_hijack ip6 nexthdr udp udp dport 53 redirect to "$DNS_PORT"
        nft add rule inet "$NFT_TABLE" dns_hijack ip6 nexthdr tcp tcp dport 53 redirect to "$DNS_PORT"
    }

    nft add rule inet "$NFT_TABLE" tcp_redir meta mark "$FW_MARK" return
    [ "$ENABLE_IPV6" != "1" ] && nft add rule inet "$NFT_TABLE" tcp_redir meta nfproto ipv6 return
    nft add rule inet "$NFT_TABLE" tcp_redir meta nfproto ipv4 ip saddr != "{ $lan4 }" return
    nft add rule inet "$NFT_TABLE" tcp_redir meta nfproto ipv4 ip daddr "{ $RESERVE4 }" return
    nft add rule inet "$NFT_TABLE" tcp_redir meta nfproto ipv4 tcp dport "{ $REDIR_PORT, $API_PORT, $DNS_PORT }" return
    nft add rule inet "$NFT_TABLE" tcp_redir meta nfproto ipv4 meta l4proto tcp redirect to "$REDIR_PORT"
    if [ "$ENABLE_IPV6" = "1" ]; then
        nft add rule inet "$NFT_TABLE" tcp_redir ip6 saddr != "{ $lan6 }" return
        nft add rule inet "$NFT_TABLE" tcp_redir ip6 daddr "{ $RESERVE6 }" return
        nft add rule inet "$NFT_TABLE" tcp_redir meta nfproto ipv6 tcp dport "{ $REDIR_PORT, $API_PORT, $DNS_PORT }" return
        nft add rule inet "$NFT_TABLE" tcp_redir meta nfproto ipv6 meta l4proto tcp redirect to "$REDIR_PORT"
    fi

    nft add rule inet "$NFT_TABLE" udp_tun meta mark "$FW_MARK" return
    [ "$ENABLE_IPV6" != "1" ] && nft add rule inet "$NFT_TABLE" udp_tun meta nfproto ipv6 return
    nft add rule inet "$NFT_TABLE" udp_tun meta nfproto ipv4 ip saddr != "{ $lan4 }" return
    nft add rule inet "$NFT_TABLE" udp_tun meta nfproto ipv4 ip daddr "{ $RESERVE4 }" return
    nft add rule inet "$NFT_TABLE" udp_tun meta nfproto ipv4 udp dport 53 return
    nft add rule inet "$NFT_TABLE" udp_tun meta nfproto ipv4 udp dport "{ $REDIR_PORT, $API_PORT, $DNS_PORT }" return
    nft add rule inet "$NFT_TABLE" udp_tun meta nfproto ipv4 meta l4proto udp meta mark set "$FW_MARK"
    if [ "$ENABLE_IPV6" = "1" ]; then
        nft add rule inet "$NFT_TABLE" udp_tun ip6 saddr != "{ $lan6 }" return
        nft add rule inet "$NFT_TABLE" udp_tun ip6 daddr "{ $RESERVE6 }" return
        nft add rule inet "$NFT_TABLE" udp_tun meta nfproto ipv6 udp dport 53 return
        nft add rule inet "$NFT_TABLE" udp_tun meta nfproto ipv6 udp dport "{ $REDIR_PORT, $API_PORT, $DNS_PORT }" return
        nft add rule inet "$NFT_TABLE" udp_tun meta nfproto ipv6 meta l4proto udp meta mark set "$FW_MARK"
    fi

    log "nftables table installed: inet $NFT_TABLE"
}

start_fw() {
    need_cmd nft
    need_cmd ip
    nft_start
    route_start
}

stop_fw() {
    route_stop
    nft delete table inet "$NFT_TABLE" 2>/dev/null || true
    log "firewall cleaned"
}

case "$1" in
    start) start_fw ;;
    stop) stop_fw ;;
    restart) stop_fw; start_fw ;;
    *) die "usage: $0 {start|stop|restart}" ;;
esac
