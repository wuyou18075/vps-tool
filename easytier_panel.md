
# EasyTier 交互式一键安装与管理脚本

![Shell](https://img.shields.io/badge/shell-bash-blue)
![License](https://img.shields.io/badge/license-MIT-green)

## 项目简介

这是一个功能强大且极度用户友好的 Bash 脚本，旨在彻底简化在 Linux 服务器上部署和管理 [EasyTier](https://github.com/EasyTier/EasyTier) 虚拟局域网的过程。

无论您是想快速搭建一个私有网络、让不同地理位置的设备能够互相访问，还是需要一个自动化的客户端部署工具，这个脚本都能满足您的需求。它将复杂的下载、配置、服务管理等操作，全部封装成了一个清晰的交互式管理面板。

## 核心功能

* **🚀 全自动安装与更新**: 自动检测服务器架构 (amd64/arm64)，并从 GitHub API 获取最新版本的 EasyTier 核心程序进行下载和安装。

* **面板化管理**: 提供一个清晰的、可重复使用的交互式管理面板，涵盖了从安装到卸载的全生命周期操作。

* **强大的服务集成**: 与 `systemd` 深度集成，将 EasyTier 作为系统服务来管理，确保了运行的稳定性和开机自启的能力。

* **两种组网模式**:
    * **新建网络**: 引导您创建并成为一个新的私有网络的“主机”。
    * **加入网络**: 允许您通过粘贴一条命令，轻松地将设备作为“客户端”加入一个已存在的网络。

* **智能命令生成**: 无论您是网络的创建者还是加入者，都可以方便地生成新的客户端连接命令，以邀请更多成员加入。

* **一键式部署**: 支持通过命令行参数传入 `join` 命令，实现完全无交互的客户端自动化部署。

* **聚合信息展示**:
    * **状态概览**: 在面板顶部实时显示核心程序、运行状态、虚拟地址、节点数等关键信息。
    * **节点列表**: 提供一个经过格式化和颜色高亮的节点列表，让您对网络成员一目了然。

* **快捷命令**: 首次运行时，脚本会自动将自身安装为 `easy` 命令，之后您只需执行 `sudo easy` 即可随时调出管理面板。

## 依赖与环境

* **操作系统**: 支持 `systemd` 的主流 Linux 发行版 (例如 Debian, Ubuntu, CentOS 等)。
* **用户权限**: 需要 `root` 权限来运行 (或使用 `sudo`)。
* **依赖工具**: `curl`, `unzip`, `find`, `awk` (脚本会自动检查)。

## 使用方法

#### 模式一：非交互式加入网络 (自动化部署, 推荐)

**新建局域网:**
```bash
bash <(curl -sSL https://raw.githubusercontent.com/wuyou18075/vps-tool/main/easytier_panel.sh)
```
**加入局域网:**
```bash
sudo join="<完整的客户端命令>" bash <(curl -sSL https://raw.githubusercontent.com/wuyou18075/vps-tool/main/easytier_panel.sh)
```
**示例:**

假设您已经有了一条客户端连接命令，您可以在新设备上这样执行：

```bash
sudo join="easytier-core -d --ipv4 100.100.100.2 --network-name xxxx-xxxx --network-secret yyyy-yyyy -p tcp://z.z.z.z:11010" bash <(curl -sSL https://raw.githubusercontent.com/wuyou18075/vps-tool/main/easytier_panel.sh)
```
#### 模式二：面板管理模式

直接远程使用一键脚本,首次运行后，脚本会自动安装为 `easy` 命令。之后，您可以通过以下更简单的方式随时进入面板。

```bash
bash <(curl -sSL https://raw.githubusercontent.com/wuyou18075/vps-tool/main/easytier_panel.sh)
```

之后，您可以通过以下更简单的方式随时进入面板：

```bash
sudo easy
```

**菜单选项详解:**

* `1. 安装/更新 EasyTier`: 下载或更新 EasyTier 的核心二进制文件。
* `2. 系统服务：新建网络`: 引导您设置IP、网络名、密钥等，创建一个全新的网络，并作为服务运行。
* `3. 系统服务：加入网络`: 通过粘贴一个已有的客户端命令，将本机加入到一个网络中，并作为服务运行。
* `4. 查看服务运行状态`: 显示 `systemctl status` 的详细输出，用于调试。
* `5. 查看内网节点`: 以优化的、带颜色的格式显示当前网络中的所有节点（包括本机和官网服务器）。
* `6. 查看节点路由列表 (完整)`: 显示 `easytier-cli route` 的原始、完整输出。
* `7. 查看本机启动命令`: 显示当前 systemd 服务所使用的 `ExecStart` 命令。
* `8. 生成客户端连接命令`: 为其他设备生成加入当前网络的命令。无论您是创建者还是加入者，此功能都可用。
* `9. 关闭开机自启`: 取消服务的开机自启，但不会停止当前正在运行的服务。
* `10. 关闭 EasyTier 服务`: 停止当前正在运行的服务。
* `99. 彻底卸载 EasyTier`: 停止服务，并清除所有相关文件（程序、配置、服务定义）。
* `100. 卸载 'easy' 快捷命令`: 仅删除 `easy` 这个快捷方式，不影响已安装的程序。



## 授权 (License)

[MIT License](https://opensource.org/licenses/MIT)
