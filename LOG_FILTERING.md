# Log Filtering Guide

## Quick Filter (Recommended)

### Option 1: Use the Filter Script

```bash
# Run the filter script
./filter_logs.sh
```

This will:
- ✅ Show only Flutter/Dart logs
- ✅ Hide MIUI system logs
- ✅ Hide graphics/rendering logs
- ✅ Hide Android system noise

### Option 2: Manual ADB Filter

```bash
# Clear logs first
adb logcat -c

# Show only Flutter logs
adb logcat | grep flutter

# Or more specific - only your app
adb logcat | grep "extended_mobile\|flutter"
```

### Option 3: Filter Specific Tags

```bash
# Only show Flutter logs, exclude system logs
adb logcat | grep -E "flutter" | grep -v -E "MIUI|HandWriting|VRI|SurfaceView|Gralloc|Adreno|qdgralloc|HardwareBuffer|GraphicBuffer|AppScout|OpenGLRenderer"
```

### Option 4: Use Logcat Filters (Most Control)

```bash
# Show only Flutter logs with specific priority
adb logcat flutter:V *:S

# Or show Flutter + your app package
adb logcat flutter:V extended_mobile:V *:S
```

---

## Filter Out Specific Logs

### Hide MIUI Logs
```bash
adb logcat | grep -v MIUI
```

### Hide Graphics/Rendering Logs
```bash
adb logcat | grep -v -E "Gralloc|Adreno|qdgralloc|HardwareBuffer|GraphicBuffer|OpenGLRenderer"
```

### Hide Handwriting/Input Logs
```bash
adb logcat | grep -v HandWriting
```

### Hide All System Logs (Keep Only Flutter)
```bash
adb logcat | grep flutter | grep -v -E "MIUI|HandWriting|VRI|SurfaceView|Gralloc|Adreno|qdgralloc|HardwareBuffer|GraphicBuffer|AppScout|OpenGLRenderer|D/MIUI|I/HandWriting|D/VRI|D/SurfaceView|E/OpenGLRenderer|E/qdgralloc|E/AdrenoUtils|W/qdgralloc|E/Gralloc|E/GraphicBufferAllocator|E/AHardwareBuffer|D/AppScout"
```

---

## Best Practice: Clean Flutter Logs Only

```bash
# Clear logs
adb logcat -c

# Show only Flutter app logs (cleanest)
adb logcat flutter:V *:S | grep -E "\[.*\]"
```

This shows:
- ✅ Only Flutter logs
- ✅ Only logs with brackets (your debug prints)
- ✅ No system noise

---

## In Flutter Run

When running `flutter run`, you can also filter:

```bash
# Run with filtered output
flutter run 2>&1 | grep -E "flutter|\[.*\]"
```

---

## Recommended Setup

**For development, use this command:**

```bash
# Clear and show only Flutter logs
adb logcat -c && adb logcat flutter:V *:S
```

Or use the provided script:
```bash
./filter_logs.sh
```

This gives you clean, readable logs with only your app's output.

