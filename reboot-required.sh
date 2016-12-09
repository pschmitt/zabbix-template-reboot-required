#!/usr/bin/env sh

if test -r /etc/os-release
then
    . /etc/os-release
elif test -r /etc/turris-version
then
    ID=turris
elif test -r /etc/openwrt_version
then
    ID=openwrt
fi

usage() {
    echo "Usage: $(basename "$0") [discover|pkg-check]"
}

arch_current_version() {
    uname -r | sed 's/-[^0-9]*$//'
}

archarm_current_version() {
    arch_current_version
}

turris_current_version() {
    arch_current_version
}

openwrt_current_version() {
    arch_current_version
}

arch_latest_installed() {
    case "$1" in
        LTS)
            package=linux-lts
            ;;
        *)
            package=linux
            ;;
    esac
    pacman -Qi "$package" | awk '/Version/ {print $3}'
}

archarm_latest_installed() {
    case "$1" in
        *)
            package=linux-raspberrypi
            ;;
    esac
    pacman -Qi "$package" | awk '/Version/ {print $3}'
}

turris_latest_installed() {
    opkg list-installed | awk '/kernel - / {print $NF}'
}

openwrt_latest_installed() {
    opkg list-installed | awk '/kernel - / {print $NF}' | cut -d - -f 1
}

arch_kernel_flavour() {
    if uname -a | grep -iq lts
    then
        echo LTS
    else
        echo latest
    fi
}

archarm_kernel_flavour() {
    echo latest
}

turris_kernel_flavour() {
    echo latest
}

openwrt_kernel_flavour() {
    echo latest
}

kernel_flavour() {
    case "$ID" in
        arch|antergos)
            arch_kernel_flavour
            ;;
        archarm)
            archarm_kernel_flavour
            ;;
        turris|openwrt)
            echo latest
            ;;
        *)
            echo "Unsupported distribution" >&2
            exit 3
            ;;
    esac
}

package_check() {
    local current_version
    local latest_installed_version
    case "$ID" in
        arch|antergos)
            current_version=$(arch_current_version)
            latest_installed_version=$(arch_latest_installed "$1")
            ;;
        archarm)
            current_version=$(archarm_current_version)
            latest_installed_version=$(archarm_latest_installed "$1")
            ;;
        turris)
            current_version=$(turris_current_version "$1")
            latest_installed_version=$(turris_latest_installed "$1")
            ;;
        openwrt)
            current_version=$(openwrt_current_version "$1")
            latest_installed_version=$(openwrt_latest_installed "$1")
            ;;
        *)
            echo "Unsupported distribution" >&2
            exit 3
            ;;
    esac
    if test "$current_version" != "$latest_installed_version"
    then
        echo "Yes - Kernel update: $current_version -> $latest_installed_version"
    else
        echo No
    fi
}

case "$1" in
    kernel-flavour)
        kernel_flavour
        ;;
    update-available)
        ;;
    *)
        package_check "$(kernel_flavour)"
        ;;
esac

