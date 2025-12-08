#!/bin/bash
# Common utilities for MTAV deployment
# This file is not meant to be executed directly - it provides shared functions for deploy.sh

# Color codes
GREEN='\033[0;32m'
BLUE='\033[0;34m'
YELLOW='\033[1;33m'
RED='\033[0;31m'
NC='\033[0m'

# Logging functions
print_info() { echo -e "${BLUE}ℹ️  $1${NC}"; }
print_success() { echo -e "${GREEN}✅ $1${NC}"; }
print_warning() { echo -e "${YELLOW}⚠️  $1${NC}"; }
print_error() { echo -e "${RED}❌ $1${NC}"; }

# Function to run docker compose with consistent options and environment variables
run_docker_compose() {
    local cmd_args=("$@")

    # Export environment variables for docker compose
    export APP_KEY="${APP_KEY:-}"
    export APP_PREVIOUS_KEYS="${APP_PREVIOUS_KEYS:-}"

    # Export service-specific TAG environment variables from target versions
    export PHP_TAG="${TARGET_PHP:-}"
    export ASSETS_TAG="${TARGET_ASSETS:-}"
    export NGINX_TAG="${TARGET_NGINX:-}"
    export MYSQL_TAG="${TARGET_MYSQL:-}"
    export MIGRATIONS_TAG="${TARGET_MIGRATIONS:-}"    # Run docker compose with consistent options
    docker compose --project-name prod -f "$COMPOSE_FILE" --env-file "$ENV_FILE" "${cmd_args[@]}"
}