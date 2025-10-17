-- Copyright 2025 SmartThings
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

local data_types = require "st.zigbee.data_types"
local battery_defaults = require "st.zigbee.defaults.battery_defaults"
--ZCL
local zcl_clusters = require "st.zigbee.zcl.clusters"
local cluster_base = require "st.zigbee.cluster_base"
local Basic = zcl_clusters.Basic
local IASWD = zcl_clusters.IASWD
local IASZone = zcl_clusters.IASZone
local IaswdLevel = IASWD.types.IaswdLevel
local SirenConfiguration = IASWD.types.SirenConfiguration
local SquawkConfiguration = IASWD.types.SquawkConfiguration
local SquawkMode = IASWD.types.SquawkMode
local WarningMode = IASWD.types.WarningMode
local PowerConfiguration = zcl_clusters.PowerConfiguration

--capability
local capabilities = require "st.capabilities"
local alarm = capabilities.alarm

local ALARM_COMMAND = "alarmCommand"
local ALARM_LAST_DURATION = "lastDuration"
local ALARM_MAX_DURATION = "maxDuration"
local SIREN_FIXED_ENDIAN_SW_VERSION = "010903"

local ALARM_DEFAULT_MAX_DURATION = 0x00F0
local PRIMARY_SW_VERSION = "primary_sw_version"
local DEVELCO_BASIC_PRIMARY_SW_VERSION_ATTR = 0x8000
local DEVELCO_MANUFACTURER_CODE = 0x1015
local IASZONE_ENDPOINT = 0x2B

local alarm_command = {
  OFF = 0,
  SIREN = 1,
}

local IASZone_configuration = {
  {
    cluster = IASZone.ID,
    attribute = IASZone.attributes.ZoneStatus.ID,
    minimum_interval = 0,
    maximum_interval = 6*60*60,
    data_type = IASZone.attributes.ZoneStatus.base_type,
    reportable_change = 1
  }
}

local SQUAWK_VOICE_MAP = {
  ["Armed"] = 0,
  ["Disarmed"] = 1
}

local VOLUME_MAP = {
  ["Low"] = 0,
  ["Medium"] = 1,
  ["High"] = 2,
  ["Very High"] = 3
}
local SIREN_VOICE_MAP = {
  ["Burglar"] = 1,
  ["Fire"] = 2,
  ["Emergency"] = 3,
  ["Panic"] = 4,
  ["Panic Fire"] = 5,
  ["Panic Emergency"] = 6
}

local function configure_battery_handling_based_on_fw(driver, device)
  local sw_version = device:get_field(PRIMARY_SW_VERSION)

  if sw_version and sw_version < SIREN_FIXED_ENDIAN_SW_VERSION then
    -- Old firmware - does not support BatteryPercentageRemaining attribute, use battery defaults (voltage-based)
    battery_defaults.build_linear_voltage_init(3.3, 4.1)(driver, device)
  else
    -- New firmware - supports BatteryPercentageRemaining, remove voltage monitoring
    device:remove_configured_attribute(PowerConfiguration.ID, PowerConfiguration.attributes.BatteryVoltage.ID)
    device:remove_monitored_attribute(PowerConfiguration.ID, PowerConfiguration.attributes.BatteryVoltage.ID)
  end
end

local function device_init(driver, device)
  for _, attribute in ipairs(IASZone_configuration) do
    device:add_configured_attribute(attribute)
    device:add_monitored_attribute(attribute)
  end
end

local function device_added (driver, device)
  for comp_name, comp in pairs(device.profile.components) do
    if comp_name ~= "main" then
      if comp_name == "SirenVoice" then
        device:emit_component_event(comp, capabilities.mode.supportedModes({"Burglar", "Fire", "Emergency", "Panic","Panic Fire","Panic Emergency" }, {visibility = {displayed = false}}))
        device:emit_component_event(comp, capabilities.mode.supportedArguments({"Burglar", "Fire", "Emergency", "Panic","Panic Fire","Panic Emergency" }, {visibility = {displayed = false}}))
        device:emit_component_event(comp, capabilities.mode.mode("Burglar"))
      elseif comp_name == "SquawkVoice" then
        device:emit_component_event(comp, capabilities.mode.supportedModes({"Armed", "Disarmed"}, {visibility = {displayed = false}}))
        device:emit_component_event(comp, capabilities.mode.supportedArguments({"Armed", "Disarmed"}, {visibility = {displayed = false}}))
        device:emit_component_event(comp, capabilities.mode.mode("Armed"))
      else
        device:emit_component_event(comp, capabilities.mode.supportedModes({"Low", "Medium", "High", "Very High"}, {visibility = {displayed = false}}))
        device:emit_component_event(comp, capabilities.mode.supportedArguments({"Low", "Medium", "High", "Very High"}, {visibility = {displayed = false}}))
        device:emit_component_event(comp, capabilities.mode.mode("Very High"))
      end
    end
  end

  device:emit_event(capabilities.alarm.alarm.off())

  if(device:supports_capability(capabilities.tamperAlert)) then
    device:emit_event(capabilities.tamperAlert.tamper.clear())
  end
end

local function do_refresh(driver, device)
  device:send(IASZone.attributes.ZoneStatus:read(device):to_endpoint(IASZONE_ENDPOINT))

  -- Check if we have the software version
  local sw_version = device:get_field(PRIMARY_SW_VERSION)
  if ((sw_version == nil) or (sw_version == "")) then
    device:send(cluster_base.read_manufacturer_specific_attribute(device, Basic.ID, DEVELCO_BASIC_PRIMARY_SW_VERSION_ATTR, DEVELCO_MANUFACTURER_CODE))
  end
end

local function do_configure(driver, device)
  device:set_field(ALARM_MAX_DURATION, device.preferences.warningDuration == nil and ALARM_DEFAULT_MAX_DURATION or device.preferences.warningDuration, {persist = true})
  device:send(IASWD.attributes.MaxDuration:write(device, device.preferences.warningDuration == nil and ALARM_DEFAULT_MAX_DURATION or device.preferences.warningDuration):to_endpoint(0x2B))

  -- Check if we have the software version
  local sw_version = device:get_field(PRIMARY_SW_VERSION)
  if ((sw_version == nil) or (sw_version == "")) then
    device:send(cluster_base.read_manufacturer_specific_attribute(device, Basic.ID, DEVELCO_BASIC_PRIMARY_SW_VERSION_ATTR, DEVELCO_MANUFACTURER_CODE))
  else
    configure_battery_handling_based_on_fw(driver, device)
  end

  device.thread:call_with_delay(5, function()
    do_refresh(driver, device)
  end)
  device:configure()
end

local function primary_sw_version_attr_handler(driver, device, value, zb_rx)
  local primary_sw_version = value.value:gsub('.', function (c) return string.format('%02x', string.byte(c)) end)
  device:set_field(PRIMARY_SW_VERSION, primary_sw_version, {persist = true})
  configure_battery_handling_based_on_fw(driver, device)
end

local function generate_event_from_zone_status(driver, device, zone_status, zb_rx)
  if device:supports_capability(capabilities.tamperAlert) then
    device:emit_event_for_endpoint(
        zb_rx.address_header.src_endpoint.value,
        zone_status:is_tamper_set() and capabilities.tamperAlert.tamper.detected() or capabilities.tamperAlert.tamper.clear()
    )
  end
  device:emit_event_for_endpoint(
      zb_rx.address_header.src_endpoint.value,
      zone_status:is_ac_mains_fault_set() and capabilities.powerSource.powerSource.battery() or capabilities.powerSource.powerSource.mains()
  )
end

local function ias_zone_status_attr_handler(driver, device, zone_status, zb_rx)
  generate_event_from_zone_status(driver, device, zone_status, zb_rx)
end

local function ias_zone_status_change_handler(driver, device, zb_rx)
  local zone_status = zb_rx.body.zcl_body.zone_status
  generate_event_from_zone_status(driver, device, zone_status, zb_rx)
end

local function send_siren_command(device, warning_mode, warning_siren_level)
  -- Check if we have the software version first
  local sw_version = device:get_field(PRIMARY_SW_VERSION)
  if ((sw_version == nil) or (sw_version == "")) then
    device:send(cluster_base.read_manufacturer_specific_attribute(device, Basic.ID, DEVELCO_BASIC_PRIMARY_SW_VERSION_ATTR, DEVELCO_MANUFACTURER_CODE))
  end

  local max_duration = device:get_field(ALARM_MAX_DURATION)
  local warning_duration = max_duration and max_duration or ALARM_DEFAULT_MAX_DURATION

  device:set_field(ALARM_LAST_DURATION, warning_duration, {persist = true})

  local siren_configuration

  if (sw_version and sw_version < SIREN_FIXED_ENDIAN_SW_VERSION) then
    -- Old frient firmware, the endian format is reversed
    local siren_config_value = (warning_siren_level << 6) | warning_mode
    siren_configuration = SirenConfiguration(siren_config_value)
  else
    siren_configuration = SirenConfiguration(0x00)
    siren_configuration:set_warning_mode(warning_mode)
    siren_configuration:set_siren_level(warning_siren_level)
  end

  device:send(
      IASWD.server.commands.StartWarning(
          device,
          siren_configuration,
          data_types.Uint16(warning_duration),
          data_types.Uint8(0x00),
          data_types.Enum8(0x00)
      )
  )
end

local function siren_switch_off_handler(driver, device, command)
  device:set_field(ALARM_COMMAND, alarm_command.OFF, {persist = true})
  send_siren_command(device, WarningMode.STOP, IaswdLevel.LOW_LEVEL)
end

local function siren_alarm_siren_handler(driver, device, command)
  device:set_field(ALARM_COMMAND, alarm_command.SIREN, {persist = true})

  -- delay is needed to allow st automations get updated fields when mode, volume, voice is set sequentially
  device.thread:call_with_delay(1, function()
    local sirenVoice_msg = device:get_field("sirenVoice")
    local sirenVolume_msg = device:get_field("sirenVolume")
    send_siren_command(device,sirenVoice_msg == nil and WarningMode.BURGLAR or SIREN_VOICE_MAP[sirenVoice_msg] , sirenVolume_msg == nil and IaswdLevel.VERY_HIGH_LEVEL or VOLUME_MAP[sirenVolume_msg])
  end)

  local warningDurationDelay = device.preferences.warningDuration or ALARM_DEFAULT_MAX_DURATION
  device.thread:call_with_delay(warningDurationDelay, function() -- Send command to switch from siren to off in the app when the siren is done
    if(device:get_field(ALARM_COMMAND) == alarm_command.SIREN) then
      siren_switch_off_handler(driver, device, command)
    end
  end)
end

local function send_squawk_command(device, squawk_mode, squawk_siren_level)
  -- Check if we have the software version first
  local sw_version = device:get_field(PRIMARY_SW_VERSION)

  if ((sw_version == nil) or (sw_version == "")) then
    device:send(cluster_base.read_manufacturer_specific_attribute(device, Basic.ID, DEVELCO_BASIC_PRIMARY_SW_VERSION_ATTR, DEVELCO_MANUFACTURER_CODE))
  end

  local squawk_configuration

  if (sw_version and sw_version < SIREN_FIXED_ENDIAN_SW_VERSION) then
    -- Old frient firmware, the endian format is reversed
    local squawk_config_value = (squawk_siren_level << 6) | squawk_mode
    squawk_configuration = SquawkConfiguration(squawk_config_value)
  else
    squawk_configuration = SquawkConfiguration(0x00)
    squawk_configuration:set_squawk_mode(squawk_mode)
    squawk_configuration:set_squawk_level(squawk_siren_level)
  end

  device:send(
      IASWD.server.commands.Squawk(
              device,
              squawk_configuration
      )
  )
end

local function siren_tone_beep_handler(driver, device, command)
  device.thread:call_with_delay(1, function ()
    local squawkVolume_msg = device:get_field("squawkVolume")
    local squawkVoice_msg = device:get_field("squawkVoice")
    send_squawk_command(device, SQUAWK_VOICE_MAP[squawkVoice_msg] or SquawkMode.SOUND_FOR_SYSTEM_IS_ARMED,VOLUME_MAP[squawkVolume_msg] or IaswdLevel.VERY_HIGH_LEVEL)
  end )
end

local function info_changed(driver, device, event, args)
  for name, info in pairs(device.preferences) do
    if (device.preferences[name] ~= nil and args.old_st_store.preferences[name] ~= device.preferences[name]) then
      local input = device.preferences[name]
      if (name == "warningDuration") then
        device:set_field(ALARM_LAST_DURATION, input, {persist = true})
        device:send(IASWD.attributes.MaxDuration:write(device, tonumber(input)))
      end
    end
  end
end

local function siren_mode_handler(driver, device, command)
  local mode_set = command.args.mode
  local component = command.component
  local compObj = device.profile.components[component]

  if compObj then
    if component == "SirenVolume" then
      device:set_field("sirenVolume", mode_set, {persist = true})
    elseif component == "SirenVoice" then
      device:set_field("sirenVoice", mode_set, {persist = true})
    elseif component == "SquawkVolume" then
      device:set_field("squawkVolume", mode_set, {persist = true})
    elseif component == "SquawkVoice" then
      device:set_field("squawkVoice", mode_set, {persist = true})
    end
  end

  device.thread:call_with_delay(2,function()
    device:emit_component_event(
            compObj,
            capabilities.mode.mode(mode_set))
  end)
end

local frient_siren_driver = {
  NAME = "frient A/S",
  lifecycle_handlers = {
    added = device_added,
    init = device_init,
    doConfigure = do_configure,
    infoChanged = info_changed,
  },
  capability_handlers = {
    [alarm.ID] = {
      [alarm.commands.off.NAME] = siren_switch_off_handler,
      [alarm.commands.siren.NAME] = siren_alarm_siren_handler,
      [alarm.commands.both.NAME] = siren_alarm_siren_handler
    },
    [capabilities.tone.ID] = {
      [capabilities.tone.commands.beep.NAME] = siren_tone_beep_handler
    },
    [capabilities.mode.ID] = {
      [capabilities.mode.commands.setMode.NAME] = siren_mode_handler
    },
    [capabilities.refresh.ID] = {
      [capabilities.refresh.commands.refresh.NAME] = do_refresh
    }
  },
  zigbee_handlers = {
    cluster = {
      [IASZone.ID] = {
        [IASZone.client.commands.ZoneStatusChangeNotification.ID] = ias_zone_status_change_handler
      }
    },
    attr = {
      [IASZone.ID] = {
        [IASZone.attributes.ZoneStatus.ID] = ias_zone_status_attr_handler
      },
      [Basic.ID] = {
        [DEVELCO_BASIC_PRIMARY_SW_VERSION_ATTR] = primary_sw_version_attr_handler
      }
    }
  },
  can_handle = function(opts, driver, device, ...)
    return device:get_manufacturer() == "frient A/S" and (device:get_model() == "SIRZB-110" or device:get_model() == "SIRZB-111" or device:get_model() == "SIRZB-112")
  end
}

return frient_siren_driver
