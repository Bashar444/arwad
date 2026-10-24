#!/usr/bin/env bash
# Build the Phase 0.4 proof of concept: Goose kernels -> C -> rgoosepoc.dll for R.
# Run from the repository root in Git Bash:  bash poc/build.sh
set -euo pipefail

GOOSE="${GOOSE:-toolchains/goose-v2026.3/goose-v2026.3-windows-x64/goose.exe}"
R_HOME_DIR="${R_HOME_DIR:-D:/ALL FOLDERS DISKTOP 09-06-2026/R_PhD_Expert_Course/runtime/R-4.6.0}"
export RTOOLS45_HOME="${RTOOLS45_HOME:-D:/rtools45}"
export GOOSE_HOME="${GOOSE_HOME:-D:/_caches/goose}"
export PATH="/d/rtools45/x86_64-w64-mingw32.static.posix/bin:/d/rtools45/usr/bin:$PATH"

cd poc
"../$GOOSE" -O2 --standalone --header rgoose_kernels.h -o rgoose_kernels.c rgoose_kernels.goose
"$R_HOME_DIR/bin/x64/R.exe" CMD SHLIB -o rgoosepoc.dll shim.c rgoose_kernels.c
echo "built poc/rgoosepoc.dll"
