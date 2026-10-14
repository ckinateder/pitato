#!/bin/sh
# Renders the Squid allowlist from env, then starts Squid in the foreground.
# Allowed: the host in PI_BASE_URL, plus comma-separated ALLOWED_DOMAINS.
# ALLOWED_DOMAINS=* allows every host and port (the only way to get open network).
set -eu

[ -n "${PI_BASE_URL:-}" ] || { echo "error: PI_BASE_URL is required" >&2; exit 1; }

# Reduce http(s)://[user@]host[:port]/path to host and port
scheme="${PI_BASE_URL%%://*}"
authority="${PI_BASE_URL#*://}"
authority="${authority%%/*}"
authority="${authority##*@}"
host="${authority%%:*}"
case "$authority" in
    *:*) port="${authority#*:}" ;;
    *)   if [ "$scheme" = "http" ]; then port=80; else port=443; fi ;;
esac

# Values are written into squid.conf; refuse anything that isn't a plain host or port.
extra_domains="$(echo "${ALLOWED_DOMAINS:-}" | tr ',' ' ')"
# Match before the loop below, where an unquoted * would glob-expand
allow_all=
case " $extra_domains " in *" * "*) allow_all=1; extra_domains= ;; esac
for value in "$host" $extra_domains; do
    case "$value" in
        ''|*[!A-Za-z0-9._-]*) echo "error: bad host '$value' in PI_BASE_URL/ALLOWED_DOMAINS" >&2; exit 1 ;;
    esac
done
case "$port" in
    ''|*[!0-9]*) echo "error: bad port '$port' in PI_BASE_URL" >&2; exit 1 ;;
esac

# Squid matches IPs with `dst`, names with `dstdomain`
case "$host" in
    *[!0-9.]*) model_acl="dstdomain $host" ;;
    *)         model_acl="dst $host" ;;
esac

conf=/tmp/squid.conf
cat > "$conf" <<EOF
http_port 3128
acl allowed $model_acl
EOF
# Leading dot (.example.com) also matches subdomains
[ -z "$extra_domains" ] || echo "acl allowed dstdomain $extra_domains" >> "$conf"
if [ -n "$allow_all" ]; then
    echo "http_access allow all" >> "$conf"
else
    cat >> "$conf" <<EOF
acl allowed_ports port 80 443 $port
http_access deny !allowed_ports
http_access allow allowed
http_access deny all
EOF
fi
cat >> "$conf" <<EOF
cache deny all
via off
forwarded_for delete
pid_filename none
pinger_enable off
access_log stdio:/dev/stdout
cache_log /dev/stderr
coredump_dir /tmp
EOF

exec squid -N -f "$conf"
