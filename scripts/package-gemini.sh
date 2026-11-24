#!/usr/bin/env bash
set -euo pipefail

cd "$(dirname "$0")/.."

out="${1:-dist/obsidian-gemini.tar.gz}"
plugin="plugins/obsidian"

stage="$(mktemp -d)"
trap 'rm -rf "$stage"' EXIT

cp "$plugin/gemini-extension.json" "$plugin/LICENSE" "$stage/"
# Gemini copies an installed extension with fs.cp, which breaks symlinks, so the archive needs real files.
cp -RL "$plugin/skills" "$stage/skills"

mkdir -p "$(dirname "$out")"
tar -czf "$out" -C "$stage" gemini-extension.json LICENSE skills

echo "Wrote $out"
