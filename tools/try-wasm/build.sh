#!/bin/bash
# Builds VolantCore's calculator for wasm32-unknown-wasip1 and writes the gzipped module the /try
# demo loads (website/public/try/calculator/VolantAnswers.wasm.gz, git-ignored; about 19 MB, under
# Cloudflare's 25 MiB static-asset limit, where the raw 55 MB module is not).
# Needs the swift.org 6.4.2 toolchain and its Wasm SDK: Xcode's compiler can't use the SDK.
set -euo pipefail
ROOT="$(cd "$(dirname "$0")/../.." && pwd)"
SWIFT="${SWIFT:-$HOME/Library/Developer/Toolchains/swift-6.4.2-RELEASE.xctoolchain/usr/bin/swift}"
cd "$ROOT/tools/try-wasm"
"$SWIFT" build --swift-sdk swift-6.4.2-RELEASE_wasm -c release --product VolantAnswers -Xswiftc -Osize -Xlinker --strip-all
mkdir -p "$ROOT/website/public/try/calculator"
gzip -9c .build/release/VolantAnswers.wasm > "$ROOT/website/public/try/calculator/VolantAnswers.wasm.gz"
ls -l .build/release/VolantAnswers.wasm "$ROOT/website/public/try/calculator/VolantAnswers.wasm.gz"
