local clusters = require "st.zigbee.zcl.clusters"
local cluster_base = require "st.zigbee.cluster_base"
local data_types = require "st.zigbee.data_types"
local capabilities = require "st.capabilities"
local battery_defaults = require "st.zigbee.defaults.battery_defaults"

local OnOff = clusters.OnOff
local IASZone = clusters.IASZone
local PowerConfiguration = clusters.PowerConfiguration

local MFG_CODE = 0x115F
local PRIVATE_CLUSTER_ID = 0xFCC0
local PRIVATE_ATTRIBUTE_ID = 0x0009
local PRIVATE_HEART_BATTERY_ENERGY_ID = 0x00F7

local FINGERPRINTS = {
  { mfr = "LUMI", model = "lumi.magnet.agl02" }
}

local CONFIGURATIONS = {
  {
    cluster = OnOff.ID,
    attribute = OnOff.attributes.OnOff.ID,
    minimum_interval = 30,
    maximum_interval = 3600,
    data_type = OnOff.attributes.OnOff.base_type,
    reportable_change = 1
  },
  {
    cluster = PowerConfiguration.ID,
    attribute = PowerConfiguration.attributes.BatteryVoltage.ID,
    minimum_interval = 30,
    maximum_interval = 3600,
    data_type = PowerConfiguration.attributes.BatteryVoltage.base_type,
    reportable_change = 1
  }
}

local is_aqara_products = function(opts, driver, device, ...)
  for _, fingerprint in ipairs(FINGERPRINTS) do
    if device:get_manufacturer() == fingerprint.mfr and device:get_model() == fingerprint.model then
      return true
    end
  end
  return false
end

local function device_init(driver, device)
  device:remove_configured_attribute(IASZone.ID, IASZone.attributes.ZoneStatus.ID)
  device:remove_monitored_attribute(IASZone.ID, IASZone.attributes.ZoneStatus.ID)

  battery_defaults.build_linear_voltage_init(2.6, 3.0)(driver, device)

  for _, attribute in ipairs(CONFIGURATIONS) do
    device:add_configured_attribute(attribute)
    device:add_monitored_attribute(attribute)
  end
end

local function do_configure(self, device)
  device:configure()
  device:send(cluster_base.write_manufacturer_specific_attribute(device,
    PRIVATE_CLUSTER_ID, PRIVATE_ATTRIBUTE_ID, MFG_CODE, data_types.Uint8, 0x01))
end

local function emit_event_if_latest_state_missing(device, component, capability, attribute_name, value)
  if device:get_latest_state(component, capability.ID, attribute_name) == nil then
    device:emit_event(value)
  end
end

local function added_handler(driver, device)
  device:emit_event(capabilities.batteryLevel.type("CR1632"))
  device:emit_event(capabilities.batteryLevel.quantity(1))
  device:emit_event(capabilities.batteryLevel.battery("normal"))
  emit_event_if_latest_state_missing(device, "main", capabilities.contactSensor, capabilities.contactSensor.contact.NAME, capabilities.contactSensor.contact.open())
end

local function contact_status_handler(self, device, value, zb_rx)
  if value.value == 1 or value.value == true then
    device:emit_event(capabilities.contactSensor.contact.open())
  elseif value.value == 0 or value.value == false then
    device:emit_event(capabilities.contactSensor.contact.closed())
  end
end

local function calc_battery_level(voltage)
  local batteryLevel = "normal"
  if voltage <= 25 then
    batteryLevel = "critical"
  elseif voltage < 28 then
    batteryLevel = "warning"
  end

  return batteryLevel
end

local function battery_status_handler(driver, device, value, zb_rx)
  device:emit_event(capabilities.batteryLevel.battery(calc_battery_level(value.value)))
end

local function calc_batt_from_binary(bin_str, offset)
  -- Read two bytes from the specified offset (little-endian format: low byte first)
  local low = string.byte(bin_str, offset)
  local high = string.byte(bin_str, offset + 1)

  -- Validate byte availability
  if not low or not high then return 0 end

  -- Combine bytes into a 16-bit unsigned integer (millivolts)
  local voltage = high * 256 + low

  return voltage
end

local function battery_energy_status_handler(driver, device, value, zb_rx)
  device:emit_event(capabilities.batteryLevel.battery(calc_battery_level(calc_batt_from_binary(value.value, 3))))
end

local aqara_contact_handler = {
  NAME = "Aqara Contact Handler",
  zigbee_handlers = {
    attr = {
      [PRIVATE_CLUSTER_ID] = {
        [PRIVATE_HEART_BATTERY_ENERGY_ID] = battery_energy_status_handler
      },
      [PowerConfiguration.ID] = {
        [PowerConfiguration.attributes.BatteryVoltage.ID] = battery_status_handler
      },
      [OnOff.ID] = {
        [OnOff.attributes.OnOff.ID] = contact_status_handler
      }
    }
  },
  lifecycle_handlers = {
    init = device_init,
    doConfigure = do_configure,
    added = added_handler,
  },
  can_handle = is_aqara_products
}

return aqara_contact_handler
