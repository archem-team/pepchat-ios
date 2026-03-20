#!/bin/bash

# Clean Emulator Build Script for Maestro Testing
# This script ALWAYS erases the simulator to ensure a completely fresh state:
# - No user login or authentication
# - No cached data or credentials
# - No certificates or keychain data
# - Fresh app install
#
# This is the recommended way to prepare a simulator for Maestro UI tests.

set -e  # Exit on any error

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

# Default simulator configuration
DEFAULT_SIMULATOR_NAME="iPhone 16 Pro"

# Function to list available iPhone simulators for interactive selection
list_devices() {
    echo -e "${BLUE}Available iPhone simulators:${NC}"
    echo ""
    local i=1
    while IFS= read -r line; do
        name=$(echo "$line" | sed -E 's/^[[:space:]]+(.*) \([A-F0-9-]+\).*/\1/')
        udid=$(echo "$line" | sed -E 's/.*\(([A-F0-9-]+)\).*/\1/')
        state=$(echo "$line" | sed -E 's/.*\(([A-Za-z]+)\)[[:space:]]*$/\1/')
        if [ "$name" = "$DEFAULT_SIMULATOR_NAME" ]; then
            echo -e "  ${GREEN}$i) $name${NC} ($state) [default]"
        else
            echo -e "  ${YELLOW}$i) $name${NC} ($state)"
        fi
        i=$((i + 1))
    done < <(xcrun simctl list devices available | grep "iPhone")
    echo ""
    echo -e "${BLUE}Usage: $0 --device \"iPhone 16 Pro Max\"${NC}"
    exit 0
}

# Parse command line arguments
LANG_OVERRIDE=""
SKIP_BUILD=false
LAUNCH_APP=false
DEVICE_OVERRIDE=""
while [[ $# -gt 0 ]]; do
    case $1 in
        --lang|-l)
            LANG_OVERRIDE="$2"
            shift 2
            ;;
        --skip-build|-s)
            SKIP_BUILD=true
            shift
            ;;
        --launch)
            LAUNCH_APP=true
            shift
            ;;
        --device|-d)
            if [ -z "${2:-}" ] || [[ "$2" == -* ]]; then
                list_devices
            fi
            DEVICE_OVERRIDE="$2"
            shift 2
            ;;
        --help|-h)
            echo "Usage: $0 [OPTIONS]"
            echo ""
            echo "Build and install app on a CLEAN simulator for Maestro testing."
            echo "This script ALWAYS erases the simulator to ensure a fresh state."
            echo ""
            echo "Options:"
            echo "  -d, --device [NAME] Use specific simulator (no arg to list available)"
            echo "  -l, --lang LANG     Language override (e.g., es-419, pt-BR)"
            echo "  -s, --skip-build    Skip building (use existing .app)"
            echo "  --launch            Launch the app after install (default: don't launch)"
            echo "  -h, --help          Show this help message"
            echo ""
            echo "Examples:"
            echo "  $0                              # Clean install iOS app (ready for Maestro)"
            echo "  $0 --device                     # List available simulators"
            echo "  $0 -d \"iPhone 16 Pro Max\"       # Use specific simulator"
            echo "  $0 --lang es-419                # Clean install with Spanish locale"
            echo "  $0 --launch                     # Clean install and launch app"
            echo ""
            echo "For Maestro testing:"
            echo "  $0 && maestro test flow.yaml"
            exit 0
            ;;
        *)
            shift
            ;;
    esac
done

echo -e "${BLUE}🧪 Clean Emulator Build for Maestro Testing${NC}"
echo -e "${BLUE}============================================${NC}"
echo -e "${YELLOW}🧹 Simulator will be ERASED for a completely fresh state${NC}"
if [ -n "$LANG_OVERRIDE" ]; then
    echo -e "${YELLOW}🌐 Language override: $LANG_OVERRIDE${NC}"
fi
echo -e "${YELLOW}📱 iOS mode - will build and install iOS APP${NC}"
if [ "$SKIP_BUILD" = true ]; then
    echo -e "${YELLOW}⏭️  Skip build mode - will use existing .app${NC}"
fi
if [ "$LAUNCH_APP" = true ]; then
    echo -e "${YELLOW}🚀 Will launch app after install${NC}"
else
    echo -e "${YELLOW}⏸️  App will NOT be launched (ready for Maestro)${NC}"
fi
echo ""

# Function to print status messages
print_status() {
    echo -e "${YELLOW}📋 $1${NC}"
}

print_success() {
    echo -e "${GREEN}✅ $1${NC}"
}

print_error() {
    echo -e "${RED}❌ $1${NC}"
}

# Function to detect project configuration
detect_project_config() {
    print_status "Detecting project configuration..."

    # Find Xcode project file
    XCODEPROJ_FILES=(*.xcodeproj)
    if [ ${#XCODEPROJ_FILES[@]} -eq 0 ]; then
        print_error "No Xcode project found in current directory"
        exit 1
    fi

    if [ ${#XCODEPROJ_FILES[@]} -gt 1 ]; then
        print_error "Multiple Xcode projects found. Please run from a directory with only one project."
        exit 1
    fi

    PROJECT_NAME="${XCODEPROJ_FILES[0]%.xcodeproj}"
    print_success "Found project: $PROJECT_NAME"

    # Extract bundle identifier from project file
    # Exclude test bundle IDs to get the main iOS app bundle ID
    BUNDLE_ID=$(grep "PRODUCT_BUNDLE_IDENTIFIER" "$PROJECT_NAME.xcodeproj/project.pbxproj" | grep -v "Tests" | grep -v "UITests" | grep -v "NotificationService" | head -1 | sed 's/.*= \(.*\);/\1/')
    if [ -z "$BUNDLE_ID" ]; then
        print_error "Could not detect bundle identifier from project file"
        exit 1
    fi

    # Remove quotes if present
    BUNDLE_ID=$(echo "$BUNDLE_ID" | tr -d '"')
    print_success "Bundle ID: $BUNDLE_ID"

    # Use project name as scheme name (most common convention)
    SCHEME_NAME="$PROJECT_NAME"
    print_success "Scheme: $SCHEME_NAME"
}

# Cache simctl device list (called once, reused everywhere)
SIMCTL_DEVICES_CACHE=""
get_simctl_devices() {
    if [ -z "$SIMCTL_DEVICES_CACHE" ]; then
        SIMCTL_DEVICES_CACHE=$(xcrun simctl list devices available)
    fi
    echo "$SIMCTL_DEVICES_CACHE"
}

# Function to select simulator
select_simulator() {
    print_status "Available simulators:"
    get_simctl_devices | grep "iPhone" | head -10

    # Use device override if provided, otherwise use default
    local TARGET_SIMULATOR="${DEVICE_OVERRIDE:-$DEFAULT_SIMULATOR_NAME}"

    if get_simctl_devices | grep -q "$TARGET_SIMULATOR"; then
        SIMULATOR_NAME="$TARGET_SIMULATOR"
        if [ -n "$DEVICE_OVERRIDE" ]; then
            print_success "Using requested simulator: $SIMULATOR_NAME"
        else
            print_success "Using default simulator: $SIMULATOR_NAME"
        fi
    elif [ -n "$DEVICE_OVERRIDE" ]; then
        print_error "Requested simulator '$DEVICE_OVERRIDE' not found"
        print_status "Run with --device (no argument) to list available simulators"
        exit 1
    else
        # Get first available iPhone simulator
        SIMULATOR_NAME=$(get_simctl_devices | grep "iPhone" | head -1 | sed 's/.*"\([^"]*\)".*/\1/')
        if [ -z "$SIMULATOR_NAME" ]; then
            print_error "No iPhone simulators found"
            exit 1
        fi
        print_success "Using available simulator: $SIMULATOR_NAME"
    fi

    # Get the simulator UDID to construct proper destination
    # First try to find exact match, then fall back to partial match
    SIMULATOR_UDID=$(get_simctl_devices | grep -E "^\s+$SIMULATOR_NAME \(" | head -1 | sed -E 's/.*\(([A-F0-9-]+)\).*/\1/')
    if [ -z "$SIMULATOR_UDID" ]; then
        # Fallback: try partial match (for cases where name might have extra spaces)
        SIMULATOR_UDID=$(get_simctl_devices | grep "$SIMULATOR_NAME" | head -1 | sed -E 's/.*\(([A-F0-9-]+)\).*/\1/')
    fi
    if [ -z "$SIMULATOR_UDID" ]; then
        print_error "Could not find UDID for simulator: $SIMULATOR_NAME"
        print_status "Available simulators:"
        get_simctl_devices | grep "iPhone"
        exit 1
    fi

    # Use UDID-based destination which is more reliable (no OS version needed)
    SIMULATOR_DESTINATION="id=$SIMULATOR_UDID"
    print_success "Simulator UDID: $SIMULATOR_UDID"
}

# Function to check prerequisites
check_prerequisites() {
    print_status "Checking prerequisites..."

    # Check if Xcode command line tools are installed
    if ! command -v xcodebuild &> /dev/null; then
        print_error "Xcode command line tools not found. Please install Xcode."
        exit 1
    fi

    # Check if we're in the right directory
    if [ ! -f "$PROJECT_NAME.xcodeproj/project.pbxproj" ]; then
        print_error "Xcode project not found. Please run this script from the project root directory."
        exit 1
    fi

    print_success "Prerequisites check passed"
}

# Function to erase simulator (ALWAYS runs - this is the key difference)
erase_simulator() {
    print_status "Erasing simulator '$SIMULATOR_NAME' for clean state..."
    print_status "This removes ALL data: logins, certificates, cached data, etc."

    # Shutdown simulator first if it's running
    print_status "Shutting down simulator..."
    xcrun simctl shutdown "$SIMULATOR_UDID" 2>/dev/null || true

    # Erase the simulator - this is the key step for a truly clean state
    if xcrun simctl erase "$SIMULATOR_UDID"; then
        print_success "Simulator erased - completely fresh state"
    else
        print_error "Failed to erase simulator"
        exit 1
    fi
}

# Function to boot simulator
boot_simulator() {
    print_status "Starting simulator '$SIMULATOR_NAME' (UDID: $SIMULATOR_UDID)..."
    xcrun simctl boot "$SIMULATOR_UDID" 2>/dev/null || true

    print_status "Waiting for simulator to fully boot..."
    xcrun simctl bootstatus "$SIMULATOR_UDID" -b 2>/dev/null || true
    print_success "Simulator fully booted"
}

# Function to build project
build_project() {
    if [ "$SKIP_BUILD" = true ]; then
        print_status "Skipping build (--skip-build flag set)"
        return 0
    fi

    print_status "Building project '$PROJECT_NAME' for simulator..."

    if xcodebuild \
        -scheme "$SCHEME_NAME" \
        -destination "$SIMULATOR_DESTINATION" \
        -configuration Debug \
        build; then
        print_success "Build completed successfully"
    else
        print_error "Build failed"
        exit 1
    fi
}

# Function to find and install app
install_app() {
    print_status "Locating built app..."

    # Find the most recently built app in DerivedData
    APP_PATH=$(find ~/Library/Developer/Xcode/DerivedData -name "$PROJECT_NAME.app" -path "*/Build/Products/Debug-iphonesimulator/*" -type d | grep -v "Index.noindex" | sort -t / -k 10 -r | head -1)

    if [ -z "$APP_PATH" ]; then
        # Try finding any .app bundle (fallback)
        APP_PATH=$(find ~/Library/Developer/Xcode/DerivedData -name "$PROJECT_NAME.app" -type d | grep -v "Index.noindex" | sort -t / -k 10 -r | head -1)
    fi

    if [ -z "$APP_PATH" ]; then
        print_error "Could not find built app. Build may have failed."
        exit 1
    fi

    print_success "Found app at: $APP_PATH"

    print_status "Installing app on clean simulator..."
    if xcrun simctl install "$SIMULATOR_UDID" "$APP_PATH"; then
        print_success "App installed successfully"
    else
        print_error "Failed to install app"
        exit 1
    fi
}

# Function to launch app (optional - only if --launch flag is set)
launch_app() {
    if [ "$LAUNCH_APP" != true ]; then
        return 0
    fi

    print_status "Launching app..."

    # Wait for simulator to be fully booted
    xcrun simctl bootstatus "$SIMULATOR_UDID" -b 2>/dev/null || true

    if [ -n "$LANG_OVERRIDE" ]; then
        print_status "Launching with language: $LANG_OVERRIDE"
        LAUNCH_OUTPUT=$(xcrun simctl launch "$SIMULATOR_UDID" "$BUNDLE_ID" -AppleLanguages "($LANG_OVERRIDE)" 2>&1)
    else
        LAUNCH_OUTPUT=$(xcrun simctl launch "$SIMULATOR_UDID" "$BUNDLE_ID" 2>&1)
    fi
    LAUNCH_EXIT_CODE=$?

    if [ $LAUNCH_EXIT_CODE -eq 0 ]; then
        print_success "App launched successfully"
    else
        print_error "Failed to launch app"
        echo "$LAUNCH_OUTPUT"
    fi
}

# Function to open simulator app
open_simulator() {
    print_status "Opening Simulator app..."
    open -a Simulator
    osascript -e 'tell application "Simulator" to activate' 2>/dev/null || true
}

# Main execution
main() {
    detect_project_config
    select_simulator
    check_prerequisites

    # ALWAYS erase simulator - this is the purpose of this script
    erase_simulator

    # Boot simulator
    boot_simulator
    open_simulator

    # Build and install
    build_project
    install_app
    launch_app

    echo ""
    print_success "🎉 Clean emulator setup complete!"
    echo ""
    echo -e "${BLUE}Simulator State:${NC}"
    echo -e "${GREEN}  ✓ Simulator erased (completely fresh)${NC}"
    echo -e "${GREEN}  ✓ No user login or authentication${NC}"
    echo -e "${GREEN}  ✓ No cached data or credentials${NC}"
    echo -e "${GREEN}  ✓ No certificates or keychain data${NC}"
    echo -e "${GREEN}  ✓ Fresh app installed${NC}"
    echo ""
    echo -e "${BLUE}Project Details:${NC}"
    echo -e "${YELLOW}  Project: $PROJECT_NAME${NC}"
    echo -e "${YELLOW}  Bundle ID: $BUNDLE_ID${NC}"
    echo -e "${YELLOW}  Simulator: $SIMULATOR_NAME (UDID: $SIMULATOR_UDID)${NC}"
    echo ""
    echo -e "${BLUE}Run Maestro Tests:${NC}"
    echo -e "${YELLOW}  maestro test flow.yaml${NC}"
    echo -e "${YELLOW}  maestro test --device $SIMULATOR_UDID flow.yaml${NC}"
    echo ""
    if [ "$LAUNCH_APP" != true ]; then
        echo -e "${BLUE}To launch app manually:${NC}"
        echo -e "${YELLOW}  xcrun simctl launch $SIMULATOR_UDID $BUNDLE_ID${NC}"
        echo ""
    fi
}

# Run main function
main
