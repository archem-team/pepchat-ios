#!/bin/bash

# Maestro Test Runner Script
# Prepares a clean simulator via run_on_clean_emulator.sh, then runs Maestro UI tests.

set -e

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m'

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"
MAESTRO_WORKSPACE="$PROJECT_ROOT/pepchat-maestro-testing"

# Defaults
EMULATOR_ARGS=()
FLOW_FILE=""

usage() {
    echo "Usage: $0 [OPTIONS] [flow.yaml]"
    echo ""
    echo "Prepare a clean simulator and run Maestro UI tests."
    echo ""
    echo "Arguments:"
    echo "  flow.yaml             Specific flow file to run (relative to pepchat-maestro-testing)."
    echo "                        Defaults to all top-level .yaml files in pepchat-maestro-testing."
    echo ""
    echo "Options:"
    echo "  -s, --skip-build      Skip Xcode build (pass through to run_on_clean_emulator.sh)"
    echo "  -l, --lang LANG       Language override (pass through to run_on_clean_emulator.sh)"
    echo "  -h, --help            Show this help message"
    echo ""
    echo "Examples:"
    echo "  $0                                # Clean sim + run all flows"
    echo "  $0 01_smoke_test.yaml             # Clean sim + run one flow"
    echo "  $0 --skip-build 01_smoke_test.yaml  # Reuse last build + run one flow"
    exit 0
}

while [[ $# -gt 0 ]]; do
    case $1 in
        -s|--skip-build)
            EMULATOR_ARGS+=("--skip-build")
            shift
            ;;
        -l|--lang)
            EMULATOR_ARGS+=("--lang" "$2")
            shift 2
            ;;
        -h|--help)
            usage
            ;;
        -*)
            echo -e "${RED}Unknown option: $1${NC}"
            usage
            ;;
        *)
            FLOW_FILE="$1"
            shift
            ;;
    esac
done

# Verify maestro is installed
if ! command -v maestro &> /dev/null; then
    echo -e "${RED}Error: maestro CLI not found. Install it with: curl -Ls 'https://get.maestro.mobile.dev' | bash${NC}"
    exit 1
fi

# Verify workspace exists
if [ ! -d "$MAESTRO_WORKSPACE" ]; then
    echo -e "${RED}Error: pepchat-maestro-testing not found at $MAESTRO_WORKSPACE${NC}"
    exit 1
fi

# If a specific flow was given, verify it exists
if [ -n "$FLOW_FILE" ] && [ ! -f "$MAESTRO_WORKSPACE/$FLOW_FILE" ]; then
    echo -e "${RED}Error: Flow file not found: $MAESTRO_WORKSPACE/$FLOW_FILE${NC}"
    exit 1
fi

echo -e "${BLUE}=== Maestro Test Runner ===${NC}"
echo ""

# After a full simulator erase the XCTest driver must install from scratch,
# which can take well over 120s. 300s covers worst-case on cold simulators.
export MAESTRO_DRIVER_STARTUP_TIMEOUT=300000

# Step 1: Prepare clean simulator
echo -e "${YELLOW}[1/2] Preparing clean simulator...${NC}"
echo ""

"$SCRIPT_DIR/run_on_clean_emulator.sh" "${EMULATOR_ARGS[@]}"

# Detect booted simulator UDID
SIMULATOR_UDID=$(xcrun simctl list devices booted | grep "iPhone" | head -1 | sed -E 's/.*\(([A-F0-9-]+)\).*/\1/')
if [ -z "$SIMULATOR_UDID" ]; then
    echo -e "${RED}No booted iPhone simulator found. Aborting.${NC}"
    exit 1
fi
echo -e "${BLUE}Using simulator: $SIMULATOR_UDID${NC}"

echo ""
echo -e "${YELLOW}[2/2] Running Maestro tests...${NC}"
echo ""

# Determine what to test.
# Single invocation = single XCTest driver startup (~30-60s saved vs per-flow invocations).
# Maestro runs top-level .yaml files in a directory alphabetically (01_, 02_, …).
if [ -n "$FLOW_FILE" ]; then
    MAESTRO_TARGET="$MAESTRO_WORKSPACE/$FLOW_FILE"
    echo -e "${BLUE}Running flow: $FLOW_FILE${NC}"
else
    # Verify there are flow files
    FLOW_COUNT=$(ls -1 "$MAESTRO_WORKSPACE"/*.yaml 2>/dev/null | wc -l | tr -d ' ')
    if [ "$FLOW_COUNT" -eq 0 ]; then
        echo -e "${RED}No .yaml flow files found in $MAESTRO_WORKSPACE${NC}"
        exit 1
    fi
    MAESTRO_TARGET="$MAESTRO_WORKSPACE"
    echo -e "${BLUE}Running $FLOW_COUNT flow(s) from $MAESTRO_WORKSPACE:${NC}"
    ls -1 "$MAESTRO_WORKSPACE"/*.yaml | sort | while read -r f; do echo -e "  $(basename "$f")"; done
fi
echo ""

# Run Maestro — single invocation keeps the XCTest driver alive across all flows
if maestro test --device "$SIMULATOR_UDID" --no-ansi "$MAESTRO_TARGET"; then
    echo ""
    echo -e "${GREEN}=== All tests PASSED ===${NC}"
else
    echo ""
    echo -e "${RED}=== Tests FAILED ===${NC}"
    exit 1
fi
