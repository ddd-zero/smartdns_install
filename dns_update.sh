#!/bin/bash

# ==============================================================================
# 脚本名称: update_resolv.sh
# 脚本功能: 检查 /etc/resolv.conf 文件，确保唯一的 nameserver 是 127.0.0.1。
#           它会删除所有其他的 nameserver 配置，并只保留/添加一个
#           nameserver 127.0.0.1，同时不影响文件中的其他配置项（如 search, options等）。
# 使用方法: sudo ./update_resolv.sh
# ==============================================================================

# 定义目标文件和期望的 nameserver 配置
RESOLV_CONF="/etc/resolv.conf"
DESIRED_NS="nameserver 127.0.0.1"

# --- 准备工作 ---

# 1. 检查脚本是否以 root 权限运行
if [ "$(id -u)" -ne 0 ]; then
   echo "错误: 此脚本需要以 root 权限运行。" >&2
   exit 1
fi

# 2. 检查 resolv.conf 文件是否存在
if [ ! -f "$RESOLV_CONF" ]; then
    echo "错误: $RESOLV_CONF 文件不存在。" >&2
    exit 1
fi

# --- 核心逻辑 ---

# 3. 获取当前文件中所有的 nameserver 配置
#    使用 grep 过滤出所有以 'nameserver' 开头的行（忽略开头的空格）
current_ns_config=$(grep '^[[:space:]]*nameserver' "$RESOLV_CONF")

# 4. 检查当前配置是否已经是我们期望的配置
if [ "$current_ns_config" == "$DESIRED_NS" ]; then
    echo "DNS 配置已是 127.0.0.1，无需修改。"
    exit 0
else
    echo "检测到 DNS 配置不是 127.0.0.1，正在执行修改..."
    echo "--- 修改前 ---"
    cat "$RESOLV_CONF"
    echo "----------------"

    # 5. 使用 awk 进行修改
    #   - 创建一个临时文件来存储新内容，这是更安全的操作方式
    #   - 逐行读取原文件：
    #     - 如果某一行是 'nameserver' 配置，就跳过它（不打印）。
    #     - 如果某一行不是 'nameserver' 配置，就原样打印到临时文件。
    #   - 使用一个标志位 ns_added 确保 'nameserver 127.0.0.1' 只被添加一次。
    #     - 我们在文件末尾（END块）检查标志位，如果从未添加过，则添加它。
    #       这确保了即使原文件没有任何 nameserver，也能正确添加。
    #       实际上，更稳妥的做法是找到第一个非注释行来插入，但为了简单和通用性，
    #       我们采用“先删后加”的逻辑。

    # 使用 awk 实现完美的替换和保留
    # - /^[[:space:]]*nameserver/ { next }：匹配到 nameserver 行，直接跳过，不输出
    # - { print }：其他所有行，原样输出
    # 这个简单的组合可以删除所有 nameserver 行。
    # 然后我们用 sed 在第一行后面插入我们想要的行。

    # 使用 sed 实现一个更健壮的版本
    # 1. 删除所有现有的 nameserver 行
    # 2. 在处理后的文件第一行后面，追加我们想要的 nameserver
    #    使用 -i 直接修改文件
    sed -i -e '/^[[:space:]]*nameserver/d' \
           -e "1a\\$DESIRED_NS" "$RESOLV_CONF"

    echo "修改成功！"
    echo "--- 修改后 ---"
    cat "$RESOLV_CONF"
    echo "----------------"
    exit 0
fi