#!/bin/bash
# Health monitoring functions for MTAV deployment
# This file is not meant to be executed directly - it provides health check functions for deploy.sh

# Function to wait for containers to be healthy
wait_for_containers_healthy() {
    local project_name="$1"
    shift
    local containers=("$@")
    local max_wait=300  # 5 minutes
    local wait_interval=5
    local elapsed=0

    while [ $elapsed -lt $max_wait ]; do
        local all_healthy=true

        for container in "${containers[@]}"; do
            local container_name="${project_name}-${container}-1"
            local status=$(docker container inspect "$container_name" --format='{{.State.Health.Status}}' 2>/dev/null || echo "unknown")

            if [ "$status" != "healthy" ] && [ "$status" != "" ]; then
                # If no health check is defined, check if container is running
                local state=$(docker container inspect "$container_name" --format='{{.State.Status}}' 2>/dev/null || echo "unknown")
                if [ "$state" != "running" ]; then
                    all_healthy=false
                    break
                fi
            elif [ "$status" != "healthy" ] && [ "$status" != "" ]; then
                all_healthy=false
                break
            fi
        done

        if [ "$all_healthy" = true ]; then
            return 0
        fi

        echo "  Waiting for containers to be healthy... (${elapsed}s/${max_wait}s)"
        sleep $wait_interval
        elapsed=$((elapsed + wait_interval))
    done

    print_error "Containers failed to become healthy within ${max_wait} seconds"
    return 1
}

# Function to wait for a single container to be healthy
wait_for_single_container_healthy() {
    local container_name="$1"
    local max_wait=300  # 5 minutes
    local wait_interval=5
    local elapsed=0

    while [ $elapsed -lt $max_wait ]; do
        local status=$(docker container inspect "$container_name" --format='{{.State.Health.Status}}' 2>/dev/null || echo "unknown")

        if [ "$status" = "healthy" ] || [ "$status" = "" ]; then
            # If no health check is defined, check if container is running
            if [ "$status" = "" ]; then
                local state=$(docker container inspect "$container_name" --format='{{.State.Status}}' 2>/dev/null || echo "unknown")
                if [ "$state" = "running" ]; then
                    return 0
                fi
            else
                return 0
            fi
        fi

        echo "  Waiting for $container_name to be healthy... (${elapsed}s/${max_wait}s)"
        sleep $wait_interval
        elapsed=$((elapsed + wait_interval))
    done

    print_error "Container $container_name failed to become healthy within ${max_wait} seconds"
    return 1
}

# Function to wait for a container to exit successfully (for run-once services like migrations)
wait_for_container_completion() {
    local container_name="$1"
    local max_wait=300  # 5 minutes
    local wait_interval=5
    local elapsed=0

    while [ $elapsed -lt $max_wait ]; do
        local state=$(docker container inspect "$container_name" --format='{{.State.Status}}' 2>/dev/null || echo "unknown")

        if [ "$state" = "exited" ]; then
            local exit_code=$(docker container inspect "$container_name" --format='{{.State.ExitCode}}' 2>/dev/null || echo "1")
            if [ "$exit_code" = "0" ]; then
                return 0
            else
                print_error "Container $container_name exited with code $exit_code"
                return 1
            fi
        elif [ "$state" = "unknown" ]; then
            print_error "Container $container_name not found"
            return 1
        fi

        echo "  Waiting for $container_name to complete... (${elapsed}s/${max_wait}s)"
        sleep $wait_interval
        elapsed=$((elapsed + wait_interval))
    done

    print_error "Container $container_name failed to complete within ${max_wait} seconds"
    return 1
}

# Function to cleanup leftover containers from previous failed deployments
cleanup_leftover_containers() {
    print_info "Cleaning up any leftover containers from previous deployments..."

    # Find and remove all -next-1 and -old-1 containers
    local leftover_containers=$(docker container ls -a --filter "name=-next-1" --filter "name=-old-1" --format "{{.Names}}" 2>/dev/null)

    if [ -n "$leftover_containers" ]; then
        echo "$leftover_containers" | while read -r container; do
            if [ -n "$container" ]; then
                print_info "  Removing leftover container: $container"
                docker container stop "$container" >/dev/null 2>&1 || true
                docker container rm "$container" >/dev/null 2>&1 || true
            fi
        done
        print_success "Cleanup complete"
    else
        echo "  No leftover containers found"
    fi
}

# Function to cleanup temporary containers
cleanup_temp_containers() {
    local containers=("$@")
    for container in "${containers[@]}"; do
        if docker container inspect "$container" >/dev/null 2>&1; then
            print_info "Cleaning up temporary container: $container"
            docker container stop "$container" >/dev/null 2>&1 || true
            docker container rm "$container" >/dev/null 2>&1 || true
        fi
    done
}