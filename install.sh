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

moudle_rubypackages() {
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

    run_cmd "ruby install -y $packages" true "安装ruby包"
}

# GitHub项目安装模块
module_gitpackages() {
    log "INFO" "===== 开始安装GitHub项目 ====="
    
    # 检查仓库列表文件
    local repo_list_file="./config/gitrepos.list"
    if [[ ! -f "$repo_list_file" ]]; then
        log "WARN" "Git仓库列表文件 $repo_list_file 不存在，跳过此模块"
        return 0
    fi

    # 读取并处理仓库列表
    local line_count=0
    while IFS= read -r line; do
        # 跳过注释和空行
        [[ "$line" =~ ^# ]] || [[ -z "$line" ]] && continue
        ((line_count++))
        
        # 分割行内容
        IFS='|' read -ra parts <<< "$line"
        if [ ${#parts[@]} -lt 4 ]; then
            log "ERROR" "第 $line_count 行格式错误: $line"
            log "INFO" "正确格式: 仓库URL|安装目录|安装类型|分支/标签|安装命令(可选)"
            continue
        fi
        
        local repo_url="${parts[0]}"
        local install_dir="${parts[1]}"
        local install_type="${parts[2]}"
        local ref="${parts[3]}"
        local custom_cmd="${parts[4]:-}"
        
        # 处理安装目录
        if [[ "$install_dir" == "DEFAULT" ]]; then
            repo_name=$(basename "$repo_url" .git)
            install_dir="$TARGET_DIR/$repo_name"
        fi
        
        # 判断是否需要特权
        local need_priv=false
        if [[ "$install_dir" == /usr/*]]; then
            need_priv=true
        fi
        
        # 克隆或更新仓库
        local clone_cmd="
if [ ! -d \"$install_dir\" ]; then
    git clone \"$repo_url\" \"$install_dir\" || { echo '克隆失败'; exit 1; }
    cd \"$install_dir\"
else
    cd \"$install_dir\"
    git fetch --all
fi
"
        run_cmd "$clone_cmd" "$need_priv" "克隆/更新仓库: $(basename "$repo_url" .git) 到 $install_dir"
        
        # 检出指定引用
        if [[ -n "$ref" && "$ref" != "DEFAULT" ]]; then
            run_cmd "cd \"$install_dir\" && git checkout \"$ref\"" "$need_priv" "检出 $ref"
        fi
        
        # 执行安装步骤
        case "$install_type" in
            "CLONE_ONLY")
                log "SUCCESS" "安装完成: 仅克隆仓库"
                ;;
                
            "RUN_SCRIPT")
                if [[ -z "$custom_cmd" ]]; then
                    log "WARN" "未指定安装脚本，尝试查找常见安装脚本"
                    find_and_run_install_script "$install_dir" "$need_priv"
                else
                    run_install_script "$install_dir" "$custom_cmd" "$need_priv"
                fi
                ;;
                
            "MAKE_INSTALL")
                compile_and_install "$install_dir" "$need_priv" "$custom_cmd"
                ;;
                
            "CUSTOM")
                if [[ -z "$custom_cmd" ]]; then
                    log "ERROR" "自定义安装类型需要指定安装命令"
                else
                    run_cmd "cd \"$install_dir\" && $custom_cmd" "$need_priv" "执行自定义命令"
                fi
                ;;
                
            *)
                log "ERROR" "未知安装类型: $install_type"
                ;;
        esac
        
    done < "$repo_list_file"
}

# 查找并运行安装脚本
find_and_run_install_script() {
    local install_dir=$1
    local need_priv=$2
    
    local possible_scripts=("install.sh" "setup.sh" "bootstrap.sh" "configure" "autogen.sh")
    
    for script in "${possible_scripts[@]}"; do
        if [[ -f "$install_dir/$script" ]]; then
            run_install_script "$install_dir" "./$script" "$need_priv"
            return
        fi
    done
    
    log "ERROR" "未找到安装脚本，请在配置中指定"
}

# 运行安装脚本
run_install_script() {
    local install_dir=$1
    local script=$2
    local need_priv=$3
    
    # 添加执行权限
    run_cmd "cd \"$install_dir\" && chmod +x \"$script\"" "$need_priv" "添加执行权限"
    
    # 运行脚本
    run_cmd "cd \"$install_dir\" && ./\"$script\"" "$need_priv" "运行安装脚本"
}

# 编译并安装
compile_and_install() {
    local install_dir=$1
    local need_priv=$2
    local configure_flags=$3
    
    # 配置步骤
    local configure_cmd="./configure"
    if [[ -n "$configure_flags" ]]; then
        configure_cmd+=" $configure_flags"
    fi
    
    if [[ -f "$install_dir/configure" ]]; then
        run_cmd "cd \"$install_dir\" && $configure_cmd" "$need_priv" "配置编译选项"
    elif [[ -f "$install_dir/CMakeLists.txt" ]]; then
        run_cmd "cd \"$install_dir\" && mkdir -p build && cd build && cmake .." "$need_priv" "CMake配置"
    else
        log "WARN" "未找到标准配置脚本，尝试直接编译"
    fi
    
    # 编译步骤
    if [[ -f "$install_dir/Makefile" ]]; then
        run_cmd "cd \"$install_dir\" && make -j$(nproc)" "$need_priv" "编译项目"
    elif [[ -f "$install_dir/build/Makefile" ]]; then
        run_cmd "cd \"$install_dir/build\" && make -j$(nproc)" "$need_priv" "编译项目"
    else
        log "ERROR" "未找到Makefile，无法编译"
        return
    fi
    
    # 安装步骤
    if [[ -f "$install_dir/Makefile" ]] && grep -q "install:" "$install_dir/Makefile"; then
        run_cmd "cd \"$install_dir\" && make install" "$need_priv" "安装项目"
    else
        log "WARN" "Makefile中没有install目标，可能需要手动安装"
    fi
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