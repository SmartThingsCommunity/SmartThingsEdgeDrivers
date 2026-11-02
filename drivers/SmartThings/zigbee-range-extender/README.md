# Zigbee Range Extender

## Signal strength

The reusable `range-extender-signal` profile exposes the standard
`signalStrength` capability alongside `refresh`.
Assign it to a device's fingerprint to enable signal strength support.

The `range-extender-signal` sub-driver handles devices whose `main` component
includes `signalStrength`, independently of manufacturer and model. The driver's
existing refresh handler reads the Basic cluster's `ZCLVersion` attribute during
default configuration and manual refresh. The 300-second health poll also reads
this attribute. Each successful response supplies the received-message
metadata used to emit:

- `signalStrength.lqi`: LQI, from 0 to 255.
- `signalStrength.rssi`: RSSI, in dBm.

The driver publishes measured values only after receiving a response; it does
not initialize signal strength with placeholder values. These values describe
reception at the hub. In a routed network they can reflect the last received hop,
and do not measure overall mesh coverage or repeater throughput.

Existing devices retain their profile when a driver is updated. Devices using
the original `range-extender` profile need their profile updated or must rejoin
to receive the new fingerprint's profile. A profile change triggers a fresh
read. Profiles without `signalStrength` retain their existing behavior.

## Hardware verification

1. Use router/range-extender firmware and verify the joined device matches a
   fingerprint assigned to `range-extender-signal`.
2. Verify a newly joined device exposes `signalStrength` and `refresh`, and
   receives an initial RSSI/LQI sample.
3. Pull to refresh and confirm a Basic `ZCLVersion` response produces new
   RSSI/LQI events. Check that sampling repeats after five minutes.
4. Update an existing device's profile to `range-extender-signal` or rejoin the
   device, and confirm signal strength becomes available.
5. Check power cycling/rejoining and confirm an unavailable device does not
   produce fabricated signal measurements.

Integration tests cover the command/response paths, polling, profile changes,
metadata values, and capability-based device matching. Certification still
requires physical sample evaluation as requested by SmartThings; local tests
do not replace it.
