# ngx_dynamic_upstream

[![Build & Test][build-test-badge]][build-test-link]
[![FreeBSD][freebsd-badge]][freebsd-link]
[![Stream][stream-badge]][stream-link]
[![DNS][dns-badge]][dns-link]
[![Reload][reload-badge]][reload-link]
[![A/UBSan][sanitizers-badge]][sanitizers-link]
[![Valgrind][valgrind-badge]][valgrind-link]
[![CodeQL][codeql-badge]][codeql-link]
[![Lint][lint-badge]][lint-link]

[build-test-badge]: https://github.com/sysadmin-labs/nginx-dynamic-upstream-module/actions/workflows/build-test.yml/badge.svg
[build-test-link]: https://github.com/sysadmin-labs/nginx-dynamic-upstream-module/actions/workflows/build-test.yml
[freebsd-badge]: https://github.com/sysadmin-labs/nginx-dynamic-upstream-module/actions/workflows/freebsd.yml/badge.svg
[freebsd-link]: https://github.com/sysadmin-labs/nginx-dynamic-upstream-module/actions/workflows/freebsd.yml
[stream-badge]: https://github.com/sysadmin-labs/nginx-dynamic-upstream-module/actions/workflows/stream.yml/badge.svg
[stream-link]: https://github.com/sysadmin-labs/nginx-dynamic-upstream-module/actions/workflows/stream.yml
[dns-badge]: https://github.com/sysadmin-labs/nginx-dynamic-upstream-module/actions/workflows/dns.yml/badge.svg
[dns-link]: https://github.com/sysadmin-labs/nginx-dynamic-upstream-module/actions/workflows/dns.yml
[reload-badge]: https://github.com/sysadmin-labs/nginx-dynamic-upstream-module/actions/workflows/reload.yml/badge.svg
[reload-link]: https://github.com/sysadmin-labs/nginx-dynamic-upstream-module/actions/workflows/reload.yml
[sanitizers-badge]: https://github.com/sysadmin-labs/nginx-dynamic-upstream-module/actions/workflows/sanitizers.yml/badge.svg
[sanitizers-link]: https://github.com/sysadmin-labs/nginx-dynamic-upstream-module/actions/workflows/sanitizers.yml
[valgrind-badge]: https://github.com/sysadmin-labs/nginx-dynamic-upstream-module/actions/workflows/valgrind.yml/badge.svg
[valgrind-link]: https://github.com/sysadmin-labs/nginx-dynamic-upstream-module/actions/workflows/valgrind.yml
[codeql-badge]: https://github.com/sysadmin-labs/nginx-dynamic-upstream-module/actions/workflows/codeql.yml/badge.svg
[codeql-link]: https://github.com/sysadmin-labs/nginx-dynamic-upstream-module/actions/workflows/codeql.yml
[lint-badge]: https://github.com/sysadmin-labs/nginx-dynamic-upstream-module/actions/workflows/lint.yml/badge.svg
[lint-link]: https://github.com/sysadmin-labs/nginx-dynamic-upstream-module/actions/workflows/lint.yml

`ngx_dynamic_upstream` is the module for operating upstreams dynamically with HTTP APIs
such as [`ngx_http_upstream_conf`](http://nginx.org/en/docs/http/ngx_http_upstream_conf_module.html).

This module also supports stream upstreams manipulation.

Online reconfiguration upstream addresses from DNS by hostname without reloads.

# Requirements

`ngx_dynamic_upstream` requires the `zone` directive in the `upstream` context.

# Status

Production ready.

# Directives

## dynamic_upstream

|Syntax |dynamic_upstream|
|-------|----------------|
|Default|-|
|Context|location|

## dynamic_state_file

|Syntax |dynamic_state_file file|
|-------|----------------|
|Default|-|
|Context|upstream|

Persistent state of upstream.  
Example: dynamic_state_file backend.peers;  

If you want to add servers in upstream, you **MUST** create backend.peers file manually and add these servers into it.  
Add servers directly into `upstream` section is incorrect and you will see fake 0.0.0.0:1 server in list and backend.peers file.

## dns_update

|Syntax |dns_update 60s [thread pool]|
|-------|----------------|
|Default|-|
|Context|upstream|

Background synchronization hosts addresses by DNS.

## dns_add_down

|Syntax |dns_add_down on/off|
|-------|----------------|
|Default|off|
|Context|upstream|

Add new peers in down state.

## dns_ipv6

|Syntax |dns_ipv6 on|
|-------|----------------|
|Default|-|
|Context|upstream|

Include IPv6 addresses.

# Quick Start

```nginx

http {
    upstream backends {
        zone zone_for_backends 1m;
        server 127.0.0.1:6001;
        server 127.0.0.1:6002;
        server 127.0.0.1:6003;
    }

    # Persistent state
    # DON't add servers directly into upstream section
    # Add servers into backend.peers file
    upstream backends2 {
        zone zone_for_backends2 1m;
        dynamic_state_file backend.peers;
    }

    server {
        listen 6000;

        location /dynamic {
            allow 127.0.0.1;
            deny all;
            dynamic_upstream;
        }

        location / {
            proxy_pass http://backends;
        }
    }
}

stream {
    upstream backends_stream {
        zone zone_for_backends_stream 1m;
        server 127.0.0.1:6001;
        server 127.0.0.1:6002;
        server 127.0.0.1:6003;
    }

    server {
        listen 6001;
        proxy_pass backends_stream;
    }
}
```

## DNS background updates

```nginx
http {
    upstream mail {
        zone mail 1m;
        dns_update 60s;
        dns_ipv6 off;
        server mail.ru;
        server google.com backup;
    }

    server {
        listen 6000;

        location /dynamic {
            allow 127.0.0.1;
            deny all;
            dynamic_upstream;
        }

        location / {
            proxy_pass http://backends;
        }
    }
}
```

## Starting when a name cannot be resolved

nginx resolves every `server name;` in an `upstream` block once, while it
reads the configuration, and refuses to start if a name does not resolve
(`host not found in upstream`).  That is nginx's own behaviour, not this
module's, and listing names statically ties the start of nginx to DNS.

For an upstream whose members come and go — and so may all be absent when
nginx starts — do not list the names statically.  Give the upstream a
`dynamic_state_file`, which seeds it with a `server 0.0.0.0:1 down;`
placeholder so it is always valid, together with a `dns_update`, and add
the names at run time through the API:

```nginx
http {
    upstream backends {
        zone backends 1m;
        dns_update 10s;
        dynamic_state_file backends.peers;
    }
}
```

```bash
$ curl "http://127.0.0.1:6000/dynamic?upstream=backends&add=&server=myhost.local"
```

nginx then starts whether or not the names resolve; `dns_update` keeps
their addresses in sync, and a name that stops resolving has its peers
removed rather than left pointing at an address that may have been reused.

# HTTP APIs

You can operate upstreams dynamically with HTTP APIs.

## list

```bash
$ curl "http://127.0.0.1:6000/dynamic?upstream=mail"
server mail.ru addr=217.69.139.201:80;
server mail.ru addr=94.100.180.201:80;
server mail.ru addr=217.69.139.200:80;
server mail.ru addr=94.100.180.200:80;
server google.com addr=173.194.73.139:80 backup;
server google.com addr=173.194.73.100:80 backup;
server google.com addr=173.194.73.101:80 backup;
server google.com addr=173.194.73.138:80 backup;
server google.com addr=173.194.73.102:80 backup;
server google.com addr=173.194.73.113:80 backup;
$
```

## verbose

```bash
$ curl "http://127.0.0.1:6000/dynamic?upstream=mail&verbose="
server mail.ru addr=94.100.180.200:80 weight=1 max_fails=1 fail_timeout=10 max_conns=0 conns=0;
server mail.ru addr=94.100.180.201:80 weight=1 max_fails=1 fail_timeout=10 max_conns=0 conns=0;
server mail.ru addr=217.69.139.200:80 weight=1 max_fails=1 fail_timeout=10 max_conns=0 conns=0;
server mail.ru addr=217.69.139.201:80 weight=1 max_fails=1 fail_timeout=10 max_conns=0 conns=0;
server google.com addr=64.233.165.101:80 weight=1 max_fails=1 fail_timeout=10 max_conns=0 conns=0 backup;
server google.com addr=64.233.165.102:80 weight=1 max_fails=1 fail_timeout=10 max_conns=0 conns=0 backup;
server google.com addr=64.233.165.139:80 weight=1 max_fails=1 fail_timeout=10 max_conns=0 conns=0 backup;
server google.com addr=64.233.165.138:80 weight=1 max_fails=1 fail_timeout=10 max_conns=0 conns=0 backup;
server google.com addr=64.233.165.100:80 weight=1 max_fails=1 fail_timeout=10 max_conns=0 conns=0 backup;
server google.com addr=64.233.165.113:80 weight=1 max_fails=1 fail_timeout=10 max_conns=0 conns=0 backup;
$
```

## update_parameters

```bash
$ curl "http://127.0.0.1:6000/dynamic?upstream=backends&server=127.0.0.1:6003&weight=10&max_fails=5&fail_timeout=5&max_conns=10"
server 127.0.0.1:6001 weight=1 max_fails=1 fail_timeout=10 max_conns=0 conns=0;
server 127.0.0.1:6002 weight=1 max_fails=1 fail_timeout=10 max_conns=0 conns=0;
server 127.0.0.1:6003 weight=10 max_fails=5 fail_timeout=5 max_conns=10 conns=0;
$
```

The supported parameters are below.

 * weight
 * max_fails
 * fail_timeout

## down

```bash
$ curl "http://127.0.0.1:6000/dynamic?upstream=backends&server=127.0.0.1:6003&down="
server 127.0.0.1:6001 weight=1 max_fails=1 fail_timeout=10 max_conns=0 conns=0;
server 127.0.0.1:6002 weight=1 max_fails=1 fail_timeout=10 max_conns=0 conns=0;
server 127.0.0.1:6003 weight=1 max_fails=1 fail_timeout=10 max_conns=0 conns=0 down;
$
```

## up

```bash
$ curl "http://127.0.0.1:6000/dynamic?upstream=backends&server=127.0.0.1:6003&up="
server 127.0.0.1:6001 weight=1 max_fails=1 fail_timeout=10 max_conns=0 conns=0;
server 127.0.0.1:6002 weight=1 max_fails=1 fail_timeout=10 max_conns=0 conns=0;
server 127.0.0.1:6003 weight=1 max_fails=1 fail_timeout=10 max_conns=0 conns=0;
$
```

## add peer

```bash
$ curl "http://127.0.0.1:6000/dynamic?upstream=backends&add=&server=127.0.0.1:6004"
server 127.0.0.1:6001;
server 127.0.0.1:6002;
server 127.0.0.1:6003;
server 127.0.0.1:6004;
$
```

## add host
```bash
$ curl "http://127.0.0.1:6000/dynamic?upstream=backends&add=&server=localhost:6004"
DNS resolving in progress
$
```
Peers will be added in background.

## add backup peer

```bash
$ curl "http://127.0.0.1:6000/dynamic?upstream=backends&add=&server=127.0.0.1:6004&backup="
server 127.0.0.1:6001;
server 127.0.0.1:6002;
server 127.0.0.1:6003;
server 127.0.0.1:6004 backup;
$
```

## remove peer

```bash
$ curl "http://127.0.0.1:6000/dynamic?upstream=backends&remove=&server=127.0.0.1:6003"
server 127.0.0.1:6001;
server 127.0.0.1:6002;
server 127.0.0.1:6004;
$
```

## remove server

```bash
$ curl "http://127.0.0.1:6000/dynamic?upstream=backends&remove=&server=mail.ru"
server 127.0.0.1:6001;
server 127.0.0.1:6002;
server 127.0.0.1:6004;
$
```

## add stream

```bash
$ curl "http://127.0.0.1:6000/dynamic?upstream=backends_stream&add=&server=127.0.0.1:6004&stream="
server 127.0.0.1:6001;
server 127.0.0.1:6002;
server 127.0.0.1:6003;
server 127.0.0.1:6004;
$
```

## add backup stream

```bash
$ curl "http://127.0.0.1:6000/dynamic?upstream=backends_stream&add=&server=127.0.0.1:6004&backup=&stream="
server 127.0.0.1:6001;
server 127.0.0.1:6002;
server 127.0.0.1:6003;
server 127.0.0.1:6004 backup;
$
```

## remove stream

```bash
$ curl "http://127.0.0.1:6000/dynamic?upstream=backends_stream&remove=&server=127.0.0.1:6003&stream="
server 127.0.0.1:6001;
server 127.0.0.1:6002;
server 127.0.0.1:6004;
$
```

# License

See [LICENSE](LICENSE).  MIT (Tatsuhiko Kubo, Aleksei Konovkin), plus the
nginx two-clause BSD terms for the functions derived from `ngx_inet.c`.
