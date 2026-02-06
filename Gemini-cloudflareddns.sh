#!/bin/bash

# ==============================================================================
# Synology Cloudflare DDNS Script (Dual Stack IPv4/IPv6)
# ==============================================================================
# GitHub: https://github.com/KongQI-XianXian/Synology-DDNS-Cloudflare
# 适配 DSM 7.x / SA6400
# ==============================================================================

# --- 配置区 ---
PROXY="false"
IPV6_SUPPORT="true"

# 接收群晖参数
ZONE_ID="$1"
API_TOKEN="$2"
HOSTNAME="$3"
IP4_ADDR="$4"

# --- 1. 依赖检查 (jq) ---
if ! command -v jq &> /dev/null; then
    if [ ! -f "/tmp/jq" ]; then
        # 尝试使用镜像源下载，避免“门票”问题 (这里使用了一个常用的静态编译镜像)
        curl -L -s -o /tmp/jq https://ghproxy.com/https://github.com/jqlang/jq/releases/download/jq-1.6/jq-linux64 || \
        curl -L -s -o /tmp/jq https://github.com/jqlang/jq/releases/download/jq-1.6/jq-linux64
        chmod +x /tmp/jq
    fi
    JQ_EXEC="/tmp/jq"
else
    JQ_EXEC="jq"
fi

# --- 2. 获取 IPv6 地址 ---
if [ "$IPV6_SUPPORT" = "true" ]; then
    # 增加超时和重试逻辑，确保获取的是公网 IPv6 (过滤 fe80)
    IP6_ADDR=$(curl -6 -s --connect-timeout 5 https://api6.ipify.org | grep -vE '^fe80')
    [ -z "$IP6_ADDR" ] && IP6_ADDR=$(curl -6 -s --connect-timeout 5 https://v6.ident.me | grep -vE '^fe80')
fi

# --- 3. 更新函数 ---
update_record() {
    local type=$1
    local name=$2
    local content=$3
    local zid=$4
    local token=$5

    # 获取现有记录
    local record_info=$(curl -s -X GET "https://api.cloudflare.com/client/v4/zones/$zid/dns_records?type=$type&name=$name" \
        -H "Authorization: Bearer $token" \
        -H "Content-Type: application/json")
    
    # 验证获取是否成功
    if [[ "$(echo "$record_info" | $JQ_EXEC -r '.success')" != "true" ]]; then
        echo "failed"
        return
    fi

    local rid=$(echo "$record_info" | $JQ_EXEC -r '.result[0].id')

    if [ "$rid" = "null" ] || [ -z "$rid" ]; then
        # 新建
        curl -s -X POST "https://api.cloudflare.com/client/v4/zones/$zid/dns_records" \
            -H "Authorization: Bearer $token" \
            -H "Content-Type: application/json" \
            --data "{\"type\":\"$type\",\"name\":\"$name\",\"content\":\"$content\",\"proxied\":$PROXY}"
    else
        # 更新
        curl -s -X PUT "https://api.cloudflare.com/client/v4/zones/$zid/dns_records/$rid" \
            -H "Authorization: Bearer $token" \
            -H "Content-Type: application/json" \
            --data "{\"type\":\"$type\",\"name\":\"$name\",\"content\":\"$content\",\"proxied\":$PROXY}"
    fi
}

# --- 4. 执行逻辑 ---
# 处理 IPv4
if [ -n "$IP4_ADDR" ]; then
    RES4=$(update_record "A" "$HOSTNAME" "$IP4_ADDR" "$ZONE_ID" "$API_TOKEN")
    RES4_SUCCESS=$(echo "$RES4" | $JQ_EXEC -r ".success")
fi

# 处理 IPv6
RES6_SUCCESS="false"
if [ "$IPV6_SUPPORT" = "true" ] && [ -n "$IP6_ADDR" ]; then
    RES6=$(update_record "AAAA" "$HOSTNAME" "$IP6_ADDR" "$ZONE_ID" "$API_TOKEN")
    RES6_SUCCESS=$(echo "$RES6" | $JQ_EXEC -r ".success")
fi

# --- 5. 结果反馈 ---
if [[ "$RES4_SUCCESS" == "true" || "$RES6_SUCCESS" == "true" ]]; then
    echo "good"
else
    # 增加详细错误反馈到标准错误流，方便用户查日志
    echo "Error: IPv4_Status=$RES4_SUCCESS, IPv6_Status=$RES6_SUCCESS" >&2
    echo "badauth"
fi
