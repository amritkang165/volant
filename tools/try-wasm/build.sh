#!/bin/bash
# Builds VolantCore's calculator for wasm32-unknown-wasip1 and writes the gzipped module the /try
# demo loads, named by its content hash so browsers can cache it for good
# (website/public/try/calculator/VolantAnswers-<hash>.wasm.gz, git-ignored; about 19 MB, under
# Cloudflare's 25 MiB static-asset limit, where the raw 55 MB module is not), plus
# website/public/try/calculator.json naming that file and its size for the progress bar.
# Needs the swift.org 6.4.2 toolchain and its Wasm SDK: Xcode's compiler can't use the SDK.
set -euo pipefail
ROOT="$(cd "$(dirname "$0")/../.." && pwd)"
SWIFT="${SWIFT:-$HOME/Library/Developer/Toolchains/swift-6.4.2-RELEASE.xctoolchain/usr/bin/swift}"
cd "$ROOT/tools/try-wasm"
"$SWIFT" build --swift-sdk swift-6.4.2-RELEASE_wasm -c release --product VolantAnswers -Xswiftc -Osize -Xlinker --strip-all
OUT="$ROOT/website/public/try/calculator"
mkdir -p "$OUT"
rm -f "$OUT"/VolantAnswers*.wasm.gz
gzip -9nc .build/release/VolantAnswers.wasm > "$OUT/VolantAnswers.wasm.gz"
HASH="$(shasum -a 256 "$OUT/VolantAnswers.wasm.gz" | cut -c1-16)"
mv "$OUT/VolantAnswers.wasm.gz" "$OUT/VolantAnswers-$HASH.wasm.gz"
BYTES="$(stat -f %z "$OUT/VolantAnswers-$HASH.wasm.gz")"
printf '{"file":"VolantAnswers-%s.wasm.gz","bytes":%s}\n' "$HASH" "$BYTES" > "$ROOT/website/public/try/calculator.json"
cat "$ROOT/website/public/try/calculator.json"
