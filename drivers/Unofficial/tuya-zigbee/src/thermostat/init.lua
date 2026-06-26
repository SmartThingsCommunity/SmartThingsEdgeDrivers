-- Copyright 2026 SmartThings
--
-- Licensed under the Apache License, Version 2.0 (the "License");
-- you may not use this file except in compliance with the License.
-- You may obtain a copy of the License at
--
--     http://www.apache.org/licenses/LICENSE-2.0
--
-- Unless required by applicable law or agreed to in writing, software
-- distributed under the License is distributed on an "AS IS" BASIS,
-- WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
-- See the License for the specific language governing permissions and
-- limitations under the License.


local capabilities = require "st.capabilities"
local defaults = require "st.zigbee.defaults"
local device_management = require "st.zigbee.device_management"
local clusters = require "st.zigbee.zcl.clusters"
local tuya_utils = require "tuya_utils"
local Basic = clusters.Basic
local packet_id = 0

local FINGERPRINTS = {
  { mfr = "_TZE284_fziifcxj", model = "TS0601"}
}

local function is_tuya_thermostat(opts, driver, device)
  for _, fingerprint in ipairs(FINGERPRINTS) do
    if device:get_manufacturer() == fingerprint.mfr and device:get_model() == fingerprint.model then
      return true
    end
  end
  return false
end

local function device_added(self, device)
  device:emit_event(capabilities.thermostatMode.supportedThermostatModes({
    capabilities.thermostatMode.thermostatMode.antifreezing.NAME,
    capabilities.thermostatMode.thermostatMode.auto.NAME,
    capabilities.thermostatMode.thermostatMode.comfort.NAME,
    capabilities.thermostatMode.thermostatMode.eco.NAME,
    capabilities.thermostatMode.thermostatMode.off.NAME,
    capabilities.thermostatMode.thermostatMode.on.NAME,
  }, { visibility = { displayed = false } }))
  device:emit_event(capabilities.thermostatHeatingSetpoint.heatingSetpoint({value = 15.0, unit = "C"}))
  device:emit_event(capabilities.temperatureMeasurement.temperature({value = 20.0, unit = "C"}))
  device:emit_event(capabilities.thermostatMode.thermostatMode.auto())
  device:emit_event(capabilities.battery.battery(100))
end

local function do_configure(driver, device)
  -- configure ApplicationVersion to keep device online, tuya hub also uses this attribute
  tuya_utils.send_magic_spell(device)
  device:send(Basic.attributes.ApplicationVersion:configure_reporting(device, 30, 300, 1))
  device:send(device_management.build_bind_request(
    device,
    Basic.ID,
    driver.environment_info.hub_zigbee_eui
  ))
end

local function increase_packet_id(pid)
  return (pid + 1) % 65536
end

local function do_refresh(driver, device)
  print("do_refresh called")
end

local MODE_MAP = {
  [capabilities.thermostatMode.thermostatMode.auto.NAME]         = "\x00",
  [capabilities.thermostatMode.thermostatMode.off.NAME]          = "\x01",
  [capabilities.thermostatMode.thermostatMode.on.NAME]           = "\x02",
  [capabilities.thermostatMode.thermostatMode.comfort.NAME]      = "\x03",
  [capabilities.thermostatMode.thermostatMode.eco.NAME]          = "\x04",
  [capabilities.thermostatMode.thermostatMode.antifreezing.NAME] = "\x05",
}

local function set_thermostat_mode(driver, device, command)
  local mode_value = MODE_MAP[command.args.mode]
  if mode_value ~= nil then
    tuya_utils.send_tuya_command(device, "\x02", tuya_utils.DP_TYPE_ENUM, mode_value, packet_id)
    packet_id = increase_packet_id(packet_id)
  end
end

local function set_heating_setpoint(driver, device, command)
  local value = command.args.setpoint
  local setpoint_raw = math.floor(value * 10 + 0.5)
  tuya_utils.send_tuya_command(
    device,
    "\x04",
    tuya_utils.DP_TYPE_VALUE,
    string.pack(">I4", setpoint_raw),
    packet_id
  )
  packet_id = increase_packet_id(packet_id)
end

local function tuya_cluster_handler(driver, device, zb_rx)
  local event
  local raw = zb_rx.body.zcl_body.body_bytes
  local dp = raw:byte(3)
  local dp_type = raw:byte(4)
  local dp_data_len = string.unpack(">I2", raw:sub(5, 6))
  local dp_data = raw:sub(7, 6 + dp_data_len)

  if dp == 0x04 then -- Target temperature
    if dp_type == 0x02 and dp_data_len >= 4 then -- value
      local target_temp_raw = string.unpack(">I4", dp_data:sub(1, 4))
      local target_temp = target_temp_raw / 10.0
      event = capabilities.thermostatHeatingSetpoint.heatingSetpoint({
        value = target_temp,
        unit = "C"
      })
    end

  elseif dp == 0x05 then -- Current temperature
    if dp_type == 0x02 and dp_data_len >= 4 then -- value
      local temp_raw = string.unpack(">I4", dp_data:sub(1, 4))
      local temp = temp_raw / 10.0
      event = capabilities.temperatureMeasurement.temperature({
        value = temp,
        unit = "C"
      })
    end

  elseif dp == 0x02 then -- Thermostat mode
    if dp_type == 0x04 and dp_data_len >= 1 then -- enum
      local mode = dp_data:byte(1)
      if     mode == 0x00 then -- auto
        event = capabilities.thermostatMode.thermostatMode.auto()
      elseif mode == 0x01 then -- off
        event = capabilities.thermostatMode.thermostatMode.off()
      elseif mode == 0x02 then -- on
        event = capabilities.thermostatMode.thermostatMode.on()
      elseif mode == 0x03 then -- comfort
        event = capabilities.thermostatMode.thermostatMode.comfort()
      elseif mode == 0x04 then -- eco
        event = capabilities.thermostatMode.thermostatMode.eco()
      elseif mode == 0x05 then -- antifreezing
        event = capabilities.thermostatMode.thermostatMode.antifreezing()
      end
    end

  elseif dp == 0x06 then -- Battery level
    if dp_type == 0x02 and dp_data_len >= 4 then -- value
      local battery_level = string.unpack(">I4", dp_data:sub(1, 4))
      event = capabilities.battery.battery(battery_level)
    end
  end

  if event ~= nil then
    device:emit_event(event)
  end
end

local tuya_thermostat_driver = {
  NAME = "tuya thermostat",
  supported_capabilities = {
    capabilities.temperatureMeasurement,
    capabilities.thermostatHeatingSetpoint,
    capabilities.thermostatMode,
    capabilities.battery,
    capabilities.refresh
  },
  zigbee_handlers = {
    cluster = {
      [tuya_utils.TUYA_PRIVATE_CLUSTER] = {
        [tuya_utils.TUYA_PRIVATE_CMD_REPORT] = tuya_cluster_handler,
        [tuya_utils.TUYA_PRIVATE_CMD_RESPONSE] = tuya_cluster_handler,
      }
    }
  },
  capability_handlers = {
    [capabilities.thermostatMode.ID] = {
      [capabilities.thermostatMode.commands.setThermostatMode.NAME] = set_thermostat_mode,
    },
    [capabilities.thermostatHeatingSetpoint.ID] = {
      [capabilities.thermostatHeatingSetpoint.commands.setHeatingSetpoint.NAME] = set_heating_setpoint,
    },
    [capabilities.refresh.ID] = {
      [capabilities.refresh.commands.refresh.NAME] = do_refresh,
    },
  },
  lifecycle_handlers = {
    added = device_added,
    doConfigure = do_configure
  },
  can_handle = is_tuya_thermostat
}

defaults.register_for_default_handlers(
  tuya_thermostat_driver,
  tuya_thermostat_driver.supported_capabilities,
  {}
)
return tuya_thermostat_driver