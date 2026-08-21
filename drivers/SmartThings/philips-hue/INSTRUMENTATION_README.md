# Hue Driver Instrumentation - Capture Branch

## Overview

This branch contains a heavily instrumented version of the Philips Hue driver designed to capture comprehensive real-world behavior for analysis and refactoring.

## What's Been Added

### Core Logging Infrastructure

1. **`capture_logger.lua`** - Structured JSON logging module
   - Logs all network traffic (REST requests/responses, SSE events)
   - Logs all IPC communication (commands, capability events, lifecycle)
   - Logs state changes (device fields, datastore, discovery cache)
   - Generates correlation IDs for request→response tracking
   - High-resolution timestamps (milliseconds)
   - Configurable sanitization of sensitive data

2. **`capture_device_wrapper.lua`** - Automatic device event capture
   - Wraps `device:emit_event()` to capture all capability events
   - Wraps `device:set_field()` to capture state changes
   - Wraps device creation/deletion
   - Wraps online/offline status changes

### Instrumented Modules

- **`lunchbox/rest.lua`** - REST client with request/response logging
- **`lunchbox/sse/eventsource.lua`** - SSE client with event logging
- **`handlers/commands.lua`** - Command handlers with IPC logging
- **`handlers/lifecycle_handlers/init.lua`** - Lifecycle event logging
- **`init.lua`** - Driver initialization with wrapper integration

## Log Format

All capture logs are prefixed with `[CAPTURE]` and contain JSON objects with these fields:

- `type` - Log category (NETWORK_OUT, NETWORK_IN, IPC_IN, IPC_OUT, etc.)
- `subtype` - Specific event type (REST_REQUEST, SSE_EVENT, COMMAND, etc.)
- `timestamp` - Milliseconds since epoch
- Event-specific fields

See `CAPTURE_TEST_PLAN.md` Appendix for detailed log format examples.

## Configuration

Edit `capture_logger.lua` to configure:

```lua
M.enabled = true              -- Enable/disable capture logging
M.log_to_hub = true          -- Send logs to hub (visible in hub logs)
M.include_sensitive = false  -- Log API keys/tokens (CAUTION!)
```

## Usage

### Building & Installing

```bash
# Package driver
cd ~/Projects/SmartThingsEdgeDrivers
./tools/package_driver.sh drivers/SmartThings/philips-hue

# Install to hub
smartthings edge:drivers:install
```

### Capturing Logs

```bash
# Stream logs from hub
smartthings edge:drivers:logcat --hub-address=<HUB_IP> | tee hue_capture.log

# Extract only capture logs
grep '\[CAPTURE\]' hue_capture.log > capture_only.log

# Pretty-print JSON
jq . capture_only.log > capture_pretty.json
```

### Test Plan

See **`CAPTURE_TEST_PLAN.md`** for comprehensive testing scenarios including:
- Initial discovery and pairing
- Device operations (lights, buttons, sensors)
- Network interruptions and recovery
- Error handling
- Long-running stability tests

## Performance Impact

⚠️ **This instrumented driver has significant performance overhead:**
- Every network request/response is logged
- Every capability event is logged
- All logs are JSON-encoded
- High volume of log data

**Do not use in production!** This is for behavior capture only.

## Log Analysis

After capturing logs, analyze them to:
1. Identify all REST API endpoints used
2. Document all SSE event types
3. Map command→API call→event sequences
4. Find error patterns and edge cases
5. Generate integration test scenarios

## File Summary

### New Files
- `src/capture_logger.lua` - Core logging infrastructure (467 lines)
- `src/capture_device_wrapper.lua` - Device event wrapper (151 lines)
- `CAPTURE_TEST_PLAN.md` - Comprehensive test plan (900+ lines)
- `INSTRUMENTATION_README.md` - This file

### Modified Files
- `src/init.lua` - Initialize capture logging
- `src/lunchbox/rest.lua` - REST client instrumentation
- `src/lunchbox/sse/eventsource.lua` - SSE client instrumentation
- `src/handlers/commands.lua` - Command logging
- `src/handlers/lifecycle_handlers/init.lua` - Lifecycle logging

## Next Steps

1. **Execute Test Plan** - Follow `CAPTURE_TEST_PLAN.md` scenarios
2. **Collect Logs** - Organize by scenario with annotations
3. **Analyze Data** - Parse JSON, identify patterns, map behavior
4. **Build Tests** - Create integration tests based on captured behavior
5. **Refactor** - Simplify driver while maintaining captured behavior

## Troubleshooting

### Logs Not Appearing

- Check `capture_logger.M.enabled = true`
- Verify hub logs are streaming
- Look for "[CAPTURE]" prefix in logs

### Too Much Log Volume

- Disable capture temporarily: `M.enabled = false`
- Run specific scenarios in isolation
- Filter logs by subtype

### Driver Instability

- Check for errors in capture modules
- Verify JSON encoding doesn't fail
- Add error handling in critical paths

## Reverting to Normal Driver

To switch back to non-instrumented driver:

```bash
git checkout main  # or your production branch
./tools/package_driver.sh drivers/SmartThings/philips-hue
smartthings edge:drivers:install
```

---

**Branch:** `hue-instrumented-capture`  
**Purpose:** Behavior capture for refactoring  
**Status:** Ready for testing  
**Created:** 2026-08-21
