#!/bin/bash
set -euo pipefail
cd "$(dirname "$0")/.."
mkdir -p .build/update-verification
swiftc scripts/verify-update.swift -o .build/update-verification/verify-update
swift scripts/test-update-verification.swift "$PWD/.build/update-verification/verify-update"
