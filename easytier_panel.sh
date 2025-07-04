#!/bin/bash

#================================================================
# EasyTier 交互式一键安装与管理脚本 V4.3 (最终优化版)
#
# 作者: Gemini @ Google
# 版本: 4.3 (2025-07-05)
# 更新日志 (V4.3):
#   - [最终格式优化] “连接池”列表彻底重构为双行格式，完美解决对齐问题。
#   - [最终文本优化] 状态概览中的“内网 IP”改为“虚拟地址”，“连接池”改为“内网节点”。
#================================================================

# --- 全局定义 ---
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
    if ! command -v curl &> /dev/null || ! command -v unzip &> /dev/null || ! command -v find &> /dev/null || ! command -v awk &> /dev/null; then
        echo -e "${RED}错误: 依赖 'curl, unzip, find, awk' 未找到。${NC}"
        exit 1
    fi
}
generate_uuid() {
    if command -v uuidgen &> /dev/null; then
        uuidgen
    else
        cat /proc/sys/kernel/random/uuid
    fi
}
load_config() {
    if [ -f "$CONFIG_FILE" ]; then
        source "$CONFIG_FILE"
        return 0
    else
        return 1
    fi
}
save_config() {
    mkdir -p "$CONFIG_DIR"
    echo "# EasyTier 自定义配置" > "$CONFIG_FILE"
    echo "CFG_IPV4='${CFG_IPV4}'" >> "$CONFIG_FILE"
    echo "CFG_USER='${CFG_USER}'" >> "$CONFIG_FILE"
    echo "CFG_PASSWORD='${CFG_PASSWORD}'" >> "$CONFIG_FILE"
    echo "CFG_NODE='${CFG_NODE}'" >> "$CONFIG_FILE"
}

parse_external_args() {
    for arg in "$@"; do
        case $arg in
            join=*)
            CFG_JOIN_COMMAND="${arg#*=}"
            ;;
        esac
    done
}

# --- 核心功能函数 ---

# 1. 安装/更新 EasyTier
install_easytier() {
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
    if [[ "$ARCH" != "x86_64" ]] && [[ "$ARCH" != "aarch64" ]]; then
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
    chmod +x "${INSTALL_DIR}/easytier-core"
    chmod +x "${INSTALL_DIR}/easytier-cli"
    rm -f "/tmp/${PACKAGE_NAME}"
    rm -rf "${TEMP_UNZIP_DIR}"
    echo -e "\n${GREEN}✔ EasyTier 核心程序安装成功!${NC}"
}

# 2. 系统服务：新建网络
create_network_service() {
    echo -e "${BLUE}--- 2. 系统服务：新建网络 ---${NC}"
    if ! command -v easytier-core &> /dev/null; then
        echo -e "${RED}错误: 'easytier-core' 未安装。请先执行选项 1。${NC}"
        return
    fi
    read -p "请输入局域网 IP (例如 10.10.10.1) [回车随机生成]: " input_ipv4
    if [ -z "$input_ipv4" ]; then
        CFG_IPV4="100.$(shuf -i 0-255 -n 1).$(shuf -i 0-255 -n 1).1"
        echo -e "${GREEN}未指定IP，已为您随机生成: ${YELLOW}${CFG_IPV4}${NC}"
    else
        CFG_IPV4=$input_ipv4
    fi
    local default_user; default_user=$(generate_uuid)
    local default_password; default_password=$(generate_uuid)
    read -p "请输入网络名称 [回车随机生成]: " input_user; CFG_USER=${input_user:-$default_user}
    read -p "请输入网络密钥 [回车随机生成]: " input_password; CFG_PASSWORD=${input_password:-$default_password}
    read -p "请输入注册中心节点 [默认: tcp://public.easytier.cn:11010]: " input_node; CFG_NODE=${input_node:-"tcp://public.easytier.cn:11010"}
    save_config
    local full_command="${INSTALL_DIR}/easytier-core --ipv4 ${CFG_IPV4} --network-name ${CFG_USER} --network-secret ${CFG_PASSWORD} -p ${CFG_NODE}"
    echo -e "${GREEN}正在创建服务文件...${NC}"
    cat > "$SERVICE_FILE" << EOF
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
        read -p "是否设置为开机自启? [Y/n]: " confirm_autostart
        if [[ "$confirm_autostart" =~ ^[Nn]$ ]]; then
            systemctl disable "${SERVICE_NAME}"
            echo -e "${YELLOW}已取消开机自启。${NC}"
        else
            systemctl enable "${SERVICE_NAME}"
            echo -e "${GREEN}已设置为开机自启。${NC}"
        fi
    else
        echo -e "${RED}❌ 服务启动失败! 请执行选项 4 查看详细错误。${NC}"
    fi
}

# 3. 系统服务：加入网络
join_network_service() {
    echo -e "${BLUE}--- 3. 系统服务：加入网络 ---${NC}"
    if ! command -v easytier-core &> /dev/null; then
        echo -e "${RED}错误: 'easytier-core' 未安装。请先执行选项 1。${NC}"
        return 1
    fi
    
    local join_command=""
    if [ -n "$CFG_JOIN_COMMAND" ]; then
        echo -e "${GREEN}检测到外部传入的 join 命令。${NC}"
        join_command="$CFG_JOIN_COMMAND"
    else
        echo -e "${YELLOW}请粘贴完整的客户端连接命令 (例如: easytier-core -d --ipv4 ...):${NC}"
        read -p "> " join_command
    fi

    if [[ ! "$join_command" == *"easytier-core"* ]]; then
        echo -e "${RED}错误: 输入的不是一个有效的 easytier-core 命令。${NC}"
        return 1
    fi

    local full_command
    full_command=$(echo "$join_command" | sed "s|easytier-core|${INSTALL_DIR}/easytier-core|")
    
    echo -e "${GREEN}正在根据提供的命令创建服务文件...${NC}"
    cat > "$SERVICE_FILE" << EOF
[Unit]
Description=EasyTier Join-Network Service by Script
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
        read -p "是否设置为开机自启? [Y/n]: " confirm_autostart
        if [[ "$confirm_autostart" =~ ^[Nn]$ ]]; then
            systemctl disable "${SERVICE_NAME}"
            echo -e "${YELLOW}已取消开机自启。${NC}"
        else
            systemctl enable "${SERVICE_NAME}"
            echo -e "${GREEN}已设置为开机自启。${NC}"
        fi
    else
        echo -e "${RED}❌ 服务启动失败! 请执行选项 4 查看详细错误。${NC}"
    fi
    return 0
}

# 4. 查看服务运行状态
view_service_status() {
    echo -e "${BLUE}--- 4. 查看服务运行状态 (systemctl) ---${NC}"
    if [ ! -f "$SERVICE_FILE" ]; then
        echo -e "${YELLOW}服务尚未被注册。${NC}"
        return
    fi
    systemctl --no-pager status "${SERVICE_NAME}"
}

# 5. 查看内网节点
view_pool_ips() {
    echo -e "${BLUE}--- 5. 查看内网节点 ---${NC}"
    if ! command -v easytier-cli &> /dev/null; then
        echo -e "${RED}错误: 'easytier-cli' 未安装。${NC}"
        return
    fi
    if ! systemctl is-active --quiet "${SERVICE_NAME}"; then
        echo -e "${RED}错误: EasyTier 服务未运行。${NC}"
        return
    fi
    
    local clean_list
    clean_list=$(easytier-cli route 2>/dev/null | awk -F '│' '
        /┌|└|├|ipv4/ { next; }
        {
            ip_raw = $2;
            hostname_raw = $3;
            gsub(/^[[:space:]]+|[[:space:]]+$/, "", hostname_raw);
            if (hostname_raw == "") { next; }
            ip_clean = ip_raw;
            gsub(/^[[:space:]]+|[[:space:]]+$/, "", ip_clean);
            sub(/\/.*$/, "", ip_clean);
            if (ip_clean == "") { ip_clean = "N/A"; }
            print ip_clean "\t" hostname_raw;
        }')

    if [ -z "$clean_list" ]; then
        echo -e "${YELLOW}当前连接池中没有有效节点。${NC}"
        return
    fi

    local public_servers
    local ip_nodes
    local local_ip=""
    public_servers=$(echo -e "$clean_list" | grep "PublicServer")
    ip_nodes=$(echo -e "$clean_list" | grep -v "PublicServer")
    
    if [ -f "$SERVICE_FILE" ]; then
        local_ip=$(grep -oP '(?<=--ipv4 )[^ ]+' "$SERVICE_FILE" | head -n 1)
    fi

    echo -e "${CYAN}当前内网节点列表:${NC}"
    
    # [修改] 采用全新的双行显示格式，彻底解决对齐问题
    if [ -n "$public_servers" ]; then
        echo -e "$public_servers" | awk -F'\t' -v blue="$BLUE" -v nc="$NC" '{ 
            printf "%s官网中心%s\n", blue, nc;
            printf "    %s主机名: %s%s\n", blue, $2, nc;
        }'
    fi

    if [ -n "$ip_nodes" ]; then
        echo -e "$ip_nodes" | sort -t . -k 1,1n -k 2,2n -k 3,3n -k 4,4n | awk -F'\t' -v local_ip="$local_ip" -v yellow="$YELLOW" -v nc="$NC" '{ 
            if ($1 == local_ip) {
                printf "%s%s%s\n", yellow, $1, nc;
                printf "    %s主机名: %s%s\n", yellow, $2, nc;
            } else {
                printf "%s\n", $1;
                printf "    主机名: %s\n", $2;
            }
        }'
    fi
}

# 6. 查看节点路由列表
view_routes() {
    echo -e "${BLUE}--- 6. 查看节点路由列表 (完整信息) ---${NC}"
    if ! command -v easytier-cli &> /dev/null; then
        echo -e "${RED}错误: 'easytier-cli' 未安装。${NC}"
        return
    fi
    if ! systemctl is-active --quiet "${SERVICE_NAME}"; then
        echo -e "${RED}错误: EasyTier 服务未运行。${NC}"
        return
    fi
    easytier-cli route
}

# 7. 查看本机启动命令
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

# 8. 生成客户端连接命令
generate_client_command() {
    echo -e "${BLUE}--- 8. 生成客户端连接命令 (用于新网络) ---${NC}"
    if ! load_config; then
        echo -e "${RED}错误: 找不到配置文件。请先执行选项 2 (新建网络)。${NC}"
        return
    fi
    
    local server_ip_base
    local server_ip_last
    server_ip_base=$(echo "$CFG_IPV4" | cut -d'.' -f1-3)
    server_ip_last=$(echo "$CFG_IPV4" | cut -d'.' -f4)
    
    read -p "请输入客户端 IP 的末尾数字 (2-254) [回车不指定]: " client_last_octet

    local client_command
    client_command="easytier-core -d --network-name ${CFG_USER} --network-secret ${CFG_PASSWORD} -p ${CFG_NODE}"

    if [ -n "$client_last_octet" ]; then
        if [[ "$client_last_octet" == "$server_ip_last" ]]; then
            echo -e "${RED}错误: 客户端 IP 末尾不能与服务端 (${server_ip_last}) 相同。${NC}"
            return
        fi
        local client_ip="${server_ip_base}.${client_last_octet}"
        client_command="${client_command} --ipv4 ${client_ip}"
    fi

    echo -e "\n${GREEN}生成的客户端连接命令是:${NC}"
    echo -e "${YELLOW}${client_command}${NC}"
}

# 9. 关闭开机自启
disable_autostart() {
    echo -e "${BLUE}--- 9. 关闭开机自启 ---${NC}"
    if [ ! -f "$SERVICE_FILE" ]; then
        echo -e "${YELLOW}警告: 服务文件不存在，无需操作。${NC}"
        return
    fi
    if ! systemctl is-enabled --quiet "${SERVICE_NAME}"; then
        echo -e "${YELLOW}服务已处于“未开机自启”状态。${NC}"
    else
        systemctl disable "${SERVICE_NAME}"
        echo -e "${GREEN}✔ 已成功关闭开机自启。${NC}"
    fi
}

# 10. 关闭 EasyTier 服务
stop_service() {
    echo -e "${BLUE}--- 10. 关闭 EasyTier 服务 ---${NC}"
    if [ ! -f "$SERVICE_FILE" ]; then
        echo -e "${YELLOW}警告: 服务文件不存在，无需操作。${NC}"
        return
    fi
    echo -e "${GREEN}正在停止服务...${NC}"
    systemctl stop "${SERVICE_NAME}" 2>/dev/null
    echo -e "${GREEN}✔ EasyTier 服务已停止。${NC}"
    echo -e "${YELLOW}提示: 开机自启状态未改变，若需关闭请使用选项 9。${NC}"
}

# 99. 彻底卸载 EasyTier
uninstall_easytier() {
    echo -e "${YELLOW}--- 99. 彻底卸载 EasyTier ---${NC}"
    echo -e "${GREEN}正在停止并删除系统服务...${NC}"
    systemctl stop "${SERVICE_NAME}" 2>/dev/null
    systemctl disable "${SERVICE_NAME}" 2>/dev/null
    rm -f "$SERVICE_FILE"
    systemctl daemon-reload
    echo -e "${GREEN}正在删除可执行文件...${NC}"
    rm -f "${INSTALL_DIR}/easytier-core"
    rm -f "${INSTALL_DIR}/easytier-cli"
    read -p "是否删除所有配置文件 (${CONFIG_DIR})? [y/N]: " confirm_delete_config
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

# 100. 卸载 'easy' 快捷命令
uninstall_easy_command() {
    echo -e "${BLUE}--- 100. 卸载 'easy' 快捷命令 ---${NC}"
    if [ -f "$EASY_COMMAND_PATH" ]; then
        rm -f "$EASY_COMMAND_PATH"
        echo -e "${GREEN}✔ 快捷命令 'easy' 已成功卸载。${NC}"
        echo -e "${YELLOW}您需要重新打开终端，或执行 'hash -r' 来让卸载生效。${NC}"
    else
        echo -e "${YELLOW}快捷命令 'easy' 未安装，无需操作。${NC}"
    fi
}

# 状态概览面板
display_status_dashboard() {
    local install_status_text="${RED}未安装${NC}"
    if [ -f "${INSTALL_DIR}/easytier-core" ]; then
        install_status_text="${GREEN}已安装${NC}"
    fi
    local easy_cmd_status_text="${RED}未安装${NC}"
    if [ -f "$EASY_COMMAND_PATH" ]; then
        easy_cmd_status_text="${GREEN}easy${NC}"
    fi
    local status_text="${RED}未运行${NC}"
    local autostart_text="${RED}否${NC}"
    local ip_text="${YELLOW}无${NC}"
    local conn_count=0

    if systemctl is-active --quiet "${SERVICE_NAME}"; then
        status_text="${GREEN}运行中 (systemd)${NC}"
        if [ -f "$SERVICE_FILE" ]; then
            ip_text_from_service=$(grep -oP '(?<=--ipv4 )[^ ]+' "$SERVICE_FILE" | head -n 1)
            ip_text="${CYAN}${ip_text_from_service:-未知}${NC}"
        elif load_config; then 
            ip_text="${CYAN}${CFG_IPV4}${NC}"
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

# 显示主菜单
show_menu() {
    display_status_dashboard
    echo -e "${BLUE}========== EasyTier 管理面板 V4.3 ==========${NC}"
    echo -e " ${GREEN}1. 安装/更新 EasyTier${NC}"
    echo -e " ${GREEN}2. 系统服务：新建网络${NC}"
    echo -e " ${GREEN}3. 系统服务：加入网络${NC}"
    echo -e " ${YELLOW}4. 查看服务运行状态 (systemctl)${NC}"
    echo -e "------------------------------------"
    echo -e " ${CYAN}5. 查看内网节点${NC}"
    echo -e " ${CYAN}6. 查看节点路由列表 (完整)${NC}"
    echo -e " ${CYAN}7. 查看本机启动命令${NC}"
    echo -e " ${CYAN}8. 生成客户端连接命令 (用于新网络)${NC}"
    echo -e "------------------------------------"
    echo -e " ${YELLOW}9. 关闭开机自启${NC}"
    echo -e " ${RED}10. 关闭 EasyTier 服务${NC}"
    echo -e " ${RED}99. 彻底卸载 EasyTier${NC}"
    echo -e " ${RED}100. 卸载 'easy' 快捷命令${NC}"
    echo -e " ${RED}0. 退出脚本${NC}"
    echo -e "${BLUE}===========================================${NC}"
    read -p "请输入选项 [0-100]: " choice
}

# 脚本主入口
first_run_install() {
    if [ ! -f "$EASY_COMMAND_PATH" ]; then
        echo -e "${YELLOW}检测到是首次运行，将安装 'easy' 快捷命令...${NC}"
        mkdir -p "${INSTALL_DIR}"
        cp "$0" "$EASY_COMMAND_PATH"
        chmod +x "$EASY_COMMAND_PATH"
        if [ $? -eq 0 ]; then
            echo -e "${GREEN}✔ 'easy' 命令安装成功!${NC}"
            sleep 1
        else
            echo -e "${RED}❌ 'easy' 命令安装失败!${NC}"
            exit 1
        fi
    fi
}

# 主程序执行
check_root
parse_external_args "$@"

if [ -n "$CFG_JOIN_COMMAND" ]; then
    install_easytier
    join_network_service
    exit $?
fi

first_run_install

while true; do
    clear
    show_menu
    case $choice in
        1) install_easytier ;;
        2) create_network_service ;;
        3) join_network_service ;;
        4) view_service_status ;;
        5) view_pool_ips ;;
        6) view_routes ;;
        7) view_startup_command ;;
        8) generate_client_command ;;
        9) disable_autostart ;;
        10) stop_service ;;
        99) uninstall_easytier; exit 0 ;;
        100) uninstall_easy_command ;;
        0) echo -e "${GREEN}退出脚本。${NC}"; exit 0 ;;
        *) echo -e "${RED}无效选项，请重新输入。${NC}" ;;
    esac
    read -p $'\n按回车键返回主菜单...'
done
