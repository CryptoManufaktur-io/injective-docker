#!/usr/bin/env bats

# Setup and teardown functions
setup() {
    # Create a temporary directory for testing
    export TEST_DIR="$(mktemp -d)"
    export ORIGINAL_DIR="$(pwd)"
    cd "$TEST_DIR"

    # Copy the ethd script to test directory
    cp "$ORIGINAL_DIR/ethd" .
    chmod +x ethd

    # Create mock files
    echo "This is Injective Node Docker v1.0.0" > README.md
    echo "ENV_VERSION=1" > default.env
    echo "COMPOSE_FILE=injective.yml" >> default.env
    echo "INJECTIVE_TAG=latest" >> default.env
    echo "INJECTIVE_REPO=injectiveprotocol/core" >> default.env

    # Create initial .env file
    cp default.env .env

    # Mock git repository
    git init --quiet
    git config user.email "test@example.com"
    git config user.name "Test User"
    git add .
    git commit -m "Initial commit" --quiet
}

teardown() {
    cd "$ORIGINAL_DIR"
    rm -rf "$TEST_DIR"
}

# Test basic script execution and help
@test "ethd displays help when run without arguments" {
    run ./ethd
    [ "$status" -eq 0 ]
    [[ "$output" =~ "usage:" ]]
    [[ "$output" =~ "commands:" ]]
}

@test "ethd displays help with --help flag" {
    run ./ethd --help
    [ "$status" -eq 0 ]
    [[ "$output" =~ "usage:" ]]
    [[ "$output" =~ "commands:" ]]
}

@test "ethd displays help with -h flag" {
    run ./ethd -h
    [ "$status" -eq 0 ]
    [[ "$output" =~ "usage:" ]]
    [[ "$output" =~ "commands:" ]]
}

@test "ethd help command works" {
    run ./ethd help
    [ "$status" -eq 0 ]
    [[ "$output" =~ "usage:" ]]
    [[ "$output" =~ "install" ]]
    [[ "$output" =~ "update" ]]
    [[ "$output" =~ "start" ]]
}

@test "ethd help update shows update-specific help" {
    run ./ethd help update
    [ "$status" -eq 0 ]
    [[ "$output" =~ "usage: ./ethd update" ]]
    [[ "$output" =~ "--refresh-targets" ]]
    [[ "$output" =~ "--non-interactive" ]]
}

@test "ethd detects when docker is not available" {
    # Remove docker from PATH
    export PATH="/usr/bin:/bin"

    run ./ethd start
    [ "$status" -ne 0 ]
}

@test "ethd rejects unrecognized commands" {
    run ./ethd invalid_command
    [ "$status" -ne 0 ]
    [[ "$output" =~ "Unrecognized command" ]]
}

# Test space functionality
@test "space command structure works" {
    # Mock docker commands
    export PATH="$TEST_DIR/mock:$PATH"
    mkdir -p mock

    cat > mock/docker << 'EOF'
#!/bin/bash
case "$*" in
    *"system info --format"*)
        echo "/var/lib/docker"
        ;;
    *"volume ls"*)
        echo ""
        ;;
    *"run --rm -v macos-space-check"*)
        echo "Filesystem     1K-blocks    Used Available Use% Mounted on"
        echo "/dev/disk1     1000000000 500000000 500000000  50% /dummy"
        ;;
    *)
        exit 0
        ;;
esac
EOF
    chmod +x mock/docker

    # Mock df command
    cat > mock/df << 'EOF'
#!/bin/bash
echo "Filesystem     1K-blocks    Used Available Use% Mounted on"
echo "/dev/sda1      1000000000 500000000 500000000  50% /var/lib/docker"
EOF
    chmod +x mock/df

    run ./ethd space
    [ "$status" -eq 0 ]
    [[ "$output" =~ "free" ]]
}

# Test error handling
@test "ethd handles missing .env file gracefully" {
    rm -f .env

    # Mock docker commands to avoid actual docker calls
    export PATH="$TEST_DIR/mock:$PATH"
    mkdir -p mock

    cat > mock/docker << 'EOF'
#!/bin/bash
exit 0
EOF
    chmod +x mock/docker

    run ./ethd version
    # Should not crash, may have specific behavior for missing .env
    [[ "$status" -eq 0 ]]
    [[ "$output" =~ "No environment file (.env) found. Please create one before proceeding." ]]
}

@test "ethd prevents running as root user" {
    # Mock the ownership check
    export PATH="$TEST_DIR/mock:$PATH"
    mkdir -p mock

    cat > mock/ls << 'EOF'
#!/bin/bash
if [[ "$*" =~ "-ld ." ]]; then
    echo "drwxr-xr-x 2 root root 4096 Jan 1 00:00 ."
fi
EOF
    chmod +x mock/ls

    run ./ethd start
    [ "$status" -eq 0 ]  # Should exit gracefully with message
    [[ "$output" =~ "non-root user" ]]
}

# Test command aliases
@test "up command is alias for start" {
    export PATH="$TEST_DIR/mock:$PATH"
    mkdir -p mock

    cat > mock/docker << 'EOF'
#!/bin/bash
exit 0
EOF
    chmod +x mock/docker

    run ./ethd up --help
    # Should not error out and should be treated as start command
    # The specific behavior depends on docker compose
    [[ "$status" -eq 0 || "$status" -eq 1 ]]
}

@test "down command is alias for stop" {
    export PATH="$TEST_DIR/mock:$PATH"
    mkdir -p mock

    cat > mock/docker << 'EOF'
#!/bin/bash
exit 0
EOF
    chmod +x mock/docker

    run ./ethd down --help
    # Should not error out and should be treated as stop command
    [[ "$status" -eq 0 || "$status" -eq 1 ]]
}

# Test install command requirements
@test "install command requires sudo capabilities" {
    # Mock groups command to not include sudo
    export PATH="$TEST_DIR/mock:$PATH"
    mkdir -p mock

    cat > mock/groups << 'EOF'
#!/bin/bash
echo "user wheel"
EOF
    chmod +x mock/groups

    # Mock id command to return non-zero EUID
    cat > mock/id << 'EOF'
#!/bin/bash
if [[ "$*" =~ "-u" ]]; then
    echo "1000"
fi
EOF
    chmod +x mock/id

    run ./ethd install
    [ "$status" -eq 1 ]
    [[ "$output" =~ "sudo group" ]]
}

# Test terminate command safety
@test "terminate command requires confirmation" {
    export PATH="$TEST_DIR/mock:$PATH"
    mkdir -p mock

    cat > mock/docker << 'EOF'
#!/bin/bash
if [[ "$*" =~ "volume ls" ]]; then
    echo "test_volume_1"
    echo "test_volume_2"
fi
exit 0
EOF
    chmod +x mock/docker

    # Simulate "No" response
    run bash -c 'echo "No" | ./ethd terminate'
    [ "$status" -eq 130 ]
    [[ "$output" =~ "WARNING" ]]
    [[ "$output" =~ "Aborting" ]]
}