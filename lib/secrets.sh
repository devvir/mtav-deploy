#!/bin/bash
# Secrets management functions for MTAV deployment
# This file is not meant to be executed directly - it provides secrets handling functions for deploy.sh

# Function to generate a new APP_KEY
generate_app_key() {
    openssl rand -base64 32
}

# Function to handle .secrets file management
manage_secrets() {
    if [ "$NEW_APP_KEY" = true ]; then
        print_info "Generating new APP_KEY..."
        NEW_KEY="base64:$(generate_app_key)"

        if [ ! -f "$SECRETS_FILE" ]; then
            # Create new .secrets file
            print_info "Creating new .secrets file..."
            echo "APP_KEY=$NEW_KEY" > "$SECRETS_FILE"
            print_success "Created .secrets with new APP_KEY"
        else
            # Read existing file and rotate keys
            print_info "Rotating APP_KEY in existing .secrets file..."

            # Read current APP_KEY
            CURRENT_KEY=""
            if grep -q "^APP_KEY=" "$SECRETS_FILE"; then
                CURRENT_KEY=$(grep "^APP_KEY=" "$SECRETS_FILE" | cut -d'=' -f2-)
            fi

            # Read existing previous keys (if any)
            EXISTING_PREVIOUS=""
            if grep -q "^APP_PREVIOUS_KEYS=" "$SECRETS_FILE"; then
                EXISTING_PREVIOUS=$(grep "^APP_PREVIOUS_KEYS=" "$SECRETS_FILE" | cut -d'=' -f2-)
            fi

            # Build new previous keys list
            if [ -n "$CURRENT_KEY" ]; then
                if [ -n "$EXISTING_PREVIOUS" ]; then
                    NEW_PREVIOUS="$EXISTING_PREVIOUS,$CURRENT_KEY"
                else
                    NEW_PREVIOUS="$CURRENT_KEY"
                fi
            else
                NEW_PREVIOUS="$EXISTING_PREVIOUS"
            fi

            # Write updated file
            echo "APP_KEY=$NEW_KEY" > "$SECRETS_FILE"
            if [ -n "$NEW_PREVIOUS" ]; then
                echo "APP_PREVIOUS_KEYS=$NEW_PREVIOUS" >> "$SECRETS_FILE"
            fi

            print_success "APP_KEY rotated and added to .secrets"
        fi
    else
        # Check if .secrets exists when not generating new key
        if [ ! -f "$SECRETS_FILE" ]; then
            print_error "No .secrets file found!"
            echo ""
            echo "You need to either:"
            echo "  1. Run this script with --new-app-key flag (recommended):"
            echo "     $0 --new-app-key"
            echo ""
            echo "  2. Create .secrets file manually with the format:"
            echo "     APP_KEY=base64:your_key_here"
            echo ""
            exit 1
        fi

        # Validate that .secrets contains a proper APP_KEY
        if ! grep -q "^APP_KEY=base64:" "$SECRETS_FILE"; then
            print_error "Invalid or missing APP_KEY in .secrets file!"
            echo ""
            echo "The .secrets file exists but doesn't contain a valid APP_KEY."
            echo "Expected format: APP_KEY=base64:your_key_here"
            echo ""
            echo "You can either:"
            echo "  1. Run this script with --new-app-key to generate a new key:"
            echo "     $0 --new-app-key"
            echo ""
            echo "  2. Fix the .secrets file manually with the correct format"
            echo ""
            exit 1
        fi

        print_info "Using existing .secrets file"
    fi
}

# Function to read secrets and set environment variables
setup_environment() {
    if [ -f "$SECRETS_FILE" ]; then
        print_info "Loading secrets for deployment..."

        # Read APP_KEY
        if grep -q "^APP_KEY=" "$SECRETS_FILE"; then
            export APP_KEY=$(grep "^APP_KEY=" "$SECRETS_FILE" | cut -d'=' -f2-)
            print_success "APP_KEY loaded from .secrets"
        fi

        # Read APP_PREVIOUS_KEYS
        if grep -q "^APP_PREVIOUS_KEYS=" "$SECRETS_FILE"; then
            export APP_PREVIOUS_KEYS=$(grep "^APP_PREVIOUS_KEYS=" "$SECRETS_FILE" | cut -d'=' -f2-)
            print_success "APP_PREVIOUS_KEYS loaded from .secrets"
        fi
    fi
}