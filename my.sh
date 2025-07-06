#!/usr/bin/env bash

cmd_name="my"  # 你想要的命令名

if [[ $EUID -ne 0 ]]; then
    echo "需要 root 权限注册命令，请输入密码..."
    sudo cp -f "$0" /usr/local/bin/$cmd_name
    sudo chmod +x /usr/local/bin/$cmd_name
    echo "已自动注册命令 $cmd_name"
    exit 0
fi

if [[ "$(basename "$0")" != "$cmd_name" ]] || [[ "$0" != "/usr/local/bin/$cmd_name" ]]; then
    cp -f "$0" /usr/local/bin/$cmd_name
    chmod +x /usr/local/bin/$cmd_name
    echo "已自动注册命令 $cmd_name，可在任意位置直接输入 $cmd_name 使用"
    exit 0
fi

# 获取命令行参数作为 compose 文件名，否则用默认
if [[ -n "$1" ]]; then
    compose_file="$1"
else
    compose_file="docker-compose.yml"
fi

# 支持参数指定 compose 文件
if [[ -n "$1" ]]; then
    compose_file="$1"
     echo "使用指定配置文件:$compose_file"
else
    compose_file="docker-compose.yml"
    echo "使用默认配置文件:$compose_file"
fi

if [ ! -f "$compose_file" ]; then
    echo "未找到 $compose_file 文件，请确认后重试。"
    exit 1
fi

services=$(docker compose -f "$compose_file" config --services)
services_array=($services)

while true; do
    echo "可用的服务列表:"
    i=1
    for service in "${services_array[@]}"; do
        echo "$i. $service"
        ((i++))
    done
    echo "0. 退出"
    echo

    read -p "请输入服务编号 (0退出): " service_index

    if [[ "$service_index" == "0" ]]; then
        echo "退出程序。"
        exit 0
    fi

    if [[ "$service_index" =~ ^[0-9]+$ ]] && [ "$service_index" -ge 1 ] && [ "$service_index" -le "${#services_array[@]}" ]; then
        service_name=${services_array[$service_index-1]}
    else
        echo "无效的服务编号: $service_index"
        continue
    fi

    while true; do
        echo "请选择操作类型:"
        echo "1. 删除并重启"
        echo "2. 查看日志"
        echo "3. 重启"
        echo "4. 删除"
        echo "5. 导出为tar包 (docker save)"
        echo "0. 返回上一级菜单"
        read -p "请输入操作编号 (0返回): " action

        if [[ "$action" == "0" ]]; then
            echo "返回服务选择菜单。"
            break
        fi

        case $action in
            1)
                echo "正在删除并重启 $service_name ..."
                docker compose -f "$compose_file" kill "$service_name"
                docker compose -f "$compose_file" rm -f "$service_name"
                docker compose -f "$compose_file" up -d "$service_name"
                ;;
            2)
                echo "正在查看 $service_name 日志..."
                docker compose -f "$compose_file" logs -f "$service_name"
                ;;
            3)
                echo "正在重启 $service_name ..."
                docker compose -f "$compose_file" restart "$service_name"
                ;;
            4)
                echo "正在删除 $service_name ..."
                docker compose -f "$compose_file" kill "$service_name"
                docker compose -f "$compose_file" rm -f "$service_name"
                ;;
            5)
                image_name=$(docker compose -f "$compose_file" config | awk -v svc="$service_name:" '
                    $1 == "services:" {in_services=1}
                    in_services && $1 == svc {getline; if ($1=="image:") print $2; exit}
                ')
                if [ -z "$image_name" ]; then
                    echo "未能获取服务 $service_name 的镜像名，无法导出。"
                    continue
                fi
                tar_file="${service_name}_$(date +%Y%m%d%H%M%S).tar"
                echo "正在导出镜像 $image_name 到文件 $tar_file ..."
                docker save -o "$tar_file" "$image_name"
                echo "导出完成。"
                ;;
            *)
                echo "无效的操作编号: $action"
                ;;
        esac
    done
done
