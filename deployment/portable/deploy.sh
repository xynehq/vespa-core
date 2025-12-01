#!/bin/bash

# =============================================================================
# Vespa Deployment Script
# =============================================================================
# Manages Vespa search engine deployment with GPU/CPU support
# =============================================================================

set -e

# Colors
GREEN='\033[0;32m'
BLUE='\033[0;34m'
YELLOW='\033[1;33m'
RED='\033[0;31m'
NC='\033[0m'

show_help() {
    echo "Usage: $0 [COMMAND] [OPTIONS]"
    echo ""
    echo "Commands:"
    echo "  start              Start Vespa service"
    echo "  stop               Stop Vespa service"
    echo "  restart            Restart Vespa service"
    echo "  logs               Show Vespa logs"
    echo "  status             Show Vespa status"
    echo "  cleanup            Clean up old containers and images"
    echo "  help               Show this help message"
    echo ""
    echo "Options:"
    echo "  --force-gpu        Force GPU mode even if GPU not detected"
    echo "  --force-cpu        Force CPU-only mode even if GPU detected"
    echo ""
    echo "Environment Variables:"
    echo "  VESPA_DATA_DIR     Data directory path (default: ./data)"
    echo "                     Example: VESPA_DATA_DIR=../vespa-data ./deploy.sh start"
    echo ""
    echo "Examples:"
    echo "  $0 start           # Start Vespa (auto-detect GPU/CPU)"
    echo "  $0 start --force-cpu    # Force CPU-only mode"
    echo "  $0 logs            # Show Vespa logs"
    echo "  $0 status          # Check Vespa status"
    echo "  VESPA_DATA_DIR=../vespa-data $0 start  # Use existing data directory"
}

detect_gpu_support() {
    # Check if GPU support should be forced
    if [ "$FORCE_GPU" = "true" ]; then
        echo -e "${YELLOW}GPU mode forced via --force-gpu flag${NC}"
        return 0
    fi
    
    if [ "$FORCE_CPU" = "true" ]; then
        echo -e "${YELLOW}CPU-only mode forced via --force-cpu flag${NC}"
        return 1
    fi
    
    # Auto-detect GPU support
    echo -e "${YELLOW}🔍 Detecting GPU support...${NC}"
    
    # Check for NVIDIA GPU and Docker GPU runtime
    if command -v nvidia-smi >/dev/null 2>&1; then
        if nvidia-smi >/dev/null 2>&1; then
            echo -e "${GREEN}✓ NVIDIA GPU detected${NC}"
            
            # Check for Docker GPU runtime
            if docker info 2>/dev/null | grep -i nvidia >/dev/null 2>&1; then
                echo -e "${GREEN}✓ Docker GPU runtime detected${NC}"
                return 0
            else
                echo -e "${YELLOW}⚠ WARNING: NVIDIA GPU found but Docker GPU runtime not available${NC}"
                echo -e "${BLUE}ℹ INFO: Install NVIDIA Container Toolkit for GPU acceleration${NC}"
                return 1
            fi
        fi
    fi
    
    # Check for Apple Silicon or other non-NVIDIA systems
    if [ "$(uname -m)" = "arm64" ] && [ "$(uname -s)" = "Darwin" ]; then
        echo -e "${BLUE}ℹ INFO: Apple Silicon detected - using CPU-only mode${NC}"
        return 1
    fi
    
    echo -e "${BLUE}ℹ INFO: No compatible GPU detected - using CPU-only mode${NC}"
    return 1
}

# Parse command line arguments
COMMAND=${1:-""}
FORCE_GPU=false
FORCE_CPU=false

# Show help if no command provided
if [ -z "$COMMAND" ]; then
    show_help
    exit 0
fi

# Parse additional arguments
shift 2>/dev/null || true
while [[ $# -gt 0 ]]; do
    case $1 in
        --force-gpu)
            FORCE_GPU=true
            shift
            ;;
        --force-cpu)
            FORCE_CPU=true
            shift
            ;;
        *)
            echo -e "${RED}✗ Unknown option: $1${NC}"
            show_help
            exit 1
            ;;
    esac
done

# Initialize data directory from environment or use default
DATA_DIR="${VESPA_DATA_DIR:-./data}"

# Detect Docker Compose command (docker-compose vs docker compose)
get_docker_compose_cmd() {
    if docker compose version >/dev/null 2>&1; then
        echo "docker compose"
    elif command -v docker-compose >/dev/null 2>&1; then
        echo "docker-compose"
    else
        echo -e "${RED}✗ ERROR: Neither 'docker-compose' nor 'docker compose' is available${NC}"
        exit 1
    fi
}

setup_environment() {
    echo -e "${YELLOW}⚙ Setting up Vespa environment...${NC}"

    # Create necessary directories for Vespa
    echo "  📁 Creating Vespa data directories..."
    mkdir -p "$DATA_DIR"/{vespa-data,vespa-models}

    # Create Vespa tmp directory
    mkdir -p "$DATA_DIR"/vespa-data/tmp
    
    # Set proper permissions for Vespa
    echo "  🔒 Setting up permissions..."
    chmod -f 755 "$DATA_DIR" 2>/dev/null || true
    chmod -f 755 "$DATA_DIR"/vespa-data 2>/dev/null || true
    chmod -f 755 "$DATA_DIR"/vespa-models 2>/dev/null || true
    chmod -f 755 "$DATA_DIR"/vespa-data/tmp 2>/dev/null || true
    
    # Copy .env.default to .env if .env doesn't exist
    if [ ! -f .env ] && [ -f .env.default ]; then
        echo "  📄 Copying .env.default to .env..."
        cp .env.default .env
    fi
    
    echo -e "${GREEN}✓ Environment setup completed${NC}"
}

setup_permissions() {
    echo -e "${YELLOW}🔒 Setting Vespa directory permissions...${NC}"

    # Set UID and GID to 1000 to match Vespa user
    USER_UID="1000"
    USER_GID="1000"

    # Set permissions for Vespa directories
    docker run --rm -v "$(pwd)/$DATA_DIR/vespa-data:/data" busybox chown -R "$USER_UID:$USER_GID" /data 2>/dev/null || true
    docker run --rm -v "$(pwd)/$DATA_DIR/vespa-models:/data" busybox chown -R "$USER_UID:$USER_GID" /data 2>/dev/null || true

    echo -e "${GREEN}✓ Permissions configured${NC}"
}

start_vespa() {
    echo -e "${YELLOW}🚀 Starting Vespa service...${NC}"

    # Determine GPU or CPU mode
    if detect_gpu_support; then
        echo -e "${GREEN}⚡ Using GPU-accelerated Vespa${NC}"
        VESPA_MODE="gpu"
    else
        echo -e "${BLUE}💻 Using CPU-only Vespa${NC}"
        VESPA_MODE="cpu"
    fi

    # Build and start Vespa container
    DOCKER_COMPOSE=$(get_docker_compose_cmd)
    
    cd vespa-deploy
    if [ "$VESPA_MODE" = "gpu" ]; then
        echo "  🔨 Building GPU-enabled Vespa image..."
        docker build -t vespa-custom:latest .
        # Run with GPU support
        docker run -d \
            --name vespa \
            --gpus all \
            -p 8080:8080 \
            -p 19071:19071 \
            -v "$(pwd)/../$DATA_DIR/vespa-data:/opt/vespa/var" \
            -v "$(pwd)/../$DATA_DIR/vespa-models:/opt/vespa/models" \
            vespa-custom:latest
    else
        echo "  🔨 Building CPU-only Vespa image..."
        docker build -t vespa-custom:latest .
        # Run without GPU
        docker run -d \
            --name vespa \
            -p 8080:8080 \
            -p 19071:19071 \
            -v "$(pwd)/../$DATA_DIR/vespa-data:/opt/vespa/var" \
            -v "$(pwd)/../$DATA_DIR/vespa-models:/opt/vespa/models" \
            vespa-custom:latest
    fi
    cd ..
    
    echo -e "${GREEN}✓ Vespa service started${NC}"
}

stop_vespa() {
    echo -e "${YELLOW}🛑 Stopping Vespa service...${NC}"
    
    if docker ps -a --format '{{.Names}}' | grep -q '^vespa$'; then
        docker stop vespa 2>/dev/null || true
        docker rm vespa 2>/dev/null || true
        echo -e "${GREEN}✓ Vespa service stopped${NC}"
    else
        echo -e "${BLUE}ℹ Vespa service is not running${NC}"
    fi
}

show_logs() {
    echo -e "${YELLOW}📋 Showing Vespa logs...${NC}"
    
    if docker ps --format '{{.Names}}' | grep -q '^vespa$'; then
        docker logs -f vespa
    else
        echo -e "${RED}✗ Vespa service is not running${NC}"
        exit 1
    fi
}

show_status() {
    echo -e "${YELLOW}📊 Vespa Service Status:${NC}"
    echo ""
    
    if docker ps --format '{{.Names}}' | grep -q '^vespa$'; then
        echo -e "${GREEN}✓ Vespa is running${NC}"
        docker ps --filter name=vespa --format "table {{.Names}}\t{{.Status}}\t{{.Ports}}"
        echo ""
        echo -e "${YELLOW}🌐 Access URLs:${NC}"
        echo "  • Vespa Config Server: http://localhost:19071"
        echo "  • Vespa Query API: http://localhost:8080"
        echo ""
        # Show GPU/CPU mode
        if docker inspect vespa 2>/dev/null | grep -q '"Gpus"'; then
            echo -e "${GREEN}  ⚡ Mode: GPU-accelerated${NC}"
        else
            echo -e "${BLUE}  💻 Mode: CPU-only${NC}"
        fi
    else
        echo -e "${RED}✗ Vespa service is not running${NC}"
        echo "  Start with: ./deploy.sh start"
    fi
}

cleanup() {
    echo -e "${YELLOW}🧹 Cleaning up old containers and images...${NC}"
    docker system prune -f
    docker volume prune -f
    echo -e "${GREEN}✓ Cleanup completed${NC}"
}

# Main script logic
case $COMMAND in
    start)
        setup_environment
        setup_permissions
        start_vespa
        echo ""
        show_status
        ;;
    stop)
        stop_vespa
        ;;
    restart)
        stop_vespa
        sleep 3
        setup_environment
        setup_permissions
        start_vespa
        echo ""
        show_status
        ;;
    logs)
        show_logs
        ;;
    status)
        show_status
        ;;
    cleanup)
        cleanup
        ;;
    help|--help|-h)
        show_help
        ;;
    *)
        echo -e "${RED}✗ Unknown command: $COMMAND${NC}"
        echo ""
        show_help
        exit 1
        ;;
esac
