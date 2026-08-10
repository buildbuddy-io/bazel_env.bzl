#!/usr/bin/env bash
# Shared helpers for bazel_env's watch-file lock, sourced by both the per-tool
# launcher (launcher.sh.tpl) and the status script (status.sh.tpl).

# bazel_env_collect_watch_files <watch_base> <list_file>...
#
# In:
#   <watch_base>    workspace root the list entries are relative to.
#   <list_file>...  *_watch_dirs.txt (dirs to watch) and/or *_watch_files.txt
#                   (files to watch); missing list files are ignored.
# Out (stdout):     every watched file as an absolute path, one per line,
#                   sorted and de-duplicated (empty if none).
bazel_env_collect_watch_files() {
  local watch_base="$1"
  shift
  # Canonicalize (resolve symlinks) so launcher and status agree on paths.
  if [[ -d "$watch_base" ]]; then
    watch_base="$(cd "$watch_base" && pwd -P)"
  fi
  local list dir file
  local out=()
  for list in "$@"; do
    [[ -f "$list" ]] || continue
    case "$list" in
    *_watch_dirs.txt)
      for dir in $(cat "$list"); do
        [[ -d "$watch_base/$dir" ]] || continue
        while IFS= read -r file; do
          out+=("$file")
        done < <(find "$watch_base/$dir" -type f)
      done
      ;;
    *_watch_files.txt)
      for file in $(cat "$list"); do
        [[ -f "$watch_base/$file" ]] && out+=("$watch_base/$file")
      done
      ;;
    esac
  done
  [[ ${#out[@]} -gt 0 ]] || return 0
  printf '%s\n' "${out[@]}" | sort -u
}

# bazel_env_merge_lock <sha256_cmd> <lock_file> <file>...
#
# In:
#   <sha256_cmd>  sha256sum binary used to hash the files.
#   <lock_file>   lock to update in place (workspace-global, shared by all targets).
#   <file>...     absolute paths whose lock entries to refresh.
# Out:            <lock_file> updated - these files' hashes refreshed, all other
#                 entries kept. Atomic (temp + rename); left untouched on any
#                 failure (returns non-zero).
bazel_env_merge_lock() {
  local sha256_cmd="$1" lock_file="$2"
  shift 2
  [[ $# -gt 0 ]] || return 0
  # Run in a subshell so the cleanup trap is scoped here and never touches the caller's traps
  (
    tmp="$(mktemp "${lock_file}.XXXXXX")" || exit 1
    trap 'rm -f "$tmp"' EXIT INT TERM
    if [[ -f "$lock_file" ]]; then
      awk '
        NR==FNR { seen[$0] = 1; next }
        { match($0, /^[^ ]+ +/); p = substr($0, RSTART + RLENGTH); if (!(p in seen)) print }
      ' <(printf '%s\n' "$@") "$lock_file" > "$tmp" || exit 1
    fi
    "$sha256_cmd" "$@" >> "$tmp" || exit 1
    mv "$tmp" "$lock_file"
  )
}
