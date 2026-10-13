#!/usr/bin/env bash
# Smoke tests for the egress proxy, pi-here flags and rtk. Needs Docker, a built
# image (docker compose build) and a working .env.
# Temporarily edits .env and recreates the proxy; both are restored on exit.
set -uo pipefail
cd "$(dirname "$(readlink -f "$0")")/.."

fails=0
check() { # description, expected substring, actual
    if [[ $3 == *"$2"* ]]; then echo "ok   $1"; else echo "FAIL $1 (wanted '$2', got '$3')"; fails=$((fails + 1)); fi
}

backup="$(mktemp)"
cp .env "$backup"
trap 'cp "$backup" .env; docker compose up -d --wait proxy >/dev/null 2>&1; rm -f "$backup"' EXIT

in_pi() { docker compose run --rm -T --entrypoint bash pi -c "$1" 2>/dev/null | tr -d '\r'; }
# First line of the proxy's reply to a CONNECT, e.g. "HTTP/1.1 403 Forbidden"
connect() { in_pi "exec 3<>/dev/tcp/proxy/3128; printf 'CONNECT $1 HTTP/1.1\r\nHost: $1\r\n\r\n' >&3; timeout 8 head -1 <&3"; }
# Rewrites ALLOWED_DOMAINS (and optionally PI_BASE_URL) in .env, then restarts the proxy
set_env() { # ALLOWED_DOMAINS [PI_BASE_URL]
    grep -v -E '^(ALLOWED_DOMAINS|PI_BASE_URL)=' "$backup" > .env
    printf '\nALLOWED_DOMAINS=%s\n' "$1" >> .env
    if [[ -z ${2+x} ]]; then grep -E '^PI_BASE_URL=' "$backup" >> .env; else printf 'PI_BASE_URL=%s\n' "$2" >> .env; fi
    docker compose up -d --wait proxy >/dev/null 2>&1
}

url="$(grep -E '^PI_BASE_URL=' "$backup" | cut -d= -f2-)"
model_hostport="${url#*://}"; model_hostport="${model_hostport%%/*}"
[[ $model_hostport == *:* ]] || { [[ $url == http://* ]] && model_hostport+=:80 || model_hostport+=:443; }

echo "== pi-here help"
check "-h prints usage" "Usage: pi-here" "$(./pi-here -h)"
check "--help prints usage" "Usage: pi-here" "$(./pi-here --help)"

echo "== proxy: default allowlist"
set_env ""
check "model host allowed" "200" "$(connect "$model_hostport")"
check "other host refused" "403" "$(connect example.com:443)"
check "other port refused" "403" "$(connect example.com:22)"
check "no route around proxy" "blocked" "$(in_pi 'timeout 4 bash -c "exec 3<>/dev/tcp/1.1.1.1/443" 2>/dev/null && echo reachable || echo blocked')"

echo "== proxy: ALLOWED_DOMAINS"
set_env "example.com,.github.com"
check "exact domain allowed" "200" "$(connect example.com:443)"
check "exact domain excludes subdomain" "403" "$(connect www.example.com:443)"
check "leading dot allows subdomain" "200" "$(connect api.github.com:443)"
check "unlisted host refused" "403" "$(connect evil.com:443)"

echo "== proxy: bad config fails loudly"
set_env 'foo.com;rm' && failed=no || failed=yes
check "bad ALLOWED_DOMAINS: up --wait fails" "yes" "$failed"
check "bad ALLOWED_DOMAINS: error logged" "error: bad host" "$(docker compose logs proxy 2>&1)"
set_env "" "" && failed=no || failed=yes
check "empty PI_BASE_URL: up --wait fails" "yes" "$failed"
check "empty PI_BASE_URL: error logged" "PI_BASE_URL is required" "$(docker compose logs proxy 2>&1)"
cp "$backup" .env; docker compose up -d --wait proxy >/dev/null 2>&1

echo "== pi-here --open"
# pi-here needs a tty (compose sets tty: true), so go through script(1)
open_log="$(mktemp)"
script -qec "./pi-here --open --shell -c 'timeout 5 bash -c \"exec 3<>/dev/tcp/1.1.1.1/443\" && echo OPEN-REACHABLE; echo proxyvars=\$(env | grep -ci proxy)'" "$open_log" >/dev/null 2>&1
open_out="$(tr -d '\r\0' < "$open_log")"; rm -f "$open_log"
check "--open reaches the internet" "OPEN-REACHABLE" "$open_out"
check "--open sets no proxy env" "proxyvars=0" "$open_out"

echo "== rtk"
check "extension readable by the container user" "readable" "$(in_pi 'test -r /opt/rtk/rtk.ts && echo readable')"
check "git status is rewritten" "rtk git status" "$(in_pi 'rtk rewrite "git status"')"
check "unknown command is not rewritten" "none" "$(in_pi 'out=$(rtk rewrite "echo hi") && echo "$out" || echo none')"

echo
if [[ $fails -eq 0 ]]; then echo "all passed"; else echo "$fails failed"; exit 1; fi
