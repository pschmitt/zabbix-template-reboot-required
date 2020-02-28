#!/usr/bin/env sh

usage() {
  echo "Usage: $(basename "$0") [kernel-flavour] [-m] [-k]"
  echo
  echo "-K: Output the current kernel flavor"
  echo "-k: Only check for updated kernel version (default: enabled)"
  echo "-m: Perform extra checks (default: enabled)"
}

arch_current_version() {
  # Remove the kernel flavor at the end
  # 5.4.22-1-lts -> 5.4.22-1
  uname -r | sed 's/-[^0-9]*$//'
}

archarm_current_version() {
  arch_current_version
}

openwrt_current_version() {
  uname -r
}

fedora_current_version() {
  # Remove the Fedora version and arch at the end
  # 5.5.5-200.fc31.x86_64 -> 5.5.5-200
  uname -r | sed -r 's/.fc[0-9]+.*//'
}

ubuntu_current_version() {
  arch_current_version
}

raspbian_current_version() {
  # Remove the architecture at the end
  # 4.19.97-v7+ -> 4.19.97
  uname -r | sed -r 's/-v.+$//'
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
  local val
  local kernel_file

  case "$(uname -a)" in
    armv7l)
      kernel_file="/boot/kernel7.img"
      ;;
    aarch64)
      kernel_file="/boot/kernel8.img"
      ;;
    *)
      kernel_file="/boot/kernel7l.img"
      ;;
  esac

  if test -e /usr/lib/needrestart/vmlinuz-get-version
  then
    val="$(/usr/lib/needrestart/vmlinuz-get-version "$kernel_file")"
    # echo "Unable to determine current kernel version. Please install needrestart." >&2
  else
    # Download latest vmlinuz-get-version
    curl -qqsL -o /tmp/vmlinuz-get-version \
      https://github.com/liske/needrestart/raw/master/lib/vmlinuz-get-version
    val="$(bash /tmp/vmlinuz-get-version "$kernel_file")"
    rm /tmp/vmlinuz-get-version
  fi
  # Extract version
  # Linux version 4.19.97-v7+ (dom@buildbot) (gcc version[...]  -> 4.19.97
  # Linux version 4.19.97+ (dom@buildbot) (gcc version[...] -> 4.19.97
  echo "$val" | sed -n -r 's/Linux version ([0-9.]+)[-+]v?.*/\1/p'
}

ubuntu_latest_installed() {
  dpkg --list | grep linux-image | \
    grep -v 'linux-image-generic' | \
    awk '{ print $2 }' | \
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
      if sudo needrestart --help >/dev/null 2>&1
      then
        # shellcheck disable=2024
        need_r="$(sudo needrestart -m a -b -n -r l -l -p 2>/dev/null)"
      else
        echo "ERROR: Please install needrestart" >&2
      fi
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
  local reboot_required=0
  local message
  local KERNEL MISC
  local tmp

  if test "$#" -eq 0
  then
    KERNEL=1
    MISC=1
  else
    case "$1" in
      -k|--kernel)
        KERNEL=1
        ;;
      -m|--misc)
        MISC=1
        ;;
    esac
  fi

  if test -n "$KERNEL"
  then
    tmp=$(check_kernel_update)

    if test $? -ne 0
    then
      reboot_required=1
      message="$tmp"
    fi
  fi

  if test -n "$MISC"
  then
    tmp=$(check_extra)

    if test $? -ne 0
    then
      reboot_required=1
      if test -z "$message"
      then
        message="$tmp"
      else
        message="$message\n\n$tmp"
      fi
    fi
  fi

  if test "$reboot_required" = "0"
  then
    message="No reboot required ✔"
  fi

  # shellcheck disable=2039
  if test "$(echo -e)" != "-e"
  then
    echo -e "$message"
  else
    # printf "%s\n" "$message"
    echo "$message"
  fi
}

if test -r /etc/os-release
then
  # shellcheck disable=1091
  . /etc/os-release
# Old (pre 19.07.1) OpenWRT version don't carry an /etc/os-release
elif test -r /etc/openwrt_version
then
  ID=openwrt
fi

case "$1" in
  help|h|--help|-h)
    usage
    ;;
  -K)
    kernel_flavour
    ;;
  *)
    # -k: kernel only
    # -m: Misc. services only
    # NONE: both
    if test "$#" -gt 1
    then
      shift
    fi
    reboot_check "$@"
    ;;
esac

# vim set ft=sh et ts=2 sw=2 :
