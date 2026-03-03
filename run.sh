#!/bin/bash
set -euo pipefail

cd "$(dirname "$0")"

# Fast default runner: preserve existing TCC permissions.
# Use run_dev.sh --reset only when permissions are stale.
exec ./run_dev.sh --no-reset "$@"
