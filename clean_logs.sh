#!/bin/bash
# Clean Flutter logs - only show app debug prints

echo "Clearing logs and starting filtered output..."
echo "Press Ctrl+C to stop"
echo ""

# Clear existing logs
adb logcat -c

# Show only Flutter logs with your debug prints (lines with brackets)
adb logcat flutter:V *:S | grep -E "\[.*\]"
