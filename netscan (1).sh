#!/usr/bin/env bash
#
# netscan.sh — quick neighbor-box discovery, no nmap/netcat required
# Uses bash's built-in /dev/tcp for TCP connect scans, plus a light
# banner grab on each open port so students get a service string to
# report, not just a bare port number.
#
# Usage:
#   ./netscan.sh                         # interactive — prompts for target/ports
#   ./netscan.sh 192.168.1.0/24          # scan whole /24, ports 1-100
#   ./netscan.sh 192.168.1.0/24 1-1000   # custom port range
#   ./netscan.sh 192.168.1.50            # scan a single host
#
# Output: live hosts with open ports + grabbed banners, written to
# screen and a timestamped log file in the current directory.
#
# Note: this is a plaintext banner grab (connect, optionally send a
# bare HTTP GET, read whatever comes back). It won't decode TLS, so
# HTTPS-only ports (443 etc.) will show as open but banner-less or
# garbled. That's a hard limit of doing this without a real TLS
# library — nmap's -sV has the same probe-based approach under the
# hood, just a much bigger signature set.

set -u

TARGET="${1:-}"
PORT_RANGE="${2:-}"
CONNECT_TIMEOUT=1        # seconds per port connect attempt
BANNER_TIMEOUT=1         # seconds to wait for a banner read
MAX_PARALLEL=40          # concurrent host scans
LOGFILE="netscan_$(date +%Y%m%d_%H%M%S).log"

# --- interactive fallback: no target given on the command line -----------
if [[ -z "$TARGET" ]]; then
    echo "netscan.sh — interactive mode (run with args instead to skip this)"
    echo "  e.g. ./netscan.sh 192.168.1.0/24 1-100"
    echo
    read -rp "Target (single IP or /24 CIDR, e.g. 192.168.1.0/24): " TARGET
    if [[ -z "$TARGET" ]]; then
        echo "No target entered, exiting."
        exit 1
    fi
    read -rp "Port range [default 1-100]: " PORT_RANGE
fi

PORT_RANGE="${PORT_RANGE:-1-100}"

PORT_START="${PORT_RANGE%-*}"
PORT_END="${PORT_RANGE#*-}"

# --- build the host list -----------------------------------------------
hosts=()

if [[ "$TARGET" == */* ]]; then
    base="${TARGET%/*}"
    cidr="${TARGET#*/}"
    if [[ "$cidr" != "24" ]]; then
        echo "Only /24 CIDR is supported by this simple script (got /$cidr)."
        echo "Pass a single host instead, or a /24 like 192.168.1.0/24."
        exit 1
    fi
    prefix="${base%.*}"
    for i in $(seq 1 254); do
        hosts+=("${prefix}.${i}")
    done
else
    hosts+=("$TARGET")
fi

echo "Target(s): ${#hosts[@]} host(s) | Ports: ${PORT_START}-${PORT_END} | Log: $LOGFILE"
echo "----------------------------------------------------------------"

# --- probe one port: connect, optionally nudge, read whatever comes back -
# Single connection does double duty as the open/closed check AND the
# banner grab, so we don't hit the same port twice.
probe_port() {
    local host="$1" port="$2" banner=""

    exec 3<>"/dev/tcp/${host}/${port}" 2>/dev/null || return 1

    # A handful of ports stay silent until spoken to.
    case "$port" in
        80|8080|8000|8888|8081)
            printf 'GET / HTTP/1.0\r\nHost: %s\r\n\r\n' "$host" >&3 2>/dev/null
            ;;
    esac

    banner=$(timeout "$BANNER_TIMEOUT" head -c 300 <&3 2>/dev/null \
             | tr -d '\000' | tr '\r\n' '  ' | sed -E 's/ +/ /g; s/^ //; s/ $//')

    exec 3>&- 2>/dev/null
    exec 3<&- 2>/dev/null

    printf '%s' "$banner"
    return 0
}

# --- scan one host, all requested ports ---------------------------------
scan_host() {
    local host="$1"
    local results=()

    for ((port=PORT_START; port<=PORT_END; port++)); do
        local banner
        if banner=$(probe_port "$host" "$port"); then
            if [[ -n "$banner" ]]; then
                results+=("  [$port] ${banner:0:120}")
            else
                results+=("  [$port] open (no banner)")
            fi
        fi
    done

    if [[ ${#results[@]} -gt 0 ]]; then
        {
            echo "$host is UP"
            printf '%s\n' "${results[@]}"
        } | tee -a "$LOGFILE"
    fi
}

export -f scan_host probe_port
export PORT_START PORT_END LOGFILE CONNECT_TIMEOUT BANNER_TIMEOUT

# --- run scans with bounded parallelism ----------------------------------
running=0
for host in "${hosts[@]}"; do
    ( timeout "$(( (CONNECT_TIMEOUT + BANNER_TIMEOUT) * (PORT_END - PORT_START + 1) + 2))" bash -c "scan_host '$host'" ) 2>/dev/null &
    ((running++))
    if (( running >= MAX_PARALLEL )); then
        wait -n
        ((running--))
    fi
done
wait

echo "----------------------------------------------------------------"
echo "Scan complete. Results saved to $LOGFILE"
