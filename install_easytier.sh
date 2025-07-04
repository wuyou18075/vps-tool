#!/bin/bash

# EasyTier 一键安装与管理脚本 (2025-07-02 最终修正版)
#================================================================
# 功能:
#   - 修正了所有已知的文件名、目录名、和可执行文件名的问题
#   - 完全自包含，解决了语法错误
#   - 不自动启动，不设置开机自启
#
# 使用方法:
#   bash my.sh         (执行安装)
#   bash my.sh uninstall (执行卸载)
#================================================================

# 定义颜色
GREEN='\033[0;32m'
RED='\033[0;31m'
YELLOW='\033[1;33m'
NC='\033[0m'

# --- 配置 ---
INSTALL_DIR="/usr/local/bin"
SERVICE_NAME="easytier"
SERVICE_FILE="/etc/systemd/system/${SERVICE_NAME}.service"
CONFIG_DIR="/etc/easytier"
CONFIG_FILE="${CONFIG_DIR}/config.json"

# --- 函数定义 ---

# 检查 root 权限
check_root() {
    if [ "$EUID" -ne 0 ]; then
        echo -e "${RED}错误: 此脚本需要以 root 权限运行。${NC}"
        echo -e "${YELLOW}请尝试使用 'sudo bash $0'${NC}"
        exit 1
    fi
}

# 检查依赖
check_dependencies() {
    if ! command -v curl &> /dev/null || ! command -v unzip &> /dev/null; then
        echo -e "${RED}错误: 依赖 'curl' 或 'unzip' 未找到。${NC}"
        echo -e "${YELLOW}请先安装它们。例如在 Debian/Ubuntu 上:${NC}"
        echo -e "${YELLOW}  sudo apt-get update && sudo apt-get install -y curl unzip${NC}"
        exit 1
    fi
}

# 获取最新版本号
get_latest_version() {
    echo -e "${GREEN}正在从 GitHub API 获取最新版本号...${NC}"
    LATEST_TAG_JSON=$(curl --silent "https://api.github.com/repos/EasyTier/EasyTier/releases/latest")
    LATEST_TAG=$(echo "$LATEST_TAG_JSON" | grep '"tag_name":' | sed -E 's/.*"([^"]+)".*/\1/')

    if [ -z "$LATEST_TAG" ]; then
        echo -e "${RED}错误: 无法通过 API 获取最新的版本号。${NC}"
        exit 1
    fi
    echo -e "${GREEN}获取到最新版本标签: ${YELLOW}${LATEST_TAG}${NC}"
}

# 检测系统架构
get_arch() {
    ARCH=$(uname -m)
    if [ "$ARCH" != "x86_64" ] && [ "$ARCH" != "aarch64" ]; then
        echo -e "${RED}错误: 不支持的系统架构: $ARCH${NC}"
        exit 1
    fi
    echo -e "${GREEN}检测到系统架构: ${YELLOW}${ARCH}${NC}"
}

# 下载并解压
download_and_extract() {
    PACKAGE_NAME="easytier-linux-${ARCH}-${LATEST_TAG}.zip"
    DOWNLOAD_URL="https://github.com/EasyTier/EasyTier/releases/download/${LATEST_TAG}/${PACKAGE_NAME}"
    
    echo -e "${GREEN}正在下载安装包: ${YELLOW}${DOWNLOAD_URL}${NC}"
    curl -L -f -o "/tmp/${PACKAGE_NAME}" "${DOWNLOAD_URL}"
    if [ $? -ne 0 ]; then
        echo -e "${RED}错误: 下载失败。${NC}"
        exit 1
    fi

    echo -e "${GREEN}正在解压文件...${NC}"
    unzip -o "/tmp/${PACKAGE_NAME}" -d /tmp
    if [ $? -ne 0 ]; then
        echo -e "${RED}错误: 解压失败。${NC}"
        exit 1
    fi
}

# 安装文件
install_files() {
    # 修正: 解压目录不包含版本号
    EXTRACTED_DIR_NAME="easytier-linux-${ARCH}"
    SOURCE_DIR="/tmp/${EXTRACTED_DIR_NAME}"

    if [ ! -d "${SOURCE_DIR}" ]; then
        echo -e "${RED}错误: 解压后的目录 ${SOURCE_DIR} 未找到!${NC}"
        exit 1
    fi

    echo -e "${GREEN}正在安装可执行文件...${NC}"
    # 修正: 从解压日志看，核心程序是 easytier-core 和 easytier-cli
    mv "${SOURCE_DIR}/easytier-core" "${INSTALL_DIR}/"
    mv "${SOURCE_DIR}/easytier-cli" "${INSTALL_DIR}/"
    chmod +x "${INSTALL_DIR}/easytier-core"
    chmod +x "${INSTALL_DIR}/easytier-cli"

    if [ ! -d "$CONFIG_DIR" ]; then
        mkdir -p "$CONFIG_DIR"
    fi
}

# 创建 systemd 服务文件
create_service_file() {
    echo -e "${GREEN}正在创建 systemd 服务文件...${NC}"
    if [ ! -f "$CONFIG_FILE" ]; then
        echo -e "{ \"instance_name\": \"my_easytier_node\" }" > "$CONFIG_FILE"
    fi

    # 修正: 服务启动的是 easytier-core
    cat > "$SERVICE_FILE" << EOF
[Unit]
Description=EasyTier Service
After=network.target
[Service]
Type=simple
ExecStart=${INSTALL_DIR}/easytier-core --config_path ${CONFIG_FILE}
Restart=on-failure
RestartSec=5s
LimitNOFILE=65535
[Install]
WantedBy=multi-user.target
EOF
}

# 显示安装后的手动操作指令
post_install_instructions() {
    systemctl daemon-reload
    echo -e "\n${GREEN}EasyTier 已成功安装！${NC}"
    echo -e "${YELLOW}服务已就绪，但未启动，也未设置开机自启。${NC}"
    echo -e "--------------------------------------------------"
    echo -e "  - 手动启动服务: ${GREEN}sudo systemctl start ${SERVICE_NAME}${NC}"
    echo -e "  - 查看服务状态: ${GREEN}sudo systemctl status ${SERVICE_NAME}${NC}"
    echo -e "  - 设置开机自启: ${GREEN}sudo systemctl enable ${SERVICE_NAME}${NC}"
    echo -e "--------------------------------------------------"
}

# 清理临时文件
cleanup() {
    EXTRACTED_DIR_NAME="easytier-linux-${ARCH}"
    PACKAGE_NAME="easytier-linux-${ARCH}-${LATEST_TAG}.zip"
    echo -e "${GREEN}正在清理临时文件...${NC}"
    rm -f "/tmp/${PACKAGE_NAME}"
    rm -rf "/tmp/${EXTRACTED_DIR_NAME}"
}

# 卸载函数 (完整版)
uninstall() {
    echo -e "${YELLOW}正在开始卸载 EasyTier...${NC}"
    check_root
    
    systemctl stop "${SERVICE_NAME}" 2>/dev/null
    systemctl disable "${SERVICE_NAME}" 2>/dev/null

    if [ -f "$SERVICE_FILE" ]; then
        echo -e "${GREEN}正在删除 systemd 服务文件...${NC}"
        rm -f "$SERVICE_FILE"
        systemctl daemon-reload
    fi
    
    echo -e "${GREEN}正在删除可执行文件...${NC}"
    rm -f "${INSTALL_DIR}/easytier-cli"
    rm -f "${INSTALL_DIR}/easytier-core"
    rm -f "${INSTALL_DIR}/easytier-tui" # 也尝试删除旧的，以防万一

    read -p "你想要删除配置文件目录 (${CONFIG_DIR}) 吗? [y/N]: " confirm_delete_config
    if [[ "$confirm_delete_config" =~ ^[Yy]$ ]]; then
        echo -e "${GREEN}正在删除配置文件目录...${NC}"
        rm -rf "$CONFIG_DIR"
    fi

    echo -e "\n${GREEN}EasyTier 已成功卸载。${NC}"
}


# --- 主程序 ---
main() {
    check_root
    check_dependencies
    get_latest_version
    get_arch
    download_and_extract
    install_files
    create_service_file
    post_install_instructions
    cleanup
}

# 根据输入参数决定执行安装还是卸载
if [ "$1" == "uninstall" ]; then
    uninstall
else
    main
fi
