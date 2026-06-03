#!/usr/bin/env bash

# 哈希取模调度脚本
# 将 conf/ 目录下的 yaml 文件通过哈希取模分散到不同小时执行
# 避免 GitHub Actions 一次性处理所有文件导致超时
#
# 环境变量：
#   SYNC_MOD - 取模值，默认 24
#              配合 cron 频率使用：
#              每1小时触发 → mod=24（每次处理 1/24 的配置）
#              每2小时触发 → mod=12
#              每3小时触发 → mod=8
#              每4小时触发 → mod=6
#              每6小时触发 → mod=4

hash_and_mod() {
    local input="$1"
    local modulus="$2"
    local hash
    local decimal
    local result

    hash=$(echo -n "$input" | md5sum | awk '{ print $1 }')
    decimal=$(echo "ibase=16; $(echo $hash | tr 'a-f' 'A-F')" | bc)
    result=$((decimal % modulus))

    if [ "$result" -lt 0 ]; then
        result=$((result + modulus))
    fi

    echo "$result"
}

main() {
    hour=$(date +%-H)
    mod=${SYNC_MOD:-24}

    expect=$(expr $hour % $mod)

    list=""
    for file in ./conf/*.yaml; do
        filename=$(basename "$file")
        result=$(hash_and_mod "$filename" $mod)

        if [ "$result" -eq "$expect" ]; then
            list="$list $file"
        fi
    done

    echo $list
}

main
