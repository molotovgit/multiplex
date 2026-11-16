#!/bin/bash
# Builds libmpxtailscale.so (Tailscale's tsnet, embedded) for the Android
# app and puts it where Gradle packages native libraries.
# Needs Go (go.mod names the version) and the Android NDK.
set -euo pipefail
cd "$(dirname "$0")"
NDK=${ANDROID_NDK_HOME:-$(ls -d "${ANDROID_HOME:-$HOME/Android/Sdk}"/ndk/* | sort -V | tail -1)}
CC="$NDK/toolchains/llvm/prebuilt/linux-x86_64/bin/aarch64-linux-android26-clang"
OUT=../../android/app/src/main/jniLibs/arm64-v8a
mkdir -p "$OUT"
# -s -w: no symbol tables (the library is large enough); ts_omit_*: leave out
# features Multiplex never uses.
CGO_ENABLED=1 GOOS=android GOARCH=arm64 CC="$CC" \
  go build -buildmode=c-shared -trimpath -ldflags="-s -w" \
  -tags ts_omit_aws,ts_omit_bird,ts_omit_tap,ts_omit_kube,ts_omit_completion,ts_omit_ssh,ts_omit_taildrop,ts_omit_drive,ts_omit_capture,ts_omit_relayserver,ts_omit_webclient,ts_omit_tpm,ts_omit_syspolicy,ts_omit_wakeonlan \
  -o "$OUT/libmpxtailscale.so" .
rm -f "$OUT/libmpxtailscale.h"
ls -la "$OUT/libmpxtailscale.so"
