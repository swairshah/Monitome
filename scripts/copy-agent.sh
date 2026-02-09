#!/bin/bash
# Copy activity-agent binary into the app bundle

AGENT_SOURCE="${SRCROOT}/activity-agent/dist/activity-agent"
AGENT_DEST="${BUILT_PRODUCTS_DIR}/${PRODUCT_NAME}.app/Contents/MacOS/activity-agent"

if [ -f "$AGENT_SOURCE" ]; then
    echo "Copying activity-agent to app bundle..."
    cp "$AGENT_SOURCE" "$AGENT_DEST"
    chmod +x "$AGENT_DEST"
    # Sign the binary so Xcode can sign the app bundle
    # Use the same identity Xcode is using, or ad-hoc if not available
    if [ -n "$EXPANDED_CODE_SIGN_IDENTITY" ]; then
        echo "Signing activity-agent with: $EXPANDED_CODE_SIGN_IDENTITY"
        codesign --force --sign "$EXPANDED_CODE_SIGN_IDENTITY" --options runtime "$AGENT_DEST"
    else
        echo "Signing activity-agent with ad-hoc signature"
        codesign --force --sign - "$AGENT_DEST"
    fi
    echo "Done: $AGENT_DEST"
else
    echo "Warning: activity-agent not found at $AGENT_SOURCE"
    echo "Run: cd activity-agent && bun build src/cli.ts --compile --outfile dist/activity-agent"
fi
