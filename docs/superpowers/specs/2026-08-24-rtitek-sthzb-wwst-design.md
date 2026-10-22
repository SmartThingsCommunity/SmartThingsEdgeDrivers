# Rti-Tek STHZB WWST Driver Design

## Goal

Add WWST-compliant support for the Rti-Tek STHZB Zigbee temperature and
humidity sensor to the official `zigbee-humidity-sensor` Edge driver.  The
implementation must use only SmartThings standard capabilities and device
preferences, while retaining the device features that can be represented by
those public interfaces.

This work is isolated to the `codex/rtitek-sthzb-wwst` branch and does not
change the separately distributed `Rti-Tek STHZB Unit Enum8 v15` driver.

## Scope

The driver matches `manufacturer: Rti-Tek` and `model: STHZB` and uses the
existing `rtitek-sthzb` profile in `drivers/SmartThings/zigbee-humidity-sensor`.

The user-facing device card exposes only standard capabilities:

- `temperatureMeasurement`
- `relativeHumidityMeasurement`
- `battery`
- `refresh`
- `temperatureAlarm`

The device preferences provide the configurable manufacturer-specific
behavior:

| Preference | Device attribute | Wire type and conversion |
| --- | --- | --- |
| Display temperature unit | `0xFD22/0x0000` | `Enum8`: Celsius `0`, Fahrenheit `1` |
| Temperature calibration | `0xFD22/0xE005` | `Int8`, preference value in `0.1 C` |
| Humidity calibration | `0xFD22/0xE006` | `Int8`, preference value in `0.1 %RH` |
| Temperature alarm upper limit | `0xFD22/0xE00A` | `Int16`, preference value in `0.1 C`, written as `value * 100` |
| Temperature alarm lower limit | `0xFD22/0xE00B` | `Int16`, preference value in `0.1 C`, written as `value * 100` |
| Humidity alarm upper limit | `0xFD22/0xE00C` | `Uint16`, whole `%RH`, written as `value * 100` |
| Humidity alarm lower limit | `0xFD22/0xE00D` | `Uint16`, whole `%RH`, written as `value * 100` |

`0xFD22/0xE00E` maps to the standard `temperatureAlarm` capability:

- normal -> `cleared`
- low temperature alarm -> `freeze`
- high temperature alarm -> `heat`

`0xFD22/0xE00F` is logged for diagnosis only. SmartThings has no suitable
standard capability for a separate humidity alarm state. The thresholds remain
configurable and users can create routines from standard humidity measurements.

The driver retains diagnostic logging of Zigbee LQI and RSSI, but does not
surface either as a custom user-facing capability. The driver uses no Custom
Capabilities.

## Data Flow and Validation

On installation and refresh, the sub-driver reads standard measurements and
all relevant `0xFD22` attributes. Attribute reports update standard events,
persisted field values, and preference synchronization as appropriate.

When a setting changes, the lifecycle handler normalizes to device-supported
precision before sending a write. It validates paired alarm limits using the
latest cached value. If a proposed upper limit is less than or equal to the
lower limit, it is clamped to one device step above the lower limit; conversely,
a proposed lower limit is clamped to one device step below the upper limit.
The effective raw value is cached and read back from the device. Edge drivers
cannot overwrite the app-owned preference value, so the Settings input may
continue to display the submitted value after a paired-limit clamp.

Temperature settings use `0.1 C` increments. Humidity alarm settings use
whole-percent increments because the device accepts that precision. Unit
selection is written as a device setting; standard temperature measurement
continues to be emitted in Celsius and SmartThings performs presentation-unit
conversion.

## Implementation Boundaries

- Add a small `rtitek-sthzb` sub-driver with matching, lifecycle, report, and
  preference-write handlers.
- Update only the Rti-Tek profile, the parent sub-driver registration, and
  Rti-Tek tests in the official humidity-sensor package.
- Reuse the existing parent driver behavior for standard clusters unless the
  device-specific sub-driver must override it.
- Do not add a top-level driver package, Custom Capability definitions, OTA
  support, LQI/RSSI UI, or a separate humidity alarm card.

## Verification

Automated coverage must verify fingerprint matching, standard temperature,
humidity, and battery reports, refresh reads, each preference-to-FD22 write
conversion, paired-limit clamping, and all temperature-alarm mappings.

After local tests pass, package the official driver on a separate development
channel and assign it to the test hub. Validate pairing or driver reassignment,
reporting, refresh, every preference write and readback, invalid paired-limit
handling, temperature alarm transitions, and absence of Custom Capabilities in
the generated device profile. This local validation completes before any PR or
Console certification submission is advanced.
