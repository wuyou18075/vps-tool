#!/bin/bash
set -euo pipefail
IFS=$'\n\t'

#================================================================
# EasyTier 交互式一键安装与管理脚本 V7.1 (功能增强版)
#
# 作者: Gemini @ Google
# 版本: 7.1 (2025-07-06)
# 备注: 根据要求重新加入 'easy' 命令管理并调整菜单
#================================================================

# --- 颜色定义 ---
GREEN='\033[0;32m'
RED='\033[0;31m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
CYAN='\033[0;36m'
NC='\033[0m'

# --- 路径定义 ---
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

get_local_virtual_ip() {
    if ! systemctl is-active --quiet "${SERVICE_NAME}"; then
        echo ""
        return
    fi
    local local_ip
    local_ip=$(easytier-cli route 2>/dev/null | awk -F '│' '
        $6 ~ /Local/ {
            ip_raw = $2;
            gsub(/^[[:space:]]+|[[:space:]]+$/, "", ip_raw);
            sub(/\/.*$/, "", ip_raw);
            print ip_raw;
            exit;
        }')
    echo "$local_ip"
}

save_config() {
    mkdir -p "$CONFIG_DIR"
    {
        echo "# EasyTier 自定义配置"
        echo "CFG_IPV4='${CFG_IPV4}'"
        echo "CFG_USER='${CFG_USER}'"
        echo "CFG_PASSWORD='${CFG_PASSWORD}'"
        echo "CFG_NODE='${CFG_NODE}'"
    } > "$CONFIG_FILE"
}

update_easy_command() {
    echo -e "${YELLOW}正在安装/更新 'easy' 快捷命令至当前版本...${NC}"
    # 使用 cp 命令复制脚本自身，确保可执行
    if ! cp "$0" "$EASY_COMMAND_PATH"; then
        echo -e "${RED}❌ 'easy' 命令复制失败! 请检查 ${INSTALL_DIR} 目录权限。${NC}"
        return 1
    fi
    if ! chmod +x "$EASY_COMMAND_PATH"; then
        echo -e "${RED}❌ 'easy' 命令授权失败!${NC}"
        return 1
    fi
    
    # 仅在交互模式下显示成功信息
    if [[ "${1:-}" != "non_interactive_first_run" ]]; then
       echo -e "${GREEN}✔ 'easy' 快捷命令已安装/更新。现在您可以在任何地方使用 'sudo easy' 来运行此脚本。${NC}"
    fi
}

uninstall_easy_command() {
    echo -e "${BLUE}--- 卸载 'easy' 快捷命令 ---${NC}"
    if [ -f "$EASY_COMMAND_PATH" ]; then
        if rm -f "$EASY_COMMAND_PATH"; then
            echo -e "${GREEN}✔ 快捷命令 'easy' 已成功卸载。${NC}"
            echo -e "${YELLOW}您可能需要重新打开终端使其完全失效。${NC}"
        else
            echo -e "${RED}❌ 快捷命令 'easy' 卸载失败。${NC}"
        fi
    else
        echo -e "${YELLOW}快捷命令 'easy' 未安装，无需卸载。${NC}"
    fi
}

# --- 核心功能函数 ---

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
    curl -L -f -o "/tmp/${PACKAGE_NAME}" "${DOWNLOAD_URL}" || { echo -e "${RED}下载失败!${NC}"; return 1; }
    TEMP_UNZIP_DIR=$(mktemp -d /tmp/easytier.XXXXXX)
    echo -e "${GREEN}正在解压...${NC}"
    unzip -o "/tmp/${PACKAGE_NAME}" -d "${TEMP_UNZIP_DIR}" > /dev/null || { echo -e "${RED}解压失败!${NC}"; rm -rf "${TEMP_UNZIP_DIR}"; return 1; }
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

create_network_service() {
    local mode="$1"
    echo -e "${BLUE}--- 2. 系统服务：新建网络 ---${NC}"
    if ! command -v easytier-core &>/dev/null; then
        echo -e "${RED}错误: 'easytier-core' 未安装。请先执行选项 1。${NC}"
        return 1
    fi

    if [[ -n "${ipv4:-}" ]]; then
        CFG_IPV4="$ipv4"
        echo -e "${GREEN}✔ 已从环境变量读取虚拟地址: ${CFG_IPV4}${NC}"
    else
        read -r -p "请输入局域网 IP (例如 10.10.10.1) [回车随机生成]: " input_ipv4
        if [ -z "$input_ipv4" ]; then
            CFG_IPV4="100.$(shuf -i 0-255 -n 1).$(shuf -i 0-255 -n 1).1"
            echo -e "${GREEN}未指定IP，已为您随机生成: ${YELLOW}${CFG_IPV4}${NC}"
        else
            CFG_IPV4="$input_ipv4"
        fi
    fi

    if [[ -n "${network_name:-}" ]]; then
        CFG_USER="$network_name"
        echo -e "${GREEN}✔ 已从环境变量读取网络名称: ${CFG_USER}${NC}"
    else
        read -r -p "请输入网络名称 [回车随机生成]: " input_user
        CFG_USER="${input_user:-$(generate_uuid)}"
    fi

    if [[ -n "${network_secret:-}" ]]; then
        CFG_PASSWORD="$network_secret"
        echo -e "${GREEN}✔ 已从环境变量读取网络密钥。${NC}"
    else
        read -r -p "请输入网络密钥 [回车随机生成]: " input_password
        CFG_PASSWORD="${input_password:-$(generate_uuid)}"
    fi

    if [[ -n "${node:-}" ]]; then
        CFG_NODE="$node"
        echo -e "${GREEN}✔ 已从环境变量读取注册中心节点: ${CFG_NODE}${NC}"
    else
        if [[ "$mode" == "non_interactive" ]]; then
            CFG_NODE="tcp://public.easytier.cn:11010"
            echo -e "${GREEN}✔ 未指定 'node'，已使用默认注册中心节点。${NC}"
        else
            read -r -p "请输入注册中心节点 [默认: tcp://public.easytier.cn:11010]: " input_node
            CFG_NODE="${input_node:-tcp://public.easytier.cn:11010}"
        fi
    fi

    save_config

    local full_command="${INSTALL_DIR}/easytier-core --ipv4 ${CFG_IPV4} --network-name ${CFG_USER} --network-secret ${CFG_PASSWORD} -p ${CFG_NODE}"

    echo -e "${GREEN}正在创建服务文件...${NC}"
    {
        echo "[Unit]"
        echo "Description=EasyTier Custom Service by Script"
        echo "After=network.target"
        echo "[Service]"
        echo "Type=simple"
        echo "ExecStart=${full_command}"
        echo "Restart=on-failure"
        echo "RestartSec=5s"
        echo "LimitNOFILE=65535"
        echo "[Install]"
        echo "WantedBy=multi-user.target"
    } > "$SERVICE_FILE"

    echo -e "${GREEN}正在重载 systemd 并启动服务...${NC}"
    systemctl daemon-reload
    systemctl restart "${SERVICE_NAME}"
    sleep 2
    if systemctl is-active --quiet "${SERVICE_NAME}"; then
        echo -e "${GREEN}✔ 服务 '${SERVICE_NAME}' 已成功启动。${NC}"
        if [[ "$mode" == "non_interactive" ]]; then
            if [[ "${auto_start:-}" == "n" ]]; then
                systemctl disable "${SERVICE_NAME}"
                echo -e "${YELLOW}根据 'auto_start=n' 参数，已取消开机自启。${NC}"
            else
                systemctl enable "${SERVICE_NAME}"
                echo -e "${GREEN}根据 'auto_start' 参数 (或默认)，已设置为开机自启。${NC}"
            fi
        else
            read -r -p "是否设置为开机自启? [Y/n]: " confirm_autostart
            if [[ "$confirm_autostart" =~ ^[Nn]$ ]]; then
                systemctl disable "${SERVICE_NAME}"
                echo -e "${YELLOW}已取消开机自启。${NC}"
            else
                systemctl enable "${SERVICE_NAME}"
                echo -e "${GREEN}已设置为开机自启。${NC}"
            fi
        fi
    else
        echo -e "${RED}❌ 服务启动失败! 请执行选项 4 查看详细错误。${NC}"
        return 1
    fi
}

join_network_service() {
    local mode="$1"
    local join_command_env="$2"
    echo -e "${BLUE}--- 3. 系统服务：加入网络 ---${NC}"
    if ! command -v easytier-core &>/dev/null; then
        echo -e "${RED}错误: 'easytier-core' 未安装。请先执行选项 1。${NC}"
        return 1
    fi
    local join_command=""
    if [ -n "$join_command_env" ]; then
        echo -e "${GREEN}检测到外部传入的 join 命令。${NC}"
        join_command="$join_command_env"
    else
        echo -e "${YELLOW}请粘贴完整的客户端连接命令...:${NC}"
        read -r -p "> " join_command
    fi
    if [[ "$join_command" != *"easytier-core"* ]]; then
        echo -e "${RED}错误: 输入的不是一个有效的 easytier-core 命令。${NC}"
        return 1
    fi
    local full_command
    full_command=$(echo "$join_command" | sed "s|easytier-core|${INSTALL_DIR}/easytier-core|")
    echo -e "${GREEN}正在根据提供的命令创建服务文件...${NC}"
    {
        echo "[Unit]"
        echo "Description=EasyTier Join-Network Service by Script"
        echo "After=network.target"
        echo "[Service]"
        echo "Type=simple"
        echo "ExecStart=${full_command}"
        echo "Restart=on-failure"
        echo "RestartSec=5s"
        echo "LimitNOFILE=65535"
        echo "[Install]"
        echo "WantedBy=multi-user.target"
    } > "$SERVICE_FILE"
    
    echo -e "${GREEN}正在重载 systemd 并启动服务...${NC}"
    systemctl daemon-reload
    systemctl restart "${SERVICE_NAME}"
    sleep 2
    if systemctl is-active --quiet "${SERVICE_NAME}"; then
        echo -e "${GREEN}✔ 服务 '${SERVICE_NAME}' 已成功启动。${NC}"
        if [[ "$mode" == "non_interactive" ]]; then
            if [[ "${auto_start:-}" == "n" ]]; then
                systemctl disable "${SERVICE_NAME}"
                echo -e "${YELLOW}根据 'auto_start=n' 参数，已取消开机自启。${NC}"
            else
                systemctl enable "${SERVICE_NAME}"
                echo -e "${GREEN}根据 'auto_start' 参数 (或默认)，已设置为开机自启。${NC}"
            fi
        else
            read -r -p "是否设置为开机自启? [Y/n]: " confirm_autostart
            if [[ "$confirm_autostart" =~ ^[Nn]$ ]]; then
                systemctl disable "${SERVICE_NAME}"
                echo -e "${YELLOW}已取消开机自启。${NC}"
            else
                systemctl enable "${SERVICE_NAME}"
                echo -e "${GREEN}已设置为开机自启。${NC}"
            fi
        fi
    else
        echo -e "${RED}❌ 服务启动失败! 请执行选项 4 查看详细错误。${NC}"
        return 1
    fi
}

view_service_status() {
    echo -e "${BLUE}--- 4. 查看服务运行状态 (systemctl) ---${NC}"
    if [ ! -f "$SERVICE_FILE" ]; then
        echo -e "${YELLOW}服务尚未被注册。${NC}"
        return
    fi
    systemctl --no-pager status "${SERVICE_NAME}"
}

view_pool_ips() {
    echo -e "${BLUE}--- 5. 查看内网节点 ---${NC}"
    if ! command -v easytier-cli &>/dev/null; then
        echo -e "${RED}错误: 'easytier-cli' 未安装。${NC}"
        return
    fi
    if ! systemctl is-active --quiet "${SERVICE_NAME}"; then
        echo -e "${RED}错误: EasyTier 服务未运行。${NC}"
        return
    fi
    local clean_list
    clean_list=$(easytier-cli route 2>/dev/null | awk -F '│' '/┌|└|├|ipv4/ { next; } { ip_raw = $2; hostname_raw = $3; gsub(/^[[:space:]]+|[[:space:]]+$/, "", hostname_raw); if (hostname_raw == "") { next; } ip_clean = ip_raw; gsub(/^[[:space:]]+|[[:space:]]+$/, "", ip_clean); sub(/\/.*$/, "", ip_clean); if (ip_clean == "") { ip_clean = "N/A"; } print ip_clean "\t" hostname_raw; }')
    if [ -z "$clean_list" ]; then
        echo -e "${YELLOW}当前连接池中没有有效节点。${NC}"
        return
    fi
    local public_servers; local ip_nodes; local local_ip
    public_servers=$(echo -e "$clean_list" | grep "PublicServer" || true)
    ip_nodes=$(echo -e "$clean_list" | grep -v "PublicServer" || true)
    local_ip=$(get_local_virtual_ip)
    echo -e "${CYAN}当前内网节点列表:${NC}"
    if [ -n "$public_servers" ]; then
        echo -e "$public_servers" | awk -F'\t' -v blue="$BLUE" -v nc="$NC" '{ printf "%s官网中心%s\n", blue, nc; printf "     %s主机名: %s%s\n", blue, $2, nc; }'
    fi
    if [ -n "$ip_nodes" ]; then
        echo -e "$ip_nodes" | sort -t . -k 1,1n -k 2,2n -k 3,3n -k 4,4n | awk -F'\t' -v local_ip="$local_ip" -v yellow="$YELLOW" -v nc="$NC" '{ if ($1 == local_ip) { printf "%s%s%s\n", yellow, $1, nc; printf "     %s主机名: %s%s\n", yellow, $2, nc; } else { printf "%s\n", $1; printf "     主机名: %s\n", $2; } }'
    fi
}

view_routes() {
    echo -e "${BLUE}--- 6. 查看节点路由列表 (完整信息) ---${NC}"
    if ! command -v easytier-cli &>/dev/null; then
        echo -e "${RED}错误: 'easytier-cli' 未安装。${NC}"
        return
    fi
    if ! systemctl is-active --quiet "${SERVICE_NAME}"; then
        echo -e "${RED}错误: EasyTier 服务未运行。${NC}"
        return
    fi
    easytier-cli route
}

view_startup_command() {
    echo -e "${BLUE}--- 7. 查看本机启动命令 ---${NC}"
    if [ ! -f "$SERVICE_FILE" ]; then
        echo -e "${RED}错误: 服务未安装，找不到启动命令。${NC}"
        return
    fi
    local command
    command=$(grep 'ExecStart=' "$SERVICE_FILE" | sed 's/ExecStart=//')
    if [ -z "$command" ]; then
        echo -e "${RED}无法从服务文件中解析启动命令。${NC}"
    else
        echo -e "当前服务使用的启动命令为:"
        echo -e "${YELLOW}${command}${NC}"
    fi
}

generate_client_command() {
    echo -e "${BLUE}--- 8. 生成客户端连接命令 (用于新网络) ---${NC}"
    local network_name="" network_secret="" peer_node="" base_ip=""
    if source "$CONFIG_FILE" 2>/dev/null; then
        echo -e "${CYAN}INFO: 使用配置文件中的网络参数。${NC}"
        network_name="$CFG_USER"
        network_secret="$CFG_PASSWORD"
        peer_node="$CFG_NODE"
        base_ip="$CFG_IPV4"
    elif [ -f "$SERVICE_FILE" ]; then
        echo -e "${CYAN}INFO: 未找到配置文件，正在从当前服务解析网络参数...${NC}"
        local command
        command=$(grep 'ExecStart=' "$SERVICE_FILE" | sed 's/ExecStart=//')
        network_name=$(echo "$command" | awk '{for(i=1;i<=NF;i++) if($i=="--network-name") print $(i+1)}')
        network_secret=$(echo "$command" | awk '{for(i=1;i<=NF;i++) if($i=="--network-secret") print $(i+1)}')
        peer_node=$(echo "$command" | awk '{for(i=1;i<=NF;i++) if($i=="-p") print $(i+1)}')
        base_ip=$(get_local_virtual_ip)
    else
        echo -e "${RED}错误: 找不到配置文件，且服务也未安装。无法生成命令。${NC}"
        return
    fi
    if [ -z "$network_name" ] || [ -z "$network_secret" ] || [ -z "$peer_node" ] || [ -z "$base_ip" ]; then
        echo -e "${RED}错误: 未能从服务中获取全部所需的网络参数。${NC}"
        return
    fi
    local server_ip_base server_ip_last client_last_octet client_ip client_command
    server_ip_base=$(echo "$base_ip" | cut -d'.' -f1-3)
    server_ip_last=$(echo "$base_ip" | cut -d'.' -f4)
    read -r -p "请输入客户端 IP 的末尾数字 (2-254) [回车不指定]: " client_last_octet
    client_command="easytier-core -d --network-name ${network_name} --network-secret ${network_secret} -p ${peer_node}"
    if [ -n "$client_last_octet" ]; then
        if [[ "$client_last_octet" == "$server_ip_last" ]]; then
            echo -e "${RED}错误: 客户端 IP 末尾不能与服务端 (${server_ip_last}) 相同。${NC}"
            return
        fi
        client_ip="${server_ip_base}.${client_last_octet}"
        client_command="${client_command} --ipv4 ${client_ip}"
    fi
    echo -e "\n${GREEN}生成的客户端连接命令是:${NC}"
    echo -e "${YELLOW}${client_command}${NC}"
}

manage_easy_command() {
    echo -e "${BLUE}--- 9. 设置 'easy' 快捷命令 ---${NC}"
    read -r -p "是否启用 'easy' 快捷命令? (y: 启用 / n: 禁用) [Y/n]: " choice
    if [[ "$choice" =~ ^[Nn]$ ]]; then
        uninstall_easy_command
    else
        update_easy_command
    fi
}

manage_autostart() {
    echo -e "${BLUE}--- 10. 设置开机自启 ---${NC}"
    if [ ! -f "$SERVICE_FILE" ]; then
        echo -e "${YELLOW}警告: 服务文件不存在，无法进行设置。${NC}"
        return
    fi
    read -r -p "是否设置开机自启? (y: 开启 / n: 关闭) [Y/n]: " choice
    if [[ "$choice" =~ ^[Nn]$ ]]; then
        if ! systemctl is-enabled --quiet "${SERVICE_NAME}"; then
            echo -e "${YELLOW}服务已处于“未开机自启”状态。${NC}"
        else
            systemctl disable "${SERVICE_NAME}"
            echo -e "${GREEN}✔ 已成功关闭开机自启。${NC}"
        fi
    else
        if systemctl is-enabled --quiet "${SERVICE_NAME}"; then
            echo -e "${YELLOW}服务已处于“开机自启”状态。${NC}"
        else
            systemctl enable "${SERVICE_NAME}"
            echo -e "${GREEN}✔ 已成功开启开机自启。${NC}"
        fi
    fi
}

stop_service() {
    echo -e "${BLUE}--- 11. 关闭 EasyTier 服务 ---${NC}"
    if [ ! -f "$SERVICE_FILE" ]; then
        echo -e "${YELLOW}警告: 服务文件不存在，无需操作。${NC}"
        return
    fi
    echo -e "${GREEN}正在停止服务...${NC}"
    systemctl stop "${SERVICE_NAME}" 2>/dev/null
    echo -e "${GREEN}✔ EasyTier 服务已停止。${NC}"
    echo -e "${YELLOW}提示: 开机自启状态未改变，若需调整请使用选项 10。${NC}"
}

uninstall_easytier() {
    echo -e "${YELLOW}--- 99. 彻底卸载 EasyTier ---${NC}"
    echo -e "${GREEN}正在停止并删除系统服务...${NC}"
    systemctl stop "${SERVICE_NAME}" 2>/dev/null || true
    systemctl disable "${SERVICE_NAME}" 2>/dev/null || true
    rm -f "$SERVICE_FILE"
    systemctl daemon-reload
    echo -e "${GREEN}正在删除可执行文件...${NC}"
    rm -f "${INSTALL_DIR}/easytier-core" "${INSTALL_DIR}/easytier-cli"
    read -r -p "是否删除所有配置文件 (${CONFIG_DIR})? [y/N]: " confirm_delete_config
    if [[ "$confirm_delete_config" =~ ^[Yy]$ ]]; then
        echo -e "${GREEN}正在删除配置文件目录...${NC}"
        rm -rf "$CONFIG_DIR"
    fi
    if [ -f "$EASY_COMMAND_PATH" ]; then
        echo -e "${GREEN}正在删除 'easy' 快捷命令...${NC}"
        rm -f "$EASY_COMMAND_PATH"
    fi
    echo -e "\n${GREEN}✔ EasyTier 已彻底卸载。${NC}"
}

display_status_dashboard() {
    local install_status_text="${RED}未安装${NC}"
    if [ -f "${INSTALL_DIR}/easytier-core" ]; then
        install_status_text="${GREEN}已安装${NC}"
    fi
    local easy_cmd_status_text="${RED}未启用${NC}"
    if [ -f "$EASY_COMMAND_PATH" ]; then
        easy_cmd_status_text="${GREEN}已启用 (easy)${NC}"
    fi
    local status_text="${RED}未运行${NC}"
    local autostart_text="${RED}否${NC}"
    local ip_text="${YELLOW}无${NC}"
    local conn_count=0
    if systemctl is-active --quiet "${SERVICE_NAME}"; then
        status_text="${GREEN}运行中 (systemd)${NC}"
        local_virt_ip=$(get_local_virtual_ip)
        if [ -n "$local_virt_ip" ]; then
            ip_text="${CYAN}${local_virt_ip}${NC}"
        else
            ip_text="${CYAN}获取中...${NC}"
        fi
        local route_output
        route_output=$(easytier-cli route 2>/dev/null)
        if [ -n "$route_output" ]; then
            conn_count=$(echo "$route_output" | awk -F '│' '/┌|└|├|ipv4/ { next; } { hostname_raw = $3; gsub(/^[[:space:]]+|[[:space:]]+$/, "", hostname_raw); if (hostname_raw != "") { print; } }' | wc -l)
        fi
    fi
    if systemctl is-enabled --quiet "${SERVICE_NAME}"; then
        autostart_text="${GREEN}是${NC}"
    fi
    echo -e "\n${BLUE}==== 当前 EasyTier 状态概览 ====${NC}"
    printf "  %-22s: %b\n" "核心程序" "${install_status_text}"
    printf "  %-22s: %b\n" "快捷指令" "${easy_cmd_status_text}"
    printf "  %-22s: %b\n" "运行状态" "${status_text}"
    printf "  %-22s: %b\n" "开机启动" "${autostart_text}"
    printf "  %-22s: %b\n" "虚拟地址" "${ip_text}"
    printf "  %-22s: %b\n" "内网节点" "${CYAN}${conn_count}${NC}"
    echo -e "${BLUE}===================================${NC}"
}

show_menu() {
    display_status_dashboard
    echo -e "${BLUE}======== EasyTier 管理面板 V7.1 ==========${NC}"
    echo -e " ${GREEN}1. 安装/更新 EasyTier${NC}"
    echo -e " ${GREEN}2. 系统服务：新建网络${NC}"
    echo -e " ${GREEN}3. 系统服务：加入网络${NC}"
    echo -e " ${YELLOW}4. 查看服务运行状态 (systemctl)${NC}"
    echo -e "------------------------------------"
    echo -e " ${CYAN}5. 查看内网节点${NC}"
    echo -e " ${CYAN}6. 查看节点路由列表 (完整)${NC}"
    echo -e " ${CYAN}7. 查看本机启动命令${NC}"
    echo -e " ${CYAN}8. 生成客户端连接命令${NC}"
    echo -e "------------------------------------"
    echo -e " ${YELLOW}9. 设置 'easy' 快捷命令${NC}"
    echo -e " ${YELLOW}10. 设置开机自启${NC}"
    echo -e " ${RED}11. 关闭 EasyTier 服务${NC}"
    echo -e " ${RED}99. 彻底卸载 EasyTier${NC}"
    echo -e " ${RED}0. 退出脚本${NC}"
    echo -ne "请输入选项 [0-99]: "
    read -r choice
}

# --- 主程序执行 ---
check_root

if [[ -n "${ipv4:-}" || -n "${network_name:-}" || -n "${network_secret:-}" ]]; then
    echo -e "${YELLOW}检测到 '新建网络' 参数，进入非交互模式...${NC}"
    install_easytier && create_network_service "non_interactive"
    echo -e "\n${GREEN}✔ 非交互式任务执行完毕。${NC}"
    update_easy_command "non_interactive_first_run"
    echo -e "${CYAN}提示: 'easy' 快捷命令已安装，您现在可以使用 'sudo easy' 来打开管理面板。${NC}"
    exit 0
fi

if [[ -n "${join:-}" ]]; then
    echo -e "${YELLOW}检测到 'join' 参数，进入非交互模式...${NC}"
    install_easytier && join_network_service "non_interactive" "$join"
    echo -e "\n${GREEN}✔ 非交互式任务执行完毕。${NC}"
    update_easy_command "non_interactive_first_run"
    echo -e "${CYAN}提示: 'easy' 快捷命令已安装，您现在可以使用 'sudo easy' 来打开管理面板。${NC}"
    exit 0
fi

# 如果是通过URL下载后直接执行的，脚本名可能是 /proc/self/fd/63 这类
# 如果脚本名不是 easy, 则提示用户可以安装
if [[ "$(basename "$0")" != "easy" && "$0" != "$EASY_COMMAND_PATH" && ! -f "$EASY_COMMAND_PATH" ]]; then
    echo -e "${YELLOW}>>> 检测到您还未安装 'easy' 快捷命令。${NC}"
    echo -e "${YELLOW}>>> 安装后，您可以在任何路径下使用 'sudo easy' 打开此面板。${NC}"
    read -r -p "是否立即安装? [Y/n]: " install_easy_now
    if [[ ! "$install_easy_now" =~ ^[Nn]$ ]]; then
        update_easy_command
    fi
fi

while true; do
    clear
    show_menu
    case "$choice" in
        1) install_easytier ;;
        2) create_network_service "interactive" ;;
        3) join_network_service "interactive" "" ;;
        4) view_service_status ;;
        5) view_pool_ips ;;
        6) view_routes ;;
        7) view_startup_command ;;
        8) generate_client_command ;;
        9) manage_easy_command ;;
        10) manage_autostart ;;
        11) stop_service ;;
        99) uninstall_easytier; exit 0 ;;
        0) echo -e "${GREEN}退出脚本。${NC}"; exit 0 ;;
        *) echo -e "${RED}无效选项，请重新输入。${NC}" ;;
    esac
    echo -ne "\n按回车键返回主菜单..."
    read -r
done
