# EasyTier 全能自动化部署与管理脚本

![Shell](https://img.shields.io/badge/shell-bash-blue)
![License](https://img.shields.io/badge/license-MIT-green)
![Version](https://img.shields.io/badge/version-v6.2-brightgreen)

## 项目简介

这是一个功能强大且极度用户友好的 Bash 脚本，旨在彻底简化在 Linux 服务器上部署和管理 [EasyTier](https://github.com/EasyTier/EasyTier) 虚拟局域网的全过程。

无论您是想快速搭建一个私有网络的主节点，还是需要将成百上千的客户端设备自动化地加入网络，这个脚本都能提供一键式的解决方案。它将复杂的下载、配置、服务管理等操作，全部封装成了一个统一的、同时支持**交互式面板**和**非交互式部署**的强大工具。

## 核心功能

* **🚀 一键流式执行**: 无需手动下载文件，通过 `bash <(curl ...)` 命令直接从网络执行，干净、方便、快捷。
* **🕹️ 便捷的交互式面板**: 为手动操作提供了清晰的菜单，涵盖了从安装到卸载的全生命周期管理。
* **⚡ 强大的服务集成**: 与 `systemd` 深度集成，将 EasyTier 作为系统服务来管理，确保了运行的稳定性和开机自启的能力。
* **🤖 双重非交互部署模式**:
    * **新建网络模式**: 通过环境变量传入网络参数，实现全自动部署一个新的网络主节点。
    * **加入网络模式**: 通过环境变量传入 `join` 命令，实现全自动部署一个网络客户端。
* **🧠 智能参数处理**:
    * 在非交互模式下，您可以只提供部分核心参数，脚本会对未提供的参数使用合理的默认值或随机值，极大增强了灵活性。
    * 通过 `auto_start` 参数，您可以精确控制服务在非交互模式下是否需要开机自启。
* **✨ 智能快捷命令**: 脚本会自动将自身安装为 `easy` 命令。每次直接运行脚本时，都会自动更新 `easy` 命令，确保其始终是最新版本。

## 依赖与环境

* **操作系统**: 支持 `systemd` 的主流 Linux 发行版 (例如 Debian, Ubuntu, CentOS 等)。
* **用户权限**: 需要 `root` 权限来运行 (或使用 `sudo`)。
* **依赖工具**: `curl`, `unzip`, `find`, `awk` (脚本会自动检查)。

## 使用方法 (推荐)

### 用法一：面板管理模式 (手动操作)

如果您希望通过菜单进行交互式管理，请运行以下命令。它会直接从网络执行脚本并进入管理面板。

```bash
sudo bash <(curl -sSL https://raw.githubusercontent.com/wuyou18075/vps-tool/main/install_easytier.sh)
```

首次运行后，脚本会自动安装为 `easy` 命令。之后，您可以通过以下更简单的方式随时启动面板：

```bash
sudo easy
```

### 用法二：非交互式部署模式 (自动化)

通过在命令前附加环境变量，可以实现全自动部署。

#### 场景A: 新建网络

**命令格式:**
`sudo [参数1=值1] [参数2=值2] ... bash <(curl -sSL ...)`

**参数说明及默认值:**

| 参数 (Parameter)   | 说明                                   | 默认值 (Default Value)                  | 示例 (Example)         |
| ------------------ | -------------------------------------- | --------------------------------------- | ---------------------- |
| `ipv4`             | 新网络的虚拟 IP 地址                   | (无，若不提供则**随机生成**)            | `100.10.10.1`          |
| `network_name`     | 新网络的名称                           | (无，若不提供则**随机生成UUID**)        | `my-net`               |
| `network_secret`   | 新网络的密钥                           | (无，若不提供则**随机生成UUID**)        | `my-secret-key`        |
| `node`             | 注册中心节点地址 (可选)                | `tcp://public.easytier.cn:11010`        | `tcp://x.x.x.x:11010`  |
| `auto_start`       | 是否设置开机自启, `n`为否 (可选)       | `y` (是)                                | `n`                    |

**注意**: 只要提供了 `ipv4`, `network_name`, `network_secret` 中的**任意一个**，脚本就会进入此模式。

**示例:**
```bash
# 创建一个所有参数都指定的网络，且不开机自启
sudo ipv4=192.168.99.1 network_name=my-office network_secret=Secret123 auto_start=n bash <(curl -sSL https://raw.githubusercontent.com/wuyou18075/vps-tool/main/install_easytier.sh)
```

#### 场景B: 加入网络

**命令格式:**
`sudo join="<完整的客户端命令>" [auto_start=n] bash <(curl -sSL ...)`

**参数说明及默认值:**

| 参数 (Parameter)   | 说明                                   | 默认值 (Default Value) | 示例 (Example)                                                                                        |
| ------------------ | -------------------------------------- | ---------------------- | ------------------------------------------------------------------------------------------------------- |
| `join`             | **必需**，完整的客户端连接命令字符串     | (无)                   | `"easytier-core -d --ipv4 ..."`                                                                       |
| `auto_start`       | 是否设置开机自启, `n`为否 (可选)       | `y` (是)               | `n`                                                                                                   |

**示例:**
```bash
# 将本机自动加入一个网络，并设置为开机自启
sudo join="easytier-core -d --ipv4 100.10.10.2 --network-name my-net --network-secret my-secret-key -p tcp://1.2.3.4:11010" bash <(curl -sSL [https://raw.githubusercontent.com/wuyou18075/vps-tool/main/install_easytier.sh](https://raw.githubusercontent.com/wuyou18075/vps-tool/main/install_easytier.sh))
```

## 授权 (License)

[MIT License](https://opensource.org/licenses/MIT)
