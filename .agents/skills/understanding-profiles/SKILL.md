---
name: understanding-profiles
description: Understanding and defining SmartThings capabilities, device profiles, preferences, and embedded device configurations for Edge Drivers
---

# SmartThings Capabilities, Profiles, and Preferences

## 1. What Are Capabilities?

Capabilities are the fundamental abstraction in SmartThings. They define what a device can do and what state it can report. Each capability consists of:

- **Attributes**: State/status values (e.g., `switch` has attribute `switch` with values `on`/`off`)
- **Commands**: Actions that control the device (e.g., `on()`, `off()`, `setLevel(level)`)

A capability definition specifies data types, units, and constraints for its attributes and commands.

### Data Types
| Type | Example | Description |
|------|---------|-------------|
| string | `"locked"` | May have enum or pattern constraints |
| integer | `5` | Whole number, may have min/max |
| number | `5.5` | Fractional values allowed |
| boolean | `true` | true or false |
| object | `{x: 12}` | Map of name-value pairs |
| array | `["heat","cool"]` | List of single type |

### Common Capabilities
- `switch` - on/off control
- `switchLevel` - dimming (0-100)
- `temperatureMeasurement` - temperature reading
- `battery` - battery percentage
- `contactSensor` - open/closed
- `motionSensor` - active/inactive
- `lock` - locked/unlocked
- `thermostatMode`, `thermostatHeatingSetpoint`, `thermostatCoolingSetpoint`
- `colorTemperature`, `colorControl`
- `refresh` - request device state update
- `firmwareUpdate` - OTA firmware management
- `healthCheck` - device connectivity monitoring

Full reference: https://developer.smartthings.com/docs/devices/capabilities/capabilities-reference

## 2. Standard vs Custom Capabilities

### Standard Capabilities
Standard capabilities live under the `smartthings` namespace but are referenced without a namespace prefix:
```yaml
- id: switch
  version: 1
- id: temperatureMeasurement
  version: 1
```

### Custom Capabilities
Custom capabilities use the format `namespace.capabilityName`:
```yaml
- id: perfectlife6617.customGarageDoor
  version: 1
```

A namespace is auto-generated per developer account (e.g., `perfectlife6617`). Custom capabilities are created via the SmartThings CLI:
```
smartthings capabilities:create -i capability.json
```

Custom capabilities require a Capability Presentation to render properly in the app.

## 3. Device Profile YAML Format

Device profiles define which capabilities a device exposes, organized into components. They live in `profiles/` directories within driver packages.

### Basic Profile Example (from `zwave-lock`)
```yaml
name: base-lock
components:
- id: main
  capabilities:
  - id: lock
    version: 1
  - id: lockCodes
    version: 1
  - id: battery
    version: 1
  - id: refresh
    version: 1
  categories:
  - name: SmartLock
```

### Multi-Component Profile (from `zigbee-fan`)
```yaml
name: fan-light
components:
  - id: main
    label: Fan
    capabilities:
      - id: switch
        version: 1
      - id: fanSpeed
        version: 1
        config:
          values:
            - key: "fanSpeed.value"
              range: [0, 3]
      - id: firmwareUpdate
        version: 1
      - id: refresh
        version: 1
    categories:
      - name: Fan
  - id: light
    label: Light
    capabilities:
      - id: switch
        version: 1
      - id: switchLevel
        version: 1
        config:
          values:
            - key: "level.value"
              range: [0, 100]
      - id: refresh
        version: 1
    categories:
      - name: Light
```

### Profile with Embedded Config and Preferences (from `zigbee-contact`)
```yaml
name: multi-sensor
components:
- id: main
  capabilities:
  - id: contactSensor
    version: 1
  - id: temperatureMeasurement
    version: 1
  - id: threeAxis
    version: 1
  - id: accelerationSensor
    version: 1
  - id: battery
    version: 1
  - id: firmwareUpdate
    version: 1
  - id: refresh
    version: 1
  categories:
  - name: MultiFunctionalSensor
preferences:
  - preferenceId: tempOffset
    explicit: true
  - preferenceId: certifiedpreferences.garageSensor
    explicit: true
```

### Key Profile Rules
- Must have at least one component; the primary is always `id: main`
- Use multiple components when the same capability is needed more than once (e.g., multi-gang switch)
- Each component needs at least one capability
- `categories` determines the device icon in the app (e.g., `SmartLock`, `Fan`, `Light`, `Thermostat`, `MultiFunctionalSensor`)
- `version: 1` is always used (only version supported)

## 4. Embedded Device Configurations

Embedded device configs let you customize the SmartThings app UI directly in the profile YAML, without creating a separate Device Presentation. Only supported by Edge Drivers.

### Range Constraint
```yaml
- id: colorTemperature
  config:
    values:
      - key: "colorTemperature.value"
        range: [2600, 6200]
```

### Enabled Values (filter enum options)
```yaml
- id: thermostatOperatingState
  version: 1
  config:
    values:
      - key: "thermostatOperatingState.value"
        enabledValues:
          - heating
          - cooling
          - fan only
          - idle
```

### Separate Attribute vs Command Values
```yaml
- id: thermostatMode
  config:
    values:
      - key: thermostatMode.value
        enabledValues:
          - off
          - heat
          - eco
      - key: setThermostatMode
        enabledValues:
          - off
          - heat
```

### Enum Commands
```yaml
- id: alarm
  config:
    values:
      - key: alarm.value
        enabledValues:
          - off
          - siren
      - key: "{{enumCommands}}"
        enabledValues:
          - off
          - siren
```

When you package the driver, the platform auto-generates a Device Presentation from these configs.

## 5. Preferences

Preferences let users configure device behavior from Settings in the SmartThings app.

### Two Types

**Explicit (shared/reusable):** Defined externally, referenced by ID in the profile:
```yaml
preferences:
  - preferenceId: tempOffset
    explicit: true
```

Standard explicit preferences include: `tempOffset`, `humidityOffset`, `motionSensitivity`, `reportingInterval`, `reverse`, `presetPosition`, `username`, `password`.

`tempOffset` and `humidityOffset` are automatically applied by the platform to attribute values - no driver code needed.

**Embedded (inline in profile):** Defined directly in the profile YAML:
```yaml
preferences:
  - title: "IP Address"
    name: ipAddress
    description: "IP address of the Pi-Hole"
    required: true
    preferenceType: string
    definition:
      minLength: 7
      maxLength: 15
      stringType: text
      default: localhost
```

### Preference Types
| Type | Definition Fields |
|------|------------------|
| boolean | `default` |
| integer | `minimum`, `maximum`, `default` |
| number | `minimum`, `maximum`, `default` |
| string | `stringType` (text/paragraph/password), `minLength`, `maxLength`, `default` |
| enumeration | `options` (key-value map), `default` (must match a key) |

### Accessing Preferences in Lua

Query current value:
```lua
local offset = device.preferences.tempOffset
local level = command.args.level + device.preferences.levelOffset
```

Handle preference changes via `infoChanged` lifecycle:
```lua
local function device_info_changed(driver, device, event, args)
  if args.old_st_store.preferences.sensitivityLevel ~= device.preferences.sensitivityLevel then
    device:send(<message_to_control_device>)
  end
end
```

For sleepy Z-Wave devices, use `device:set_update_preferences_fn(fn)` which fires on wakeup.

## 6. config.yml

The `config.yml` file is the driver package manifest. It lives at the root of each driver directory.

```yaml
name: 'Zigbee Thermostat'
defaultProfile: 'thermostat-battery-powerSource'
packageKey: 'zigbee-thermostat'
permissions:
  zigbee: {}
description: "SmartThings driver for Zigbee thermostat devices"
vendorSupportInformation: "https://support.smartthings.com"
```

### Fields
| Field | Description |
|-------|-------------|
| `name` | Human-readable driver name |
| `packageKey` | Unique package identifier |
| `permissions` | Protocol access: `zigbee: {}`, `zwave: {}`, `lan: {}`, `matter: {}` |
| `description` | Driver description |
| `defaultProfile` | Profile name used when no fingerprint match specifies one |
| `vendorSupportInformation` | Support URL |

## 7. Fingerprints

Fingerprints map physical devices to profiles. They live in `fingerprints.yml` at the driver root.

### Zigbee Fingerprints
```yaml
zigbeeManufacturer:
  - id: "LUMI/lumi.motion.ac02"
    deviceLabel: Aqara Motion Sensor P1
    manufacturer: LUMI
    model: lumi.motion.ac02
    deviceProfileName: motion-illuminance-battery-aqara
  - id: "SmartThings/motionv5"
    deviceLabel: Motion Sensor
    manufacturer: SmartThings
    model: motionv5
    deviceProfileName: motion-temp-battery

zigbeeGeneric:
  - id: kickstarter/motion/1
    deviceLabel: SmartThings Motion Sensor
    zigbeeProfiles:
      - 0xFC01
    deviceIdentifiers:
      - 0x013A
    deviceProfileName: smartsense-motion
```

### Key Fingerprint Fields
| Field | Description |
|-------|-------------|
| `id` | Unique identifier for the fingerprint |
| `deviceLabel` | Default label shown to users |
| `manufacturer` | Device manufacturer string |
| `model` | Device model string |
| `deviceProfileName` | Which profile from `profiles/` to use |
| `zigbeeProfiles` | (zigbeeGeneric) Zigbee profile IDs |
| `deviceIdentifiers` | (zigbeeGeneric) Zigbee device type IDs |

Z-Wave fingerprints use `manufacturerId`, `productType`, and `productId` instead.

## 8. Relationship: config.yml + Profiles + Fingerprints

```
driver/
├── config.yml              # Package manifest, declares defaultProfile
├── fingerprints.yml        # Maps hardware → profile by deviceProfileName
├── profiles/
│   ├── basic-device.yml    # Profile A
│   └── advanced-device.yml # Profile B
└── src/
    └── init.lua            # Driver logic
```

Flow:
1. A device joins the hub
2. The platform matches it against `fingerprints.yml` entries
3. The matched fingerprint's `deviceProfileName` selects which profile to use
4. If no fingerprint matches, `defaultProfile` from `config.yml` is used
5. The profile defines capabilities, components, categories, and preferences
6. Embedded `config` in the profile customizes the app UI
7. The driver's Lua code handles capability commands and emits attribute events
