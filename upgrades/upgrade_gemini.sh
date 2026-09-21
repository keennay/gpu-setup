#!/usr/bin/env bash
set -euo pipefail

GEMINI_PREFIX=$(npm prefix --global)
if [ -z "$GEMINI_PREFIX" ]; then
    printf 'Error: cannot determine the npm global installation path.\n' >&2
    exit 1
fi

npm install --global @google/gemini-cli@latest

GEMINI_BINARY="$GEMINI_PREFIX/bin/gemini"
if [ ! -x "$GEMINI_BINARY" ] || ! "$GEMINI_BINARY" --version; then
    printf 'Error: Gemini CLI is not usable at %s.\n' "$GEMINI_BINARY" >&2
    exit 1
fi
printf 'Gemini CLI upgraded at %s\n' "$GEMINI_BINARY"
case ":$PATH:" in
    *":$GEMINI_PREFIX/bin:"*) ;;
    *) printf 'Add %s/bin to PATH to run gemini.\n' "$GEMINI_PREFIX" ;;
esac
