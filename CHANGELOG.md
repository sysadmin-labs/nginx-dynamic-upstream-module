# Changelog

Newest first.  Dates are release dates.

## Unreleased

Forked from ZigzagAK/ngx_dynamic_upstream at a445940 (2026-03-12), itself
the maintained fork of cubicdaiya's original.  Work in progress: the open
upstream findings are being addressed here.

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
