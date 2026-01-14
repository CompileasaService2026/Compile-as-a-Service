#!/bin/bash
default() {
  # Usage: default VAR "value"
  local var="$1"
  local val="$2"

  if [[ -z "${!var:-}" ]]; then
    printf -v "$var" '%s' "$val"
  fi
}
require() {
  # Usage: require VAR
  local var="$1"

  if [[ -z "${!var:-}" ]]; then
    echo "Error: Missing required variable: $var" >&2
    exit 1
  fi
}
detect_distro() {
  if command -v lsb_release >/dev/null 2>&1; then
    lsb_release -si | tr '[:upper:]' '[:lower:]'
  elif [[ -f /etc/os-release ]]; then
    . /etc/os-release
    echo "${ID}"
  else
    return 1
  fi
}
detect_distro_version() {
  if command -v lsb_release >/dev/null 2>&1; then
    lsb_release -rs
  elif [[ -f /etc/os-release ]]; then
    . /etc/os-release
    echo "${VERSION_ID}"
  else
    return 1
  fi
}
normalize_distro() {
  case "$1" in
    debian|ubuntu|centos|fedora) echo "$1" ;;
    amazonlinux|amzn|amazon)     echo "amazonlinux" ;;
    rocky)  echo "rocky" ;;
    almalinux)  echo "almalinux" ;;
    *) echo "$1" ;;
  esac
}
default DISTRO "$(detect_distro)"
default DISTRO_VERSION "$(detect_distro_version)"
default KVER "$(uname -r)"
DISTRO="$(normalize_distro "$DISTRO")"
require DISTRO
require DISTRO_VERSION
require KVER

echo "DISTRO: $DISTRO"
echo "DISTRO_VER: $DISTRO_VERSION"
echo "KERNEL: $KVER"
