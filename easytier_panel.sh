#!/bin/bash

#================================================================
# EasyTier 交互式一键安装与管理脚本 V7.1
# 支持环境变量和参数传递非交互执行
#================================================================

GREEN='\033[0;32m'
RED='\033[0;31m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
CYAN='\033[0;36m'
NC='\033[0m'

INSTALL_DIR="/usr/local/bin"
EASY_COMMAND_PATH="${INSTALL_DIR}/easy"
CONFIG_DIR="/etc/easytier"
CONFIG_FILE="${CONFIG_DIR}/easy.conf"
SERVICE_NAME="easytier-custom"
SERVICE_FILE="/etc/systemd/system/${SERVICE_NAME}.service"

# --- 辅助函数 ---
check_root() {
    if [ "$(id -u)" -ne 0 ]; then
        echo -e "${RED}错误: 此脚本需要以 root 权限运行。${NC}"
        exit 1
    fi
}

check_dependencies() {
    for cmd in curl unzip find awk; do
        if ! command -v "$cmd" &>/dev/null; then
            echo -e "${RED}错误: 依赖 '$cmd' 未找到。${NC}"
            exit 1
        fi
    done
}

generate_uuid() {
    if command -v uuidgen &>/dev/null; then
        uuidgen
    else
        cat /proc/sys/kernel/random/uuid
    fi
}

parse_args() {
    for arg in "$@"; do
        case $arg in
            ipv4=*) CFG_IPV4="${arg#*=}" ;;
            network_name=*) CFG_NETWORK_NAME="${arg#*=}" ;;
            network_secret=*) CFG_NETWORK_SECRET="${arg#*=}" ;;
            auto_start=*) CFG_AUTO_START="${arg#*=}" ;;
            join=*) CFG_JOIN_COMMAND="${arg#*=}" ;;
        esac
    done
}

# 支持环境变量同步到内部变量，优先使用命令行参数
sync_env_vars() {
    CFG_IPV4=${CFG_IPV4:-${ipv4:-}}
    CFG_NETWORK_NAME=${CFG_NETWORK_NAME:-${network_name:-}}
    CFG_NETWORK_SECRET=${CFG_NETWORK_SECRET:-${network_secret:-}}
    CFG_AUTO_START=${CFG_AUTO_START:-${auto_start:-}}
    CFG_JOIN_COMMAND=${CFG_JOIN_COMMAND:-${join:-}}
}

update_easy_command() {
    local is_first_run=false
    if [ ! -f "$EASY_COMMAND_PATH" ]; then
        is_first_run=true
        echo -e "${YELLOW}首次运行，正在安装 'easy' 快捷命令...${NC}"
    else
        if ! cmp -s "$0" "$EASY_COMMAND_PATH"; then
            echo -e "${YELLOW}检测到新版本，正在更新 'easy' 快捷命令...${NC}"
        else
            return 0
        fi
    fi

    cp "$0" "$EASY_COMMAND_PATH"
    chmod +x "$EASY_COMMAND_PATH"

    if [ $? -ne 0 ]; then
        echo -e "${RED}❌ 'easy' 命令安装/更新失败! 请检查 ${INSTALL_DIR} 目录权限。${NC}"
        exit 1
    fi

    # 非交互模式跳过提示和sleep
    if [ "$is_first_run" = true ]; then
        if [ -n "$CFG_IPV4" ] || [ -n "$CFG_NETWORK_NAME" ] || [ -n "$CFG_NETWORK_SECRET" ] || [ -n "$CFG_JOIN_COMMAND" ]; then
            return 0
        else
            echo -e "${GREEN}✔ 'easy' 命令安装成功。${NC}"
            echo -e "${CYAN}现在将进入管理面板。您下次可以直接运行 'sudo easy'。${NC}"
            sleep 2
        fi
    else
        echo -e "${GREEN}✔ 'easy' 命令已更新至最新。${NC}"
    fi
}

install_easytier() {
    if [ -f "${INSTALL_DIR}/easytier-core" ]; then
        echo -e "${GREEN}✔ EasyTier 核心程序已安装，跳过安装步骤。${NC}"
        return 0
    fi

    echo -e "${BLUE}--- 1. 安装/更新 EasyTier 核心程序 ---${NC}"
    check_dependencies

    echo -e "${GREEN}正在获取最新版本号...${NC}"
    LATEST_TAG=$(curl --silent "https://api.github.com/repos/EasyTier/EasyTier/releases/latest" | grep '"tag_name":' | sed -E 's/.*"([^"]+)".*/\1/')
    if [ -z "$LATEST_TAG" ]; then
        echo -e "${RED}获取版本号失败!${NC}"
        return 1
    fi
    echo -e "${GREEN}最新版本: ${YELLOW}${LATEST_TAG}${NC}"

    ARCH=$(uname -m)
    if [[ "$ARCH" != "x86_64" && "$ARCH" != "aarch64" ]]; then
        echo -e "${RED}不支持的架构: $ARCH${NC}"
        return 1
    fi
    echo -e "${GREEN}系统架构: ${YELLOW}${ARCH}${NC}"

    PACKAGE_NAME="easytier-linux-${ARCH}-${LATEST_TAG}.zip"
    DOWNLOAD_URL="https://github.com/EasyTier/EasyTier/releases/download/${LATEST_TAG}/${PACKAGE_NAME}"

    echo -e "${GREEN}正在下载: ${YELLOW}${DOWNLOAD_URL}${NC}"
    curl -L -f -o "/tmp/${PACKAGE_NAME}" "${DOWNLOAD_URL}" || {
        echo -e "${RED}下载失败!${NC}"
        return 1
    }

    TEMP_UNZIP_DIR=$(mktemp -d /tmp/easytier.XXXXXX)
    echo -e "${GREEN}正在解压...${NC}"
    unzip -o "/tmp/${PACKAGE_NAME}" -d "${TEMP_UNZIP_DIR}" > /dev/null || {
        echo -e "${RED}解压失败!${NC}"
        rm -rf "${TEMP_UNZIP_DIR}"
        return 1
    }

    CORE_PATH=$(find "${TEMP_UNZIP_DIR}" -name "easytier-core" -type f | head -n 1)
    CLI_PATH=$(find "${TEMP_UNZIP_DIR}" -name "easytier-cli" -type f | head -n 1)

    if [ -z "$CORE_PATH" ] || [ -z "$CLI_PATH" ]; then
        echo -e "${RED}错误: 未找到核心文件。${NC}"
        rm -rf "${TEMP_UNZIP_DIR}"
        rm -f "/tmp/${PACKAGE_NAME}"
        return 1
    fi

    echo -e "${GREEN}正在安装可执行文件...${NC}"
    mv "${CORE_PATH}" "${INSTALL_DIR}/easytier-core"
    mv "${CLI_PATH}" "${INSTALL_DIR}/easytier-cli"
    chmod +x "${INSTALL_DIR}/easytier-core" "${INSTALL_DIR}/easytier-cli"

    rm -f "/tmp/${PACKAGE_NAME}"
    rm -rf "${TEMP_UNZIP_DIR}"

    echo -e "\n${GREEN}✔ EasyTier 核心程序安装成功!${NC}"
}

save_config() {
    mkdir -p "$CONFIG_DIR"
    {
        echo "# EasyTier 自定义配置"
        echo "CFG_IPV4='${CFG_IPV4}'"
        echo "CFG_USER='${CFG_NETWORK_NAME}'"
        echo "CFG_PASSWORD='${CFG_NETWORK_SECRET}'"
        echo "CFG_NODE='tcp://public.easytier.cn:11010'"
    } > "$CONFIG_FILE"
}

create_network_service() {
    local mode="$1"
    echo -e "${BLUE}--- 2. 系统服务：新建网络 ---${NC}"

    if ! command -v easytier-core &>/dev/null; then
        echo -e "${RED}错误: 'easytier-core' 未安装。请先执行选项 1。${NC}"
        return 1
    fi

    # 交互或非交互模式获取参数
    if [ -z "$CFG_IPV4" ]; then
        read -p "请输入局域网 IP (例如 10.10.10.1) [回车随机生成]: " input_ipv4
        if [ -z "$input_ipv4" ]; then
            CFG_IPV4="100.$(shuf -i 0-255 -n 1).$(shuf -i 0-255 -n 1).1"
            echo -e "${GREEN}未指定IP，已为您随机生成: ${YELLOW}${CFG_IPV4}${NC}"
        else
            CFG_IPV4="$input_ipv4"
        fi
    fi

    if [ -z "$CFG_NETWORK_NAME" ]; then
        read -p "请输入网络名称 [回车随机生成]: " input_user
        CFG_NETWORK_NAME=${input_user:-$(generate_uuid)}
    fi

    if [ -z "$CFG_NETWORK_SECRET" ]; then
        read -p "请输入网络密钥 [回车随机生成]: " input_password
        CFG_NETWORK_SECRET=${input_password:-$(generate_uuid)}
    fi

    save_config

    local full_command="${INSTALL_DIR}/easytier-core --ipv4 ${CFG_IPV4} --network-name ${CFG_NETWORK_NAME} --network-secret ${CFG_NETWORK_SECRET} -p tcp://public.easytier.cn:11010"

    echo -e "${GREEN}正在创建服务文件...${NC}"
    cat > "$SERVICE_FILE" <<EOF
[Unit]
Description=EasyTier Custom Service by Script
After=network.target

[Service]
Type=simple
ExecStart=${full_command}
Restart=on-failure
RestartSec=5s
LimitNOFILE=65535

[Install]
WantedBy=multi-user.target
EOF

    echo -e "${GREEN}正在重载 systemd 并启动服务...${NC}"
    systemctl daemon-reload
    systemctl restart "${SERVICE_NAME}"
    sleep 2

    if systemctl is-active --quiet "${SERVICE_NAME}"; then
        echo -e "${GREEN}✔ 服务 '${SERVICE_NAME}' 已成功启动。${NC}"
        if [ "$mode" = "non_interactive" ]; then
            if [ "${CFG_AUTO_START}" = "n" ]; then
                systemctl disable "${SERVICE_NAME}"
                echo -e "${YELLOW}根据 'auto_start=n' 参数，已取消开机自启。${NC}"
            else
                systemctl enable "${SERVICE_NAME}"
                echo -e "${GREEN}根据 'auto_start' 参数 (或默认)，已设置为开机自启。${NC}"
            fi
        else
            read -p "是否设置为开机自启? [Y/n]: " confirm_autostart
            case "$confirm_autostart" in
                [Nn]*) systemctl disable "${SERVICE_NAME}"; echo -e "${YELLOW}已取消开机自启。${NC}" ;;
                *) systemctl enable "${SERVICE_NAME}"; echo -e "${GREEN}已设置为开机自启。${NC}" ;;
            esac
        fi
    else
        echo -e "${RED}❌ 服务启动失败! 请执行选项 4 查看详细错误。${NC}"
    fi
}

# 主程序入口

check_root

# 解析命令行参数
parse_args "$@"

# 同步环境变量到内部变量，优先命令行参数
sync_env_vars

# 仅当直接运行脚本文件时才更新快捷命令，避免递归
if [ "$0" != "$EASY_COMMAND_PATH" ]; then
    update_easy_command
fi

# 非交互模式判断（传入了关键变量）
if [ -n "$CFG_IPV4" ] && [ -n "$CFG_NETWORK_NAME" ] && [ -n "$CFG_NETWORK_SECRET" ]; then
    echo -e "${YELLOW}检测到非交互模式参数，开始自动安装并创建网络服务...${NC}"
    install_easytier && create_network_service "non_interactive"
    echo -e "\n${GREEN}✔ 非交互式任务执行完毕。${NC}"
    echo -e "${CYAN}提示: 'easy' 快捷命令已更新，您现在可以使用 'sudo easy' 来打开管理面板。${NC}"
    exit 0
fi

# 交互菜单（这里只示范安装和创建网络，你可继续补充其他功能）
while true; do
    clear
    echo -e "${BLUE}EasyTier 管理面板${NC}"
    echo "1) 安装/更新 EasyTier"
    echo "2) 新建网络服务"
    echo "0) 退出"
    read -p "请输入选项: " choice
    case $choice in
        1) install_easytier ;;
        2) create_network_service "interactive" ;;
        0) exit 0 ;;
        *) echo "无效选项" ;;
    esac
    read -p "按回车继续..."
done
