-- NodOn SIN-4-FP-21 Fil Pilote Controller Driver
-- Uses custom capability for exact fil pilote mode names
-- Handles manufacturer cluster 0xFC00 for French electric heating control

local capabilities = require "st.capabilities"
local ZigbeeDriver = require "st.zigbee"
local data_types = require "st.zigbee.data_types"
local zcl_messages = require "st.zigbee.zcl"
local messages = require "st.zigbee.messages"
local zb_const = require "st.zigbee.constants"
local log = require "log"

-- Load custom capability with error handling
local filPiloteMode
local status, err = pcall(function()
  filPiloteMode = capabilities["musictheme49844.filPiloteMode"]
end)

if not status then
  log.error("Failed to load custom capability: " .. tostring(err))
  -- Fallback: create capability reference manually
  filPiloteMode = {
    ID = "musictheme49844.filPiloteMode",
    filPiloteMode = {
      NAME = "filPiloteMode"
    },
    commands = {
      setFilPiloteMode = {
        NAME = "setFilPiloteMode"
      }
    }
  }
end

log.info("NodOn Fil Pilote driver starting...")

-- Manufacturer cluster constants
local MFG_CLUSTER = 0xFC00
local MFG_CODE = 0x128B  -- NodOn manufacturer code
local MODE_ATTRIBUTE = 0x0000
local SET_MODE_COMMAND = 0x00

-- SimpleMetering cluster constants
local SIMPLE_METERING_CLUSTER = 0x0702
local INSTANTANEOUS_DEMAND = 0x0400  -- Power in Watts
local CURRENT_SUMMATION_DELIVERED = 0x0000  -- Energy in Wh

-- Fil Pilote mode mappings
local FP_MODE = {
  OFF = 0x00,
  COMFORT = 0x01,
  ECO = 0x02,
  ANTI_FREEZE = 0x03,
  COMFORT_1 = 0x04,
  COMFORT_2 = 0x05
}

-- Map Zigbee values to custom capability values
local function zigbee_to_capability_mode(zigbee_value)
  if zigbee_value == FP_MODE.OFF then
    return "off"
  elseif zigbee_value == FP_MODE.COMFORT then
    return "comfort"
  elseif zigbee_value == FP_MODE.ECO then
    return "eco"
  elseif zigbee_value == FP_MODE.ANTI_FREEZE then
    return "antiFreeze"
  elseif zigbee_value == FP_MODE.COMFORT_1 then
    return "comfort1"
  elseif zigbee_value == FP_MODE.COMFORT_2 then
    return "comfort2"
  else
    return "off"
  end
end

-- Map capability values to Zigbee values
local function capability_to_zigbee_mode(capability_value)
  if capability_value == "off" then
    return FP_MODE.OFF
  elseif capability_value == "comfort" then
    return FP_MODE.COMFORT
  elseif capability_value == "eco" then
    return FP_MODE.ECO
  elseif capability_value == "antiFreeze" then
    return FP_MODE.ANTI_FREEZE
  elseif capability_value == "comfort1" then
    return FP_MODE.COMFORT_1
  elseif capability_value == "comfort2" then
    return FP_MODE.COMFORT_2
  else
    return FP_MODE.OFF
  end
end

-- Helper: Build read message for manufacturer attribute
local function build_read_mfg_attribute(device, cluster, attribute, mfg_code)
  local zclh = zcl_messages.ZclHeader({
    cmd = data_types.ZCLCommandId(0x00)  -- Read Attributes = 0x00
  })
  zclh.frame_ctrl:set_mfg_specific()
  zclh.mfg_code = data_types.Uint16(mfg_code)

  local addrh = messages.AddressHeader(
    zb_const.HUB.ADDR,
    zb_const.HUB.ENDPOINT,
    device:get_short_address(),
    device:get_endpoint(cluster),
    zb_const.HA_PROFILE_ID,
    cluster
  )

  local attr_id = data_types.validate_or_build_type(attribute, data_types.Uint16, "payload")

  return messages.ZigbeeMessageTx({
    address_header = addrh,
    body = zcl_messages.ZclMessageBody({zcl_header = zclh, zcl_body = attr_id})
  })
end

-- Helper: Build write message using cluster-specific command for manufacturer cluster
local function build_write_mfg_attribute(device, cluster, attribute, value, mfg_code)
  local zclh = zcl_messages.ZclHeader({
    cmd = data_types.ZCLCommandId(SET_MODE_COMMAND)  -- Cluster-specific command
  })
  zclh.frame_ctrl:set_mfg_specific()
  zclh.frame_ctrl:set_cluster_specific()
  zclh.mfg_code = data_types.Uint16(mfg_code)

  local addrh = messages.AddressHeader(
    zb_const.HUB.ADDR,
    zb_const.HUB.ENDPOINT,
    device:get_short_address(),
    device:get_endpoint(cluster),
    zb_const.HA_PROFILE_ID,
    cluster
  )

  -- Payload is just the mode value
  local payload = data_types.Uint8(value)

  return messages.ZigbeeMessageTx({
    address_header = addrh,
    body = zcl_messages.ZclMessageBody({zcl_header = zclh, zcl_body = payload})
  })
end

-- Handle manufacturer cluster attribute reports
local function mode_attribute_handler(driver, device, value, zb_rx)
  log.info("mode_attribute_handler called")
  local zigbee_mode = value.value
  local capability_mode = zigbee_to_capability_mode(zigbee_mode)

  log.info(string.format("Fil Pilote mode report: Zigbee=0x%02X, Capability=%s",
    zigbee_mode, capability_mode))

  -- Emit event using capability
  device:emit_event(capabilities["musictheme49844.filPiloteMode"].filPiloteMode(capability_mode))
end

-- Handle power (instantaneous demand) reports from SimpleMetering cluster
local function power_handler(driver, device, value, zb_rx)
  local power_watts = value.value
  log.info(string.format("Power report: %d W", power_watts))
  device:emit_event(capabilities.powerMeter.power({value = power_watts, unit = "W"}))
end

-- Handle energy (current summation delivered) reports from SimpleMetering cluster
local function energy_handler(driver, device, value, zb_rx)
  local energy_wh = value.value
  local energy_kwh = energy_wh / 1000.0
  log.info(string.format("Energy report: %.3f kWh", energy_kwh))
  device:emit_event(capabilities.energyMeter.energy({value = energy_kwh, unit = "kWh"}))
end

-- Handle setFilPiloteMode command from custom capability
local function set_mode_handler(driver, device, command)
  log.info("set_mode_handler called")
  local mode = command.args.mode
  local zigbee_mode = capability_to_zigbee_mode(mode)

  log.info(string.format("Setting Fil Pilote mode: Capability=%s, Zigbee=0x%02X",
    mode, zigbee_mode))

  -- Build and send manufacturer-specific write message
  local write_msg = build_write_mfg_attribute(device, MFG_CLUSTER, MODE_ATTRIBUTE, zigbee_mode, MFG_CODE)
  device:send(write_msg)

  -- Read back to confirm
  device.thread:call_with_delay(1, function(d)
    local read_msg = build_read_mfg_attribute(device, MFG_CLUSTER, MODE_ATTRIBUTE, MFG_CODE)
    device:send(read_msg)
  end)
end

-- Handle refresh command
local function refresh_handler(driver, device, command)
  log.info("Refreshing Fil Pilote status for device: " .. device.label)

  -- Read fil pilote mode
  local mode_msg = build_read_mfg_attribute(device, MFG_CLUSTER, MODE_ATTRIBUTE, MFG_CODE)
  device:send(mode_msg)

  -- Read power and energy from SimpleMetering cluster using standard read
  local read_power = messages.ZigbeeMessageTx({
    address_header = messages.AddressHeader(
      zb_const.HUB.ADDR,
      zb_const.HUB.ENDPOINT,
      device:get_short_address(),
      device:get_endpoint(SIMPLE_METERING_CLUSTER),
      zb_const.HA_PROFILE_ID,
      SIMPLE_METERING_CLUSTER
    ),
    body = zcl_messages.ZclMessageBody({
      zcl_header = zcl_messages.ZclHeader({cmd = data_types.ZCLCommandId(0x00)}),
      zcl_body = data_types.Uint16(INSTANTANEOUS_DEMAND)
    })
  })
  device:send(read_power)

  local read_energy = messages.ZigbeeMessageTx({
    address_header = messages.AddressHeader(
      zb_const.HUB.ADDR,
      zb_const.HUB.ENDPOINT,
      device:get_short_address(),
      device:get_endpoint(SIMPLE_METERING_CLUSTER),
      zb_const.HA_PROFILE_ID,
      SIMPLE_METERING_CLUSTER
    ),
    body = zcl_messages.ZclMessageBody({
      zcl_header = zcl_messages.ZclHeader({cmd = data_types.ZCLCommandId(0x00)}),
      zcl_body = data_types.Uint16(CURRENT_SUMMATION_DELIVERED)
    })
  })
  device:send(read_energy)
end

-- Device initialization
local function device_init(driver, device)
  log.info("Initializing NodOn Fil Pilote device: " .. device.label)

  -- Read initial mode from manufacturer cluster
  local mode_msg = build_read_mfg_attribute(device, MFG_CLUSTER, MODE_ATTRIBUTE, MFG_CODE)
  device:send(mode_msg)

  -- Read initial power and energy
  device.thread:call_with_delay(2, function(d)
    refresh_handler(driver, device, {})
  end)
end

-- Device added
local function device_added(driver, device)
  log.info("NodOn Fil Pilote device added: " .. device.label)

  -- Set initial state
  device:emit_event(capabilities["musictheme49844.filPiloteMode"].filPiloteMode("off"))

  -- Initialize device
  device_init(driver, device)
end

-- Driver configuration
local nodon_driver = {
  supported_capabilities = {
    filPiloteMode,
    capabilities.powerMeter,
    capabilities.energyMeter,
    capabilities.refresh
  },
  capability_handlers = {
    [filPiloteMode.ID] = {
      [filPiloteMode.commands.setFilPiloteMode.NAME] = set_mode_handler
    },
    [capabilities.refresh.ID] = {
      [capabilities.refresh.commands.refresh.NAME] = refresh_handler
    }
  },
  zigbee_handlers = {
    attr = {
      [MFG_CLUSTER] = {
        [MODE_ATTRIBUTE] = mode_attribute_handler
      },
      [SIMPLE_METERING_CLUSTER] = {
        [INSTANTANEOUS_DEMAND] = power_handler,
        [CURRENT_SUMMATION_DELIVERED] = energy_handler
      }
    }
  },
  lifecycle_handlers = {
    init = device_init,
    added = device_added
  }
}

-- Run the driver
local driver = ZigbeeDriver("nodon-fil-pilote", nodon_driver)
driver:run()
