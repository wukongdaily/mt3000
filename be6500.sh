#!/bin/sh
# 定义颜色输出函数
red() { echo -e "\033[31m\033[01m$1\033[0m"; }
green() { echo -e "\033[32m\033[01m$1\033[0m"; }
yellow() { echo -e "\033[33m\033[01m$1\033[0m"; }
blue() { echo -e "\033[34m\033[01m$1\033[0m"; }
light_magenta() { echo -e "\033[95m\033[01m$1\033[0m"; }
light_yellow() { echo -e "\033[93m\033[01m$1\033[0m"; }
cyan() { echo -e "\033[38;2;0;255;255m$1\033[0m"; }
third_party_source="https://istore.linkease.com/repo/all/nas_luci"
HTTP_HOST="https://mt3000.netlify.app"
setup_base_init() {
	#添加出处信息
	add_author_info
	#添加安卓时间服务器
	add_dhcp_domain
	##设置时区
	uci set system.@system[0].zonename='Asia/Shanghai'
	uci set system.@system[0].timezone='CST-8'
	uci commit system
	/etc/init.d/system reload
	green "安装完毕！请使用8080端口访问luci界面：http://192.168.8.1:8080"
	green "作者更多动态务必收藏：https://tvhelper.cpolar.cn/"
}

## 安装应用商店和主题
install_istore_os_style() {
	##设置Argon 紫色主题
	do_install_argon_skin
	#增加终端
	opkg install luci-i18n-ttyd-zh-cn
	#默认安装必备工具SFTP 方便下载文件 比如finalshell等工具可以直接浏览路由器文件
	opkg install openssh-sftp-server
	#默认使用体积很小的文件传输：系统——文件传输
	do_install_filetransfer
	FILE_PATH="/etc/openwrt_release"
	NEW_DESCRIPTION="Openwrt like iStoreOS Style by wukongdaily"
	CONTENT=$(cat $FILE_PATH)
	UPDATED_CONTENT=$(echo "$CONTENT" | sed "s/DISTRIB_DESCRIPTION='[^']*'/DISTRIB_DESCRIPTION='$NEW_DESCRIPTION'/")
	echo "$UPDATED_CONTENT" >$FILE_PATH
}
# 安装iStore
do_istore() {
	echo "do_istore 64bit ==================>"
	opkg update
	# 定义目标 URL 和本地目录
	URL="https://repo.istoreos.com/repo/all/store/"
	DIR="/tmp/ipk_store"

	# 创建目录
	mkdir -p "$DIR"
	cd "$DIR" || exit 1

	for ipk in $(wget -qO- "$URL" | grep -oE 'href="[^"]+\.ipk"' | cut -d'"' -f2); do
		echo "下载 $ipk"
		wget -q "${URL}${ipk}"
	done

	# 安装所有下载的 .ipk 包
	opkg install ./*.ipk

	#覆盖 bin/is-opkg
	wget -O /bin/is-opkg $HTTP_HOST/64bit/is-opkg.sh
	chmod +x /bin/is-opkg

	#添加istore软件源
	wget -O /etc/opkg/customfeeds.conf $HTTP_HOST/64bit/customfeeds.conf

	#调整a53架构优先级
	add_arch_64bit

}

# 首页和网络向导
do_quickstart() {
	download_lib_quickstart
	download_luci_quickstart
	opkg install /tmp/ipk_downloads/*.ipk
	hide_ui_elements
	green "正在更新到最新版iStoreOS首页风格 "
	wget $HTTP_HOST/install_new_quickstart.sh -O /tmp/install_new_quickstart.sh && chmod +x /tmp/install_new_quickstart.sh
	sh /tmp/install_new_quickstart.sh
	green "首页风格安装完毕！请使用8080端口访问luci界面：http://192.168.8.1:8080"
	green "作者更多动态务必收藏：https://tvhelper.cpolar.cn/"
}

download_luci_quickstart() {
	# 目标目录
	REPO_URL="https://repo.istoreos.com/repo/all/nas_luci/"
	DOWNLOAD_DIR="/tmp/ipk_downloads"

	# 创建下载目录
	mkdir -p "$DOWNLOAD_DIR"

	# 获取目录索引并筛选 quickstart ipk 链接
	wget -qO- "$REPO_URL" | grep -oE 'href="[^"]*quickstart[^"]*\.ipk"' |
		sed 's/href="//;s/"//' | while read -r FILE; do
		echo "📦 正在下载: $FILE"
		wget -q -P "$DOWNLOAD_DIR" "$REPO_URL$FILE"
	done

	echo "✅ 所有 quickstart 相关 IPK 文件已下载到: $DOWNLOAD_DIR"
}

download_lib_quickstart() {
	# 目标目录
	REPO_URL="https://repo.istoreos.com/repo/aarch64_cortex-a53/nas/"
	DOWNLOAD_DIR="/tmp/ipk_downloads"

	# 创建下载目录
	mkdir -p "$DOWNLOAD_DIR"

	# 获取目录索引并筛选 quickstart ipk 链接
	wget -qO- "$REPO_URL" | grep -oE 'href="[^"]*quickstart[^"]*\.ipk"' |
		sed 's/href="//;s/"//' | while read -r FILE; do
		echo "📦 正在下载: $FILE"
		wget -q -P "$DOWNLOAD_DIR" "$REPO_URL$FILE"
	done

	echo "✅ 所有 quickstart 相关 IPK 文件已下载到: $DOWNLOAD_DIR"
}

# 判断系统是否为iStoreOS
is_iStoreOS() {
	DISTRIB_ID=$(cat /etc/openwrt_release | grep "DISTRIB_ID" | cut -d "'" -f 2)
	# 检查DISTRIB_ID的值是否等于'iStoreOS'
	if [ "$DISTRIB_ID" = "iStoreOS" ]; then
		return 0 # true
	else
		return 1 # false
	fi
}

## 去除opkg签名
remove_check_signature_option() {
	local opkg_conf="/etc/opkg.conf"
	sed -i '/option check_signature/d' "$opkg_conf"
}

## 添加opkg签名
add_check_signature_option() {
	local opkg_conf="/etc/opkg.conf"
	echo "option check_signature 1" >>"$opkg_conf"
}

#设置第三方软件源
setup_software_source() {
	## 传入0和1 分别代表原始和第三方软件源
	if [ "$1" -eq 0 ]; then
		echo "# add your custom package feeds here" >/etc/opkg/customfeeds.conf
		##如果是iStoreOS系统,还原软件源之后，要添加签名
		if is_iStoreOS; then
			add_check_signature_option
		else
			echo
		fi
		# 还原软件源之后更新
		opkg update
	elif [ "$1" -eq 1 ]; then
		#传入1 代表设置第三方软件源 先要删掉签名
		remove_check_signature_option
		# 先删除再添加以免重复
		echo "# add your custom package feeds here" >/etc/opkg/customfeeds.conf
		echo "src/gz third_party_source $third_party_source" >>/etc/opkg/customfeeds.conf
		# 设置第三方源后要更新
		opkg update
	else
		echo "Invalid option. Please provide 0 or 1."
	fi
}

# 添加主机名映射(解决安卓原生TV首次连不上wifi的问题)
add_dhcp_domain() {
	local domain_name="time.android.com"
	local domain_ip="203.107.6.88"

	# 检查是否存在相同的域名记录
	existing_records=$(uci show dhcp | grep "dhcp.@domain\[[0-9]\+\].name='$domain_name'")
	if [ -z "$existing_records" ]; then
		# 添加新的域名记录
		uci add dhcp domain
		uci set "dhcp.@domain[-1].name=$domain_name"
		uci set "dhcp.@domain[-1].ip=$domain_ip"
		uci commit dhcp
	else
		echo
	fi
}

#添加出处信息
add_author_info() {
	uci set system.@system[0].description='wukongdaily'
	uci set system.@system[0].notes='文档说明:
    https://tvhelper.cpolar.cn/'
	uci commit system
}

##获取软路由型号信息
get_router_name() {
	model_info=$(cat /tmp/sysinfo/model)
	echo "$model_info"
}

get_router_hostname() {
	hostname=$(uci get system.@system[0].hostname)
	echo "$hostname 路由器"
}

# 安装体积非常小的文件传输软件 默认上传位置/tmp/upload/
do_install_filetransfer() {
	mkdir -p /tmp/luci-app-filetransfer/
	cd /tmp/luci-app-filetransfer/
	wget --user-agent="Mozilla/5.0" -O luci-app-filetransfer_all.ipk "$HTTP_HOST/luci-app-filetransfer/luci-app-filetransfer_all.ipk"
	wget --user-agent="Mozilla/5.0" -O luci-lib-fs_1.0-14_all.ipk "$HTTP_HOST/luci-app-filetransfer/luci-lib-fs_1.0-14_all.ipk"
	opkg install *.ipk --force-depends
}
do_install_depends_ipk() {
	wget --user-agent="Mozilla/5.0" -O "/tmp/luci-lua-runtime_all.ipk" "$HTTP_HOST/theme/luci-lua-runtime_all.ipk"
	wget --user-agent="Mozilla/5.0" -O "/tmp/libopenssl3.ipk" "$HTTP_HOST/theme/libopenssl3.ipk"
	opkg install "/tmp/luci-lua-runtime_all.ipk"
	opkg install "/tmp/libopenssl3.ipk"
}
#单独安装argon主题
do_install_argon_skin() {
	echo "正在尝试安装argon主题......."
	#下载和安装argon的依赖
	do_install_depends_ipk
	# bug fix 由于2.3.1 最新版的luci-argon-theme 登录按钮没有中文匹配,而2.3版本字体不对。
	# 所以这里安装上一个版本2.2.9,考虑到主题皮肤并不需要长期更新，因此固定版本没问题
	opkg update
	opkg install luci-lib-ipkg
	wget --user-agent="Mozilla/5.0" -O "/tmp/luci-theme-argon.ipk" "$HTTP_HOST/theme/luci-theme-argon-master_2.2.9.4_all.ipk"
	wget --user-agent="Mozilla/5.0" -O "/tmp/luci-app-argon-config.ipk" "$HTTP_HOST/theme/luci-app-argon-config_0.9_all.ipk"
	wget --user-agent="Mozilla/5.0" -O "/tmp/luci-i18n-argon-config-zh-cn.ipk" "$HTTP_HOST/theme/luci-i18n-argon-config-zh-cn.ipk"
	cd /tmp/
	opkg install luci-theme-argon.ipk luci-app-argon-config.ipk luci-i18n-argon-config-zh-cn.ipk
	# 检查上一个命令的返回值
	if [ $? -eq 0 ]; then
		echo "argon主题 安装成功"
		# 设置主题和语言
		uci set luci.main.mediaurlbase='/luci-static/argon'
		uci set luci.main.lang='zh_cn'
		uci commit
		sed -i 's/value="<%:Login%>"/value="登录"/' /usr/lib/lua/luci/view/themes/argon/sysauth.htm
		echo "重新登录web页面后, 查看新主题 "
	else
		echo "argon主题 安装失败! 建议再执行一次!再给我一个机会!事不过三!"
	fi
}

recovery() {
	echo "⚠️ 警告：此操作将恢复出厂设置，所有配置将被清除！"
	echo "⚠️ 请确保已备份必要数据。"
	read -p "是否确定执行恢复出厂设置？(yes/[no]): " confirm

	if [ "$confirm" = "yes" ]; then
		echo "正在执行恢复出厂设置..."
		# 安静执行 firstboot，不显示其内部的提示信息
		firstboot -y >/dev/null 2>&1
		echo "操作完成，正在重启设备..."
		reboot
	else
		echo "操作已取消。"
	fi
}

add_arch_64bit() {
	if ! wget -O /etc/opkg/arch.conf $HTTP_HOST/64bit/arch.conf; then
		echo "下载 arch.conf 失败，脚本终止。"
		exit 1
	fi
}

# 防止误操作 隐藏首页的格式化按钮
hide_ui_elements() {

    TARGET="/www/luci-static/quickstart/style.css"
    MARKER="/* hide custom luci elements */"

    # 如果没有追加过，就添加
    if ! grep -q "$MARKER" "$TARGET"; then
        cat <<EOF >>"$TARGET"

$MARKER
/* 隐藏首页格式化按钮 */
.value-data button {
  display: none !important;
}

/* 隐藏网络页的第 3 个 item */
#main > div > div.network-container.align-c > div > div > div:nth-child(3) {
  display: none !important;
}

/* 隐藏网络页的第 5 个 item */
#main > div > div.network-container.align-c > div > div > div:nth-child(5) {
  display: none !important;
}

/* 隐藏网络页的第 6 个 item */
#main > div > div.network-container.align-c > div > div > div:nth-child(6) {
  display: none !important;
}

/* 隐藏 feature-card.pink */
#main > div > div.card-container > div.feature-card.pink {
  display: none !important;
}

EOF
        echo "✅ 自定义元素已隐藏"
    else
        echo "⚠️ 无需重复操作"
    fi
}




#自定义风扇开始工作的温度
set_glfan_temp() {

	is_integer() {
		if [[ $1 =~ ^[0-9]+$ ]]; then
			return 0 # 是整数
		else
			return 1 # 不是整数
		fi
	}
	echo "兼容带风扇机型的GL-iNet路由器"
	echo "请输入风扇开始工作的温度(建议40-70之间的整数):"
	read temp

	if is_integer "$temp"; then
		uci set glfan.@globals[0].temperature="$temp"
		uci set glfan.@globals[0].warn_temperature="$temp"
		uci set glfan.@globals[0].integration=4
		uci set glfan.@globals[0].differential=20
		uci commit glfan
		/etc/init.d/gl_fan restart
		echo "设置成功！稍等片刻,请查看风扇转动情况"
	else
		echo "错误: 请输入整数."
	fi
}

toggle_adguardhome() {
	status=$(uci get adguardhome.config.enabled)

	if [ "$status" -eq 1 ]; then
		echo "Disabling AdGuardHome..."
		uci set adguardhome.config.enabled='0' >/dev/null 2>&1
		uci commit adguardhome >/dev/null 2>&1
		/etc/init.d/adguardhome disable >/dev/null 2>&1
		/etc/init.d/adguardhome stop >/dev/null 2>&1
		green "AdGuardHome 已关闭"
	else
		echo "Enabling AdGuardHome..."
		uci set adguardhome.config.enabled='1' >/dev/null 2>&1
		uci commit adguardhome >/dev/null 2>&1
		/etc/init.d/adguardhome enable >/dev/null 2>&1
		/etc/init.d/adguardhome start >/dev/null 2>&1
		green "AdGuardHome 已开启 访问 http://192.168.8.1:3000"
	fi
}

# 安装[官方辅助UI]插件 by 论坛 iBelieve
do_install_ui_helper() {

  echo "⚠️ 请您确保当前固件版本大于 4.7.2，若低于此版本建议先升级。"
  read -p "👉 如果您已确认，请按 [回车] 继续；否则按 Ctrl+C 或输入任意内容后回车退出：" user_input

  if [ -n "$user_input" ]; then
    echo "🚫 用户取消安装。"
    return 1
  fi

  local ipk_file="/tmp/glinjector_3.0.5-6_all.ipk"
  local sha_file="${ipk_file}.sha256"

  echo "📥 正在下载 IPK 及 SHA256 校验文件..."
  wget -O "$sha_file" "$HTTP_HOST/ui/glinjector_3.0.5-6_all.ipk.sha256" || {
    echo "❌ 下载 SHA256 文件失败"
    return 1
  }

  wget --user-agent="Mozilla/5.0" -O "$ipk_file" "$HTTP_HOST/ui/glinjector_3.0.5-6_all.ipk" || {
    echo "❌ 下载 IPK 文件失败"
    return 1
  }

  echo "🔐 正在进行 SHA256 校验..."

  cd "$(dirname "$ipk_file")"
  sha256sum -c "$sha_file" || {
    echo "❌ 校验失败：文件已损坏或未完整下载"
    rm -f "$ipk_file"
    return 1
  }

  echo "✅ 校验通过，开始安装..."

  opkg update
  opkg install "$ipk_file"
}
#高级卸载
advanced_uninstall(){
	echo "📥 正在下载 高级卸载插件..."
	wget -O /tmp/advanced_uninstall.run $HTTP_HOST/luci-app-uninstall-v1.0.6.run && chmod +x /tmp/advanced_uninstall.run
	sh /tmp/advanced_uninstall.run
}

while true; do
	clear
	gl_name=$(get_router_name)
	result="GL-iNet Be6500 一键iStoreOS风格化(新版)"
	echo "***********************************************************************"
	echo "*      一键安装工具箱(for gl-inet be6500)  by @wukongdaily        "
	echo "**********************************************************************"
	echo "*******支持的机型列表***************************************************"
	green "*******GL-iNet BE-6500********"
	green "请确保您的固件版本在4.7.2以上"
	echo

	light_magenta " 1. $result"
	echo
	light_magenta " 2. 安装argon紫色主题"
	echo
	light_magenta " 3. 单独安装iStore商店"
	echo
	light_magenta " 4. 隐藏首页无用元素"
	echo
	light_magenta " 5. 自定义风扇启动温度"
	echo
	light_magenta " 6. 安装个性化UI辅助插件(by VMatrices)"
	echo
	light_magenta " 7. 安装高级卸载"
	echo
	light_magenta " 8. 恢复出厂设置"
	echo
	echo " Q. 退出本程序"
	echo
	read -p "请选择一个选项: " choice

	case $choice in

	1)
		#安装iStore风格
		install_istore_os_style
		#基础必备设置
		setup_base_init
		#安装iStore商店
		do_istore
		#安装首页和网络向导
		do_quickstart
		;;
	2)
		do_install_argon_skin
		;;
	3)
		do_istore
		;;
	4)
		hide_ui_elements
		;;
	5)
		set_glfan_temp
		;;
	6)
		do_install_ui_helper
		;;
	7)
		advanced_uninstall
		;;
	8)
		recovery
		;;
	q | Q)
		echo "退出"
		exit 0
		;;
	*)
		echo "无效选项，请重新选择。"
		;;
	esac

	read -p "按 Enter 键继续..."
done