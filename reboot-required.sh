#!/usr/bin/env sh

if test -r /etc/os-release
then
  # shellcheck disable=1091
  . /etc/os-release
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

openwrt_current_version() {
  uname -r
}

fedora_current_version() {
  uname -r | sed -r 's/.fc[0-9]+.*//'
}

arch_latest_installed() {
  local package
  case "$1" in
    LTS)
      package=linux-lts
      ;;
    VFIO)
      package=linux-vfio
      ;;
    *)
      package=linux
      ;;
  esac
  pacman -Qi "$package" | awk '/Version/ {print $3}'
}

archarm_latest_installed() {
  local package
  case "$1" in
    *)
      package=linux-raspberrypi
      ;;
  esac
  pacman -Qi "$package" | awk '/Version/ {print $3}'
}

openwrt_latest_installed() {
  opkg list-installed | awk '/kernel - / {print $NF}' | cut -d - -f 1
}

fedora_latest_installed() {
  dnf list installed | grep "kernel.$(uname -m)" | \
    awk '{ print $2 }' | sort -rn | head -1 | sed -r 's/.fc[0-9]+$//g'
}

arch_kernel_flavour() {
  case "$(uname -a)" in
    *vfio*) echo VFIO ;;
    *lts*) echo LTS ;;
    *) echo latest ;;
  esac
}

kernel_flavour() {
  case "$ID" in
    arch|antergos)
      arch_kernel_flavour
      ;;
    archarm|turrisos|openwrt|lede|fedora)
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
    openwrt|lede|turrisos)
      current_version=$(openwrt_current_version "$1")
      latest_installed_version=$(openwrt_latest_installed "$1")
      ;;
    fedora)
      current_version=$(fedora_current_version "$1")
      latest_installed_version=$(fedora_latest_installed "$1")
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
  *)
    package_check "$(kernel_flavour)"
    ;;
esac

# vim set ft=sh et ts=2 sw=2 :
