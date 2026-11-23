#!/usr/bin/env bash
set -eu
cd "$(dirname "$0")/.."
LUA="${LUA:-lua}"
PY="${PYTHON:-python}"
OUT="${RQ_PREVIEW_OUT:-.cache/preview}"
mkdir -p "$OUT"
[ -f .cache/preview-art/manifest.json ] || "$PY" RavenquillExpedition/dev/preview/art.py
"$LUA" RavenquillExpedition/dev/preview/preview.lua "$OUT" "$@"
"$PY" RavenquillExpedition/dev/preview/render.py "$OUT"
