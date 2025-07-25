#!/bin/sh
# this script MUST supports executting without luci-app-store installed,
# so we can use this script to install luci-app-store itself

action=${1}
shift
if [ "${action:0:9}" = "AUTOCONF=" ]; then
    export "ISTORE_${action}"
    exec "$0" "$@"
fi

IS_ROOT=/tmp/is-root
DL_DIR=${IS_ROOT}/tmp/dl
LISTS_DIR_O=/tmp/opkg-lists
LISTS_DIR=${IS_ROOT}${LISTS_DIR_O}
OPKG_CONF_DIR=${IS_ROOT}/etc/opkg
OPKG_CONF_DIR_M=${IS_ROOT}/etc/opkg_m
FEEDS_SERVER=https://istore.istoreos.com/repo
FEEDS_SERVER_MIRRORS="https://repo.istoreos.com/repo"
DISABLE_MIRROR=false
#ARCH="aarch64_cortex-a53"
ARCH=`sed -n -e 's/^Architecture: *\([^ ]\+\) *$/\1/p' /rom/usr/lib/opkg/info/libc.control /usr/lib/opkg/info/libc.control 2>/dev/null | head -1`
# for istore self upgrade
ISTORE_PKG=luci-app-store
ISTORE_DEP_PKGS="luci-lib-taskd luci-lib-xterm taskd"
ISTORE_INDEX=https://istore.istoreos.com/repo/all/store/Packages.gz

is_init() {
    mkdir -p ${DL_DIR} ${LISTS_DIR} ${IS_ROOT}/etc ${IS_ROOT}/var

    cat /etc/opkg.conf | grep -Fv lists_dir | grep -Fv check_signature > ${IS_ROOT}/etc/opkg.conf

    cp ${IS_ROOT}/etc/opkg.conf ${IS_ROOT}/etc/opkg_o.conf

    echo >> ${IS_ROOT}/etc/opkg.conf
    echo "lists_dir ext ${LISTS_DIR}" >> ${IS_ROOT}/etc/opkg.conf
    # create opkg_o.conf for executting 'opkg update' with offline-root, so we don't overwrite system opkg list
    echo >> ${IS_ROOT}/etc/opkg_o.conf
    echo "lists_dir ext ${LISTS_DIR_O}" >> ${IS_ROOT}/etc/opkg_o.conf

    cp -au /etc/opkg ${IS_ROOT}/etc/
    [ -e ${IS_ROOT}/var/lock ] || ln -s /var/lock ${IS_ROOT}/var/lock
}

opkg_wrap() {
    OPKG_CONF_DIR=${OPKG_CONF_DIR} opkg -f ${IS_ROOT}/etc/opkg.conf "$@"
}

opkg_wrap_mirrors() {
    local server
    local file
    if ! $DISABLE_MIRROR; then
        for server in $FEEDS_SERVER_MIRRORS ; do
            rm -rf "${OPKG_CONF_DIR_M}" 2>/dev/null
            mkdir -p "${OPKG_CONF_DIR_M}" 2>/dev/null
            ls "${OPKG_CONF_DIR}/" | while read; do
                file="$REPLY"
                if [ -f "${OPKG_CONF_DIR}/$file" -a "${file: -5}" = ".conf" ]; then
                    sed "s#$FEEDS_SERVER/#$server/#g" "${OPKG_CONF_DIR}/$file" >"${OPKG_CONF_DIR_M}/$file"
                    touch -r "${OPKG_CONF_DIR}/$file" "${OPKG_CONF_DIR_M}/$file" 2>/dev/null
                else
                    cp -a "${OPKG_CONF_DIR}/$file" "${OPKG_CONF_DIR_M}/"
                fi
            done
            echo "Try mirror server $server"
            OPKG_CONF_DIR=${OPKG_CONF_DIR_M} opkg -f ${IS_ROOT}/etc/opkg.conf "$@" && return 0
        done
        DISABLE_MIRROR=true
    fi
    echo "Try origin server $FEEDS_SERVER"
    OPKG_CONF_DIR=${OPKG_CONF_DIR} opkg -f ${IS_ROOT}/etc/opkg.conf "$@"
}

alias fcurl='curl -L --fail --show-error'

check_space() {
    local free="$((`df -kP / | awk 'NR==2 {print $4}'` >> 10 ))"
    if [ "$free" -lt 1 ]; then
        echo "Root disk full!" >&2
        exit 1
    fi
    return 0
}

update() {
    if [ -z "${ARCH}" ]; then
        echo "Get architecture failed" >&2
        return 1
    fi

    echo "Fetch feed list for ${ARCH}"
    fcurl --no-progress-meter -o ${OPKG_CONF_DIR}/meta.conf "${FEEDS_SERVER}/all/meta.conf" && \
      fcurl --no-progress-meter -o ${OPKG_CONF_DIR}/all.conf "${FEEDS_SERVER}/all/isfeeds.conf" && \
      fcurl --no-progress-meter -o ${OPKG_CONF_DIR}/arch.conf "${FEEDS_SERVER}/${ARCH}/isfeeds.conf" || \
      return 1

    echo "Update feeds index"
    opkg -f ${IS_ROOT}/etc/opkg_o.conf --offline-root ${IS_ROOT} update

    return 0
}

update_if_outdate() {
    local idle_t=$((`date '+%s'` - `date -r ${IS_ROOT}/.last_force_ts '+%s' 2>/dev/null || echo '0'`))
    [ $idle_t -gt ${1:-120} ] || return 2
    update || return 1
    touch ${IS_ROOT}/.last_force_ts
    return 0
}

check_self_upgrade() {
    local newest=`curl --connect-timeout 2 --max-time 5 -s ${ISTORE_INDEX} | gunzip | grep -FA10 "Package: ${ISTORE_PKG}" | grep -Fm1 'Version: ' | sed 's/^Version: //'`
    local current=`grep -Fm1 'Version: ' /usr/lib/opkg/info/${ISTORE_PKG}.control | sed 's/^Version: //'`
    if [ "v$newest" = "v" -o "v$current" = "v" ]; then
        echo "Check version failed!" >&2
        exit 255
    fi
    if [ "$newest" != "$current" ]; then
        echo "$newest"
    fi
    return 0
}

do_self_upgrade_0() {
    opkg_wrap upgrade ${ISTORE_DEP_PKGS} && opkg_wrap upgrade ${ISTORE_PKG}
}

do_self_upgrade() {
    check_mtime || return 1
    local newest=`curl --connect-timeout 2 --max-time 5 -s ${ISTORE_INDEX} | gunzip | grep -FA10 "Package: ${ISTORE_PKG}" | grep -Fm1 'Version: ' | sed 's/^Version: //'`
    local current=`grep -Fm1 'Version: ' /usr/lib/opkg/info/${ISTORE_PKG}.control | sed 's/^Version: //'`
    if [ "v$newest" = "v" -o "v$current" = "v" ]; then
        echo "Check version failed!" >&2
        return 1
    fi
    if [ "$newest" = "$current" ]; then
        echo "Already the latest version!" >&2
        return 1
    fi
    if opkg_wrap info ${ISTORE_PKG} | grep -qFm1 "Version: $newest"; then
        do_self_upgrade_0 && return 0
        update_if_outdate || return 1
        do_self_upgrade_0
    else
        update_if_outdate || return 1
        do_self_upgrade_0
    fi
}

check_mtime() {
    find ${OPKG_CONF_DIR}/arch.conf -mtime -1 2>/dev/null | grep -q .  || update
}

wrapped_in_update() {
    check_mtime || return 1
    eval "$@" && return 0
    update_if_outdate || return 1
    eval "$@"
}

step_upgrade() {
    local pkg
    local pkgs=""
    local metapkg=""
    for pkg in $@; do
        if [[ $pkg == app-meta-* ]]; then
            metapkg="$metapkg $pkg"
        else
            pkgs="$pkgs $pkg"
        fi
    done
    if [ -n "$pkgs" ]; then
        opkg_wrap_mirrors upgrade $pkgs || return 1
    fi
    if [ -n "$metapkg" ]; then
        opkg_wrap_mirrors upgrade $metapkg || return 1
    fi
    return 0
}

new_upgrade() {
    check_mtime || return 1
    local metapkg=`echo "$@" | sed 's/ /\n/g' | grep -F app-meta-`
    if [ -z "$metapkg" ] || opkg_wrap info $metapkg | grep -qF not-installed ; then
        true
    else
        update_if_outdate
    fi
    wrapped_in_update step_upgrade "$@"
}

remove() {
    opkg_wrap --autoremove --force-removal-of-dependent-packages remove "$@"
}

autoconf_to_env() {
    local autoconf path enable
    eval "local autoconf=$ISTORE_AUTOCONF"
    export -n ISTORE_AUTOCONF
    export -n ISTORE_DONT_START
    export -n ISTORE_CONF_DIR
    export -n ISTORE_CACHE_DIR
    export -n ISTORE_PUBLIC_DIR
    export -n ISTORE_DL_DIR

    ISTORE_AUTOCONF=$autoconf

    if [ -n "$path" ]; then
        export ISTORE_CONF_DIR="$path/Configs"
        export ISTORE_CACHE_DIR="$path/Caches"
        export ISTORE_PUBLIC_DIR="$path/Public"
        export ISTORE_DL_DIR="$ISTORE_PUBLIC_DIR/Downloads"
    fi
    [ "$enable" = 0 ] && export ISTORE_DONT_START="1"
}

try_autoconf() {
    [ -n "$ISTORE_AUTOCONF" ] || return 0
    autoconf_to_env
    [ -n "$ISTORE_AUTOCONF" ] || return 1
    echo "Auto configure $ISTORE_AUTOCONF"
    /usr/libexec/istorea/${ISTORE_AUTOCONF}.sh
}

try_upgrade_depends() {
    local pkg="$1"
    if [[ $pkg == app-meta-* ]]; then
        local deps=$(grep '^Depends: ' /usr/lib/opkg/info/$pkg.control | busybox sed -e 's/^Depends: //' -e 's/,/\n/g' -e 's/ //g' | grep -vFw libc | xargs echo)
        [ -z "$deps" ] || opkg_wrap_mirrors install $deps
    fi
    return 0
}

usage() {
    echo "usage: is-opkg sub-command [arguments...]"
    echo "where sub-command is one of:"
    echo "      update                          Update list of available packages"
    echo "      upgrade <pkgs>                  Upgrade package(s)"
    echo "      install <pkgs>                  Install package(s)"
    echo "      remove <pkgs|regexp>            Remove package(s)"
    echo "      info [pkg|regexp]               Display all info for <pkg>"
    echo "      list-upgradable                 List installed and upgradable packages"
    echo "      check_self_upgrade              Check iStore upgrade"
    echo "      do_self_upgrade                 Upgrade iStore"
    echo "      arch                            Show libc architecture"
    echo "      opkg                            sys opkg wrap"
}

is_init >/dev/null 2>&1

case $action in
    "update")
        update
    ;;
    "install")
        opkg update
        opkg install "$1"
        #check_space
        #wrapped_in_update opkg_wrap_mirrors install "$@" && try_upgrade_depends "$1" && try_autoconf
    ;;
    "autoconf")
        try_autoconf
    ;;
    "upgrade")
        new_upgrade "$@"
    ;;
    "remove")
        remove "$@" || remove "$@"
    ;;
    "info")
        opkg_wrap info "$@"
    ;;
    "list-upgradable")
        opkg_wrap list-upgradable
    ;;
    "check_self_upgrade")
        check_self_upgrade
    ;;
    "do_self_upgrade")
        check_space
        do_self_upgrade
    ;;
    "arch")
        echo "$ARCH"
    ;;
    "opkg")
        opkg_wrap "$@"
    ;;

    *)
        usage
    ;;
esac
