#!/usr/bin/env bash

set -euo pipefail

SRC="/Applications/WeChat.app"
BASE_BUNDLE_ID="com.tencent.xinWeChat"

# Scan existing WeChat copies
scan_wechat_copies() {
    local copies=()
    for i in {2..99}; do
        local app="/Applications/WeChat${i}.app"
        if [ -d "$app" ]; then
            copies+=("$i")
        fi
    done
    echo "${copies[@]:-}"
}

# Get copy count
get_copy_count() {
    local copies=($(scan_wechat_copies))
    echo "${#copies[@]}"
}

# Create a single copy
create_copy() {
    local num=$1
    local dst="/Applications/WeChat${num}.app"
    local bundle_id="${BASE_BUNDLE_ID}${num}"

    echo "Creating WeChat${num}.app..."

    # Copy the application
    sudo cp -R "$SRC" "$dst"

    # Modify Bundle ID
    sudo /usr/libexec/PlistBuddy -c "Set :CFBundleIdentifier $bundle_id" \
        "$dst/Contents/Info.plist"

    # Modify display name
    sudo /usr/libexec/PlistBuddy -c "Set :CFBundleName WeChat${num}" \
        "$dst/Contents/Info.plist" || true
    sudo /usr/libexec/PlistBuddy -c "Set :CFBundleDisplayName WeChat${num}" \
        "$dst/Contents/Info.plist" || true

    # Clear extended attributes
    sudo xattr -cr "$dst" || true

    # Re-sign the application
    sudo codesign --force --deep --sign - "$dst" || {
        echo "Warning: Could not sign WeChat${num}.app"
    }

    # Fix permissions
    sudo chown -R "$(whoami)" "$dst"

    echo "WeChat${num}.app created successfully!"
}

# Create multiple copies to reach a total instance count
create_instances() {
    local total_instances=$1
    local target_copies=$((total_instances - 1))
    local copies=($(scan_wechat_copies))
    local current_count="${#copies[@]}"

    if [ "$current_count" -ge "$target_copies" ]; then
        echo "Already have $((current_count + 1)) instances, no need to create more."
        return
    fi

    local to_create=$((target_copies - current_count))
    echo "Creating $to_create additional copies to reach $total_instances total instances."

    local next_num=2
    for ((i=1; i<=to_create; i++)); do
        while [ -d "/Applications/WeChat${next_num}.app" ]; do
            ((next_num++))
        done
        create_copy "$next_num"
        ((next_num++))
    done

    echo "Done! Now have $total_instances WeChat instances."
}

# Check current instances
check_instances() {
    local copies=($(scan_wechat_copies))
    local count="${#copies[@]}"
    echo "You have $((count + 1)) WeChat instances."
}

# Main function
main() {
    # Check if WeChat app exists
    if [ ! -d "$SRC" ]; then
        echo "Error: WeChat app not found at $SRC"
        exit 1
    fi

    if [ $# -eq 0 ]; then
        # Default: check instances
        check_instances
    else
        command=$1
        case "$command" in
            check)
                check_instances
                ;;
            create)
                if [ $# -lt 2 ]; then
                    echo "Usage: $0 create <total_instances>"
                    exit 1
                fi
                if ! [[ "$2" =~ ^[0-9]+$ ]] || [ "$2" -lt 2 ] || [ "$2" -gt 20 ]; then
                    echo "Error: Total instances must be a number between 2 and 20"
                    exit 1
                fi
                create_instances "$2"
                ;;
            *)
                echo "Usage: $0 [check|create <total_instances>]"
                exit 1
                ;;
        esac
    fi
}

main "$@"
