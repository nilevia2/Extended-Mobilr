#!/bin/bash
# Filter Flutter logs - only show app logs, hide system logs

# Filter to only show Flutter/Dart logs
adb logcat -c  # Clear existing logs
adb logcat | grep -E "(flutter|I/flutter|D/flutter|E/flutter|W/flutter)" | grep -v -E "(MIUI|HandWriting|VRI|SurfaceView|Gralloc|Adreno|qdgralloc|HardwareBuffer|GraphicBuffer|AppScout|OpenGLRenderer)"

