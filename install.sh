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
MODULES=("config" "aptpackages" "rubypackages" "gitpackages")                 # 启用的模块列表

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

# 配置文件设置模块
module_config() {
    log "INFO" "===== 开始配置环境 ====="
    
    # 创建用户目录下的配置文件
    run_cmd "sudo mkdir -p $TARGET_DIR" true "创建软件目录"

    # 设置文件权限
    run_cmd "chown $TARGET_USER:$TARGET_GROUP $TARGET_DIR" true "设置所有权"
    run_cmd "chmod 775 $TARGET_DIR" true "设置目录权限"
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

module_rubypackages() {
    log "INFO" "===== 开始安装Ruby包 ====="
    
    # 检查包列表文件
    local pkg_list_file="./config/rubypackages.list"
    if [[ ! -f "$pkg_list_file" ]]; then
        log "ERROR" "软件包列表文件 $pkg_list_file 不存在"
        return 1
    fi

    local packages=$(grep -vE '^\s*#' "$pkg_list_file" | tr '\n' ' ')

    if [[ -z "$packages" ]]; then
        log "WARN" "ruby软件包列表文件中未找到有效软件包"
        return 0
    fi

    log "INFO" "检测到以下软件包需要安装:"
    log "INFO" "$packages"

    run_cmd "gem install $packages" true "安装ruby包"
}

# GitHub项目安装模块
module_gitpackages() {
    log "INFO" "===== 开始安装GitHub项目 ====="
    
    # 从 gitrepos.list 读取仓库列表
    local pkg_list_file="./config/gitrepos.list"
    if [[ ! -f "$pkg_list_file" ]]; then
        log "ERROR" "git仓库列表文件 $pkg_list_file 不存在"
        return 1
    fi

    # 确保目标目录存在
    run_cmd "mkdir -p \"$TARGET_DIR\"" true "创建目标目录 $TARGET_DIR"
    
    # 统计处理结果
    local success_count=0
    local skip_count=0
    local error_count=0
    
    # 读取仓库列表文件
    while IFS= read -r repo_spec || [[ -n "$repo_spec" ]]; do
        # 跳过空行和注释
        if [[ -z "$repo_spec" || "$repo_spec" =~ ^\s*# ]]; then
            continue
        fi
        
        # 解析仓库规格 (格式: [name/]repo[.git][@branch])
        local repo_url branch repo_name
        if [[ "$repo_spec" =~ @ ]]; then
            branch="${repo_spec#*@}"
            repo_spec="${repo_spec%@*}"
        else
            branch=""
        fi
        
        # 规范化仓库URL
        if [[ "$repo_spec" =~ ^https:// || "$repo_spec" =~ ^git@ ]]; then
            repo_url="$repo_spec"
        else
            repo_url="https://github.com/$repo_spec"
            # 确保以.git结尾
            [[ "$repo_url" != *.git ]] && repo_url="${repo_url}.git"
        fi
        
        # 提取仓库名称
        repo_name=$(basename "$repo_url" .git)
        
        # 目标路径
        local target_path="$TARGET_DIR/$repo_name"
        
        log "INFO" "处理仓库: $repo_name ($repo_url)"
        
        # 检查是否已存在
        if [[ -d "$target_path" ]]; then
            log "WARN" "目录已存在: $target_path, 跳过克隆"
            ((skip_count++))
            continue
        fi
        
        # 构建克隆命令
        local clone_cmd="git clone \"$repo_url\" \"$target_path\""
        [[ -n "$branch" ]] && clone_cmd+=" -b \"$branch\""
        
        # 执行克隆
        if run_cmd "$clone_cmd" false "克隆仓库 $repo_name"; then
            # 更改所有权 (如果需要)
            if [ "$TARGET_USER" != "root" ] && [ "$(id -un)" != "$TARGET_USER" ]; then
                if run_cmd "chown -R $TARGET_USER:$TARGET_GROUP \"$target_path\"" true \
                    "更改 $repo_name 的所有权"; then
                    log "SUCCESS" "设置所有权: $TARGET_USER:$TARGET_GROUP"
                fi
            fi
            ((success_count++))
        else
            ((error_count++))
            # 清理失败目录
            [[ -d "$target_path" ]] && run_cmd "rm -rf \"$target_path\"" true "清理失败目录"
        fi
        
    done < "$pkg_list_file"
    
    # 输出统计结果
    log "INFO" "===== GitHub项目安装完成 ====="
    log "INFO" "成功: $success_count, 跳过: $skip_count, 失败: $error_count"
    [[ $error_count -gt 0 ]] && return 1 || return 0
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