[README.md](https://github.com/user-attachments/files/32212748/README.md)
# netscan.sh

Quick TCP port + banner scanner in pure bash — no `nmap`, no `netcat`,
no external dependencies. Built as a fallback for environments where
`nmap` won't run.

## What it does

- Connects to each port on each target host using bash's built-in
  `/dev/tcp` pseudo-device (a TCP connect scan, same idea as `nmap -sT`).
- For each open port, reads whatever the service sends back on connect
  (banner grab). Silent services on common web ports get a bare
  `GET / HTTP/1.0` request first, to pull back the `Server:` header.
- Runs multiple hosts in parallel (bounded, so it won't fork-bomb your
  shell) and logs results to a timestamped file as it goes.

## Requirements

- `bash` with `/dev/tcp` support (default on Linux/macOS bash, and
  Git Bash / WSL on Windows). No other tools required.

## Usage

```bash
chmod +x netscan.sh

./netscan.sh 192.168.1.0/24          # scan a /24, ports 1-100 (default)
./netscan.sh 192.168.1.0/24 1-1000   # custom port range
./netscan.sh 192.168.1.50            # single host, ports 1-100
./netscan.sh 192.168.1.50 1-65535    # single host, full range
```

Arguments:

| Position | Meaning | Example | Default |
|---|---|---|---|
| 1 | Target — single IP or `/24` CIDR | `192.168.1.0/24` | required |
| 2 | Port range | `1-1000` | `1-100` |

Only `/24` CIDRs are supported (254 hosts). For anything else, pass
individual hosts.

## Output

Printed live to the screen and written to
`netscan_YYYYMMDD_HHMMSS.log` in the current directory:

```
127.0.0.1 is UP
  [22]   SSH-2.0-OpenSSH_8.9p1 Ubuntu-3ubuntu0.4
  [8080] HTTP/1.0 200 OK Server: SimpleHTTP/0.6 Python/3.12.3 ...
  [3306] open (no banner)
```

Hosts with no open ports in the scanned range are omitted from the
output entirely — only live, reachable hosts get printed.

## Tuning

Edit these near the top of the script if needed:

- `CONNECT_TIMEOUT` — seconds to wait for a port to open (default `1`)
- `BANNER_TIMEOUT` — seconds to wait for a banner read (default `1`)
- `MAX_PARALLEL` — number of hosts scanned concurrently (default `40`)

## Known limitations

- **No TLS.** Ports like 443 (HTTPS) will show as open but with no
  readable banner — this is a plain-socket scanner, it can't decode
  encrypted traffic. `nmap`'s `-sV`/`--script ssl-cert` handles this
  with a real TLS stack; replicating that in bash isn't practical.
- **No service fingerprint database.** Version detection here is just
  "read what the service volunteers." `nmap -sV` sends a large table
  of protocol-specific probes and matches responses against thousands
  of known signatures — this script does neither, so some services
  (especially non-HTTP, non-banner-on-connect ones) will report
  `open (no banner)` even though nmap could identify them.
- **`/24` only** for CIDR targets, to keep the host-list logic simple.
- **TCP connect scan only** — no SYN scan, no UDP, no OS fingerprinting.
- Speed scales with host count × port count × timeout; large ranges
  (e.g. full `/24` × 1-65535) will take a while even with parallelism.

## Why this exists

`nmap` occasionally isn't available or won't run in a given lab/demo
environment. This script covers the "is anything alive nearby, and
what's it running" use case with nothing but bash, so it's always
available for quick recon during setup, troubleshooting, or classroom
exercises.
