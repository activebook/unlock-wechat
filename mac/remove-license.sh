#!/bin/bash

# Remove the license key from the app's preferences to test without license
defaults delete com.activebook.unlockwechat licenseKey 2>/dev/null || true
echo "License key removed (if it existed)."
