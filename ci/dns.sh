#!/bin/sh
#
# A name that stops resolving has its peers dropped, not kept.
#
# This is the one thing t/ cannot do: it needs a name whose resolution
# changes under a running nginx, and the module resolves through
# getaddrinfo(3), so the lever is /etc/hosts.  A peer left pointing at an
# address that DNS no longer gives out is a peer pointing at whatever took
# that address next, which is why the numbers here are the oracle, not the
# status code.  (upstream issue #9)
#
# usage: ci/dns.sh <nginx binary>
#
# Set DNS_LOAD_MODULES to the .so path to test a loadable build; DNS_PORT
# moves the listener.  Needs root, because it edits /etc/hosts; it restores
# it on the way out and skips (without failing) when it is not root.

set -eu

NGINX=${1:?path to the nginx binary missing}
SRC=$(cd "$(dirname "$0")/.." && pwd)
WORK=${CI_WORK:-$SRC/ci-work}/dns
PORT=${DNS_PORT:-18823}
NAME=dyntest.ci.invalid
ADDR=127.0.0.9

command -v curl > /dev/null || { echo "curl(1) is needed" >&2; exit 2; }

if [ "$(id -u)" != 0 ]; then
	echo "ci/dns.sh: needs root to steer name resolution via /etc/hosts; skipping" >&2
	exit 0
fi

rm -rf "$WORK"
mkdir -p "$WORK/conf" "$WORK/logs"

fail=0
note() { echo "  $1" >&2; fail=1; }

# Drop every line mentioning the name from /etc/hosts.  Not sed -i, which
# wants a backup suffix on the BSDs and none on GNU.
hosts_del() {
	sed "/$NAME/d" /etc/hosts > "$WORK/hosts.tmp" &&
		cat "$WORK/hosts.tmp" > /etc/hosts
}

# Put the name in /etc/hosts and take it back out no matter how we leave.
hosts_bak=$WORK/hosts.bak
cp /etc/hosts "$hosts_bak"
cleanup() {
	cp "$hosts_bak" /etc/hosts 2>/dev/null || true
	[ -f "$WORK/logs/nginx.pid" ] &&
		kill -QUIT "$(cat "$WORK/logs/nginx.pid")" 2>/dev/null || true
}
trap cleanup EXIT INT TERM

hosts_del
echo "$ADDR $NAME" >> /etc/hosts

ngx_load=
for so in ${DNS_LOAD_MODULES:-}; do
	ngx_load="load_module $so;"
done

ngx_user=
if [ "$(id -u)" = 0 ]; then
	ngx_user="user root $(id -gn);"
fi

cat > "$WORK/conf/nginx.conf" <<CONF
$ngx_load
$ngx_user
daemon on;
master_process on;
worker_processes 1;
pid $WORK/logs/nginx.pid;
error_log $WORK/logs/error.log info;
events { worker_connections 64; }
http {
    access_log off;
    upstream backends {
        zone backends 128k;
        dns_update 1s;
        server 127.0.0.1:1;
    }
    server {
        listen 127.0.0.1:$PORT;
        location /dynamic { dynamic_upstream; }
    }
}
CONF

"$NGINX" -t -c "$WORK/conf/nginx.conf" -p "$WORK" > "$WORK/t.log" 2>&1 ||
	{ cat "$WORK/t.log"; exit 1; }
"$NGINX" -c "$WORK/conf/nginx.conf" -p "$WORK"
sleep 1

base="http://127.0.0.1:$PORT/dynamic?upstream=backends"

curl -s --max-time 5 "$base&add=&server=$NAME" > /dev/null || true
sleep 2

echo "--- the name is resolved and its address is in the pool ---"
if curl -s --max-time 5 "$base" | grep -q "$ADDR"; then
	echo "  $NAME -> $ADDR"
else
	note "the resolved address $ADDR is not in the pool"
	curl -s --max-time 5 "$base" >&2
fi

echo "--- the name stops resolving ---"
hosts_del
echo "  removed $NAME from /etc/hosts"
sleep 3

echo "--- and its stale address is dropped, not kept ---"
if curl -s --max-time 5 "$base" | grep -q "$ADDR"; then
	note "the stale address $ADDR is still in the pool"
	curl -s --max-time 5 "$base" >&2
else
	echo "  $ADDR is gone"
fi

echo "--- the log records the removal and nothing died ---"
if grep -q "removed server $NAME" "$WORK/logs/error.log"; then
	echo "  removed server $NAME peer $ADDR:..."
else
	note "no removal of $NAME in the log"
fi
if grep -E '\[alert\]|\[emerg\]|exited on signal' "$WORK/logs/error.log"; then
	note "the log carries an alert, an emerg or a worker that died"
fi

if [ "$fail" -ne 0 ]; then
	echo >&2
	echo "--- the error log, last 20 lines ---" >&2
	tail -20 "$WORK/logs/error.log" >&2 2>/dev/null || true
fi

exit $fail
