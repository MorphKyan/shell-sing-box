#!/bin/sh

. /usr/libexec/shell-sing-box/common.sh

filter_rules() {
    filter_file="$BASE_DIR/fake_ip_filter.list"
    [ -f "$filter_file" ] || return 0

    domain_items=
    suffix_items=
    regex_items=

    while IFS= read -r line || [ -n "$line" ]; do
        line=${line%%#*}
        line=$(printf '%s' "$line" | sed 's/^[[:space:]]*//;s/[[:space:]]*$//')
        [ -z "$line" ] && continue
        case "$line" in
            *'*'*)
                regex=$(printf '%s' "$line" | sed 's/\./\\\\./g;s/\*/.*/g;s/^+/.+/')
                regex_items="${regex_items}${regex_items:+, }\"$regex\""
                ;;
            +.*|.*)
                suffix=${line#*.}
                suffix=${suffix#+.}
                suffix_items="${suffix_items}${suffix_items:+, }\"$suffix\""
                ;;
            *)
                domain_items="${domain_items}${domain_items:+, }\"$line\""
                ;;
        esac
    done < "$filter_file"

    [ -n "$domain_items" ] && printf '      { "domain": [%s], "server": "dns_direct" },\n' "$domain_items"
    [ -n "$suffix_items" ] && printf '      { "domain_suffix": [%s], "server": "dns_direct" },\n' "$suffix_items"
    [ -n "$regex_items" ] && printf '      { "domain_regex": [%s], "server": "dns_direct" },\n' "$regex_items"
}

dns_server_json() {
    tag=$1
    value=$2
    detour=$3
    ecs=$4
    
    props=""
    [ -n "$detour" ] && props="${props}, \"detour\": \"$detour\""

    case "$value" in
        https://*)
            server=${value#https://}
            server=${server%%/*}
            printf '      { "type": "https", "tag": "%s", "server": "%s", "domain_resolver": "dns_hosts"%s }' "$tag" "$server" "$props"
            ;;
        quic://*)
            server=${value#quic://}
            server=${server%%/*}
            printf '      { "type": "quic", "tag": "%s", "server": "%s", "domain_resolver": "dns_hosts"%s }' "$tag" "$server" "$props"
            ;;
        tls://*)
            server=${value#tls://}
            server=${server%%/*}
            printf '      { "type": "tls", "tag": "%s", "server": "%s", "server_port": 853, "domain_resolver": "dns_hosts"%s }' "$tag" "$server" "$props"
            ;;
        tcp://*)
            server=${value#tcp://}
            server=${server%%/*}
            printf '      { "type": "tcp", "tag": "%s", "server": "%s", "server_port": 53%s }' "$tag" "$server" "$props"
            ;;
        udp://*)
            server=${value#udp://}
            server=${server%%/*}
            printf '      { "type": "udp", "tag": "%s", "server": "%s", "server_port": 53%s }' "$tag" "$server" "$props"
            ;;
        *)
            printf '      { "type": "udp", "tag": "%s", "server": "%s", "server_port": 53%s }' "$tag" "$value" "$props"
            ;;
    esac
}

normalize_generated_rulesets() {
    src=$1
    dst=$2
    awk -v ruleset_dir="$RULESET_DIR" '
        function basename(url, n, parts) {
            sub(/\?.*$/, "", url)
            n = split(url, parts, "/")
            if (parts[n] == "") return "ruleset.srs"
            return parts[n]
        }
        function flush_remote(close_line, i, last) {
            for (i = 1; i <= n; i++) print buf[i]
            print close_line
            remote=0; n=0; url=""; path=""
        }
        remote {
            if (/"url"[[:space:]]*:/) {
                line=$0
                sub(/^.*"url"[[:space:]]*:[[:space:]]*"/, "", line)
                sub(/".*$/, "", line)
                url=line
            }
            if (/"path"[[:space:]]*:/) path="set"
            if ($0 ~ /^[[:space:]]*}/) {
                flush_remote($0)
            } else {
                buf[++n]=$0
            }
            next
        }
        /"type"[[:space:]]*:[[:space:]]*"remote"/ {
            remote=1
            n=0
            url=""
            path=""
            buf[++n]=$0
            next
        }
        { print }
        END {
            if (remote) {
                for (i = 1; i <= n; i++) print buf[i]
            }
        }
    ' "$src" > "$dst"
}

generate_cn_ruleset() {
    if grep -q "\"tag\"[[:space:]]*:[[:space:]]*\"$CN_RULESET_TAG\"" "$CONFIG_RUNTIME_DIR"/*.json 2>/dev/null; then
        return 0
    fi

    cat > "$CONFIG_RUNTIME_DIR/20-cn-ruleset.json" <<EOF
{
  "route": {
    "rule_set": [
      {
        "type": "remote",
        "tag": "$CN_RULESET_TAG",
        "format": "binary",
        "url": "https://raw.githubusercontent.com/DustinWin/ruleset_geodata/sing-box-ruleset/cn.srs"
      }
    ]
  }
}
EOF
}

detect_ecs_subnet() {
    [ -n "$DNS_CLIENT_SUBNET" ] && printf '%s' "$DNS_CLIENT_SUBNET" && return

    # Check OpenWrt ISP DNS
    file="/tmp/resolv.conf.d/resolv.conf.auto"
    [ -f "$file" ] || file="/etc/resolv.conf"

    # Get first public IPv4 nameserver
    auto_dns=$(grep "^nameserver " "$file" 2>/dev/null | awk '{print $2}' | grep -E '^[0-9]+\.[0-9]+\.[0-9]+\.[0-9]+$' | while read -r ip; do
        case "$ip" in
            127.*|10.*|172.1[6-9].*|172.2[0-9].*|172.3[01].*|192.168.*|169.254.*) continue ;;
            *) printf '%s' "$ip"; break ;;
        esac
    done)

    [ -n "$auto_dns" ] && printf '%s' "${auto_dns%.*}.0/24"
}

generate_dns() {
    ecs_to_use=$(detect_ecs_subnet)
    servers_json=""
    hosts_json='      {
        "type": "hosts",
        "tag": "dns_hosts",
        "predefined": {
          "dns.alidns.com": ["223.5.5.5", "223.6.6.6", "2400:3200::1", "2400:3200:baba::1"],
          "doh.pub": ["1.12.12.12", "120.53.53.53", "2402:4e00::"],
          "dns.google": ["8.8.8.8", "8.8.4.4", "2001:4860:4860::8888", "2001:4860:4860::8844"],
          "cloudflare-dns.com": ["1.1.1.1", "1.0.0.1", "2606:4700:4700::1111", "2606:4700:4700::1001"],
          "dns11.quad9.net": ["9.9.9.11", "149.112.112.11", "2620:fe::11", "2620:fe::fe:11"]
        }
      }'
    servers_json="${hosts_json}"

    # Helper function to generate multiple servers and a group
    # Usage: build_group "base_tag" "csv_list" "detour" "ecs"
    build_group() {
        base_tag=$1
        list=$2
        detour=$3
        ecs=$4
        
        count=0
        OLD_IFS=$IFS; IFS=','
        for s in $list; do
            [ -z "$s" ] && continue
            count=$((count+1))
            # Use base_tag for the first server so rules can reference it
            if [ $count -eq 1 ]; then
                tag="$base_tag"
            else
                tag="${base_tag}_$count"
            fi
            obj=$(dns_server_json "$tag" "$s" "$detour" "$ecs")
            servers_json="${servers_json},
${obj}"
        done
        IFS=$OLD_IFS
    }

    build_group "dns_resolver" "$DNS_RESOLVER" "" ""
    build_group "dns_direct" "$DNS_DIRECT" "" "$ecs_to_use"
    build_group "dns_proxy" "$DNS_PROXY" "GLOBAL" "$ecs_to_use"

    # 4. FakeIP server
    servers_json="${servers_json},
      {
        \"type\": \"fakeip\",
        \"tag\": \"dns_fakeip\",
        \"inet4_range\": \"$FAKEIP_INET4\",
        \"inet6_range\": \"$FAKEIP_INET6\"
      }"

    filter_tmp="$RUNTIME_DIR/fakeip-rules.json"
    filter_rules > "$filter_tmp"

    ecs_json=""
    [ -n "$ecs_to_use" ] && ecs_json=", \"client_subnet\": \"$ecs_to_use\""

    cat > "$CONFIG_RUNTIME_DIR/30-dns.json" <<EOF
{
  "dns": {
    "servers": [
${servers_json}
    ],
    "rules": [
      { "clash_mode": "direct", "server": "dns_direct", "strategy": "prefer_ipv4" },
$(cat "$filter_tmp")
      { "rule_set": ["$CN_RULESET_TAG"], "server": "dns_direct", "strategy": "prefer_ipv4" },
      { "query_type": ["A", "AAAA"], "server": "dns_fakeip", "strategy": "prefer_ipv4", "rewrite_ttl": 1 }
    ],
    "final": "dns_proxy",
    "strategy": "prefer_ipv4",
    "cache_capacity": 1024,
    "reverse_mapping": true${ecs_json}
  }
}
EOF
    rm -f "$filter_tmp"
}

generate_outbounds() {
    direct_line=
    global_line=
    if ! grep -q '"tag"[[:space:]]*:[[:space:]]*"DIRECT"' "$CONFIG_RUNTIME_DIR"/*.json 2>/dev/null; then
        direct_line='    { "type": "direct", "tag": "DIRECT" }'
    fi
    if ! grep -q '"tag"[[:space:]]*:[[:space:]]*"GLOBAL"' "$CONFIG_RUNTIME_DIR"/*.json 2>/dev/null; then
        global_line='    { "type": "selector", "tag": "GLOBAL", "outbounds": ["DIRECT"] }'
    fi
    [ -n "$direct_line$global_line" ] || return 0

    {
        printf '{\n  "outbounds": [\n'
        if [ -n "$direct_line" ] && [ -n "$global_line" ]; then
            printf '%s,\n%s\n' "$direct_line" "$global_line"
        elif [ -n "$direct_line" ]; then
            printf '%s\n' "$direct_line"
        else
            printf '%s\n' "$global_line"
        fi
        printf '  ]\n}\n'
    } > "$CONFIG_RUNTIME_DIR/35-outbounds.json"
}

generate_inbounds() {
    ipv6_addr=
    [ "$ENABLE_IPV6" = "1" ] && ipv6_addr="\"$TUN_INET6\","

    cat > "$CONFIG_RUNTIME_DIR/40-inbounds.json" <<EOF
{
  "inbounds": [
    {
      "type": "direct",
      "tag": "dns-in",
      "listen": "::",
      "listen_port": $DNS_PORT
    },
    {
      "type": "redirect",
      "tag": "redirect-in",
      "listen": "::",
      "listen_port": $REDIR_PORT
    },
    {
      "type": "tun",
      "tag": "tun-in",
      "interface_name": "$TUN_NAME",
      "address": [
        $ipv6_addr
        "$TUN_INET4"
      ],
      "auto_route": false,
      "strict_route": false,
      "stack": "system"
    }
  ]
}
EOF
}

generate_route() {
    cat > "$CONFIG_RUNTIME_DIR/50-route-system.json" <<EOF
{
  "route": {
    "default_domain_resolver": "dns_resolver",
    "rules": [
      { "inbound": ["dns-in"], "action": "hijack-dns" },
      { "clash_mode": "direct", "outbound": "DIRECT" },
      { "clash_mode": "global", "outbound": "GLOBAL" }
    ]
  }
}
EOF
}

generate_experimental() {
    cat > "$CONFIG_RUNTIME_DIR/60-experimental.json" <<EOF
{
  "experimental": {
    "cache_file": {
      "enabled": true,
      "path": "$BASE_DIR/cache.db",
      "cache_id": "shell-sing-box",
      "store_fakeip": true
    },
    "clash_api": {
      "external_controller": "0.0.0.0:$API_PORT",
      "external_ui": "$UI_DIR",
      "secret": "$API_SECRET",
      "default_mode": "rule"
    }
  }
}
EOF
}

main() {
    mkdirs
    [ -s "$CONFIG_SOURCE_FILE" ] || die "missing generated config: $CONFIG_SOURCE_FILE"
    rm -rf "$CONFIG_RUNTIME_DIR"
    mkdir -p "$CONFIG_RUNTIME_DIR"
    normalize_generated_rulesets "$CONFIG_SOURCE_FILE" "$CONFIG_RUNTIME_DIR/00-generated.json"
    generate_cn_ruleset
    generate_dns
    generate_outbounds
    generate_inbounds
    generate_route
    generate_experimental
}

main "$@"
