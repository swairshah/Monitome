#!/bin/bash
set -euo pipefail

cd "$(dirname "$0")"

APP_NAME="Monitome"
BUNDLE_ID="swair.Monitome"
BUILD_DIR="build"
DERIVED_DATA="$BUILD_DIR"
APP_PATH="$DERIVED_DATA/Build/Products/Debug/$APP_NAME.app"
APP_BIN="$APP_PATH/Contents/MacOS/$APP_NAME"

FORCE_AGENT_BUILD=0
RESET_PERMISSIONS=0
OPEN_SETTINGS=0

usage() {
  cat <<EOF
Usage: ./run_dev.sh [options]

Options:
  --full            Force rebuild activity-agent
  --reset           Reset Accessibility + Screen Recording permissions for $BUNDLE_ID
  --no-reset        Do not reset permissions (default)
  --open-settings   Open macOS Privacy settings before launch
  -h, --help        Show this help
EOF
}

for arg in "$@"; do
  case "$arg" in
    --full) FORCE_AGENT_BUILD=1 ;;
    --reset) RESET_PERMISSIONS=1 ;;
    --no-reset) RESET_PERMISSIONS=0 ;;
    --open-settings) OPEN_SETTINGS=1 ;;
    -h|--help)
      usage
      exit 0
      ;;
    *)
      echo "Unknown flag: $arg"
      usage
      exit 1
      ;;
  esac
done

# Colors
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m'

echo -e "${GREEN}=== Monitome Dev Build & Run ===${NC}"

mkdir -p "$BUILD_DIR"

# Stop existing app
pkill -f "$APP_BIN" 2>/dev/null || true
pkill -f "Monitome.app/Contents/MacOS/Monitome" 2>/dev/null || true

# Build activity-agent only when needed (or with --full)
if command -v bun >/dev/null 2>&1 && command -v npm >/dev/null 2>&1; then
  AGENT_BIN="activity-agent/dist/activity-agent"
  EXT_BUNDLE="activity-agent/dist/extension-bundle.js"

  NEED_BUILD=0
  if [ "$FORCE_AGENT_BUILD" -eq 1 ]; then
    NEED_BUILD=1
  elif [ ! -f "$AGENT_BIN" ] || [ ! -f "$EXT_BUNDLE" ] || [ ! -d "activity-agent/node_modules" ]; then
    NEED_BUILD=1
  elif [ -n "$(find activity-agent/src activity-agent/package.json activity-agent/tsconfig.json -type f -newer "$AGENT_BIN" -print -quit 2>/dev/null)" ]; then
    NEED_BUILD=1
  elif [ -n "$(find activity-agent/src activity-agent/package.json activity-agent/tsconfig.json -type f -newer "$EXT_BUNDLE" -print -quit 2>/dev/null)" ]; then
    NEED_BUILD=1
  fi

  if [ "$NEED_BUILD" -eq 1 ]; then
    echo -e "${YELLOW}Building activity-agent...${NC}"
    (
      cd activity-agent
      if [ ! -d node_modules ]; then
        npm install --silent
      fi
      npm run build:binary
      npm run build:extension
    )
  else
    echo -e "${GREEN}activity-agent: up to date (skip)${NC}"
  fi
else
  echo -e "${YELLOW}Skipping activity-agent build (bun/npm not found).${NC}"
fi

# Build app (incremental)
echo -e "${YELLOW}Building app (xcodebuild Debug)...${NC}"
xcodebuild \
  -project Monitome.xcodeproj \
  -scheme Monitome \
  -configuration Debug \
  -derivedDataPath "$DERIVED_DATA" \
  build

if [ ! -d "$APP_PATH" ]; then
  echo -e "${RED}Missing built app at: $APP_PATH${NC}"
  exit 1
fi

if [ "$RESET_PERMISSIONS" -eq 1 ]; then
  echo -e "${YELLOW}Resetting permissions for ${BUNDLE_ID}...${NC}"
  tccutil reset Accessibility "$BUNDLE_ID" 2>/dev/null || true
  tccutil reset ScreenCapture "$BUNDLE_ID" 2>/dev/null || true
  OPEN_SETTINGS=1

  echo ""
  echo -e "${YELLOW}Permissions were reset. You'll need to re-grant:${NC}"
  echo -e "  • Accessibility"
  echo -e "  • Screen Recording"
  echo ""
fi

if [ "$OPEN_SETTINGS" -eq 1 ]; then
  echo -e "${YELLOW}Opening Privacy settings...${NC}"
  open "x-apple.systempreferences:com.apple.preference.security?Privacy_Accessibility" || true
  open "x-apple.systempreferences:com.apple.preference.security?Privacy_ScreenCapture" || true
  echo -e "${YELLOW}Make sure Monitome is enabled, then return here and press Enter to launch.${NC}"
  read -r
fi

# Launch app
echo -e "${GREEN}Launching Monitome...${NC}"
open "$APP_PATH"
sleep 2

if pgrep -f "$APP_BIN" >/dev/null 2>&1; then
  echo -e "${GREEN}Monitome process: running${NC}"
else
  echo -e "${RED}Monitome process: not running${NC}"
fi

echo -e "${GREEN}Done.${NC}"
