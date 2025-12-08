#!/bin/bash

# MTAV Production Deployment Script
# Usage: deploy.sh [--new-app-key] [docker-compose-args...]

set -e

# Get the directory of this script
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

# Import deployment modules
source "$SCRIPT_DIR/lib/common.sh"
source "$SCRIPT_DIR/lib/secrets.sh"
source "$SCRIPT_DIR/lib/versions.sh"
source "$SCRIPT_DIR/lib/health.sh"
source "$SCRIPT_DIR/lib/deployment.sh"

# Parse arguments
NEW_APP_KEY=false
DOCKER_ARGS=()

while [[ $# -gt 0 ]]; do
    case $1 in
        --new-app-key)
            NEW_APP_KEY=true
            shift
            ;;
        -h|--help)
            echo "Usage: $0 [--new-app-key] [docker-compose-args...]"
            echo ""
            echo "Options:"
            echo "  --new-app-key    Generate and add a new APP_KEY to .secrets file"
            echo "  -h, --help       Show this help message"
            echo ""
            echo "Examples:"
            echo "  $0                    # Deploy using existing APP_KEY"
            echo "  $0 --new-app-key      # Deploy with a new APP_KEY (old keys still work)"
            echo "  $0 -d                 # Deploy in detached mode"
            exit 0
            ;;
        *)
            DOCKER_ARGS+=("$1")
            shift
            ;;
    esac
done

# Configuration
COMPOSE_FILE="compose.yml"
ENV_FILE=".env"
SECRETS_FILE=".secrets"

print_info "MTAV Production Deployment"
print_info "Using env file: ${ENV_FILE}"
print_info "Using secrets file: ${SECRETS_FILE}"
echo ""

# Manage secrets file
manage_secrets

# Check if compose file exists
if [ ! -f "$COMPOSE_FILE" ]; then
    print_error "Compose file not found: $COMPOSE_FILE"
    exit 1
fi

# Check if env file exists
if [ ! -f "$ENV_FILE" ]; then
    print_error "Environment file not found: $ENV_FILE"
    exit 1
fi

# Setup environment variables from secrets
setup_environment

print_success "Secrets management complete!"
echo ""

# Load target versions
get_target_versions
echo ""

# Get running versions
get_running_versions
echo ""

# Check what needs deployment and get confirmation
check_deployment_needed
echo ""

print_info "Environment variables set:"
echo "APP_KEY=${APP_KEY:0:20}... (truncated for security)"
if [ -n "$APP_PREVIOUS_KEYS" ]; then
    echo "APP_PREVIOUS_KEYS=<${#APP_PREVIOUS_KEYS} characters> (hidden for security)"
fi
echo ""

# Blue-Green Deployment Strategy
print_info "Starting deployment with MySQL special handling..."

# Execute the deployment
perform_blue_green_deployment