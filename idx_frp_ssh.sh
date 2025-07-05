#!/usr/bin/env bash

#================================================================
# 一键 FRP 开启局域网 SSH 连接管理面板 V3.0
#
# 作者: Gemini @ Google
#================================================================

# --- 全局定义 ---
RED="\033[31m"
GREEN="\033[32m"
YELLOW="\033[33m"
RESET="\033[0m"

# --- 辅助函数 ---

# 检测是否具有 root 权限
check_root() {
    if [[ $EUID -ne 0 ]]; then
        echo -e "${RED}错误: 请以 root 权限执行此脚本 (例如: sudo bash $0)${RESET}"
        exit 1
    fi
}

# SSH 配置函数
configure_ssh() {
    echo -e "${YELLOW}[+] 正在配置 SSH 服务...${RESET}"
    
    if grep -q "^#\?PermitRootLogin" /etc/ssh/sshd_config; then
        sed -i 's/^#\?PermitRootLogin.*/PermitRootLogin yes/g' /etc/ssh/sshd_config
    else
        echo "PermitRootLogin yes" >> /etc/ssh/sshd_config
    fi

    if grep -q "^#\?PasswordAuthentication" /etc/ssh/sshd_config; then
        sed -i 's/^#\?PasswordAuthentication.*/PasswordAuthentication yes/g' /etc/ssh/sshd_config
    else
        echo "PasswordAuthentication yes" >> /etc/ssh/sshd_config
    fi

    echo -e "${YELLOW}[+] 正在设置 root 密码并重启 SSH 服务...${RESET}"
    echo "root:$PASSWORD" | chpasswd
    
    systemctl restart sshd || systemctl restart ssh
}

# --- 核心功能 ---

# 1. 开启/重置 FRP 连接
setup_frp() {
    echo -e "${GREEN}--- 1. 开启/重置内网SSH远程连接 ---${RESET}"
    
    # 获取必要信息 (环境变量优先，否则交互)
    echo -e "${YELLOW}[+] 获取连接信息...${RESET}"

    if [[ -z "$password" ]]; then
        while true; do
            read -s -p "请输入新的 root 密码 (至少10位): " PASSWORD
            echo
            if [[ ${#PASSWORD} -ge 10 ]]; then break; else echo -e "${RED}错误: 密码长度不足10位，请重新输入${RESET}"; fi
        done
    else
        PASSWORD="$password"; echo -e "${GREEN}✔ 已从环境变量中读取 SSH 密码。${RESET}"
    fi
    if [[ ${#PASSWORD} -lt 10 ]]; then echo -e "${RED}错误: 密码长度不足10位，脚本终止。${RESET}"; exit 1; fi

    if [[ -z "$ip" ]]; then read -p "请输入 FRP 服务器地址 (域名或IP): " FRP_SERVER; else FRP_SERVER="$ip"; echo -e "${GREEN}✔ 已从环境变量中读取 FRP 服务器地址: ${FRP_SERVER}${RESET}"; fi
    if [[ -z "$frp_port" ]]; then read -p "请输入 FRP 服务器端口 (例如 7000): " FRP_PORT; else FRP_PORT="$frp_port"; echo -e "${GREEN}✔ 已从环境变量中读取 FRP 服务器端口: ${FRP_PORT}${RESET}"; fi
    if [[ -z "$token" ]]; then read -p "请输入 FRP Token: " FRP_TOKEN; else FRP_TOKEN="$token"; echo -e "${GREEN}✔ 已从环境变量中读取 FRP Token。${RESET}"; fi
    if [[ -z "$remote_port" ]]; then read -p "请输入希望映射到的远程端口 (例如 6000): " FRP_REMOTE_PORT; else FRP_REMOTE_PORT="$remote_port"; echo -e "${GREEN}✔ 已从环境变量中读取远程映射端口: ${FRP_REMOTE_PORT}${RESET}"; fi

    configure_ssh

    echo -e "${YELLOW}[+] 正在下载和配置 Frp 客户端...${RESET}"
    ARCH=$(uname -m); FRP_ARCH="";
    if [[ "$ARCH" == "x86_64" ]]; then FRP_ARCH="amd64"; elif [[ "$ARCH" == "aarch64" ]]; then FRP_ARCH="arm64"; else echo -e "${RED}错误: 不支持的系统架构: $ARCH${RESET}"; exit 1; fi
    echo -e "${GREEN}检测到系统架构: ${FRP_ARCH}${RESET}"

    FRP_URL=$(wget -qO- https://api.github.com/repos/fatedier/frp/releases/latest | grep "browser_download_url.*linux_${FRP_ARCH}" | cut -d '"' -f 4)
    if [ -z "$FRP_URL" ]; then echo -e "${RED}错误: 无法自动获取 Frp 下载链接，请检查网络。${RESET}"; exit 1; fi

    wget -qO- "$FRP_URL" | tar xz
    mv frp_*/frpc /usr/local/bin/
    rm -rf frp_*

    mkdir -p /etc/frp
    cat > /etc/frp/frpc.toml << EOF
serverAddr = "${FRP_SERVER}"
serverPort = ${FRP_PORT}
auth.method = "token"
auth.token = "${FRP_TOKEN}"

[[proxies]]
name = "ssh-$(hostname)"
type = "tcp"
localIP = "127.0.0.1"
localPort = 22
remotePort = ${FRP_REMOTE_PORT}
EOF

    echo -e "${GREEN}[+] 准备启动 FRP 客户端...${RESET}"
    pkill -f "frpc -c /etc/frp/frpc.toml" 2>/dev/null || true
    sleep 1
    nohup /usr/local/bin/frpc -c /etc/frp/frpc.toml >/dev/null 2>&1 &
    sleep 2
    if ! pgrep -f "frpc -c /etc/frp/frpc.toml" > /dev/null; then
        echo -e "${RED}错误: frpc 客户端启动失败! 请检查配置后重试。${RESET}"
        return 1
    fi

    echo -e "${GREEN}===== 设置完成 =====${RESET}"
    echo -e "${GREEN}SSH 地址: ${RESET}${FRP_SERVER}"
    echo -e "${GREEN}SSH 端口: ${RESET}${FRP_REMOTE_PORT}"
    echo -e "${GREEN}SSH 用户: ${RESET}root"
    echo -e "${GREEN}SSH 密码: ${RESET}${PASSWORD}"
    echo -e "\n${YELLOW}命令: ssh root@${FRP_SERVER} -p ${FRP_REMOTE_PORT}${RESET}"
}

# 2. 卸载 FRP 连接
uninstall_frp() {
    echo -e "${YELLOW}--- 2. 卸载内网SSH远程连接 ---${RESET}"
    
    echo -e "${YELLOW}[+] 正在停止所有 frpc 进程...${RESET}"
    pkill -f "frpc" 2>/dev/null || true
    
    echo -e "${YELLOW}[+] 正在删除 frpc 可执行文件...${RESET}"
    rm -f /usr/local/bin/frpc
    
    echo -e "${YELLOW}[+] 正在删除 frpc 配置文件...${RESET}"
    rm -rf /etc/frp
    
    echo -e "\n${GREEN}✔ 卸载完成。${RESET}"
}

# 显示主菜单
show_menu() {
    clear
    echo -e "${GREEN}========== FRP SSH 管理面板 ==========${RESET}"
    echo -e " ${YELLOW}1. 开启/重置 内网SSH远程连接${RESET}"
    echo -e " ${YELLOW}2. 卸载 内网SSH远程连接${RESET}"
    echo -e " ----------------------------------"
    echo -e " ${YELLOW}0. 退出面板${RESET}"
    echo -e "${GREEN}====================================${RESET}"
    read -p "请输入选项 [0-2]: " choice
}


# --- 脚本主入口 ---

check_root

# 检查是否为直接执行模式
if [[ -n "$ip" && -n "$frp_port" && -n "$token" && -n "$remote_port" && -n "$password" ]]; then
    echo -e "${YELLOW}检测到所有必需参数，进入直接执行模式...${RESET}"
    setup_frp
    exit 0
fi

# 进入面板管理模式
while true; do
    show_menu
    case $choice in
        1)
            setup_frp
            ;;
        2)
            uninstall_frp
            ;;
        0)
            echo -e "${GREEN}已退出面板。${RESET}"
            exit 0
            ;;
        *)
            echo -e "${RED}无效选项，请重新输入。${RESET}"
            ;;
    esac
    read -p $'\n按回车键返回主菜单...'
done