#!/bin/bash
# Deployment strategy functions for MTAV deployment
# This file is not meant to be executed directly - it provides deployment strategy functions for deploy.sh

# Function to get target tag for a service
get_service_target_tag() {
    local service="$1"
    case "$service" in
        "php")
            echo "$TARGET_PHP"
            ;;
        "assets")
            echo "$TARGET_ASSETS"
            ;;
        "nginx")
            echo "$TARGET_NGINX"
            ;;
        "mysql")
            echo "$TARGET_MYSQL"
            ;;
        "migrations")
            echo "$TARGET_MIGRATIONS"
            ;;
        *)
            echo "ERROR: Unknown service: $service" >&2
            exit 1
            ;;
    esac
}

# Function to perform deployment with MySQL special handling
perform_blue_green_deployment() {
    local services_needing_deployment=()
    local mysql_needs_deployment=false
    local non_mysql_services=()

    # Extract service names from SERVICES_TO_DEPLOY array
    for service_info in "${SERVICES_TO_DEPLOY[@]}"; do
        # Extract service name (everything before the first space)
        service_name=$(echo "$service_info" | cut -d' ' -f1)
        services_needing_deployment+=("$service_name")

        if [ "$service_name" = "MySQL" ]; then
            mysql_needs_deployment=true
        else
            non_mysql_services+=("${service_name,,}")  # Convert to lowercase for docker compose
        fi
    done

    if [ ${#services_needing_deployment[@]} -eq 0 ]; then
        print_success "No services need deployment. Exiting."
        return 0
    fi

    print_info "Services to deploy: ${services_needing_deployment[*]}"
    echo ""

    # Cleanup any leftover containers from previous failed deployments
    cleanup_leftover_containers

    # Special handling for MySQL deployment
    if [ "$mysql_needs_deployment" = true ]; then
        deploy_mysql_with_downtime
    fi

    # Blue-green deployment for non-MySQL services
    if [ ${#non_mysql_services[@]} -gt 0 ]; then
        print_info "Phase 2: Blue-green deployment for remaining services..."
        deploy_non_mysql_services "${non_mysql_services[@]}"
    fi

    # Restart nginx if PHP or Assets were deployed (to refresh backend connections)
    local needs_nginx_restart=false
    for service in "${non_mysql_services[@]}"; do
        if [ "$service" = "php" ] || [ "$service" = "assets" ]; then
            needs_nginx_restart=true
            break
        fi
    done

    if [ "$needs_nginx_restart" = true ]; then
        # Check if nginx was already deployed (don't restart if it was just deployed)
        local nginx_was_deployed=false
        for service in "${non_mysql_services[@]}"; do
            if [ "$service" = "nginx" ]; then
                nginx_was_deployed=true
                break
            fi
        done

        if [ "$nginx_was_deployed" = false ] && docker container inspect "prod-nginx-1" >/dev/null 2>&1; then
            print_info "Restarting nginx to refresh backend connections..."
            docker restart prod-nginx-1 >/dev/null 2>&1
            print_success "Nginx restarted"
        fi
    fi

    print_success "Deployment completed successfully!"
    print_info "Deployment summary:"
    for service in "${services_needing_deployment[@]}"; do
        echo "  ✅ $service: Updated and running"
    done
}

# Function to deploy MySQL with planned downtime
deploy_mysql_with_downtime() {
    print_warning "⚠️  MySQL deployment detected!"
    print_warning "   This will cause brief database downtime during MySQL restart."
    print_warning "   All database connections will be interrupted temporarily."
    echo ""
    read -p "Continue with MySQL deployment? (y/N): " -n 1 -r
    echo
    if [[ ! $REPLY =~ ^[Yy]$ ]]; then
        print_info "MySQL deployment cancelled by user."
        exit 0
    fi
    echo ""

    print_info "Phase 1: Deploying MySQL with downtime..."

    # Stop old MySQL container
    if docker container inspect "prod-mysql-1" >/dev/null 2>&1; then
        print_info "Stopping old MySQL container..."
        TAG="$TARGET_MYSQL" run_docker_compose stop mysql

        print_info "Renaming old MySQL container to backup..."
        docker container rename "prod-mysql-1" "prod-mysql-old-1"
    fi

    # Start new MySQL container
    print_info "Starting new MySQL container..."

    if ! TAG="$TARGET_MYSQL" run_docker_compose up -d mysql; then
        print_error "Failed to start new MySQL container. Attempting rollback..."
        # Rollback MySQL
        if docker container inspect "prod-mysql-old-1" >/dev/null 2>&1; then
            docker container rename "prod-mysql-old-1" "prod-mysql-1"
            TAG="$TARGET_MYSQL" run_docker_compose start mysql
        fi
        exit 1
    fi

    # Wait for MySQL to be healthy
    print_info "Waiting for MySQL to be ready..."
    if ! wait_for_containers_healthy "prod" "mysql"; then
        print_error "New MySQL container failed health checks. Manual intervention required."
        exit 1
    fi

    # Clean up old MySQL container
    if docker container inspect "prod-mysql-old-1" >/dev/null 2>&1; then
        print_info "Removing old MySQL container..."
        docker container rm "prod-mysql-old-1" >/dev/null 2>&1 || true
    fi

    print_success "MySQL deployment completed!"
    echo ""
}

# Function to deploy non-MySQL services with blue-green strategy
deploy_non_mysql_services() {
    local services=("$@")

    print_info "Deploying services: ${services[*]}"

    # Start new containers with temporary names
    print_info "Starting candidate containers..."
    local temp_containers=()

    for service in "${services[@]}"; do
        local temp_name="prod-${service}-next-1"
        temp_containers+=("$temp_name")

        print_info "Starting candidate $service container..."

        # Get the target tag for this service
        local service_tag=$(get_service_target_tag "$service")

        # Use 'run' with --use-aliases to ensure proper service discovery
        # For nginx, this tests it works but without port binding (to avoid conflicts)
        if ! TAG="$service_tag" run_docker_compose run --use-aliases -d --name "$temp_name" "$service"; then
            print_error "Failed to start candidate $service container."
            cleanup_temp_containers "${temp_containers[@]}"
            exit 1
        fi
    done    # Wait for all new containers to be ready
    print_info "Waiting for candidate containers to be ready..."
    local all_ready=true
    for service in "${services[@]}"; do
        local temp_name="prod-${service}-next-1"

        if [ "$service" = "migrations" ]; then
            # Migrations is a run-once service - wait for successful completion
            if ! wait_for_container_completion "$temp_name"; then
                print_error "Candidate $service container failed to complete successfully."
                all_ready=false
                break
            fi
        else
            # Regular services - wait for health checks
            if ! wait_for_single_container_healthy "$temp_name"; then
                print_error "Candidate $service container failed health checks."
                all_ready=false
                break
            fi
        fi
    done

    if [ "$all_ready" != true ]; then
        print_error "Readiness checks failed. Rolling back candidate containers..."
        cleanup_temp_containers "${temp_containers[@]}"
        exit 1
    fi

    print_success "All candidate containers are ready!"

    # Atomic swap: rename containers
    print_info "Performing atomic container swap..."

    # Handle nginx port conflict specially
    local nginx_in_deployment=false
    for service in "${services[@]}"; do
        if [ "$service" = "nginx" ]; then
            nginx_in_deployment=true
            break
        fi
    done

    if [ "$nginx_in_deployment" = true ]; then
        # Stop old nginx first to release port 8080
        if docker container inspect "prod-nginx-1" >/dev/null 2>&1; then
            print_info "Stopping old nginx to release port 8080..."
            docker container stop "prod-nginx-1" >/dev/null 2>&1 || true
            docker container rename "prod-nginx-1" "prod-nginx-old-1"
        fi
    fi

    # Rename old containers to backup (except nginx, already handled)
    for service in "${services[@]}"; do
        if [ "$service" != "nginx" ] && docker container inspect "prod-${service}-1" >/dev/null 2>&1; then
            print_info "Backing up old $service container..."
            docker container stop "prod-${service}-1" >/dev/null 2>&1 || true
            docker container rename "prod-${service}-1" "prod-${service}-old-1"
        fi
    done

    # Rename new containers to production names (except nginx)
    for service in "${services[@]}"; do
        if [ "$service" != "nginx" ]; then
            local temp_name="prod-${service}-next-1"
            local prod_name="prod-${service}-1"
            print_info "Activating new $service container..."
            docker container rename "$temp_name" "$prod_name"
        fi
    done

    # Atomic nginx swap with brief downtime (unavoidable for port binding swap)
    if [ "$nginx_in_deployment" = true ]; then
        print_info "Performing atomic nginx swap (brief downtime for port rebinding)..."
        # Stop and remove the test nginx
        docker container stop "prod-nginx-next-1" >/dev/null 2>&1 || true
        docker container rm "prod-nginx-next-1" >/dev/null 2>&1 || true
        # Start new nginx with proper port binding
        TAG="$TARGET_NGINX" run_docker_compose up -d nginx
    fi

    # Clean up old containers
    print_info "Cleaning up old containers..."
    for service in "${services[@]}"; do
        local old_name="prod-${service}-old-1"
        if docker container inspect "$old_name" >/dev/null 2>&1; then
            print_info "Removing old $service container..."
            docker container rm "$old_name" >/dev/null 2>&1 || true
        fi
    done

    print_success "Blue-green deployment completed for: ${services[*]}"
}