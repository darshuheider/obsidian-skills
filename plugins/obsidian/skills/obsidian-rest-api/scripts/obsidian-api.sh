#!/usr/bin/env bash
# obsidian-api.sh — Thin wrapper around the Obsidian Local REST API.
# Run it as a command, or source it to get the obsidian_* functions.
# Sourcing does not change the caller's shell options.
#
# Required env vars:
#   OBSIDIAN_API_KEY   — Bearer token from the plugin settings
#
# Optional env vars (with defaults):
#   OBSIDIAN_PROTOCOL  — "https" (default) or "http"
#   OBSIDIAN_HOST      — default "127.0.0.1"
#   OBSIDIAN_PORT      — default "27124" (HTTPS) / "27123" (HTTP)
#
# Every command exits non-zero on an HTTP error (4xx/5xx) and prints the
# response body, so check the exit status before reporting success.

: "${OBSIDIAN_PROTOCOL:=https}"
: "${OBSIDIAN_HOST:=127.0.0.1}"
if [ "$OBSIDIAN_PROTOCOL" = "https" ]; then
  : "${OBSIDIAN_PORT:=27124}"
else
  : "${OBSIDIAN_PORT:=27123}"
fi
: "${OBSIDIAN_API_KEY:=}"

OBSIDIAN_BASE="${OBSIDIAN_PROTOCOL}://${OBSIDIAN_HOST}:${OBSIDIAN_PORT}"

_obsidian_curl_opts=(-sS --fail-with-body --max-time 10)
if [ "$OBSIDIAN_PROTOCOL" = "https" ]; then
  # The plugin uses a self-signed certificate.
  _obsidian_curl_opts+=(-k)
fi

# ── Helpers ──────────────────────────────────────────────

_obsidian_err() {
  echo "obsidian-api: $*" >&2
}

_obsidian_urlencode() {
  # _obsidian_urlencode <string> [safe_chars]
  python3 -c 'import sys, urllib.parse; print(urllib.parse.quote(sys.argv[1], safe=sys.argv[2]))' \
    "$1" "${2-/}"
}

_obsidian_require() {
  # _obsidian_require <count> <usage> "$@"
  local need="$1" usage="$2"; shift 2
  if [ "$#" -lt "$need" ]; then
    _obsidian_err "usage: $usage"
    return 2
  fi
}

_obsidian_api() {
  # _obsidian_api METHOD PATH [extra curl args...]
  local method="$1" path="$2"; shift 2
  if [ -z "$OBSIDIAN_API_KEY" ]; then
    _obsidian_err "OBSIDIAN_API_KEY is not set. Ask the user to export it; don't ask them to paste the key into the chat."
    return 2
  fi
  curl "${_obsidian_curl_opts[@]}" -X "$method" \
    -H "Authorization: Bearer ${OBSIDIAN_API_KEY}" \
    "$@" \
    "${OBSIDIAN_BASE}${path}"
}

# ── Public Functions ─────────────────────────────────────

obsidian_status() {
  # No auth needed
  curl "${_obsidian_curl_opts[@]}" "${OBSIDIAN_BASE}/"
}

obsidian_list() {
  # obsidian_list [directory]
  local dir="${1:-}"
  if [ -z "$dir" ]; then
    _obsidian_api GET "/vault/"
  else
    dir="$(_obsidian_urlencode "${dir%/}")" || return
    _obsidian_api GET "/vault/${dir}/"
  fi
}

obsidian_read() {
  # obsidian_read <file> [--json]
  _obsidian_require 1 "read <file> [--json]" "$@" || return
  local file accept="text/markdown"
  file="$(_obsidian_urlencode "$1")" || return
  [ "${2:-}" = "--json" ] && accept="application/vnd.olrapi.note+json"
  _obsidian_api GET "/vault/${file}" -H "Accept: ${accept}"
}

obsidian_create() {
  # obsidian_create <file> < content
  # Creates the file, or replaces it entirely if it exists.
  _obsidian_require 1 "create <file> < content" "$@" || return
  local file
  file="$(_obsidian_urlencode "$1")" || return
  _obsidian_api PUT "/vault/${file}" \
    -H "Content-Type: text/markdown" \
    --data-binary @-
}

obsidian_append() {
  # obsidian_append <file> < content
  _obsidian_require 1 "append <file> < content" "$@" || return
  local file
  file="$(_obsidian_urlencode "$1")" || return
  _obsidian_api POST "/vault/${file}" \
    -H "Content-Type: text/markdown" \
    --data-binary @-
}

obsidian_patch() {
  # obsidian_patch <file> <operation> <target_type> <target> [content_type] < content
  # operation:   append | prepend | replace
  # target_type: heading | block | frontmatter
  # The target is URL-encoded so non-ASCII headings (e.g. Japanese) work.
  _obsidian_require 4 "patch <file> <append|prepend|replace> <heading|block|frontmatter> <target> [content_type] < content" "$@" || return
  local file target
  file="$(_obsidian_urlencode "$1")" || return
  target="$(_obsidian_urlencode "$4" ":")" || return
  _obsidian_api PATCH "/vault/${file}" \
    -H "Content-Type: ${5:-text/markdown}" \
    -H "Operation: $2" \
    -H "Target-Type: $3" \
    -H "Target: ${target}" \
    --data-binary @-
}

obsidian_delete() {
  # obsidian_delete <file>
  _obsidian_require 1 "delete <file>" "$@" || return
  local file
  file="$(_obsidian_urlencode "$1")" || return
  _obsidian_api DELETE "/vault/${file}"
}

obsidian_search() {
  # obsidian_search <query> [context_length]
  _obsidian_require 1 "search <query> [context_length]" "$@" || return
  local query
  query="$(_obsidian_urlencode "$1" "")" || return
  _obsidian_api POST "/search/simple/?query=${query}&contextLength=${2:-100}"
}

obsidian_search_jsonlogic() {
  # obsidian_search_jsonlogic < json
  _obsidian_api POST "/search/" \
    -H "Content-Type: application/vnd.olrapi.jsonlogic+json" \
    --data-binary @-
}

obsidian_search_dataview() {
  # obsidian_search_dataview < dql
  _obsidian_api POST "/search/" \
    -H "Content-Type: application/vnd.olrapi.dataview.dql+txt" \
    --data-binary @-
}

# ── CLI Mode ─────────────────────────────────────────────

if [[ "${BASH_SOURCE[0]}" == "$0" ]]; then
  set -uo pipefail
  cmd="${1:-help}"; shift || true
  case "$cmd" in
    status)           obsidian_status ;;
    list|ls)          obsidian_list "$@" ;;
    read|get)         obsidian_read "$@" ;;
    create|put)       obsidian_create "$@" ;;
    append|post)      obsidian_append "$@" ;;
    patch)            obsidian_patch "$@" ;;
    delete|rm)        obsidian_delete "$@" ;;
    search)           obsidian_search "$@" ;;
    search-jsonlogic) obsidian_search_jsonlogic ;;
    search-dataview)  obsidian_search_dataview ;;
    help|-h|--help|*)
      cat <<'USAGE'
Usage: obsidian-api.sh <command> [args]

  status                         Check server status (no auth)
  list [dir]                     List files in vault root or directory
  read <file> [--json]           Read a note (markdown or JSON)
  create <file> < content        Create/replace a note (stdin)
  append <file> < content        Append to a note (stdin)
  patch <file> <op> <type> <target> [content_type] < content
                                 Edit relative to a heading, block or
                                 frontmatter field (stdin)
  delete <file>                  Delete a note
  search <query> [ctx_len]       Simple text search
  search-jsonlogic < json        Advanced search (stdin)
  search-dataview < dql          Dataview DQL search (stdin)

Environment:
  OBSIDIAN_API_KEY    (required) API key from plugin settings
  OBSIDIAN_PROTOCOL   https (default) or http
  OBSIDIAN_HOST       default 127.0.0.1
  OBSIDIAN_PORT       default 27124 / 27123
USAGE
      [[ "$cmd" == help || "$cmd" == -h || "$cmd" == --help ]] || exit 2
      ;;
  esac
fi
