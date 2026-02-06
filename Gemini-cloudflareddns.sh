#!/bin/bash

# ==============================================================================
# Synology Cloudflare DDNS Script (Dual Stack IPv4/IPv6)
# ==============================================================================
# GitHub: 你的项目地址
# 适配 DSM 7.x / SA6400
# 功能：支持 IPv4/IPv6 双栈更新，内置 jq 依赖检查，支持自动提取 ZoneName
# ==============================================================================

# --- 默认配置 (可通过环境变量或 DSM 界面传入) ---
PROXY="false"   # 是否开启 CF 代理 (小云朵)
IPV6_SUPPORT="true"

# 接收群晖传入参数
# $1: 用户名 (在 DSM 界面填写你的 Zone ID)
# $2: 密码   (在 DSM 界面填写你的 API Token)
# $3: 主机名 (例如 nas.yourdomain.com)
# $4: IPv4   (DSM 自动传入的当前公网 IPv4)

ZONE_ID="$1"
API_TOKEN="$2"
HOSTNAME="$3"
IP4_ADDR="$4"

# --- 1. 环境依赖检查 (jq) ---
# 如果没有 jq，尝试自动下载静态版本
if ! command -v jq &> /dev/null; then
    # 由于 GitHub 下载慢，这里建议在 README 提醒用户先挂代理或手动执行下载
    # 脚本内尝试下载 (x86_64 架构)
    curl -L -s -o /tmp/jq https://github.com/jqlang/jq/releases/download/jq-1.6/jq-linux64
    chmod +x /tmp/jq
    JQ_EXEC="/tmp/jq"
else
    JQ_EXEC="jq"
fi

# --- 2. 获取 IPv6 地址 ---
if [ "$IPV6_SUPPORT" = "true" ]; then
    # 尝试多个源获取 IPv6
    IP6_ADDR=$(curl -s -6 --connect-timeout 5 https://api6.ipify.org || curl -s -6 --connect-timeout 5 https://v6.ident.me)
fi

# --- 3. 更新函数 ---
update_record() {
    local type=$1     # A 或 AAAA
    local name=$2     # Hostname
    local content=$3  # IP 地址
    local zid=$4      # Zone ID
    local token=$5    # API Token

    # 获取记录 ID
    local record_info=$(curl -s -X GET "https://api.cloudflare.com/client/v4/zones/$zid/dns_records?type=$type&name=$name" \
        -H "Authorization: Bearer $token" \
        -H "Content-Type: application/json")
    
    local rid=$(echo "$record_info" | $JQ_EXEC -r '.result[0].id')

    if [ "$rid" = "null" ] || [ -z "$rid" ]; then
        # 记录不存在，创建新记录
        curl -s -X POST "https://api.cloudflare.com/client/v4/zones/$zid/dns_records" \
            -H "Authorization: Bearer $token" \
            -H "Content-Type: application/json" \
            --data "{\"type\":\"$type\",\"name\":\"$name\",\"content\":\"$content\",\"proxied\":$PROXY}"
    else
        # 记录存在，执行更新
        curl -s -X PUT "https://api.cloudflare.com/client/v4/zones/$zid/dns_records/$rid" \
            -H "Authorization: Bearer $token" \
            -H "Content-Type: application/json" \
            --data "{\"type\":\"$type\",\"name\":\"$name\",\"content\":\"$content\",\"proxied\":$PROXY}"
    fi
}

# --- 4. 执行更新 ---
# 更新 IPv4
RES4=$(update_record "A" "$HOSTNAME" "$IP4_ADDR" "$ZONE_ID" "$API_TOKEN")
RES4_SUCCESS=$(echo "$RES4" | $JQ_EXEC -r ".success")

# 更新 IPv6
RES6_SUCCESS="false"
if [ "$IPV6_SUPPORT" = "true" ] && [ -n "$IP6_ADDR" ]; then
    RES6=$(update_record "AAAA" "$HOSTNAME" "$IP6_ADDR" "$ZONE_ID" "$API_TOKEN")
    RES6_SUCCESS=$(echo "$RES6" | $JQ_EXEC -r ".success")
fi

# --- 5. 反馈结果给 DSM ---
if [ "$RES4_SUCCESS" = "true" ] || [ "$RES6_SUCCESS" = "true" ]; then
    echo "good"
else
    # 输出错误信息到日志方便排查
    echo "Update Failed. IPv4: $RES4_SUCCESS, IPv6: $RES6_SUCCESS" >&2
    echo "badauth"
fi
