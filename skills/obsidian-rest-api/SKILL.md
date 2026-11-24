---
name: obsidian-rest-api
description: >
  Interact with an Obsidian vault via the Local REST API plugin.
  Use this skill whenever the user wants to create, read, update, delete, or search
  notes in Obsidian. Triggers include: "Obsidian", "vault", "note" (in the context
  of Obsidian), "daily note", "obsidian search", or any reference to reading/writing
  files in an Obsidian vault programmatically. Also trigger when the user asks to
  append to a note, patch a section of a note, list files in a vault, or search
  vault contents. Even if the user just says "add this to my note" or "find my notes
  about X", use this skill if Obsidian context is present.
---

# Obsidian Local REST API Skill

Operate on an Obsidian vault through the **Local REST API** plugin
(`obsidian-local-rest-api`). This skill covers note CRUD and search.

## Prerequisites

The user must have:
1. The **Local REST API** plugin installed and enabled in Obsidian.
2. An API key (found in Obsidian → Settings → Local REST API).

## Connection Settings

The API exposes two server modes. **Ask the user** which mode and key to use
if not already known. Store them as shell variables for the session:

```bash
# Defaults — adjust per user preference
OBSIDIAN_PROTOCOL="http"   # "http" or "https"
OBSIDIAN_PORT="27123"       # 27123 (HTTP) or 27124 (HTTPS)
OBSIDIAN_HOST="127.0.0.1"
OBSIDIAN_API_KEY="<user-provided-key>"
OBSIDIAN_BASE="${OBSIDIAN_PROTOCOL}://${OBSIDIAN_HOST}:${OBSIDIAN_PORT}"
```

For HTTPS mode, add `-k` (or `--insecure`) to curl to accept the self-signed
certificate. For HTTP mode no extra flags are needed.

### Quick connectivity check

```bash
curl -s ${OBSIDIAN_BASE}/
```

This is the **only** endpoint that does not require authentication. A JSON
response with `status` and `authenticated` fields confirms the server is up.

---

## Authentication

Every request (except `GET /`) must include a Bearer token:

```
Authorization: Bearer ${OBSIDIAN_API_KEY}
```

---

## API Reference (Compact)

All paths are relative to `${OBSIDIAN_BASE}`.

### 1. List Files

| Method | Path | Description |
|--------|------|-------------|
| GET | `/vault/` | List vault root |
| GET | `/vault/{dir}/` | List a subdirectory (trailing `/` required) |

Response: `{"files": ["note.md", "folder/"]}` — directories end with `/`.

**Example:**
```bash
curl -s -H "Authorization: Bearer ${OBSIDIAN_API_KEY}" \
  "${OBSIDIAN_BASE}/vault/"
```

### 2. Read a Note

| Method | Path | Accept Header | Returns |
|--------|------|---------------|---------|
| GET | `/vault/{filename}` | `text/markdown` (default) | Raw markdown |
| GET | `/vault/{filename}` | `application/vnd.olrapi.note+json` | JSON with metadata + tags + frontmatter |

**Example — raw markdown:**
```bash
curl -s -H "Authorization: Bearer ${OBSIDIAN_API_KEY}" \
  "${OBSIDIAN_BASE}/vault/Projects/todo.md"
```

**Example — JSON with metadata:**
```bash
curl -s -H "Authorization: Bearer ${OBSIDIAN_API_KEY}" \
  -H "Accept: application/vnd.olrapi.note+json" \
  "${OBSIDIAN_BASE}/vault/Projects/todo.md"
```

### 3. Create / Replace a Note

| Method | Path | Behaviour |
|--------|------|-----------|
| PUT | `/vault/{filename}` | Create new or **overwrite** entire file |

Send the full markdown body as `text/markdown`. Returns `204` on success.

**Example:**
```bash
curl -s -X PUT \
  -H "Authorization: Bearer ${OBSIDIAN_API_KEY}" \
  -H "Content-Type: text/markdown" \
  --data-binary @- \
  "${OBSIDIAN_BASE}/vault/Inbox/new-note.md" <<'EOF'
---
tags: [meeting, project-x]
---
# Meeting Notes
- Discussed roadmap
EOF
```

### 4. Append to a Note

| Method | Path | Behaviour |
|--------|------|-----------|
| POST | `/vault/{filename}` | Append content to end of file (creates if missing) |

**Example:**
```bash
curl -s -X POST \
  -H "Authorization: Bearer ${OBSIDIAN_API_KEY}" \
  -H "Content-Type: text/markdown" \
  --data-binary "- New item added at $(date +%H:%M)" \
  "${OBSIDIAN_BASE}/vault/Inbox/todo.md"
```

### 5. Patch (Surgical Edit)

| Method | Path | Behaviour |
|--------|------|-----------|
| PATCH | `/vault/{filename}` | Insert/replace content relative to a heading, block, or frontmatter field |

**Required headers:**

| Header | Values | Description |
|--------|--------|-------------|
| `Operation` | `append` / `prepend` / `replace` | What to do |
| `Target-Type` | `heading` / `block` / `frontmatter` | What structure to target |
| `Target` | string | Identifier (heading text, block ID, frontmatter key) |

**Optional headers:**

| Header | Default | Description |
|--------|---------|-------------|
| `Target-Delimiter` | `::` | Separator for nested headings |
| `Trim-Target-Whitespace` | `false` | Trim whitespace from target string |

**Example — append below a heading:**
```bash
curl -s -X PATCH \
  -H "Authorization: Bearer ${OBSIDIAN_API_KEY}" \
  -H "Content-Type: text/markdown" \
  -H "Operation: append" \
  -H "Target-Type: heading" \
  -H "Target: Tasks" \
  --data-binary "- [ ] Follow up with client" \
  "${OBSIDIAN_BASE}/vault/Projects/project-x.md"
```

**Example — update frontmatter field:**
```bash
curl -s -X PATCH \
  -H "Authorization: Bearer ${OBSIDIAN_API_KEY}" \
  -H "Content-Type: application/json" \
  -H "Operation: replace" \
  -H "Target-Type: frontmatter" \
  -H "Target: status" \
  --data-binary '"done"' \
  "${OBSIDIAN_BASE}/vault/Projects/project-x.md"
```

### 6. Delete a Note

| Method | Path | Behaviour |
|--------|------|-----------|
| DELETE | `/vault/{filename}` | Delete file. Returns `204`. |

**Example:**
```bash
curl -s -X DELETE \
  -H "Authorization: Bearer ${OBSIDIAN_API_KEY}" \
  "${OBSIDIAN_BASE}/vault/Trash/old-note.md"
```

### 7. Search

#### Simple text search

```
POST /search/simple/?query={text}&contextLength={n}
```

Returns matches with surrounding context. No request body needed.

**Example:**
```bash
curl -s -X POST \
  -H "Authorization: Bearer ${OBSIDIAN_API_KEY}" \
  "${OBSIDIAN_BASE}/search/simple/?query=machine+learning&contextLength=150"
```

#### Advanced search (JsonLogic)

```
POST /search/
Content-Type: application/vnd.olrapi.jsonlogic+json
```

Files are represented as NoteJson objects; use `{"var": "field.path"}` to
access properties. Custom operators: `glob`, `regexp`.

**Example — find notes with a specific tag:**
```bash
curl -s -X POST \
  -H "Authorization: Bearer ${OBSIDIAN_API_KEY}" \
  -H "Content-Type: application/vnd.olrapi.jsonlogic+json" \
  --data-binary '{"in": ["project-x", {"var": "tags"}]}' \
  "${OBSIDIAN_BASE}/search/"
```

**Example — find notes matching a filename pattern:**
```bash
curl -s -X POST \
  -H "Authorization: Bearer ${OBSIDIAN_API_KEY}" \
  -H "Content-Type: application/vnd.olrapi.jsonlogic+json" \
  --data-binary '{"glob": ["Projects/*.md", {"var": "path"}]}' \
  "${OBSIDIAN_BASE}/search/"
```

#### Advanced search (Dataview DQL)

```
POST /search/
Content-Type: application/vnd.olrapi.dataview.dql+txt
```

Send a TABLE-type Dataview query as plain text. Requires the Dataview plugin.

---

## Workflow Guidelines

1. **Always confirm connection first.** Run `GET /` before any authenticated call
   to make sure Obsidian is running and the plugin is active.
2. **URL-encode filenames** that contain spaces or special characters.
   Example: `My Notes/hello world.md` → `My%20Notes/hello%20world.md`
3. **Use PATCH for targeted edits** — avoid reading the whole file, modifying
   in memory, and PUT-ing back when you only need to change one section.
4. **Prefer POST (append)** for additive operations like adding items to a list.
5. **Use `application/vnd.olrapi.note+json`** Accept header when you need
   metadata (tags, frontmatter) along with the content.
6. **Handle errors**: `404` = not found, `400` = bad request, `405` = path is
   a directory (you likely forgot or added an extra trailing `/`).

## Common Patterns

### Create a note only if it doesn't exist
```bash
# Check first with GET, then PUT only if 404
status=$(curl -s -o /dev/null -w "%{http_code}" \
  -H "Authorization: Bearer ${OBSIDIAN_API_KEY}" \
  "${OBSIDIAN_BASE}/vault/Inbox/idea.md")
if [ "$status" = "404" ]; then
  # safe to create
  curl -s -X PUT ...
fi
```

### Bulk-read all notes in a folder
```bash
# 1. List the folder
files=$(curl -s -H "Authorization: Bearer ${OBSIDIAN_API_KEY}" \
  "${OBSIDIAN_BASE}/vault/Journal/" | jq -r '.files[]' | grep -v '/$')
# 2. Read each
for f in $files; do
  echo "=== $f ==="
  curl -s -H "Authorization: Bearer ${OBSIDIAN_API_KEY}" \
    "${OBSIDIAN_BASE}/vault/Journal/${f}"
done
```
