# Philips Hue Driver - Capture Test Plan

## Overview

This test plan is designed to capture comprehensive real-world behavior of the Philips Hue driver. The instrumented driver logs all network traffic (REST API calls, SSE events) and IPC communication (commands, capability events, device lifecycle) in structured JSON format.

**Instrumented Driver Version:** hue-instrumented-capture branch  
**Purpose:** Capture complete driver behavior for refactoring baseline  
**Duration:** 1-2 weeks of testing

---

## Hardware Requirements

### Minimum Setup
- [ ] **Hue Bridge** (v2 recommended, firmware 1.28+)
- [ ] **At least one device of each type** you intend to test:
  - [ ] White bulb (dimmable only)
  - [ ] White ambiance bulb (dimmable + color temperature)
  - [ ] Color ambiance bulb (full RGB + CT)
  - [ ] Motion sensor (if available)
  - [ ] Button/switch (if available)
  - [ ] Contact sensor (if available)
  - [ ] Plug (if available)

### Ideal Setup
- Multiple devices of common types (2-3 lights of different types)
- Mix of firmware versions (if available)
- Both wired and battery-powered devices

---

## Pre-Test Setup

### 1. Install Instrumented Driver

```bash
# Package and install the driver
cd ~/Projects/SmartThingsEdgeDrivers
./tools/package_driver.sh drivers/SmartThings/philips-hue

# Upload to hub (use SmartThings CLI or IDE)
smartthings edge:drivers:install
```

### 2. Prepare Log Collection

The driver logs to hub logs. Set up log collection:

```bash
# Stream logs from hub to file
smartthings edge:drivers:logcat --hub-address=<HUB_IP> > hue_capture_$(date +%Y%m%d_%H%M%S).log
```

Or use the SmartThings CLI advanced logging.

### 3. Document Your Setup

Create a file `test_environment.md` documenting:
- Bridge model and firmware version
- List of all devices (type, model, firmware)
- Network configuration (DHCP/static IP)
- Any known issues or quirks

---

## Test Scenarios

Execute these scenarios in order, allowing time between each for log capture. Wait ~30 seconds between operations to see natural state changes and SSE events.

### Scenario 1: Initial Discovery and Pairing (If Starting Fresh)

**Objective:** Capture the complete onboarding flow

#### Steps:
1. [ ] Factory reset bridge (if possible, or use new bridge)
2. [ ] Remove any existing Hue bridge devices from SmartThings
3. [ ] Install instrumented driver
4. [ ] Start log collection
5. [ ] Trigger SmartThings device discovery
6. [ ] Wait for bridge to be discovered via mDNS
7. [ ] Complete bridge pairing (press link button when prompted)
8. [ ] Wait for all child devices to be discovered and added
9. [ ] Verify all devices appear in SmartThings app
10. [ ] Wait 5 minutes for initial sync to complete

**Expected Capture:**
- mDNS discovery packets
- Bridge API key generation
- Initial device enumeration
- SSE connection establishment
- Initial device state queries for all devices

**Duration:** 15-30 minutes

---

### Scenario 2: Driver Restart with Existing Devices

**Objective:** Capture initialization when devices already exist

#### Steps:
1. [ ] Stop the driver (or restart the hub)
2. [ ] Wait 30 seconds
3. [ ] Start log collection (new file)
4. [ ] Start the driver
5. [ ] Observe all devices come back online
6. [ ] Wait 5 minutes

**Expected Capture:**
- Driver initialization
- Datastore loading
- Reconnection to bridge
- SSE reconnection
- Device state re-sync
- Online/offline status transitions

**Duration:** 10 minutes

---

### Scenario 3: Basic Light Operations

**Objective:** Capture all light control commands

For EACH light device you have (white, white ambiance, color):

#### 3a. White Bulb (Dimmable Only)
1. [ ] Turn light ON (via SmartThings app)
2. [ ] Wait 10 seconds
3. [ ] Turn light OFF
4. [ ] Wait 10 seconds
5. [ ] Turn light ON
6. [ ] Wait 10 seconds
7. [ ] Set level to 25%
8. [ ] Wait 10 seconds
9. [ ] Set level to 50%
10. [ ] Wait 10 seconds
11. [ ] Set level to 75%
12. [ ] Wait 10 seconds
13. [ ] Set level to 100%
14. [ ] Wait 10 seconds
15. [ ] Set level to 1%
16. [ ] Wait 10 seconds
17. [ ] Turn OFF

#### 3b. White Ambiance Bulb (If Available)
Repeat 3a, then add:
1. [ ] Turn light ON at 100%
2. [ ] Set color temperature to 2700K (warm)
3. [ ] Wait 10 seconds
4. [ ] Set color temperature to 4000K (neutral)
5. [ ] Wait 10 seconds
6. [ ] Set color temperature to 6500K (cool)
7. [ ] Wait 10 seconds
8. [ ] Set color temperature to 2200K (very warm)
9. [ ] Wait 10 seconds
10. [ ] Turn OFF

#### 3c. Color Ambiance Bulb (If Available)
Repeat 3a and 3b, then add:
1. [ ] Turn light ON at 100%
2. [ ] Set color to RED (hue=0, sat=100)
3. [ ] Wait 10 seconds
4. [ ] Set color to GREEN (hue=120, sat=100)
5. [ ] Wait 10 seconds
6. [ ] Set color to BLUE (hue=240, sat=100)
7. [ ] Wait 10 seconds
8. [ ] Set color to YELLOW (hue=60, sat=100)
9. [ ] Wait 10 seconds
10. [ ] Set color to CYAN (hue=180, sat=100)
11. [ ] Wait 10 seconds
12. [ ] Set color to MAGENTA (hue=300, sat=100)
13. [ ] Wait 10 seconds
14. [ ] Set saturation to 50% (keep same hue)
15. [ ] Wait 10 seconds
16. [ ] Set saturation to 0% (white)
17. [ ] Wait 10 seconds
18. [ ] Turn OFF

**Expected Capture:**
- All switch on/off commands
- All setLevel commands with various values
- All setColorTemperature commands
- All setColor/setHue/setSaturation commands
- REST API calls for each command
- SSE events confirming state changes

**Duration:** 30-45 minutes total

---

### Scenario 4: Rapid Commands

**Objective:** Capture behavior under rapid command sequences

#### Steps:
1. [ ] Select one color bulb
2. [ ] Execute the following sequence as fast as possible (no waits):
   - Turn ON
   - Set level 100
   - Set level 50
   - Set level 25
   - Set level 75
   - Set color RED
   - Set color BLUE
   - Set color GREEN
   - Turn OFF
3. [ ] Wait 30 seconds for system to settle
4. [ ] Turn light ON
5. [ ] Rapidly press on/off 10 times with ~1 second between each
6. [ ] Wait 30 seconds

**Expected Capture:**
- Command queuing/batching behavior
- Race conditions (if any)
- Error handling for rapid commands
- SSE events during rapid changes

**Duration:** 5 minutes

---

### Scenario 5: Button/Switch Events (If Available)

**Objective:** Capture button press events

#### Steps:
1. [ ] Press button once (short press)
2. [ ] Wait 10 seconds
3. [ ] Press button once (long press, hold 3 seconds)
4. [ ] Wait 10 seconds
5. [ ] Press button multiple times rapidly (5 times)
6. [ ] Wait 10 seconds

For multi-button devices:
1. [ ] Press each button individually
2. [ ] Wait 10 seconds between presses

**Expected Capture:**
- SSE events for button presses
- Different event types for short/long press
- Button state updates
- Capability event emissions

**Duration:** 10 minutes

---

### Scenario 6: Motion Sensor Events (If Available)

**Objective:** Capture motion detection and illuminance updates

#### Steps:
1. [ ] Trigger motion by waving in front of sensor
2. [ ] Wait for motion to clear (usually 30-60 seconds)
3. [ ] Trigger motion again
4. [ ] Leave for 5 minutes to capture motion timeout
5. [ ] Move sensor to different lighting conditions (dark to bright)
6. [ ] Observe illuminance changes

**Expected Capture:**
- SSE events for motion detected
- SSE events for motion cleared
- Illuminance level updates
- Temperature updates (if sensor has thermometer)

**Duration:** 10-15 minutes

---

### Scenario 7: Contact Sensor Events (If Available)

**Objective:** Capture open/close events

#### Steps:
1. [ ] Open contact sensor
2. [ ] Wait 10 seconds
3. [ ] Close contact sensor
4. [ ] Wait 10 seconds
5. [ ] Repeat 5 times
6. [ ] Leave open for 2 minutes
7. [ ] Close

**Expected Capture:**
- SSE events for contact open
- SSE events for contact closed
- Timing of state changes

**Duration:** 5-10 minutes

---

### Scenario 8: Network Disconnection/Reconnection

**Objective:** Capture error handling and recovery

#### 8a. Bridge Network Disconnect
1. [ ] Disconnect bridge from network (unplug ethernet or disable WiFi)
2. [ ] Wait 2 minutes
3. [ ] Observe driver behavior and device status
4. [ ] Reconnect bridge to network
5. [ ] Wait 5 minutes for recovery
6. [ ] Verify all devices come back online

#### 8b. Hub Network Disconnect (If Safe)
1. [ ] Disconnect hub from network briefly (10 seconds)
2. [ ] Reconnect
3. [ ] Observe recovery

**Expected Capture:**
- SSE connection errors
- Reconnection attempts
- REST API retry logic
- Device offline/online transitions
- Recovery sequence

**Duration:** 15 minutes

---

### Scenario 9: Bridge Restart

**Objective:** Capture behavior when bridge reboots

#### Steps:
1. [ ] Restart bridge (via Hue app or power cycle)
2. [ ] Wait for bridge to boot (usually 1-2 minutes)
3. [ ] Observe driver reconnection
4. [ ] Wait 5 minutes for full recovery
5. [ ] Test light control to verify recovery

**Expected Capture:**
- Connection failures during restart
- Detection of bridge coming back online
- SSE reconnection handshake
- Device state re-sync

**Duration:** 10 minutes

---

### Scenario 10: Driver Refresh

**Objective:** Capture manual refresh behavior

#### Steps:
1. [ ] For each device:
   - [ ] Execute "Refresh" command from SmartThings app
   - [ ] Wait 10 seconds
2. [ ] Execute refresh on bridge device
3. [ ] Wait 30 seconds

**Expected Capture:**
- Refresh command IPC
- REST API calls to query device state
- Capability events from refresh
- Any differences between refresh and SSE updates

**Duration:** 10 minutes

---

### Scenario 11: Device Addition/Removal

**Objective:** Capture discovery and deletion flows

#### 11a. Add New Device (If Available)
1. [ ] Put bridge in pairing mode (via Hue app)
2. [ ] Put Hue device in pairing mode (power cycle 5 times or hold button)
3. [ ] Wait for device to pair with bridge
4. [ ] Observe device being discovered by driver
5. [ ] Wait for device to appear in SmartThings
6. [ ] Wait 2 minutes for state to stabilize

#### 11b. Remove Device
1. [ ] Remove a non-essential device via Hue app
2. [ ] Observe device being removed from SmartThings
3. [ ] Wait 2 minutes

**Expected Capture:**
- SSE "add" events for new devices
- Device creation IPC
- Initial device state query
- SSE "delete" events for removed devices
- Device deletion IPC

**Duration:** 10-20 minutes

---

### Scenario 12: External Control (Hue App)

**Objective:** Capture SSE events from external changes

#### Steps:
1. [ ] Open official Hue app on phone
2. [ ] Control a light from Hue app (on/off, dim)
3. [ ] Wait 10 seconds
4. [ ] Create a scene in Hue app and activate it
5. [ ] Wait 10 seconds
6. [ ] Control lights via Google/Alexa (if integrated)
7. [ ] Wait 10 seconds

**Expected Capture:**
- SSE update events from external control
- Capability events reflecting external changes
- No outgoing commands (only incoming SSE)
- State synchronization

**Duration:** 10 minutes

---

### Scenario 13: Polling and Background Tasks

**Objective:** Capture periodic operations

#### Steps:
1. [ ] Leave driver running undisturbed for 2 hours
2. [ ] Do not interact with any devices
3. [ ] Observe periodic polling/health checks

**Expected Capture:**
- mDNS scans (every 10 minutes by default)
- Any periodic health checks
- SSE connection keepalives
- Automatic reconnections (if any)

**Duration:** 2 hours

---

### Scenario 14: Battery-Powered Devices (If Available)

**Objective:** Capture battery status updates

#### Steps:
1. [ ] Observe initial battery level
2. [ ] Wait 24 hours
3. [ ] Check for battery level updates in logs

**Expected Capture:**
- SSE events for battery level changes
- Battery capability events

**Duration:** 24 hours (passive)

---

### Scenario 15: Edge Cases and Errors

**Objective:** Capture error handling

#### 15a. Invalid Commands
1. [ ] Send setLevel command with value 0 (invalid for Hue)
2. [ ] Send setLevel command with value > 100
3. [ ] Send setColorTemperature with out-of-range value

#### 15b. Device Unreachable
1. [ ] Power off a light (turn off at switch, not via app)
2. [ ] Try to control the light
3. [ ] Wait 2 minutes
4. [ ] Power light back on
5. [ ] Wait for recovery

#### 15c. Bridge Overload (If Safe)
1. [ ] Control all lights simultaneously
2. [ ] Rapid on/off on multiple lights at once

**Expected Capture:**
- Error responses from Hue API
- Command validation
- Error logging
- Recovery behavior

**Duration:** 15 minutes

---

### Scenario 16: Long-Running Stability Test

**Objective:** Capture multi-day behavior

#### Steps:
1. [ ] Leave driver running for 7 days
2. [ ] Normal daily usage (lights on/off as needed)
3. [ ] Do NOT restart driver or hub
4. [ ] Rotate log files daily

**Expected Capture:**
- Memory leaks (if any)
- Connection stability over time
- Any periodic cleanup tasks
- Accumulated edge cases

**Duration:** 7 days

---

## Log Collection Best Practices

### 1. File Organization

Create a directory structure:
```
hue_capture_logs/
├── test_environment.md
├── scenario_01_initial_discovery/
│   ├── capture.log
│   └── notes.md
├── scenario_02_restart/
│   ├── capture.log
│   └── notes.md
...
```

### 2. Annotate Logs

Create a `notes.md` file for each scenario documenting:
- Start time
- End time
- Devices involved
- Expected vs. actual behavior
- Any anomalies observed
- Screenshots (if relevant)

### 3. Extract CAPTURE Logs

After each scenario, extract just the capture logs:
```bash
grep '\[CAPTURE\]' hue_full.log > scenario_01_capture.log
```

### 4. Validate Capture

Verify key log types are present:
```bash
# Check for network traffic
grep '"type":"NETWORK_OUT"' scenario_01_capture.log | wc -l
grep '"type":"NETWORK_IN"' scenario_01_capture.log | wc -l

# Check for IPC
grep '"type":"IPC_IN"' scenario_01_capture.log | wc -l
grep '"type":"IPC_OUT"' scenario_01_capture.log | wc -l

# Check for lifecycle
grep '"type":"IPC_EVENT"' scenario_01_capture.log | wc -l
```

---

## Data Analysis (Post-Capture)

### 1. Parse JSON Logs

```bash
# Pretty-print JSON for review
jq . scenario_01_capture.log > scenario_01_pretty.json
```

### 2. Identify Patterns

- Unique REST API endpoints
- SSE event types and structure
- Command/event sequences
- Error patterns
- Timing relationships

### 3. Generate Statistics

- Total requests by endpoint
- Average response time
- Error rate
- Event frequency by type
- Device state transition patterns

### 4. Build Test Coverage Map

Create a spreadsheet mapping:
- REST endpoints → test scenarios
- SSE event types → test scenarios
- Commands → test scenarios
- Device types → test scenarios

---

## Success Criteria

- [ ] All scenarios executed
- [ ] Logs collected for each scenario
- [ ] Annotations created documenting observations
- [ ] At least one instance of each device type tested
- [ ] Both "happy path" and error cases captured
- [ ] Multi-day stability test completed
- [ ] Logs validated for completeness (all log types present)

---

## Troubleshooting

### Log Volume Too Large

If logs fill up quickly:
1. Disable capture temporarily: Edit `capture_logger.lua`, set `M.enabled = false`
2. Increase log rotation frequency
3. Capture only specific scenarios

### Driver Crashes

If driver becomes unstable:
1. Check for infinite loops in instrumentation
2. Verify JSON encoding doesn't fail on edge cases
3. Add error handling around capture calls

### Missing Log Types

If certain log types aren't appearing:
1. Verify capture_logger is properly loaded
2. Check for errors in device wrapper
3. Ensure all code paths are exercised

---

## Next Steps After Capture

1. **Analyze captured data** to understand current behavior
2. **Create integration tests** based on captured patterns
3. **Build test helpers** for common sequences
4. **Document API behavior** (endpoints, event types, state machines)
5. **Begin refactoring** with comprehensive test coverage

---

## Appendix: Log Format Reference

### NETWORK_OUT (REST Request)
```json
{
  "type": "NETWORK_OUT",
  "subtype": "REST_REQUEST",
  "timestamp": 1234567890,
  "request_id": "req_1234_5678",
  "method": "GET",
  "url": "https://192.168.1.15:443/clip/v2/resource/light/abc123",
  "headers": { "hue-application-key": "***REDACTED***" },
  "body": null
}
```

### NETWORK_IN (REST Response)
```json
{
  "type": "NETWORK_IN",
  "subtype": "REST_RESPONSE",
  "timestamp": 1234567891,
  "request_id": "req_1234_5678",
  "status": 200,
  "headers": { "content-type": "application/json" },
  "body": "{\"data\":[...]}",
  "elapsed_ms": 45
}
```

### NETWORK_IN (SSE Event)
```json
{
  "type": "NETWORK_IN",
  "subtype": "SSE_EVENT",
  "timestamp": 1234567892,
  "connection_id": "req_1234_5679",
  "event_id": "evt_1234_5680",
  "event_type": "update",
  "data": "[{\"id\":\"abc123\",\"type\":\"light\",\"on\":{\"on\":true}}]"
}
```

### IPC_IN (Command)
```json
{
  "type": "IPC_IN",
  "subtype": "COMMAND",
  "timestamp": 1234567893,
  "device_id": "device-uuid",
  "command": "setLevel",
  "args": { "level": 75 },
  "component": "main"
}
```

### IPC_OUT (Capability Event)
```json
{
  "type": "IPC_OUT",
  "subtype": "CAPABILITY_EVENT",
  "timestamp": 1234567894,
  "device_id": "device-uuid",
  "capability": "switchLevel",
  "attribute": "level",
  "value": 75,
  "component": "main"
}
```

### IPC_EVENT (Lifecycle)
```json
{
  "type": "IPC_EVENT",
  "subtype": "LIFECYCLE",
  "timestamp": 1234567895,
  "device_id": "device-uuid",
  "lifecycle_event": "added",
  "details": { "label": "Hue bulb", "parent_device_id": "bridge-uuid" }
}
```

---

## Contact & Support

For questions or issues during testing:
- Check driver logs for errors
- Review this test plan
- Document unexpected behavior thoroughly
- Include relevant log snippets when reporting issues

Good luck with your capture session!
