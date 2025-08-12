#!/bin/bash
# Script to install packages listed in ./config/packages.list using apt
"""
PACKAGE_LIST="./config/packages.list"

if [[ ! -f "$PACKAGE_LIST" ]]; then
    echo "Error: Package list file '$PACKAGE_LIST' not found."
    exit 1
fi

while IFS= read -r package || [[ -n "$package" ]]; do
    if [[ -z "$package" || "$package" =~ ^# ]]; then
        continue
    fi
    echo "Installing $package..."
    if ! sudo apt install -y "$package"; then
        echo "Error: Failed to install $package"
        exit 1
    fi
done < "$PACKAGE_LIST"

echo "Done apt install packages"
"""
#!/bin/bash

# 安装Regolith桌面环境的脚本
# 需要以root权限或sudo执行

set -e  # 遇到错误时退出脚本

echo "开始安装Regolith桌面环境..."

# 1. 注册Regolith公钥
echo "正在添加Regolith GPG密钥..."
wget -qO - https://archive.regolith-desktop.com/regolith.key | \
gpg --dearmor | sudo tee /usr/share/keyrings/regolith-archive-keyring.gpg > /dev/null

# 2. 添加软件源
echo "正在添加Regolith软件源..."
echo deb "[arch=amd64 signed-by=/usr/share/keyrings/regolith-archive-keyring.gpg] \
https://archive.regolith-desktop.com/ubuntu/stable noble v3.3" | \
sudo tee /etc/apt/sources.list.d/regolith.list

# 3. 更新软件包列表
echo "正在更新软件包列表..."
sudo apt update -y

# 4. 安装Regolith桌面环境
echo "正在安装Regolith桌面组件..."
sudo apt install -y regolith-desktop regolith-session-flashback regolith-look-lascaille

# 5. 清理不必要的包
echo "正在清理..."
sudo apt autoremove -y

# 6. 完成提示
echo "Regolith桌面环境安装完成！"
echo "系统需要重启以使更改生效。"

# 询问用户是否立即重启
read -p "是否立即重启系统？[y/N] " choice
case "$choice" in
  y|Y )
    echo "正在重启系统..."
    sudo reboot
    ;;
  * )
    echo "请稍后手动重启系统以完成安装。"
    ;;
esac
