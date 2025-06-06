#!/bin/bash

# ==============================================================================
# SmartDNS 安装与配置脚本 - 第三步
#
# 功能:
#   1. 检查环境 (OS, 端口)。
#   2. 自动下载并安装最新版 SmartDNS。
#   3. 备份默认配置，下载并应用新的配置文件。
#   4. 重启并设置 SmartDNS 开机自启。
#   5. 备份并修改系统的 DNS 解析配置 (`/etc/resolv.conf`)。
# ==============================================================================

# 脚本出错时立即退出
set -e
# 管道命令中任何一个失败则整个管道失败
set -o pipefail

# --- 全局变量和函数 ---

# 定义颜色代码
readonly COLOR_RED='\033[0;31m'
readonly COLOR_GREEN='\033[0;32m'
readonly COLOR_YELLOW='\033[0;33m'
readonly COLOR_BLUE='\033[0;34m'
readonly COLOR_NC='\033[0m'

# 定义项目和配置信息
readonly GITHUB_REPO="pymumu/smartdns"
readonly GITHUB_API_URL="https://api.github.com/repos/${GITHUB_REPO}/releases/latest"
readonly NEW_CONF_URL="https://raw.githubusercontent.com/ddd-zero/smartdns_install/refs/heads/main/smartdns.conf"
readonly SMARTDNS_CONF_PATH="/etc/smartdns/smartdns.conf"
readonly RESOLV_CONF_PATH="/etc/resolv.conf"

# 临时下载文件路径
DEB_FILE_PATH=""

# 日志函数
info() { echo -e "${COLOR_GREEN}[INFO] ${1}${COLOR_NC}"; }
warn() { echo -e "${COLOR_YELLOW}[WARN] ${1}${COLOR_NC}"; }
error() { echo -e "${COLOR_RED}[ERROR] ${1}${COLOR_NC}" >&2; }
highlight() { echo -e "${COLOR_BLUE}${1}${COLOR_NC}"; }

# 清理函数
cleanup() {
    if [ -n "$DEB_FILE_PATH" ] && [ -f "$DEB_FILE_PATH" ]; then
        info "正在删除临时文件: ${DEB_FILE_PATH}"
        rm -f "$DEB_FILE_PATH"
    fi
}
trap cleanup EXIT HUP INT QUIT TERM

# --- 检查功能 ---
check_os() {
    info "正在检查操作系统..."
    if [ -f /etc/os-release ]; then
        # shellcheck source=/dev/null
        . /etc/os-release
        if [ "$ID" == "debian" ]; then
            info "操作系统检查通过: Debian"
        else
            error "此脚本仅支持 Debian 系统。检测到您的系统是: $ID"
            exit 1
        fi
    else
        error "无法找到 /etc/os-release 文件，无法确定操作系统类型。"
        exit 1
    fi
}

check_port_53() {
    info "正在检查 53 端口..."
    if ss -lunt | grep -q -w ':53'; then
        error "端口 53 已被占用。SmartDNS 需要使用此端口。"
        warn "请先停止相关服务，再重新运行此脚本。"
        exit 1
    else
        info "端口 53 未被占用，检查通过。"
    fi
}

# --- 安装功能 ---
install_dependencies() {
    info "正在更新软件包列表并安装必要工具 (curl, ca-certificates)..."
    ${SUDO} apt-get update
    ${SUDO} apt-get install -y curl ca-certificates
}

download_and_install() {
    info "正在从 GitHub 获取最新的 SmartDNS 版本信息..."
    local download_url
    download_url=$(curl -sL "$GITHUB_API_URL" | grep "browser_download_url" | grep "x86_64-debian-all.deb" | sed -E 's/.*"browser_download_url": "(.*)".*/\1/')

    if [ -z "$download_url" ]; then
        error "无法找到适用于 x86_64-debian-all 的最新版本下载链接。"
        exit 1
    fi

    local filename
    filename=$(basename "$download_url")
    DEB_FILE_PATH="/tmp/${filename}"

    info "找到最新版本，下载链接为:"
    highlight "$download_url"
    info "正在下载文件到 ${DEB_FILE_PATH} ..."
    curl -L -o "$DEB_FILE_PATH" "$download_url"
    info "文件下载成功。"

    info "开始安装 SmartDNS..."
    ${SUDO} apt-get install -y "$DEB_FILE_PATH"
    info "SmartDNS 安装成功！"
}

# --- 配置功能 ---

# 任务5: 等待 SmartDNS 启动并替换配置文件
configure_smartdns() {
    info "等待 SmartDNS 服务初步启动..."
    # 等待几秒钟，确保服务和配置文件已就位
    sleep 3

    info "备份原始配置文件..."
    if [ -f "$SMARTDNS_CONF_PATH" ]; then
        ${SUDO} mv "$SMARTDNS_CONF_PATH" "${SMARTDNS_CONF_PATH}.bak"
        info "原始配置文件已备份至: ${SMARTDNS_CONF_PATH}.bak"
    else
        warn "未找到原始配置文件 ${SMARTDNS_CONF_PATH}，可能已被移动或删除。"
    fi

    info "正在从以下地址下载新的配置文件:"
    highlight "$NEW_CONF_URL"
    # 使用 curl 下载新配置，并通过 sudo tee 写入需要权限的目录
    if ! curl -sL "$NEW_CONF_URL" | ${SUDO} tee "$SMARTDNS_CONF_PATH" > /dev/null; then
        error "下载或写入新配置文件失败！"
        # 如果失败，尝试恢复备份
        if [ -f "${SMARTDNS_CONF_PATH}.bak" ]; then
            warn "正在尝试恢复原始配置文件..."
            ${SUDO} mv "${SMARTDNS_CONF_PATH}.bak" "$SMARTDNS_CONF_PATH"
        fi
        exit 1
    fi
    info "新配置文件已成功应用。"

    info "正在重启 SmartDNS 服务以应用新配置..."
    ${SUDO} systemctl restart smartdns

    info "正在设置 SmartDNS 服务开机自启..."
    ${SUDO} systemctl enable smartdns
    # systemctl is-enabled 是幂等的，重复执行无害
    if ${SUDO} systemctl is-enabled --quiet smartdns; then
        info "SmartDNS 开机自启已成功设置。"
    else
        error "设置 SmartDNS 开机自启失败！"
        exit 1
    fi
}

# 任务6: 配置系统 DNS 解析
configure_system_dns() {
    info "正在配置系统 DNS 解析指向 SmartDNS (127.0.0.1)..."

    # Debian 系统中 /etc/resolv.conf 常常是一个指向 /run/resolvconf/resolv.conf 的软链接
    # 我们直接操作最终文件，但备份原始链接指向的文件
    local real_resolv_path
    real_resolv_path=$(readlink -f "$RESOLV_CONF_PATH")
    
    info "备份当前的 resolv.conf 文件..."
    if [ -f "$real_resolv_path" ]; then
        ${SUDO} cp "$real_resolv_path" "${RESOLV_CONF_PATH}.bak"
        info "当前 DNS 配置已备份至: ${RESOLV_CONF_PATH}.bak"
    else
        warn "未找到 ${real_resolv_path}，跳过备份。"
    fi

    info "正在修改 ${RESOLV_CONF_PATH}..."
    # 使用 tee 来写入，因为它能很好地处理权限问题
    echo "nameserver 127.0.0.1" | ${SUDO} tee "$RESOLV_CONF_PATH" > /dev/null
}

# --- 主函数 ---
main() {
    # 确保以 root 或 sudo 权限运行
    if [ "$(id -u)" -ne 0 ]; then
        SUDO="sudo"
        info "脚本将使用 'sudo' 获取管理员权限。"
    else
        SUDO=""
    fi

    check_os
    check_port_53
    install_dependencies
    download_and_install
    
    # --- 新增的配置步骤 ---
    configure_smartdns
    configure_system_dns

    info "所有操作已成功完成！"
    highlight "SmartDNS 已安装、配置并设置为系统默认 DNS 解析器。"
    info "您可以使用 nslookup -querytype=ptr smartdns 来测试解析。"
}

# --- 脚本执行入口 ---
main "$@"





