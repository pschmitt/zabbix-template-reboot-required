#!/usr/bin/env sh

if test -r /etc/os-release
then
  # shellcheck disable=1091
  . /etc/os-release
elif test -r /etc/openwrt_version
then
  ID=openwrt
fi

CACHE_FILE=/tmp/.speedtest.cache

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

ubuntu_current_version() {
  arch_current_version
}

raspbian_current_version() {
  uname -r
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
  dnf list installed kernel | \
    awk '{ print $2 }' | sort -rn | head -1 | sed -r 's/.fc[0-9]+$//g'
}

raspbian_latest_installed() {
  needrestart_cached | \
    sed -nr 's/CRIT - Kernel: (.+)!=([^ ]+) +.+/\2/p'
}

ubuntu_latest_installed() {
  dpkg --list | grep linux-image | \
    awk '{ print $2 }' | grep -v 'linux-image-generic-hwe' | \
    sort -nr | head -1 | \
    sed -r 's/linux-image-(.+)-generic/\1/'
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
    archarm|turrisos|openwrt|lede|fedora|ubuntu|neon|raspbian)
      echo latest
      ;;
    *)
      echo "Unsupported distribution" >&2
      exit 3
      ;;
  esac
}

check_kernel_update() {
  local current_version
  local flavor
  local latest_installed_version

  flavor="$(kernel_flavour)"

  case "$ID" in
    arch|antergos)
      current_version=$(arch_current_version)
      latest_installed_version=$(arch_latest_installed "$flavor")
      ;;
    archarm)
      current_version=$(archarm_current_version)
      latest_installed_version=$(archarm_latest_installed "$flavor")
      ;;
    openwrt|lede|turrisos)
      current_version=$(openwrt_current_version "$flavor")
      latest_installed_version=$(openwrt_latest_installed "$flavor")
      ;;
    fedora)
      current_version=$(fedora_current_version "$flavor")
      latest_installed_version=$(fedora_latest_installed "$flavor")
      ;;
    ubuntu|neon)
      current_version=$(ubuntu_current_version "$flavor")
      latest_installed_version=$(ubuntu_latest_installed "$flavor")
      ;;
    raspbian)
      current_version=$(raspbian_current_version "$flavor")
      latest_installed_version=$(raspbian_latest_installed "$flavor")
      ;;
    *)
      echo "Unsupported distribution" >&2
      exit 3
      ;;
  esac

  if test "$current_version" != "$latest_installed_version"
  then
    echo "Kernel update: $current_version -> $latest_installed_version"
    return 1
  fi
  return 0
}

needrestart_cached() {
  local val

  val="$(cat "$CACHE_FILE" 2>/dev/null)"
  if test -z "$val"
  then
    # echo "CACHE MISS..!" >&2
    # FIXME command -v does not work here for some reason (raspbian)
    if sudo needrestart --help >/dev/null 2>&1
    then
      sudo needrestart -m a -b -n -r l -l -k -p | tee "$CACHE_FILE" /dev/stdout
    else
      echo "ERROR: Please install needrestart" >&2
    fi
  else
    # echo "CACHE HIT" >&2
    echo "$val"
  fi
}

check_extra() {
  local failed=0
  local need_r

  case "$ID" in
    ubuntu|neon|raspbian)
      if test -e /var/run/reboot-required
      then
        echo "/var/run/reboot-required is present on the system"
        failed=1
      fi
      need_r="$(needrestart_cached)"
      if echo "$need_r" | grep -q CRIT
      then
        echo "$need_r"
        failed=1
      fi
      return $failed
      ;;
    fedora)
      needs_r=$(sudo needs-restarting -r)
      if test $? -eq 1
      then
        echo "$needs_r"
        return 1
      fi
      ;;
  esac
}

reboot_check() {
  local kernel
  local message="No reboot required ✔"
  local misc

  kernel=$(check_kernel_update)

  if test $? -ne 0
  then
    message="$kernel"
  fi

  misc=$(check_extra)

  if test $? -ne 0
  then
    if test -z "$message"
    then
      message="$misc"
    else
      message="$message\n\n$misc"
    fi
  fi

  if test "$(echo -e)" != "-e"
  then
    echo -e "$message"
  else
    # printf "%s\n" "$message"
    echo "$message"
  fi
}

rm "$CACHE_FILE" 2>/dev/null
trap 'rm -f "$CACHE_FILE"' EXIT

case "$1" in
  kernel-flavour)
    kernel_flavour
    ;;
  *)
    # TODO Add flags for only checking the kernel, or the services
    # -k: kernel only
    # -s: services only
    # NONE: both
    reboot_check
    ;;
esac

# vim set ft=sh et ts=2 sw=2 :
