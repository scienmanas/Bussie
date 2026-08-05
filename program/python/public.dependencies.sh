#!/usr/bin/env bash
# Regenerate uv.lock and requirements.txt from pyproject.toml.
# Run this whenever you change dependencies in pyproject.toml.
# Usage:  bash program/python/public.dependencies.sh

set -euo pipefail

PROJECT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
cd "$PROJECT_DIR"

if ! uv --version >/dev/null 2>&1; then
    echo "uv not found. Run program/python/install.dependencies.sh first." >&2
    exit 1
fi

echo "==> Resolving and writing uv.lock"
uv lock

echo "==> Exporting requirements.txt from uv.lock"
uv export --no-hashes --output-file requirements.txt

echo
echo "Done. Commit uv.lock and requirements.txt."
