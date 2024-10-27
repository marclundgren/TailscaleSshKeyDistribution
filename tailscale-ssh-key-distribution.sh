#!/bin/bash

# Exit on any error
set -e

# Get current username
CURRENT_USER=$(whoami)

# Get current hostname to exclude from the list
CURRENT_HOSTNAME=$(hostname)

# Get list of online Tailscale nodes, excluding the current device and filtering for specific OS types
echo "Getting list of online Tailscale nodes..."
NODES=$(tailscale status | awk -v hostname="$CURRENT_HOSTNAME" '
    NR>1 && 
    $2 != hostname && 
    $5 == "-" && 
    ($4 == "macOS" || $4 == "linux" || $4 == "windows") {
        print $1 " " $2
    }
')

if [ -z "$NODES" ]; then
    echo "No eligible Tailscale nodes found."
    exit 0
fi

# Display found nodes before proceeding
echo "Found the following eligible nodes:"
echo "$NODES" | while read -r ip hostname; do
    echo "- $hostname ($ip)"
done
echo

# Check if ssh-copy-id is available
if ! command -v ssh-copy-id &> /dev/null; then
    echo "Error: ssh-copy-id command not found. Please install openssh-client package."
    exit 1
fi

# Check if SSH key exists, if not generate one
SSH_KEY_FILE="$HOME/.ssh/id_rsa"
if [ ! -f "$SSH_KEY_FILE" ]; then
    echo "No SSH key found. Generating new SSH key..."
    ssh-keygen -t rsa -N "" -f "$SSH_KEY_FILE"
fi

# Function to copy SSH key with timeout using perl
copy_ssh_key() {
    local ip=$1
    local hostname=$2
    local timeout_seconds=30
    
    echo "Attempting to copy SSH key to ${hostname} (${ip})..."
    
    # Use perl to implement timeout
    if perl -e '
        use strict;
        use IPC::Open3;
        
        my $pid = open3(undef, undef, undef, 
            "ssh-copy-id", "-o", "StrictHostKeyChecking=accept-new", 
            "'${CURRENT_USER}@${ip}'");
        
        # Set alarm for timeout
        eval {
            local $SIG{ALRM} = sub { die "timeout\n" };
            alarm('$timeout_seconds');
            waitpid($pid, 0);
            alarm(0);
        };
        
        if ($@ eq "timeout\n") {
            kill("TERM", $pid);
            exit(1);
        }
        
        exit($? >> 8);
    '; then
        echo "✓ Successfully copied SSH key to ${hostname}"
        return 0
    else
        echo "✗ Failed to copy SSH key to ${hostname}"
        return 1
    fi
}

# Counter for successful and failed attempts
success_count=0
failed_count=0

# Process each node
while read -r ip hostname; do
    if copy_ssh_key "$ip" "$hostname"; then
        ((success_count++))
    else
        ((failed_count++))
    fi
    echo "----------------------------------------"
done <<< "$NODES"

# Print summary
echo "Summary:"
echo "Successfully copied SSH key to ${success_count} node(s)"
echo "Failed to copy SSH key to ${failed_count} node(s)"

if [ $failed_count -eq 0 ]; then
    echo "✓ All SSH keys were copied successfully!"
    exit 0
else
    echo "⚠ Some SSH key copies failed. Please check the output above for details."
    exit 1
fi