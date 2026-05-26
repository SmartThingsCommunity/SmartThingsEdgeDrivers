# Econet GateLock — SmartThings Edge Driver (Matter)

Custom SmartThings Edge driver for the Econet Bulldog GateLock. Built on the Matter-specific `st.matter.driver` class so the secure Matter session (`matter_channel`) is established per device.

## Capabilities Exposed

| SmartThings Capability | Matter Source | What it shows |
|---|---|---|
| **lock** | DoorLock cluster, LockState (attr 0x0000) | Locked / Unlocked / Not Fully Locked |
| **contactSensor** | DoorLock cluster, DoorState (attr 0x0003) | Door Open / Closed (driven by reed switch) |
| **tamperAlert** | DoorLock cluster, DoorLockAlarm event | Tampered when 4-strike PIN limit hit on the keypad |
| **battery** | PowerSource cluster, BatPercentRemaining (attr 0x000C) | 0–100% |
| **firmwareUpdate** | (infrastructure) | Required for Matter device handshake |
| **refresh** | (infrastructure) | Manual re-subscribe from the SmartThings app |

PIN management and auto-relock configuration are not exposed by this driver. PINs are managed on the lock's keypad in admin mode; auto-relock can be set via Matter's standard cluster from any other Matter controller (or the firmware shell).

## Reed-switch contact sensor

The reed switch on GPIO0.28 triggers `sendDoorStateChangeAlarmEvent()` in firmware, which updates the Matter `DoorState` attribute. This driver maps it to the SmartThings **Contact Sensor** tile:
- `DoorClosed (1)` → **closed**
- Anything else → **open**

## Tamper alert

When the keypad's 4-strikes-in-20-seconds brute-force protection trips, the firmware:

1. Adds `kTamperDetected (10)` to `GeneralDiagnostics.ActiveHardwareFaults` on endpoint 0 (also emits the `HardwareFaultChange` event).
2. Fires a legacy `DoorLockAlarm` event with `alarmCode = kWrongCodeEntryLimit (4)` for backwards compatibility.

The driver subscribes to the `ActiveHardwareFaults` attribute and maps list membership directly to the **tamperAlert** capability — `tampered` while the list contains `10`, `clear` when the firmware removes it (which happens automatically when the lockout window expires). The legacy `DoorLockAlarm` event handler is retained so older firmware builds that only fire the event still surface a `tampered` state.

## Prerequisites

- SmartThings Hub with Matter support (v46+ firmware)
- SmartThings CLI (`@smartthings/cli`)
- Personal Access Token from https://account.smartthings.com/tokens (set as `SMARTTHINGS_TOKEN` env var)

## Build & Deploy

```bash
cd smartthings-edge-driver
smartthings edge:drivers:package
# Returns a driver ID

smartthings edge:channels:assign <driver-id> <version> -C <channel-id>
smartthings edge:drivers:install <driver-id> --hub <hub-id> -C <channel-id>
```

## Re-deploy after edits

After every code change:

```bash
# Package + auto-assign + install
smartthings edge:drivers:package -C <channel-id> --hub <hub-id>

# If the hub doesn't pick up the new version (cached), force re-install:
smartthings edge:drivers:install <driver-id> --hub <hub-id> -C <channel-id>
```

## Live logs

```bash
smartthings edge:drivers:logcat <driver-id>
```

## File structure

```
smartthings-edge-driver/
├── config.yml                 # Driver metadata
├── fingerprints.yml           # Matter vendor 5480 / product 10 match
├── profiles/
│   └── gatelock-matter.yml    # Capability list
├── src/
│   └── init.lua               # Driver code (uses st.matter.driver)
└── README.md
```

## Notes

- The driver MUST use `MatterDriver = require "st.matter.driver"` and instantiate via `MatterDriver(packageKey, driverTable)`. The generic `st.driver` does not establish the Matter secure session and `device:subscribe()` will fail with `matter_channel nil`.
- `subscribed_attributes` is keyed by SmartThings capability ID, with values being arrays of cluster attribute object refs (not raw numeric IDs).
- `subscribed_events` follows the same pattern keyed by capability ID.
