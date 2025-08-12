#!/usr/bin/env bash

# ==========================================
# 环境配置自动化脚本
# ==========================================

set -euo pipefail  # 严格错误处理：命令失败/未定义变量/管道错误时立即退出

# ----------------------------
# 配置
# ----------------------------
LOG_FILE="./install_$(date +%Y%m%d_%H%M%S).log"  # 日志文件路径
NEED_ROOT=true                                   # 全局是否需要root权限
MODULES=("aptpackages" "config")                 # 启用的模块列表

TARGET_DIR="/opt"                                # 软件安装地址
TARGET_USER="f145h"                              # 用户名 必须更改
TARGET_GROUP=$TARGET_USER                           # 或使用 $TARGET_USER
# ----------------------------
# 初始化设置
# ----------------------------
# 颜色定义
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m' # 还原颜色

# 权限状态
HAS_SUDO=false
IS_ROOT=false
# ----------------------------
# 功能函数 (模块化设计)
# ----------------------------

# 日志记录器
log() {
    local level=$1
    local message=$2
    local timestamp=$(date +"%Y-%m-%d %T")
    
    case $level in
        "SUCCESS") echo -e "[$timestamp] ${GREEN}[OK]${NC} $message" | tee -a "$LOG_FILE";;
        "ERROR") echo -e "[$timestamp] ${RED}[ER]${NC} $message" | tee -a "$LOG_FILE";;
        "WARN") echo -e "[$timestamp] ${YELLOW}[WR]${NC} $message" | tee -a "$LOG_FILE";;
        "INFO") echo -e "[$timestamp] [II] $message" | tee -a "$LOG_FILE";;
        *) echo -e "[$timestamp] [DE] $message" >> "$LOG_FILE";;
    esac
}

# 错误处理函数
error_trap() {
    local lineno=$1
    local msg=$2
    log "ERROR" "发生致命错误 (行号: $lineno): $msg"
    exit 1
}

trap 'error_trap ${LINENO} "$BASH_COMMAND"' ERR

# 权限检查
check_privileges() {
    if [ "$(id -u)" -eq 0 ]; then
        IS_ROOT=true
        HAS_SUDO=true
        log "INFO" "当前为root用户"
        return
    fi

    if command -v sudo &> /dev/null && sudo -v &> /dev/null; then
        HAS_SUDO=true
        log "INFO" "当前为非root用户，但具有sudo权限"
    else
        if [ "$NEED_ROOT" = true ]; then
            log "ERROR" "脚本需要root权限，但当前用户无sudo权限"
            exit 1
        else
            log "WARN" "当前为非特权用户，部分功能可能受限"
        fi
    fi
}

# 智能执行函数 (自动处理权限)
run_cmd() {
    local cmd=$1
    local need_privilege=${2:-false}
    local desc=${3:-"执行命令: $cmd"}

    log "INFO" "开始: $desc"
    
    if [ "$need_privilege" = true ] && { [ "$IS_ROOT" = false ] && [ "$HAS_SUDO" = true ]; }; then
        sudo bash -c "$cmd" && log "SUCCESS" "$desc 完成" || {
            log "ERROR" "$desc 失败 (sudo)"
            return 1
        }
    elif [ "$need_privilege" = true ] && [ "$IS_ROOT" = true ]; then
        bash -c "$cmd" && log "SUCCESS" "$desc 完成" || {
            log "ERROR" "$desc 失败 (root)"
            return 1
        }
    else
        bash -c "$cmd" && log "SUCCESS" "$desc 完成" || {
            log "ERROR" "$desc 失败 (用户权限)"
            return 1
        }
    fi
}

# apt 软件包下载
module_aptpackages() {
    log "INFO" "===== 开始安装系统依赖 ====="
    
    # 检查包列表文件是否存在
    local pkg_list_file="./config/packages.list"
    if [[ ! -f "$pkg_list_file" ]]; then
        log "ERROR" "软件包列表文件 $pkg_list_file 不存在"
        return 1
    fi

    # 读取所有非注释行并合并为一行
    local packages=$(grep -vE '^\s*#' "$pkg_list_file" | tr '\n' ' ')
    
    if [[ -z "$packages" ]]; then
        log "WARN" "软件包列表文件中未找到有效软件包"
        return 0
    fi

    log "INFO" "检测到以下软件包需要安装:"
    log "INFO" "$packages"
    
    # 更新软件包索引
    run_cmd "apt update" true "更新软件包索引"
    
    # 一次性安装所有软件包
    run_cmd "apt install -y $packages" true "安装软件包"
    
    # 清理缓存
    run_cmd "apt autoremove -y" true "自动移除不需要的包"
    run_cmd "apt clean" true "清理软件包缓存"
}

# 配置文件设置模块
module_config() {
    log "INFO" "===== 开始配置环境 ====="
    
    # 创建用户目录下的配置文件
    run_cmd "sudo mkdir -p $TARGET_DIR" true "创建软件目录"

    # 设置文件权限
    run_cmd "chown $TARGET_USER:$TARGET_GROUP $TARGET_DIR" true "设置所有权"
    run_cmd "chmod 775 $TARGET_DIR" true "设置目录权限"
}

# ----------------------------
# 主执行逻辑
# ----------------------------
main() {
    # 初始化日志
    echo "环境配置开始于 $(date)" > "$LOG_FILE"
    log "INFO" "日志文件: $LOG_FILE"
    
    # 检查权限
    check_privileges
    
    # 模块调度器
    for module in "${MODULES[@]}"; do
        if declare -f "module_$module" > /dev/null; then
            "module_$module"
        else
            log "ERROR" "模块 '${module}' 未定义"
            exit 1
        fi
    done
    
    log "SUCCESS" "====== 环境配置成功完成 ======"
    exit 0
}

# 启动主程序
main