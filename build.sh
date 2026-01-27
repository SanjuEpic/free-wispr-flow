#!/bin/bash
set -e

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m' # No Color

# Default values
CONFIGURATION="Release"
CLEAN=false
OPEN_APP=false
UPDATE_DEPS=false
PROJECT_DIR="$(cd "$(dirname "$0")" && pwd)"
SERVER_DIR="$PROJECT_DIR/stt-server-py"

usage() {
    echo "Usage: $0 [OPTIONS]"
    echo ""
    echo "Build uttr from source with Python dependency management"
    echo ""
    echo "Options:"
    echo "  -c, --configuration  Build configuration: Debug or Release (default: Release)"
    echo "  -C, --clean          Clean build folder before building"
    echo "  -o, --open           Open app after successful build"
    echo "  -u, --update-deps    Update Python dependencies before building"
    echo "  -h, --help           Show this help message"
    echo ""
    echo "Examples:"
    echo "  $0                   # Release build"
    echo "  $0 -c Debug          # Debug build"
    echo "  $0 --clean --open    # Clean Release build, then open app"
    echo "  $0 --update-deps     # Update Python dependencies then build"
}

# Parse arguments
while [[ $# -gt 0 ]]; do
    case $1 in
        -c|--configuration)
            CONFIGURATION="$2"
            shift 2
            ;;
        -C|--clean)
            CLEAN=true
            shift
            ;;
        -o|--open)
            OPEN_APP=true
            shift
            ;;
        -u|--update-deps)
            UPDATE_DEPS=true
            shift
            ;;
        -h|--help)
            usage
            exit 0
            ;;
        *)
            echo -e "${RED}Unknown option: $1${NC}"
            usage
            exit 1
            ;;
    esac
done

# Validate configuration
if [[ "$CONFIGURATION" != "Debug" && "$CONFIGURATION" != "Release" ]]; then
    echo -e "${RED}Invalid configuration: $CONFIGURATION${NC}"
    echo "Must be 'Debug' or 'Release'"
    exit 1
fi

# Check/update Python dependencies
if [ "$UPDATE_DEPS" = true ]; then
    echo -e "${BLUE}=== Python Dependencies ===${NC}"
    
    # Check if uv is installed
    if ! command -v uv &> /dev/null; then
        echo -e "${RED}uv not found. Installing uv...${NC}"
        curl -LsSf https://astral.sh/uv/install.sh | sh
        export PATH="$HOME/.cargo/bin:$PATH"
    else
        echo -e "${GREEN}uv found: $(uv --version)${NC}"
    fi
    
    # Update dependencies
    if [ -d "$SERVER_DIR" ]; then
        echo -e "${YELLOW}Updating Python dependencies...${NC}"
        cd "$SERVER_DIR"
        uv sync --upgrade
        echo -e "${GREEN}Python dependencies updated${NC}"
        cd "$PROJECT_DIR"
    else
        echo -e "${YELLOW}Warning: stt-server-py directory not found${NC}"
    fi
    echo ""
fi

cd "$PROJECT_DIR"

echo -e "${GREEN}=== uttr Build ===${NC}"
echo -e "Configuration: ${YELLOW}$CONFIGURATION${NC}"
echo ""

# Clean if requested
if [ "$CLEAN" = true ]; then
    echo -e "${YELLOW}Cleaning build folder...${NC}"
    xcodebuild -project uttr.xcodeproj \
        -scheme uttr \
        -configuration "$CONFIGURATION" \
        -destination 'platform=macOS,arch=arm64' \
        clean
    echo ""
fi

# Build
echo -e "${YELLOW}Building...${NC}"
xcodebuild -project uttr.xcodeproj \
    -scheme uttr \
    -configuration "$CONFIGURATION" \
    -destination 'platform=macOS,arch=arm64' \
    CODE_SIGN_IDENTITY="-" \
    CODE_SIGNING_REQUIRED=NO \
    CODE_SIGNING_ALLOWED=NO \
    build

# Find the built app
BUILD_DIR=$(xcodebuild -project uttr.xcodeproj \
    -scheme uttr \
    -configuration "$CONFIGURATION" \
    -showBuildSettings 2>/dev/null | grep -m1 "BUILT_PRODUCTS_DIR" | awk '{print $3}')

APP_PATH="$BUILD_DIR/uttr.app"
FINAL_APP_PATH="/Applications/uttr.app"

echo ""
echo -e "${GREEN}=== Build Successful ===${NC}"
echo -e "Built app: ${YELLOW}$APP_PATH${NC}"

# Copy to Applications folder
echo -e "${YELLOW}Installing to Applications folder...${NC}"
if [ -d "$FINAL_APP_PATH" ]; then
    echo -e "${YELLOW}Removing existing installation...${NC}"
    rm -rf "$FINAL_APP_PATH"
fi
cp -R "$APP_PATH" "$FINAL_APP_PATH"
echo -e "${GREEN}Installed: ${YELLOW}$FINAL_APP_PATH${NC}"

# Open if requested
if [ "$OPEN_APP" = true ]; then
    if [ -d "$FINAL_APP_PATH" ]; then
        echo -e "${YELLOW}Opening app...${NC}"
        open "$FINAL_APP_PATH"
    else
        echo -e "${RED}App not found at expected location${NC}"
        exit 1
    fi
fi

