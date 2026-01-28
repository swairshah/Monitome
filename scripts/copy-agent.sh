#!/bin/bash
# Copy activity-agent binary into the app bundle

AGENT_SOURCE="${SRCROOT}/activity-agent/dist/activity-agent"
AGENT_DEST="${BUILT_PRODUCTS_DIR}/${PRODUCT_NAME}.app/Contents/MacOS/activity-agent"

if [ -f "$AGENT_SOURCE" ]; then
    echo "Copying activity-agent to app bundle..."
    cp "$AGENT_SOURCE" "$AGENT_DEST"
    chmod +x "$AGENT_DEST"
    echo "Done: $AGENT_DEST"
else
    echo "Warning: activity-agent not found at $AGENT_SOURCE"
    echo "Run: cd activity-agent && bun build src/cli.ts --compile --outfile dist/activity-agent"
fi
