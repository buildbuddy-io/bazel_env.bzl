#!/usr/bin/env bash
# Watch-file lock helpers shared by launcher.sh.tpl and status.sh.tpl.

# Usage: bazel_env_collect_watch_files <watch_base> <list_file>...
# Prints the sorted, unique absolute paths of all watched files.
bazel_env_collect_watch_files() {
  local watch_base="$1"
  shift
  # Resolve symlinks so launcher and status agree on paths.
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

# Usage: bazel_env_merge_lock <sha256_cmd> <lock_file> <file>...
# Atomically refreshes the hashes of <file>s, keeping other entries.
bazel_env_merge_lock() {
  local sha256_cmd="$1" lock_file="$2"
  shift 2
  [[ $# -gt 0 ]] || return 0
  # Subshell scopes the cleanup trap.
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
