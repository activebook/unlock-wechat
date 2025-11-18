#!/bin/bash

# Source environment variables
source ./env

set -e

# Check if required files exist
if [ ! -f "UnlockWeChat.exe" ] || [ ! -f "openmulti.dll" ] || [ ! -f "public.key" ]; then
    echo "Error: Required Windows files missing: UnlockWeChat.exe, openmulti.dll, or public.key"
    exit 1
fi

if [ ! -d "mac/UnLockWeChat.app" ]; then
    echo "Error: Required Mac file missing: mac/UnLockWeChat.app"
    exit 1
fi

echo "Creating Windows zip archive..."
zip UnlockWeChat-windows.zip UnlockWeChat.exe openmulti.dll public.key

echo "Creating Mac zip archive..."
cd mac && zip -r ../UnlockWeChat-mac.zip UnLockWeChat.app && cd ..

echo "Fetching latest tags from remote..."
git fetch --tags origin

# Get the latest tag (if any)
latest_tag=$(git describe --tags $(git rev-list --tags --max-count=1) 2>/dev/null || echo "")

if [ -z "$latest_tag" ]; then
    # No tags exist
    new_tag="v1.0.0"
    echo "No existing tags found. Creating initial release: $new_tag"
else
    # Check if there are new commits since latest tag
    tag_commit=$(git rev-parse "$latest_tag^{}")
    head_commit=$(git rev-parse HEAD)

    if [ "$tag_commit" = "$head_commit" ]; then
        echo "no update"
        rm UnlockWeChat-windows.zip UnlockWeChat-mac.zip
        exit 0
    fi

    # Increment patch version of latest tag
    version=${latest_tag#v}  # Remove 'v' prefix
    IFS='.' read -r major minor patch <<< "$version"
    new_patch=$((patch + 1))
    new_tag="v${major}.${minor}.${new_patch}"
    echo "New commits detected. Creating new release: $new_tag"
fi

# Create and push the new tag
echo "Creating tag $new_tag..."
git tag "$new_tag"
git push origin "$new_tag"

# Create GitHub release with the zip files
echo "Creating GitHub release..."
gh release create "$new_tag" UnlockWeChat-windows.zip UnlockWeChat-mac.zip --generate-notes -R activebook/unlock-wechat --title "Release $new_tag" --notes "Automated release of UnlockWeChat for Windows and Mac"

echo "Release $new_tag successfully created and published!"
