sudo cat > /sbin/cloudflareddns.sh << 'EOF'
#!/bin/bash

# --- 核心配置 ---
proxy="false"  # 强制关闭 CDN 代理
ipv6="true"    # 开启 IPv6 支持

# 接收群晖传入参数
username="$1"    # 邮箱 (或 Account ID)
password="$2"    # API Token
hostname="$3"    # 域名
ipAddr="$4"      # IPv4 地址

# 自动获取公网 IPv6 地址
if [ "$ipv6" = "true" ]; then
    ip6Addr=$(curl -s -6 https://api6.ipify.org || curl -s -6 https://v6.ident.me)
fi

# --- 兼容性逻辑：提取根域名 (Zone Name) ---
# 不使用 rev 命令，改用参数替换方式获取 example.com
if [[ "$hostname" =~ ^[0-9.]+$ ]]; then
    echo "badauth"
    exit 1
fi
# 提取最后两段作为 Zone Name
zoneName=$(echo "$hostname" | awk -F. '{print $(NF-1)"."$NF}')

# 1. 获取 Zone ID
zoneId=$(curl -s -X GET "https://api.cloudflare.com/client/v4/zones?name=$zoneName" \
     -H "Authorization: Bearer $password" \
     -H "Content-Type: application/json" | jq -r '.result[0].id')

if [ "$zoneId" = "null" ] || [ -z "$zoneId" ]; then
    echo "badauth"
    exit 1
fi

# 2. 获取 DNS 记录 ID
recordId=$(curl -s -X GET "https://api.cloudflare.com/client/v4/zones/$zoneId/dns_records?type=A&name=$hostname" \
    -H "Authorization: Bearer $password" | jq -r '.result[0].id')

if [ "$ipv6" = "true" ]; then
    recordIdv6=$(curl -s -X GET "https://api.cloudflare.com/client/v4/zones/$zoneId/dns_records?type=AAAA&name=$hostname" \
        -H "Authorization: Bearer $password" | jq -r '.result[0].id')
fi

# API 定义
createDnsApi="https://api.cloudflare.com/client/v4/zones/${zoneId}/dns_records"
updateDnsApi="https://api.cloudflare.com/client/v4/zones/${zoneId}/dns_records/${recordId}"
update6DnsApi="https://api.cloudflare.com/client/v4/zones/${zoneId}/dns_records/${recordIdv6}"

# 3. 更新 IPv4
if [[ $recordId = "null" ]] || [[ -z $recordId ]]; then
    res=$(curl -s -X POST "$createDnsApi" -H "Authorization: Bearer $password" -H "Content-Type:application/json" \
        --data "{\"type\":\"A\",\"name\":\"$hostname\",\"content\":\"$ipAddr\",\"proxied\":$proxy}")
else
    res=$(curl -s -X PUT "$updateDnsApi" -H "Authorization: Bearer $password" -H "Content-Type:application/json" \
        --data "{\"type\":\"A\",\"name\":\"$hostname\",\"content\":\"$ipAddr\",\"proxied\":$proxy}")
fi
resSuccess=$(echo "$res" | jq -r ".success")

# 4. 更新 IPv6
res6Success="false"
if [[ "$ipv6" = "true" && -n "$ip6Addr" ]] ; then
    if [[ $recordIdv6 = "null" ]] || [[ -z $recordIdv6 ]]; then
        res6=$(curl -s -X POST "$createDnsApi" -H "Authorization: Bearer $password" -H "Content-Type:application/json" \
            --data "{\"type\":\"AAAA\",\"name\":\"$hostname\",\"content\":\"$ip6Addr\",\"proxied\":$proxy}")
    else
        res6=$(curl -s -X PUT "$update6DnsApi" -H "Authorization: Bearer $password" -H "Content-Type:application/json" \
            --data "{\"type\":\"AAAA\",\"name\":\"$hostname\",\"content\":\"$ip6Addr\",\"proxied\":$proxy}")
    fi
    res6Success=$(echo "$res6" | jq -r ".success")
fi

# 最终结果
if [[ $resSuccess = "true" ]] || [[ $res6Success = "true" ]]; then
    echo "good"
else
    echo "badauth"
fi
EOF

# 赋予权限
sudo chmod +x /sbin/cloudflareddns.sh

