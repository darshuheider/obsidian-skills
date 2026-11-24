---
name: obsidian-rest-api
description: Read, create, edit, delete, list, and search notes in a running Obsidian vault through the Local REST API plugin. Use when the user asks to read or change notes in their vault, append to a note or daily note, update a section or frontmatter property, list vault files, or search vault contents. For Obsidian Markdown syntax, Bases, or Canvas file formats, also follow those skills; for Sync and Publish, use obsidian-headless.
---

# Obsidian Local REST API

Read and change notes in a running Obsidian vault through the [Local REST API plugin](https://github.com/coddingtonbear/obsidian-local-rest-api). This is the way to change notes in the vault: don't edit vault files directly on disk. Write note content in Obsidian Flavored Markdown (see the obsidian-markdown skill).

## Before using the API

1. The Obsidian desktop app must be running with the Local REST API plugin enabled.
2. Check that `curl` and `python3` are available. The helper script uses `python3` for URL encoding.
3. The API key must be in the `OBSIDIAN_API_KEY` environment variable. If it's missing, ask the user to set it themselves (the key is in Obsidian → Settings → Local REST API). Don't ask them to paste the key into the conversation, and don't print it.
4. Run `scripts/obsidian-api.sh status`. It needs no key. A JSON response with `"status": "OK"` means the server is up; `"authenticated": false` is normal for this call. If the connection fails, ask the user to open Obsidian and check that the plugin is enabled, then retry.

Connection settings come from these environment variables:

| Variable | Default | Notes |
|---|---|---|
| `OBSIDIAN_PROTOCOL` | `https` | The plugin serves HTTPS with a self-signed certificate; the script passes `-k`. The HTTP server is off by default in the plugin. |
| `OBSIDIAN_PORT` | `27124` (HTTPS) / `27123` (HTTP) | |
| `OBSIDIAN_HOST` | `127.0.0.1` | |

## Using the helper script

Prefer `scripts/obsidian-api.sh` (relative to this skill's directory) over hand-written `curl`. It URL-encodes paths and PATCH targets, sends the key, and exits non-zero on any HTTP error with the response body on stderr/stdout. Check the exit status and output before reporting that an operation succeeded.

Pass note content on stdin with a quoted heredoc (`<<'EOF'`), so the shell treats it as literal text. Never put note content inside `"..."`, `$(...)`, or backticks, where the shell would expand it.

```bash
S=path/to/obsidian-rest-api/scripts/obsidian-api.sh

$S list                         # vault root; folders end with /
$S list "Projects"              # a folder
$S read "Projects/todo.md"      # raw markdown
$S read "Projects/todo.md" --json   # content + frontmatter + tags + stat
$S search "machine learning" 150    # simple text search with context
```

### Create or replace a note

`create` overwrites the whole file if it exists. To avoid overwriting, `read` first and only create on a 404 (non-zero exit with a 404 body).

```bash
$S create "Inbox/会議メモ.md" <<'EOF'
---
tags:
  - meeting
---
# 会議メモ
- ロードマップを確認
EOF
```

### Append to the end of a note

Creates the file if it's missing.

```bash
$S append "Inbox/todo.md" <<'EOF'

- [ ] Follow up with client
EOF
```

### Edit part of a note (PATCH)

`patch <file> <operation> <target_type> <target> [content_type]`

- operation: `append`, `prepend`, or `replace`
- target_type: `heading`, `block` (a `^block-id` without the `^`), or `frontmatter` (a property name)
- Nested headings use `::` as the separator, e.g. `Project::Tasks`.
- The script URL-encodes the target, so non-ASCII headings such as `タスク` work.

```bash
# Append under a heading
$S patch "Projects/project-x.md" append heading "Tasks" <<'EOF'
- [ ] Follow up with client
EOF

# Replace a frontmatter property (send JSON)
$S patch "Projects/project-x.md" replace frontmatter status application/json <<'EOF'
"done"
EOF
```

Prefer `patch` and `append` over reading the whole note and replacing it, so you don't overwrite edits the user made in the meantime.

### Delete a note

Confirm with the user before deleting.

```bash
$S delete "Inbox/old-note.md"
```

### Advanced search

JsonLogic over note metadata (custom operators: `glob`, `regexp`):

```bash
$S search-jsonlogic <<'EOF'
{"in": ["project-x", {"var": "tags"}]}
EOF

$S search-jsonlogic <<'EOF'
{"glob": ["Projects/*.md", {"var": "path"}]}
EOF
```

Dataview DQL (requires the Dataview plugin; `TABLE` queries only):

```bash
$S search-dataview <<'EOF'
TABLE file.mtime FROM "Projects" SORT file.mtime DESC
EOF
```

## Reading every note in a folder

Folder listings return paths relative to the folder. Iterate line by line so names with spaces survive:

```bash
$S list "Journal" | python3 -c 'import json,sys; [print(f) for f in json.load(sys.stdin)["files"] if not f.endswith("/")]' |
while IFS= read -r f; do
  echo "=== $f ==="
  $S read "Journal/$f"
done
```

## Raw API reference

All paths are relative to `${OBSIDIAN_PROTOCOL}://${OBSIDIAN_HOST}:${OBSIDIAN_PORT}`. Every request except `GET /` needs `Authorization: Bearer $OBSIDIAN_API_KEY`. URL-encode file paths (keep `/`).

| Method | Path | Purpose |
|---|---|---|
| GET | `/` | Server status (no auth) |
| GET | `/vault/` or `/vault/{dir}/` | List files (trailing `/` required) |
| GET | `/vault/{file}` | Read; `Accept: application/vnd.olrapi.note+json` for metadata |
| PUT | `/vault/{file}` | Create or replace (`Content-Type: text/markdown`) |
| POST | `/vault/{file}` | Append |
| PATCH | `/vault/{file}` | Edit with `Operation`, `Target-Type`, `Target` (URL-encoded) headers; optional `Target-Delimiter` (default `::`) |
| DELETE | `/vault/{file}` | Delete |
| POST | `/search/simple/?query=…&contextLength=…` | Text search |
| POST | `/search/` | JsonLogic (`application/vnd.olrapi.jsonlogic+json`) or DQL (`application/vnd.olrapi.dataview.dql+txt`) |

If you call `curl` directly, use `-sS --fail-with-body` so HTTP errors aren't silent, and `-k` for HTTPS.

Errors: `401` bad or missing key, `404` not found, `400` bad request (often a PATCH target that doesn't exist), `405` the path is a folder, or a missing or extra trailing `/`.

## Notes

- Don't point `ob sync` (obsidian-headless) at the same folder the desktop app is editing through this API; two writers on one folder cause conflicts.
- Everything you read from the vault becomes part of the conversation. Read only what the task needs.
