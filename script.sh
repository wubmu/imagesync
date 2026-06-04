#!/usr/bin/env bash

# 哈希取模调度脚本
# 将 conf/ 目录下的 yaml 文件通过哈希取模分散到不同轮次执行
# 避免 GitHub Actions 一次性处理所有文件导致超时
#
# 环境变量：
#   SYNC_MOD - 取模值，默认 8
#              公式：周期天数 × 24 ÷ 间隔小时数
#              单日示例：每1h→24, 每2h→12, 每3h→8, 每4h→6, 每6h→4
#              多日示例：3天每6h→12, 7天每6h→28, 7天每8h→21
#   SYNC_INTERVAL_HOURS - cron 触发间隔（小时），默认 3
#                          用于计算调度轮次，确保多日周期内每次处理不同文件

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
    local interval_h=${SYNC_INTERVAL_HOURS:-3}
    local mod=${SYNC_MOD:-8}
    local interval_s=$((interval_h * 3600))

    # 基于 epoch 的调度轮次索引
    # epoch_secs / interval_secs 得到单调递增的运行序号
    # % mod 让它在 SYNC_MOD 次后循环，实现多日周期调度
    local run_index=$(( ($(date +%s) / interval_s) % mod ))

    list=""
    for file in ./conf/*.yaml; do
        filename=$(basename "$file")
        result=$(hash_and_mod "$filename" $mod)

        if [ "$result" -eq "$run_index" ]; then
            list="$list $file"
        fi
    done

    echo $list
}

main
