# -
一键脚本
### 一键安装 Easytier

请复制以下完整命令并执行：

```bash
bash <(curl -sSL https://raw.githubusercontent.com/wuyou18075/vps-tool/main/install_easytier.sh)


### 一键安装 Easytier 快捷指令面板

请复制以下完整命令并执行：

```bash
bash <(curl -sSL https://raw.githubusercontent.com/wuyou18075/vps-tool/main/easytier_panel.sh)

idx一键开启 ssh连接
bash <(wget -qO- https://raw.githubusercontent.com/fscarmen/tools/main/idx_ssh.sh)

# 一键 FRP 开启 SSH 远程连接管理脚本

![Shell](https://img.shields.io/badge/shell-bash-blue)
![License](https://img.shields.io/badge/license-MIT-green)

这是一个强大而灵活的 Bash 脚本，旨在彻底简化通过 **FRP (Fast Reverse Proxy)** 暴露内网 Linux 设备 SSH 端口的过程。无论您是想远程访问没有公网IP的家庭服务器、办公室电脑，还是云服务商提供的、仅有内网的计算实例，这个脚本都能为您提供一键式的解决方案。

## 核心功能

* **🚀 双模式执行**:
    * **面板管理模式**: 直接运行脚本即可进入一个交互式的管理菜单，轻松进行开启、重置或卸载操作。
    * **非交互式模式**: 支持通过环境变量传入所有参数，实现完全自动化的部署，非常适合集成到其他自动化脚本中。

* **⚙️ 全自动配置**:
    * **SSH服务**: 自动修改 `sshd_config` 文件，以允许 `root` 用户通过密码登录，并为您设置一个高强度的密码。
    * **FRP客户端**: 自动从 GitHub API 获取最新版本的 `frpc`，并根据您的服务器架构 (amd64 / arm64) 下载对应的二进制文件。

* **⚡️ 智能后台运行**:
    * 使用 `nohup` 将 `frpc` 客户端置于后台稳定运行，即使您关闭了终端窗口，连接也不会中断。
    * 在启动前会自动清理旧的 `frpc` 进程，避免冲突。

* **🗑️ 一键彻底卸载**:
    * 提供清晰的卸载选项，可以一键停止 `frpc` 进程，并彻底删除其二进制文件和所有配置文件，让您的系统保持干净。

## 先决条件

在运行此脚本前，请确保您已经拥有：

1.  一台 **Linux 服务器** (已在 Debian/Ubuntu/CentOS 上测试通过)。
2.  拥有 `root` 权限 (或 `sudo` 权限)。
3.  安装了基础工具: `wget`, `curl`, `tar`。
4.  **一个已经搭建好并正常运行的 FRP 服务端 (frps)**，并且您知道它的 **IP/域名**、**端口** 和 **认证 Token**。

## 使用方法

### 步骤 1: 下载脚本

首先，将脚本下载到您的 Linux 设备上，并赋予其执行权限。

```bash
wget <您的脚本URL> -O frp-ssh.sh
chmod +x frp-ssh.sh
```
*(请将 `<您的脚本URL>` 替换为实际的下载链接)*

### 步骤 2: 选择执行模式

#### 模式一：面板管理模式 (推荐首次使用)

如果您是第一次使用，或者希望手动管理，直接以 `root` 权限运行脚本即可。

```bash
sudo bash frp-ssh.sh
```

脚本会自动进入一个交互式菜单，您可以根据提示选择操作：

```
========== FRP SSH 管理面板 ==========
 1. 开启/重置 内网SSH远程连接
 2. 卸载 内网SSH远程连接
 ----------------------------------
 0. 退出面板
====================================
请输入选项 [0-2]:
```
* **选项 1**: 会引导您输入所有必要信息，然后自动完成所有配置和启动流程。
* **选项 2**: 会彻底清除脚本创建的所有 FRP 相关内容。

#### 模式二：非交互式直接执行 (适用于自动化部署)

如果您需要在脚本中自动调用，或者希望一次性完成所有配置，可以通过环境变量的方式传入所有参数。

**命令格式:**
```bash
sudo password=your_strong_password ip=your_frp_server_ip frp_port=7000 token=your_frp_token remote_port=6000 bash frp-ssh.sh
```

**参数说明:**

| 参数 (Parameter) | 说明                                                    | 是否必需 | 示例 (Example)     |
| ---------------- | ------------------------------------------------------- | -------- | ------------------ |
| `password`       | 您希望为本机 `root` 用户设置的 SSH 登录密码 (至少10位) | 是       | `My$tr0ngP@ssw0rd` |
| `ip`             | 您的 FRP 服务器的公网 IP 或域名                         | 是       | `1.2.3.4`          |
| `frp_port`       | 您的 FRP 服务器的连接端口 (frps 的 `bind_port`)         | 是       | `7000`             |
| `token`          | 您的 FRP 服务器的认证令牌 (frps 的 `token`)             | 是       | `my_secret_token`  |
| `remote_port`    | 您希望在 FRP 服务器上为 SSH 映射的公网端口              | 是       | `6000`             |

当所有这些必需的参数都被提供时，脚本会直接执行所有安装和配置步骤，然后自动退出，不会显示任何菜单。

## 注意事项

* 本脚本会修改 `/etc/ssh/sshd_config` 文件中的 `PermitRootLogin` 和 `PasswordAuthentication` 配置项，以确保远程连接成功。
* `frpc` 客户端进程会通过 `nohup` 在后台持续运行。您可以使用 `ps -ef | grep frpc` 查看进程，或使用 `pkill -f frpc` 命令来手动停止它。

## 授权 (License)

[MIT License](https://opensource.org/licenses/MIT)
