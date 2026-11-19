#!/bin/sh
# Offline signal/concurrency checks. Never opens an audio device.
set -eu
repo_dir=$(CDPATH= cd -- "$(dirname -- "$0")/.." && pwd)
check_dir=$(mktemp -d "${TMPDIR:-/tmp}/sensebar-audio-check.XXXXXX")
trap 'rm -rf "$check_dir"' EXIT HUP INT TERM
clang -O2 -Wall -Wextra -Werror -fsanitize=undefined \
  "$repo_dir/Sources/SenseBarAudioBridge/AudioEqualizer.c" \
  "$repo_dir/Tools/CheckAudioDSP.c" \
  -framework CoreAudio -framework CoreFoundation -o "$check_dir/check"
"$check_dir/check"
