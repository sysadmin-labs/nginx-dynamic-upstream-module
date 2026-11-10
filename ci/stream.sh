#!/bin/sh
#
# Drive the stream module through the API and read back what it did.
#
# The module is one templated body serving http and stream, and the http
# t/ suite already exercises that body; what it cannot reach is the stream
# half -- a second ngx_module_t, of a different type, registered into a
# different subsystem.  This builds a stream upstream, lists it, adds to it
# and removes from it through the same HTTP endpoint with stream=, so the
# stream peers are the oracle.  No Lua, so it runs anywhere the http suite
# runs.
#
# usage: ci/stream.sh <nginx binary>
#
# Set STREAM_LOAD_MODULES to the .so paths, space separated, to test a
# loadable build; STREAM_HTTP_PORT and STREAM_PORT move the listeners.

set -eu

NGINX=${1:?path to the nginx binary missing}
SRC=$(cd "$(dirname "$0")/.." && pwd)
WORK=${CI_WORK:-$SRC/ci-work}/stream
HPORT=${STREAM_HTTP_PORT:-18824}
SPORT=${STREAM_PORT:-18825}

command -v curl > /dev/null || { echo "curl(1) is needed" >&2; exit 2; }

rm -rf "$WORK"
mkdir -p "$WORK/conf" "$WORK/logs"

fail=0
note() { echo "  $1" >&2; fail=1; }

ngx_load=
for so in ${STREAM_LOAD_MODULES:-}; do
	ngx_load="$ngx_load
load_module $so;"
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
stream {
    upstream sbackends {
        zone sbackends 128k;
        server 127.0.0.1:19001;
        server 127.0.0.1:19002;
    }
    server {
        listen 127.0.0.1:$SPORT;
        proxy_pass sbackends;
    }
}
http {
    access_log off;
    server {
        listen 127.0.0.1:$HPORT;
        location /dynamic { dynamic_upstream; }
    }
}
CONF

"$NGINX" -t -c "$WORK/conf/nginx.conf" -p "$WORK" > "$WORK/t.log" 2>&1 ||
	{ cat "$WORK/t.log"; exit 1; }
"$NGINX" -c "$WORK/conf/nginx.conf" -p "$WORK"
sleep 1
trap '[ -f "$WORK/logs/nginx.pid" ] && kill -QUIT "$(cat "$WORK/logs/nginx.pid")" 2>/dev/null || true' EXIT INT TERM

base="http://127.0.0.1:$HPORT/dynamic?upstream=sbackends&stream="

echo "--- the stream upstream is listed through the http endpoint ---"
got=$(curl -s --max-time 5 "$base")
if printf '%s' "$got" | grep -q '127.0.0.1:19001' &&
   printf '%s' "$got" | grep -q '127.0.0.1:19002'; then
	echo "  19001 and 19002 are there"
else
	note "the two stream peers are not both listed"; printf '%s\n' "$got" >&2
fi

echo "--- a peer added to the stream upstream, ordered by address ---"
got=$(curl -s --max-time 5 "$base&add=&server=127.0.0.1:19003")
if printf '%s' "$got" | grep -q '127.0.0.1:19003'; then
	# ordered: 19003 is the last line (upstream #10)
	last=$(printf '%s' "$got" | sed -n '$s/.*\(127.0.0.1:19003\).*/\1/p')
	[ "$last" = "127.0.0.1:19003" ] && echo "  19003 added, last in order" ||
		note "19003 added but not in order"
else
	note "the stream add did not take"; printf '%s\n' "$got" >&2
fi

echo "--- and removed again ---"
got=$(curl -s --max-time 5 "$base&remove=&server=127.0.0.1:19003")
if printf '%s' "$got" | grep -q '127.0.0.1:19003'; then
	note "19003 is still there after remove"; printf '%s\n' "$got" >&2
else
	echo "  19003 is gone"
fi

echo "--- the stream and http peer lists are independent ---"
# A matching http upstream does not exist, so the same query without stream=
# must not answer with the stream peers.
h=$(curl -s --max-time 5 "http://127.0.0.1:$HPORT/dynamic?upstream=sbackends")
if printf '%s' "$h" | grep -q '19001'; then
	note "an http query returned the stream peers"
else
	echo "  http side does not see the stream upstream"
fi

echo "--- nothing in the error log that should not be there ---"
if grep -E '\[alert\]|\[emerg\]|exited on signal' "$WORK/logs/error.log"; then
	note "the log carries an alert, an emerg or a worker that died"
else
	echo "  no alert, no emerg, no signal"
fi

if [ "$fail" -ne 0 ]; then
	echo >&2
	echo "--- the error log, last 20 lines ---" >&2
	tail -20 "$WORK/logs/error.log" >&2 2>/dev/null || true
fi

exit $fail
