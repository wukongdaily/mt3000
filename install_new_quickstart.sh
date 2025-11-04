#!/bin/sh

PATH=/bin:/sbin:/usr/bin:/usr/sbin:/usr/local/bin:/usr/local/sbin:~/bin
export PATH

version="1.0"
APP_URL='https://fw.koolcenter.com/iStoreOS/alpha/quickstart'
app_aarch64='quickstart_0.11.7-1_aarch64_cortex-a53.ipk'
app_x86='quickstart_0.11.7-1_x86_64.ipk'
app_ui='luci-app-quickstart_0.11.7-r1_all.ipk'
app_lng='luci-i18n-quickstart-zh-cn_git-25.283.23675-635149e_all.ipk'

setup_color() {
    # Only use colors if connected to a terminal
    if [ -t 1 ]; then
        RED=$(printf '\033[31m')
        GREEN=$(printf '\033[32m')
        YELLOW=$(printf '\033[33m')
        BLUE=$(printf '\033[34m')
        BOLD=$(printf '\033[1m')
        RESET=$(printf '\033[m')
    else
        RED=""
        GREEN=""
        YELLOW=""
        BLUE=""
        BOLD=""
        RESET=""
    fi
}
setup_color
command_exists() {
    command -v "$@" >/dev/null 2>&1
}
error() {
    echo ${RED}"Error: $@"${RESET} >&2
}

Download_Files(){
  local URL=$1
  local FileName=$2
  if command_exists curl; then
    curl -sSLk ${URL} -o ${FileName}
  elif command_exists wget; then
    wget -c --progress=bar:force --prefer-family=IPv4 --no-check-certificate ${URL} -O ${FileName}
  fi
  if [ $? -eq 0 ]; then
    echo "Download OK"
  else
    echo "Download failed"
    exit 1
  fi
}

clean_app(){
    rm -f /tmp/qstart/${app_x86} /tmp/qstart/${app_aarch64} /tmp/qstart/${app_ui} /tmp/qstart/${app_lng}
}

command_exists opkg || {
    error "The program only supports Openwrt."
    clean_app
    exit 2
}

TMPATH=/tmp/qstart
mkdir -p ${TMPATH}

if echo `uname -m` | grep -Eqi 'x86_64'; then
    arch='x86_64'
    ( set -x; Download_Files ${APP_URL}/${app_x86} ${TMPATH}/${app_x86};
      Download_Files ${APP_URL}/${app_ui} ${TMPATH}/${app_ui};
      Download_Files ${APP_URL}/${app_lng} ${TMPATH}/${app_lng};
      opkg install ${TMPATH}/*.ipk; )
elif  echo `uname -m` | grep -Eqi 'aarch64'; then
    arch='aarch64'
    ( set -x; Download_Files ${APP_URL}/${app_aarch64} ${TMPATH}/${app_aarch64};
      Download_Files ${APP_URL}/${app_ui} ${TMPATH}/${app_ui};
      Download_Files ${APP_URL}/${app_lng} ${TMPATH}/${app_lng};
      opkg install ${TMPATH}/*.ipk; )
else
    error "The program only supports x86_64/aarch64/arm64."
    exit 4
fi

if [ ! $? -eq 0 ]; then
  clean_app
  echo "Install failed(安装失败)"
  exit 5
fi

echo "The quickstart version is:"
quickstart version

if [ $? -eq 0 ]; then
  echo "Install OK"
else
  clean_app
  echo "Install failed(安装失败)"
  exit 6
fi

printf "$GREEN"
cat <<-'EOF'
  quickstart is now installed!
EOF
printf "$RESET"
clean_app
