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
# 设置全局命令 g
cp -f "$0" /usr/bin/g
chmod +x /usr/bin/g


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

	## 设置防火墙wan 打开,方便主路由访问
	uci set firewall.@zone[1].input='ACCEPT'
	uci commit firewall

}

## 安装应用商店和主题
install_istore_os_style() {
	##设置Argon 紫色主题
	do_install_argon_skin
	#增加首页终端图标
	opkg install ttyd
	#默认使用体积很小的文件传输：系统——文件传输
	do_install_filetransfer
	#默认安装必备工具SFTP 方便下载文件 比如finalshell等工具可以直接浏览路由器文件
	is-opkg install app-meta-sftp
	is-opkg install 'app-meta-ddnsto'
	# 安装磁盘管理
	is-opkg install 'app-meta-diskman'
	FILE_PATH="/etc/openwrt_release"
	NEW_DESCRIPTION="Openwrt like iStoreOS Style by wukongdaily"
	CONTENT=$(cat $FILE_PATH)
	UPDATED_CONTENT=$(echo "$CONTENT" | sed "s/DISTRIB_DESCRIPTION='[^']*'/DISTRIB_DESCRIPTION='$NEW_DESCRIPTION'/")
	echo "$UPDATED_CONTENT" >$FILE_PATH

}
# 安装iStore 参考 https://github.com/linkease/istore
do_istore() {
	echo "do_istore method==================>"
	ISTORE_REPO=https://istore.linkease.com/repo/all/store
	FCURL="curl --fail --show-error"

	curl -V >/dev/null 2>&1 || {
		echo "prereq: install curl"
		opkg info curl | grep -Fqm1 curl || opkg update
		opkg install curl
	}

	IPK=$($FCURL "$ISTORE_REPO/Packages.gz" | zcat | grep -m1 '^Filename: luci-app-store.*\.ipk$' | sed -n -e 's/^Filename: \(.\+\)$/\1/p')

	[ -n "$IPK" ] || exit 1

	$FCURL "$ISTORE_REPO/$IPK" | tar -xzO ./data.tar.gz | tar -xzO ./bin/is-opkg >/tmp/is-opkg

	[ -s "/tmp/is-opkg" ] || exit 1

	chmod 755 /tmp/is-opkg
	/tmp/is-opkg update
	# /tmp/is-opkg install taskd
	/tmp/is-opkg opkg install --force-reinstall luci-lib-taskd luci-lib-xterm
	/tmp/is-opkg opkg install --force-reinstall luci-app-store || exit $?
	[ -s "/etc/init.d/tasks" ] || /tmp/is-opkg opkg install --force-reinstall taskd
	[ -s "/usr/lib/lua/luci/cbi.lua" ] || /tmp/is-opkg opkg install luci-compat >/dev/null 2>&1
	
}

#设置风扇工作温度
setup_cpu_fans() {
	#设定温度阀值,cpu高于48度,则风扇开始工作
	uci set glfan.@globals[0].temperature=48
	uci set glfan.@globals[0].warn_temperature=48
	uci set glfan.@globals[0].integration=4
	uci set glfan.@globals[0].differential=20
	uci commit glfan
	/etc/init.d/gl_fan restart
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

add_custom_feed() {
	# 先清空配置
	echo "# add your custom package feeds here" >/etc/opkg/customfeeds.conf
	# Prompt the user to enter the feed URL
	echo "请输入自定义软件源的地址(通常是https开头 aarch64_cortex-a53 结尾):"
	read feed_url
	if [ -n "$feed_url" ]; then
		echo "src/gz custom_feed $feed_url" >>/etc/opkg/customfeeds.conf
		opkg update
		if [ $? -eq 0 ]; then
			echo "已添加并更新列表."
		else
			echo "已添加但更新失败,请检查网络或重试."
		fi
	else
		echo "Error: Feed URL not provided. No changes were made."
	fi
}

remove_custom_feed() {
	echo "# add your custom package feeds here" >/etc/opkg/customfeeds.conf
	opkg update
	if [ $? -eq 0 ]; then
		echo "已删除并更新列表."
	else
		echo "已删除了自定义软件源但更新失败,请检查网络或重试."
	fi
}

# 检查是否安装了 whiptail
check_whiptail_installed() {
	if [ -e /usr/bin/whiptail ]; then
		return 0
	else
		return 1
	fi
}

#定义一个通用的Dialog
show_whiptail_dialog() {
	#判断是否具备whiptail dialog组件
	if check_whiptail_installed; then
		echo "whiptail has installed"
	else
		echo "# add your custom package feeds here" >/etc/opkg/customfeeds.conf
		opkg update
		opkg install whiptail
	fi
	local title="$1"
	local message="$2"
	local function_definition="$3"
	whiptail --title "$title" --yesno "$message" 15 60 --yes-button "是" --no-button "否"
	if [ $? -eq 0 ]; then
		eval "$function_definition"
	else
		echo "退出"
		exit 0
	fi
}

# 执行重启操作
do_reboot() {
	reboot
}

#提示用户要重启
show_reboot_tips() {
	reboot_code='do_reboot'
	show_whiptail_dialog "重启提醒" "           $(get_router_hostname)\n           一键风格化运行完成.\n           为了更好的清理临时缓存,\n           您是否要重启路由器?" "$reboot_code"
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

recovery_opkg_settings() {
	echo "# add your custom package feeds here" >/etc/opkg/customfeeds.conf
	router_name=$(get_router_name)
	case "$router_name" in
	*3000*)
		echo "Router name contains '3000'."
		mt3000_opkg="$HTTP_HOST/mt-3000/distfeeds.conf"
		wget -O /etc/opkg/distfeeds.conf ${mt3000_opkg}
		;;
	*2500*)
		echo "Router name contains '2500'."
		mt2500a_opkg="$HTTP_HOST/mt-2500a/distfeeds.conf"
		wget -O /etc/opkg/distfeeds.conf ${mt2500a_opkg}
		;;
	*6000*)
		update_opkg_config
		;;
	*)
		echo "Router name does not contain '3000' 6000 or '2500'."
		;;
	esac
}

update_opkg_config() {
	kernel_version=$(uname -r)
	echo "MT-6000 kernel version: $kernel_version"
	case $kernel_version in
	5.4*)
		mt6000_opkg="$HTTP_HOST/mt-6000/distfeeds-5.4.conf"
		wget -O /etc/opkg/distfeeds.conf ${mt6000_opkg}
		# 更换5.4.238 内核之后 缺少的依赖

		mkdir -p /tmp/mt6000
		wget -O /tmp/mt6000/script-utils.ipk "$HTTP_HOST/mt-6000/script-utils.ipk"
		wget -O /tmp/mt6000/mdadm.ipk "$HTTP_HOST/mt-6000/mdadm.ipk"
		wget -O /tmp/mt6000/lsblk.ipk "$HTTP_HOST/mt-6000/lsblk.ipk"
		opkg update
		if [ -f "/tmp/mt6000/lsblk.ipk" ]; then
			# 先卸载之前安装过的lsblk,确保使用的是正确的lsblk
			opkg remove lsblk
		fi
		opkg install /tmp/mt6000/*.ipk
		;;
	5.15*)
		mt6000_opkg="$HTTP_HOST/mt-6000/distfeeds.conf"
		wget -O /etc/opkg/distfeeds.conf ${mt6000_opkg}
		;;
	*)
		echo "Unsupported kernel version: $kernel_version"
		return 1
		;;
	esac
}

do_luci_app_wireguard() {
	setup_software_source 0
	opkg install luci-app-wireguard
	opkg install luci-i18n-wireguard-zh-cn
	echo "请访问 http://"$(uci get network.lan.ipaddr)"/cgi-bin/luci/admin/status/wireguard  查看状态 "
	echo "也可以去接口中 查看是否增加了新的wireguard 协议的选项 "
}
update_luci_app_quickstart() {
	if [ -f "/bin/is-opkg" ]; then
		# 如果 /bin/is-opkg 存在，则执行 is-opkg update
		is-opkg update
		is-opkg install luci-i18n-quickstart-zh-cn --force-depends >/dev/null 2>&1
		opkg install iptables-mod-tproxy
		opkg install iptables-mod-socket
		opkg install iptables-mod-iprange
		hide_homepage_format_button
		yellow "恭喜您!现在你的路由器已经变成iStoreOS风格啦!"
		green "现在您可以访问8080端口 查看是否生效 http://192.168.8.1:8080"
		green "更多up主项目和动态 请务必收藏我的导航站 https://tvhelper.cpolar.cn "
		green "赞助本项目作者 https://wkdaily.cpolar.cn/01 "
		addr_hostname=$(uci get system.@system[0].hostname)
	else
		red "请先执行第一项 一键iStoreOS风格化"
	fi
}

# 安装体积非常小的文件传输软件 默认上传位置/tmp/upload/
do_install_filetransfer() {
	mkdir -p /tmp/luci-app-filetransfer/
	cd /tmp/luci-app-filetransfer/
	wget -O luci-app-filetransfer_all.ipk "$HTTP_HOST/luci-app-filetransfer/luci-app-filetransfer_all.ipk"
	wget -O luci-lib-fs_1.0-14_all.ipk "$HTTP_HOST/luci-app-filetransfer/luci-lib-fs_1.0-14_all.ipk"
	opkg install *.ipk --force-depends
}
do_install_depends_ipk() {
	wget -O "/tmp/luci-lua-runtime_all.ipk" "$HTTP_HOST/theme/luci-lua-runtime_all.ipk"
	wget -O "/tmp/libopenssl3.ipk" "$HTTP_HOST/theme/libopenssl3.ipk"
	wget -O "/tmp/luci-compat.ipk" "$HTTP_HOST/theme/luci-compat.ipk"
	opkg install "/tmp/luci-lua-runtime_all.ipk"
	opkg install "/tmp/libopenssl3.ipk"
	opkg install "/tmp/luci-compat.ipk"
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
	wget -O "/tmp/luci-theme-argon.ipk" "$HTTP_HOST/theme/luci-theme-argon-master_2.2.9.4_all.ipk"
	wget -O "/tmp/luci-app-argon-config.ipk" "$HTTP_HOST/theme/luci-app-argon-config_0.9_all.ipk"
	wget -O "/tmp/luci-i18n-argon-config-zh-cn.ipk" "$HTTP_HOST/theme/luci-i18n-argon-config-zh-cn.ipk"
	cd /tmp/
	opkg install luci-theme-argon.ipk luci-app-argon-config.ipk luci-i18n-argon-config-zh-cn.ipk
	# 检查上一个命令的返回值
	if [ $? -eq 0 ]; then
		echo "argon主题 安装成功"
		# 设置主题和语言
		uci set luci.main.mediaurlbase='/luci-static/argon'
		uci set luci.main.lang='zh_cn'
		uci commit
		echo "重新登录web页面后, 查看新主题 "
	else
		echo "argon主题 安装失败! 建议再执行一次!再给我一个机会!事不过三!"
	fi
}

#单独安装文件管理器
do_install_filemanager() {
	echo "为避免bug,安装文件管理器之前,需要先iStore商店"
	do_istore
	echo "接下来 尝试安装文件管理器......."
	is-opkg install 'app-meta-linkease'
	echo "重新登录web页面,然后您可以访问:  http://192.168.8.1/cgi-bin/luci/admin/services/linkease/file/?path=/root"
}
#更新脚本
update_myself() {
	wget -O gl-inet.sh "$HTTP_HOST/gl-inet.sh" && chmod +x gl-inet.sh
	echo "脚本已更新并保存在当前目录 gl-inet.sh,现在将执行新脚本。"
	./gl-inet.sh
	exit 0
}

#根据release地址和命名前缀获取apk地址
get_docker_compose_url() {
	if [ $# -eq 0 ]; then
		echo "需要提供GitHub releases页面的URL作为参数。"
		return 1
	fi
	local releases_url=$1
	# 使用curl获取重定向的URL
	latest_url=$(curl -Ls -o /dev/null -w "%{url_effective}" "$releases_url")
	# 使用sed从URL中提取tag值,并保留前导字符'v'
	tag=$(echo $latest_url | sed 's|.*/v|v|')
	# 检查是否成功获取到tag
	if [ -z "$tag" ]; then
		echo "未找到最新的release tag。"
		return 1
	fi
	# 拼接docker-compose下载链接
	local repo_path=$(echo "$releases_url" | sed -n 's|https://github.com/\(.*\)/releases/latest|\1|p')
	docker_compose_download_url="https://github.com/${repo_path}/releases/download/${tag}/docker-compose-linux-aarch64"
	echo "$docker_compose_download_url"
}

# 下载并安装Docker Compose
do_install_docker_compose() {
	# https://github.com/docker/compose/releases/download/v2.26.0/docker-compose-linux-aarch64
	# 检查/usr/bin/docker是否存在并且可执行
	if [ -f "/usr/bin/docker" ] && [ -x "/usr/bin/docker" ]; then
		echo "Docker is installed and has execute permissions."
	else
		red "警告 您还没有安装Docker"
		exit 1
	fi
	if [[ "$gl_name" == *3000* ]]; then
		red "警告 docker-compose 组件的大小将近60MB,请谨慎安装"
		yellow "确定要继续安装吗(y|n)"
		read -r answer
		if [ "$answer" = "y" ] || [ -z "$answer" ]; then
			green "正在获取最新版docker-compose下载地址"
		else
			yellow "已退出docker-compose安装流程"
			exit 1
		fi
	fi
	local github_releases_url="https://github.com/docker/compose/releases/latest"
	local docker_compose_url=$(get_docker_compose_url "$github_releases_url")
	echo "最新版docker-compose 地址:$docker_compose_url"
	wget -O /usr/bin/docker-compose $docker_compose_url
	if [ $? -eq 0 ]; then
		green "docker-compose下载并安装成功,你可以使用啦"
		chmod +x /usr/bin/docker-compose
	else
		red "安装失败,请检查网络连接.或者手动下载到 /usr/bin/docker-compose 记得赋予执行权限"
		yellow "刚才使用的地址是:$docker_compose_url"
		exit 1
	fi

}

#mt3000更换分区
mt3000_overlay_changed() {
	wget -O mt3000.sh "$HTTP_HOST/mt-3000/mt3000.sh" && chmod +x mt3000.sh
	sh mt3000.sh
}

# 防止误操作 隐藏首页的格式化按钮
hide_homepage_format_button() {

	TARGET="/www/luci-static/quickstart/style.css"
	MARKER="/* hide quickstart disk button */"

	# 如果没有追加过，就添加
	if ! grep -q "$MARKER" "$TARGET"; then
		cat <<EOF >>"$TARGET"

$MARKER
.value-data button {
  display: none !important;
}
EOF
		echo "✅ 格式化按钮已隐藏"
	else
		echo "⚠️ 无需重复操作"
	fi

}

# 启用adguardhome
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

  echo "⚠️ 请您确保当前固件版本大于 4.7.0，若低于此版本建议先升级。"
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

  wget -O "$ipk_file" "$HTTP_HOST/ui/glinjector_3.0.5-6_all.ipk" || {
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

while true; do
	clear
	gl_name=$(get_router_name)
	result=$gl_name"一键iStoreOS风格化"
	result=$(echo "$result" | sed 's/ like iStoreOS//')
	echo "***********************************************************************"
	echo "*      一键安装工具箱(for gl-inet Router)"
	echo "*      备用脚本 by @wukongdaily        "
	echo "**********************************************************************"
	echo "*      当前的路由器型号: "$gl_name | sed 's/ like iStoreOS//'
	echo
	echo "*******支持的机型列表***************************************************"
	green "*******GL-iNet MT-2500A"
	green "*******GL-iNet MT-3000 "
	green "*******GL-iNet MT-6000 "
	echo "******************下次调用 直接输入快捷键 g  *****************************"
	echo
	light_magenta " 1. $result"
	echo
	echo " 2. 设置自定义软件源"
	echo " 3. 删除自定义软件源"
	echo
	echo " 4. 设置风扇开始工作的温度(仅限MT3000)"
	echo " 5. 恢复原厂OPKG配置软件包"
	echo
	echo " 6. 启用/关闭原厂adguardhome"
	echo " 7. 安装luci-app-wireguard"
	echo " 8. 更新luci-app-quickstart"
	echo " 9. 安装Argon紫色主题"
	echo "10. 安装文件管理器"
	light_magenta "11. 安装Docker"
	light_magenta "12. 安装docker-compose"
	light_magenta "13. 更新脚本"
	cyan "14. MT3000一键更换分区"
	light_magenta "15. 隐藏首页格式化按钮"
	light_magenta "16. 安装官方UI辅助插件(by VMatrices)"
	echo
	echo " Q. 退出本程序"
	echo
	read -p "请选择一个选项: " choice

	case $choice in

	1)
		if [[ "$gl_name" == *3000* ]]; then
			# 设置风扇工作温度
			setup_cpu_fans
		fi
		# 解决首页“已联网”的UI问题
		recovery_opkg_settings
		#先安装istore商店
		do_istore
		#安装iStore风格
		install_istore_os_style
		#安装iStore首页风格
		update_luci_app_quickstart
		#基础必备设置
		setup_base_init
		;;
	2)
		add_custom_feed
		;;
	3)
		remove_custom_feed
		;;
	4)
		case "$gl_name" in
		*3000*)
			set_glfan_temp
			;;
		*)
			echo "*      当前的路由器型号: "$gl_name | sed 's/ like iStoreOS//'
			echo "并非MT3000 它没有风扇 无需设置"
			;;
		esac
		;;
	5)
		recovery_opkg_settings
		;;
	6)
		toggle_adguardhome
		;;
	7)
		do_luci_app_wireguard
		;;
	8)
		update_luci_app_quickstart
		;;
	9)
		do_install_argon_skin
		;;
	10)
		do_install_filemanager
		;;
	11)
		yellow "注意!插入U盘之前请确认U盘数据已备份"
		red "确定要继续吗(y|n)"
		read -r answer
		if [ "$answer" = "y" ] || [ -z "$answer" ]; then
			wget -q -O do_docker.sh "$HTTP_HOST/docker/do_docker.sh" && chmod +x do_docker.sh
			./do_docker.sh
		else
			yellow "已退出Docker安装流程"
		fi
		;;
	12)
		do_install_docker_compose
		;;
	13)
		update_myself
		;;
	14)
		mt3000_overlay_changed
		;;
	15)
		hide_homepage_format_button
		;;
	16)
		do_install_ui_helper
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
