# Changelog

Newest first.  Dates are release dates.

## v2.4.2 (2026-11-27)

### Fixed

- The sync event no longer reads a connection off a stack frame that
  has already been left.  `init_worker` kept its dummy `ngx_connection_t`
  as a local and handed its address to the event, which then re-arms
  itself every 500 ms for the life of the worker; the timer code reads
  that pointer as a connection on every tick.  AddressSanitizer reports
  it as `stack-use-after-return` and takes the worker down with it, so
  the suite lost its first test file to a connection reset.  The dummy
  connection now comes from the cycle pool, where the event comes from.

- CI: the Test::Nginx cache is now keyed by the Perl build, not just by
  the runner OS.  When the hosted image moved to Ubuntu 26.04 the cached
  `~/perl5` tree was restored against a new interpreter and every test
  file died before its first assertion with `loadable library and perl
  binaries are mismatched`, taking Build & Test, A/UBSan and Valgrind
  down together.

- CI: the sanitizer run can see what it is for now.  ngx_palloc hands
  out slices of a pool block, so a write past an allocation landed inside
  memory ASan had handed over whole and no report was made; nginx keeps a
  switch for exactly this and `NGX_DEBUG_PALLOC` sends every allocation
  straight to malloc.  The reports were being lost as well, because nginx
  redirects its own stderr onto the error log file as soon as `error_log`
  names one, so both sanitizers write to files of their own now and the
  findings step runs even after a failed suite, which is precisely what a
  worker that ASan took down leaves behind.

## v2.4.1 (2026-11-10)

### Fixed

- Build on FreeBSD and the other BSDs.  config named the C++ runtime
  `-lstdc++`, which the base system there does not carry; it now picks
  `-lc++` on the BSDs and macOS and keeps `-lstdc++` with gcc and glibc.
  Verified building nginx 1.30.5 on both FreeBSD (clang/libc++) and Linux
  (gcc/libstdc++).

## v2.4.0 (2026-11-10)

Forked from ZigzagAK/ngx_dynamic_upstream at a445940 (2026-03-12), itself
the maintained fork of cubicdaiya's original.  This release works in the
open upstream findings and adds the build, test and CI scaffolding.

### Fixed

- Build against an http-only nginx.  The stream subsystem was pulled in
  unconditionally, so the module only built on an nginx configured
  `--with-stream`.  Every stream path is now guarded by
  `NGX_STREAM_UPSTREAM_ZONE`, and `config` registers the stream module
  only when nginx has stream.  (upstream issue #11)

- Build with a relative `--add-module` path.  `config` now resolves
  `$ngx_addon_dir` to a full path, so the source and include paths no
  longer depend on the directory configure was run from.  (upstream
  issue #5)

- Deterministic peer order for hash balancing.  Dynamically added peers
  were inserted at the list head in resolution order, so nodes that
  resolved the same addresses at different times held differently ordered
  lists; `hash` and `ip_hash` pick by position, so a key reached different
  upstreams per node.  Peers are now inserted ordered by address.
  (upstream issue #10)

- Drop stale peers when a name resolves to nothing.  getaddrinfo returning
  no address for a server name (its backends gone) used to keep the old
  peers; those addresses may since have been handed to a different service
  by DHCP, so traffic kept reaching the wrong place.  Such peers are now
  removed, and an emptied upstream falls back to its `0.0.0.0:1 down`
  placeholder.  (upstream issue #9)

### Documented

- Starting when a server name cannot be resolved.  nginx resolves static
  upstream names at startup and aborts if one fails; that is nginx's
  behaviour, not this module's.  The README now describes the
  `dynamic_state_file` + `dns_update` pattern, which seeds a `0.0.0.0:1
  down` placeholder so nginx always starts and names are added at run
  time.  (upstream issue #8)

### Added

- Continuous integration: a build-and-test matrix over several nginx
  releases (static and loadable), a FreeBSD VM, address/undefined
  sanitizers, valgrind, CodeQL, shellcheck and actionlint, eight reloads
  in a row, and two gates that t/ cannot cover -- `ci/stream.sh` drives the
  stream module through the API without Lua, and `ci/dns.sh` proves a name
  that stops resolving drops its peers (issue #9).
