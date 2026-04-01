#!/usr/bin/env bash
# obsidian_api.sh — Thin wrapper around the Obsidian Local REST API.
# Source this file to get helper functions, or run it as a CLI.
#
# Required env vars:
#   OBSIDIAN_API_KEY   — Bearer token from plugin settings
#
# Optional env vars (with defaults):
#   OBSIDIAN_PROTOCOL  — "http" (default) or "https"
#   OBSIDIAN_HOST      — default "127.0.0.1"
#   OBSIDIAN_PORT      — default "27123" (HTTP) / "27124" (HTTPS)

set -euo pipefail

: "${OBSIDIAN_PROTOCOL:=http}"
: "${OBSIDIAN_HOST:=127.0.0.1}"
if [ "$OBSIDIAN_PROTOCOL" = "https" ]; then
  : "${OBSIDIAN_PORT:=27124}"
else
  : "${OBSIDIAN_PORT:=27123}"
fi
: "${OBSIDIAN_API_KEY:=}"

OBSIDIAN_BASE="${OBSIDIAN_PROTOCOL}://${OBSIDIAN_HOST}:${OBSIDIAN_PORT}"

_curl_opts=(-s --fail-with-body --max-time 10)
[ "$OBSIDIAN_PROTOCOL" = "https" ] && _curl_opts+=(-k)

_auth_header="Authorization: Bearer ${OBSIDIAN_API_KEY}"

# ── Helpers ──────────────────────────────────────────────

_urlencode() {
  python3 -c "import urllib.parse, sys; print(urllib.parse.quote(sys.argv[1], safe='/'))" "$1"
}

_api() {
  # _api METHOD PATH [extra curl args...]
  local method="$1" path="$2"; shift 2
  curl "${_curl_opts[@]}" -X "$method" \
    -H "$_auth_header" \
    "$@" \
    "${OBSIDIAN_BASE}${path}"
}

# ── Public Functions ─────────────────────────────────────

obsidian_status() {
  # No auth needed
  curl "${_curl_opts[@]}" "${OBSIDIAN_BASE}/"
}

obsidian_list() {
  # obsidian_list [directory]
  local dir="${1:-}"
  if [ -z "$dir" ]; then
    _api GET "/vault/"
  else
    dir=$(_urlencode "$dir")
    _api GET "/vault/${dir}/"
  fi
}

obsidian_read() {
  # obsidian_read <filename> [--json]
  local file=$(_urlencode "$1"); shift
  local accept="text/markdown"
  [ "${1:-}" = "--json" ] && accept="application/vnd.olrapi.note+json"
  _api GET "/vault/${file}" -H "Accept: ${accept}"
}

obsidian_create() {
  # obsidian_create <filename> < content_on_stdin
  # Creates or replaces the file entirely.
  local file=$(_urlencode "$1")
  _api PUT "/vault/${file}" \
    -H "Content-Type: text/markdown" \
    --data-binary @-
}

obsidian_append() {
  # obsidian_append <filename> < content_on_stdin
  local file=$(_urlencode "$1")
  _api POST "/vault/${file}" \
    -H "Content-Type: text/markdown" \
    --data-binary @-
}

obsidian_patch() {
  # obsidian_patch <filename> <operation> <target_type> <target> [content_type] < content
  # operation: append | prepend | replace
  # target_type: heading | block | frontmatter
  local file=$(_urlencode "$1")
  local op="$2" tt="$3" tgt="$4"
  local ct="${5:-text/markdown}"
  _api PATCH "/vault/${file}" \
    -H "Content-Type: ${ct}" \
    -H "Operation: ${op}" \
    -H "Target-Type: ${tt}" \
    -H "Target: ${tgt}" \
    --data-binary @-
}

obsidian_delete() {
  # obsidian_delete <filename>
  local file=$(_urlencode "$1")
  _api DELETE "/vault/${file}"
}

obsidian_search() {
  # obsidian_search <query> [context_length]
  local query=$(_urlencode "$1")
  local ctx="${2:-100}"
  _api POST "/search/simple/?query=${query}&contextLength=${ctx}"
}

obsidian_search_jsonlogic() {
  # obsidian_search_jsonlogic < json_on_stdin
  _api POST "/search/" \
    -H "Content-Type: application/vnd.olrapi.jsonlogic+json" \
    --data-binary @-
}

obsidian_search_dataview() {
  # obsidian_search_dataview < dql_on_stdin
  _api POST "/search/" \
    -H "Content-Type: application/vnd.olrapi.dataview.dql+txt" \
    --data-binary @-
}

# ── CLI Mode ─────────────────────────────────────────────

if [[ "${BASH_SOURCE[0]}" == "$0" ]]; then
  cmd="${1:-help}"; shift || true
  case "$cmd" in
    status)           obsidian_status ;;
    list|ls)          obsidian_list "${1:-}" ;;
    read|get)         obsidian_read "$@" ;;
    create|put)       obsidian_create "$1" ;;
    append|post)      obsidian_append "$1" ;;
    patch)            obsidian_patch "$@" ;;
    delete|rm)        obsidian_delete "$1" ;;
    search)           obsidian_search "$@" ;;
    search-jsonlogic) obsidian_search_jsonlogic ;;
    search-dataview)  obsidian_search_dataview ;;
    help|*)
      cat <<'USAGE'
Usage: obsidian_api.sh <command> [args]

  status                         Check server status (no auth)
  list [dir]                     List files in vault root or directory
  read <file> [--json]           Read a note (markdown or JSON)
  create <file> < content        Create/replace a note (stdin)
  append <file> < content        Append to a note (stdin)
  patch <file> <op> <type> <tgt> [ct] < content
                                 Surgical edit (stdin)
  delete <file>                  Delete a note
  search <query> [ctx_len]       Simple text search
  search-jsonlogic < json        Advanced search (stdin)
  search-dataview < dql          Dataview DQL search (stdin)

Environment:
  OBSIDIAN_API_KEY    (required) API key from plugin settings
  OBSIDIAN_PROTOCOL   http (default) or https
  OBSIDIAN_HOST       default 127.0.0.1
  OBSIDIAN_PORT       default 27123 / 27124
USAGE
      ;;
  esac
fi
