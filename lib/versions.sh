#!/bin/bash
# Version management functions for MTAV deployment
# This file is not meant to be executed directly - it provides version handling functions for deploy.sh

# Function to read version.yml and get target versions
get_target_versions() {
    local version_file="version.yml"

    if [ ! -f "$version_file" ]; then
        print_error "Version file not found: $version_file"
        exit 1
    fi

    print_info "Reading target versions from $version_file..."

    # Read service versions from version.yml
    TARGET_PHP=$(grep "^php:" "$version_file" | sed "s/php: *['\"]//g" | sed "s/['\"] *$//g")
    TARGET_ASSETS=$(grep "^assets:" "$version_file" | sed "s/assets: *['\"]//g" | sed "s/['\"] *$//g")
    TARGET_NGINX=$(grep "^nginx:" "$version_file" | sed "s/nginx: *['\"]//g" | sed "s/['\"] *$//g")
    TARGET_MYSQL=$(grep "^mysql:" "$version_file" | sed "s/mysql: *['\"]//g" | sed "s/['\"] *$//g")
    TARGET_MIGRATIONS=$(grep "^migrations:" "$version_file" | sed "s/migrations: *['\"]//g" | sed "s/['\"] *$//g")

    print_success "Target versions loaded:"
    echo "  PHP: $TARGET_PHP"
    echo "  Assets: $TARGET_ASSETS"
    echo "  Nginx: $TARGET_NGINX"
    echo "  MySQL: $TARGET_MYSQL"
    echo "  Migrations: $TARGET_MIGRATIONS"
}

# Function to get currently running versions
get_running_versions() {
    print_info "Checking currently running container versions..."

    # Initialize running versions (empty if not running)
    RUNNING_PHP=""
    RUNNING_ASSETS=""
    RUNNING_NGINX=""
    RUNNING_MYSQL=""
    RUNNING_MIGRATIONS=""

    # Check if docker compose is available and has running containers
    if run_docker_compose ps > /dev/null 2>&1; then
        # Get running services and their images (using format without table to get tab separation)
        local running_services=$(run_docker_compose ps --format "{{.Service}}\t{{.Image}}")

        # Parse each running service
        while IFS=$'\t' read -r service image; do
            if [ -n "$service" ] && [ -n "$image" ]; then
                # Extract version tag from image (after the colon)
                local version=$(echo "$image" | grep -o ':[^:]*$' | sed 's/^://')

                case "$service" in
                    "php")
                        RUNNING_PHP="$version"
                        ;;
                    "assets")
                        RUNNING_ASSETS="$version"
                        ;;
                    "nginx")
                        RUNNING_NGINX="$version"
                        ;;
                    "mysql")
                        RUNNING_MYSQL="$version"
                        ;;
                    "migrations")
                        RUNNING_MIGRATIONS="$version"
                        ;;
                esac
            fi
        done <<< "$running_services"
    fi

    print_success "Currently running versions:"
    echo "  PHP: ${RUNNING_PHP:-not running}"
    echo "  Assets: ${RUNNING_ASSETS:-not running}"
    echo "  Nginx: ${RUNNING_NGINX:-not running}"
    echo "  MySQL: ${RUNNING_MYSQL:-not running}"
    echo "  Migrations: ${RUNNING_MIGRATIONS:-not running}"
}

# Function to determine which services need deployment
check_deployment_needed() {
    print_info "Comparing target vs running versions..."

    SERVICES_TO_DEPLOY=()

    # Check each service
    if [ "$TARGET_PHP" != "$RUNNING_PHP" ]; then
        SERVICES_TO_DEPLOY+=("PHP ($RUNNING_PHP → $TARGET_PHP)")
    fi

    if [ "$TARGET_ASSETS" != "$RUNNING_ASSETS" ]; then
        SERVICES_TO_DEPLOY+=("Assets ($RUNNING_ASSETS → $TARGET_ASSETS)")
    fi

    if [ "$TARGET_NGINX" != "$RUNNING_NGINX" ]; then
        SERVICES_TO_DEPLOY+=("Nginx ($RUNNING_NGINX → $TARGET_NGINX)")
    fi

    if [ "$TARGET_MYSQL" != "$RUNNING_MYSQL" ]; then
        SERVICES_TO_DEPLOY+=("MySQL ($RUNNING_MYSQL → $TARGET_MYSQL)")
    fi

    if [ "$TARGET_MIGRATIONS" != "$RUNNING_MIGRATIONS" ]; then
        SERVICES_TO_DEPLOY+=("Migrations ($RUNNING_MIGRATIONS → $TARGET_MIGRATIONS)")
    fi

    echo ""

    if [ ${#SERVICES_TO_DEPLOY[@]} -eq 0 ]; then
        print_success "All services are already running the target versions!"
        print_info "No deployment needed."
        exit 0
    else
        print_warning "The following services will be deployed:"
        for service in "${SERVICES_TO_DEPLOY[@]}"; do
            echo "  • $service"
        done
        echo ""

        # Ask for confirmation
        read -p "Continue with deployment? (y/N): " -n 1 -r
        echo
        if [[ ! $REPLY =~ ^[Yy]$ ]]; then
            print_info "Deployment cancelled by user."
            exit 0
        fi

        print_success "Proceeding with deployment..."
    fi
}