#!/bin/sh
#
# Build an nginx that carries this module.  The continuous integration
# workflow runs this, and so can you:
#
#     ci/build.sh 1.31.6 /tmp/nginx-test
#     TEST_NGINX_BINARY=/tmp/nginx-test/sbin/nginx prove -r t/
#
# usage: ci/build.sh <nginx version> <install prefix> [mode]
#
#     static    the module built into the binary (the default)
#     dynamic   the module built as a loadable object
#
# nginx and echo-nginx-module land in $CI_WORK, ./ci-work by default, and
# are reused on a second run.  A warning from this module's own source
# fails the build.

set -eu

NGINX=${1:?nginx version missing}
PREFIX=${2:?install prefix missing}
MODE=${3:-static}

SRC=$(cd "$(dirname "$0")/.." && pwd)
WORK=${CI_WORK:-$SRC/ci-work}
JOBS=$(getconf _NPROCESSORS_ONLN 2>/dev/null || echo 2)

# Every version, digest and commit comes from one file, so a run here pins
# exactly what a continuous integration run pins.  Deliberately not
# overridable from the environment: a version and the digest that proves it
# have to move together, and an override would separate them.
PINS=$SRC/.github/versions.env
[ -r "$PINS" ] || {
	echo "ci/build.sh: cannot read $PINS" >&2
	exit 1
}
# shellcheck source=../.github/versions.env
. "$PINS"

mkdir -p "$WORK"

# echo-nginx-module, pinned to a commit.  The t/ suite builds its requests
# with echo_location / echo_sleep, so the test nginx needs it.
echo_dir=$WORK/echo-nginx-module
if [ ! -d "$echo_dir" ]; then
	git clone --quiet https://github.com/openresty/echo-nginx-module.git \
		"$echo_dir"
fi
git -C "$echo_dir" fetch --quiet --depth 100 origin "$ECHO_TAG" 2>/dev/null || true
git -C "$echo_dir" checkout --quiet "$ECHO_COMMIT"
got=$(git -C "$echo_dir" rev-parse HEAD)
if [ "$got" != "$ECHO_COMMIT" ]; then
	echo "ci/build.sh: echo-nginx-module $ECHO_TAG is not at its pinned commit" >&2
	echo "  expected $ECHO_COMMIT" >&2
	echo "  got      $got" >&2
	exit 1
fi

tarball=$WORK/nginx-$NGINX.tar.gz
url=https://nginx.org/download/nginx-$NGINX.tar.gz

# The digest is looked up by version, so building another release means
# writing its pin down first.  A missing pin is refused rather than waved
# through: a check that skips itself when it has nothing to compare against
# is not a check, it only looks like one.
key=NGINX_$(echo "$NGINX" | tr . _)_SHA256
eval "want=\${$key:-}"
if [ -z "$want" ]; then
	echo "ci/build.sh: no sha256 for nginx $NGINX in $PINS" >&2
	echo "ci/build.sh: harvest one with" >&2
	echo "    ci/fetch-verify.sh $url - $tarball" >&2
	exit 1
fi

"$SRC/ci/fetch-verify.sh" "$url" "$want" "$tarball"

rm -rf "$WORK/nginx-$NGINX"
tar xzf "$tarball" -C "$WORK"

case $MODE in
static)
	how=--add-module
	;;
dynamic)
	how=--add-dynamic-module
	;;
*)
	echo "ci/build.sh: unknown mode \"$MODE\"" >&2
	exit 2
	;;
esac

cd "$WORK/nginx-$NGINX"

# --with-stream carries the stream module; --with-threads gives the dns
# sync its thread pool (the module also runs without it).
# --with-http_ssl_module is needed by neither module here; it stays so that
# every repository in this organization builds its nginx the same way.

# the sanitizer workflow builds through this script as well, so that
# there is one build path and not two that drift apart
set --
if [ -n "${CI_CC_OPT:-}" ]; then
	set -- "$@" --with-cc-opt="$CI_CC_OPT"
fi
if [ -n "${CI_LD_OPT:-}" ]; then
	set -- "$@" --with-ld-opt="$CI_LD_OPT"
fi

echo "--- configure ($MODE) ---"
./configure --prefix="$PREFIX" --with-debug --with-http_ssl_module \
	--with-stream --with-threads \
	--add-module="$echo_dir" "$how=$SRC" "$@" \
	> "$WORK/configure-$NGINX.log" 2>&1 ||
	{ tail -30 "$WORK/configure-$NGINX.log"; exit 1; }

echo "--- make -j$JOBS ---"
make -j"$JOBS" > "$WORK/make-$NGINX.log" 2>&1 ||
	{ tail -40 "$WORK/make-$NGINX.log"; exit 1; }

if grep -E "$SRC/src/.*warning" "$WORK/make-$NGINX.log"; then
	echo "ci/build.sh: the compiler warned about this module, see above" >&2
	exit 1
fi

make install > /dev/null
"$PREFIX/sbin/nginx" -v
