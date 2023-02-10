local ZigbeeDriver = require "st.zigbee"
local defaults = require "st.zigbee.defaults"
local constants = require "st.zigbee.constants"
local data_types = require "st.zigbee.data_types"
local zcl_global_commands = require "st.zigbee.zcl.global_commands"
local log = require "log"
local cluster_base = require "st.zigbee.cluster_base"

local zcl_clusters = require "st.zigbee.zcl.clusters"
local Status = require "st.zigbee.generated.types.ZclStatus"
local IASZone = zcl_clusters.IASZone
local IASWD = zcl_clusters.IASWD
local SirenConfiguration = IASWD.types.SirenConfiguration
local SquawkConfiguration = IASWD.types.SquawkConfiguration
local WarningMode = IASWD.types.WarningMode
local Strobe = IASWD.types.Strobe
local SquawkMode = IASWD.types.SquawkMode
local IaswdLevel = IASWD.types.IaswdLevel
local Basic = zcl_clusters.Basic

local capabilities = require "st.capabilities"

local BASE_FUNCTIONS = require "device_base_functions"

log.trace("Initializing frient driver")

-- Constants
local ALARM_STROBE_DUTY_CYCLE = 40
local ALARM_STROBE_NO_DUTY_CYCLE = 0

local alarm_command = {
  OFF = 0,
  SIREN = 1,
  STROBE = 2,
  BOTH = 3
}

--- @param device st.zigbee.Device The device this message was received from containing identifying information
local function emit_alarm_event(device, cmd)
  --log.trace("Updating alarm state:"..cmd)
  if cmd == alarm_command.OFF then
    device:emit_event(capabilities.alarm.alarm.off())
    device:emit_event(capabilities.switch.switch.off())
  else
    if cmd == alarm_command.SIREN then
      device:emit_event(capabilities.alarm.alarm.siren())
    elseif cmd == alarm_command.STROBE then
      device:emit_event(capabilities.alarm.alarm.strobe())
    else
      device:emit_event(capabilities.alarm.alarm.both())
    end
    device:emit_event(capabilities.switch.switch.on())
  end
end

--- @param device st.zigbee.Device The device this message was received from containing identifying information
--- @param warning_mode st.zigbee.zcl.clusters.IASWD.types.WarningMode Warning mode for siren
--- @param warning_siren_level st.zigbee.zcl.clusters.IASWD.types.IaswdLevel Siren level
--- @param strobe_level st.zigbee.zcl.clusters.IASWD.types.IaswdLevel Strobe level
local function send_siren_command(device, warning_mode, warning_siren_level, strobe_active, strobe_level)
  -- Check if we have the software version first
  local sw_version = device:get_field(BASE_FUNCTIONS.PRIMARY_SW_VERSION)
  if ((sw_version == nil) or (sw_version == "")) then
    log.warn("Siren: Firmware version not detected, checking software version")
    device:send(cluster_base.read_manufacturer_specific_attribute(device, Basic.ID, BASE_FUNCTIONS.DEVELCO_BASIC_PRIMARY_SW_VERSION_ATTR, BASE_FUNCTIONS.DEVELCO_MANUFACTURER_CODE))
  end

  local max_duration = device:get_field(BASE_FUNCTIONS.ALARM_MAX_DURATION)
  local warning_duration = max_duration and max_duration or BASE_FUNCTIONS.ALARM_DEFAULT_MAX_DURATION
  local duty_cycle = (strobe_active == Strobe.USE_STROBE) and ALARM_STROBE_DUTY_CYCLE or ALARM_STROBE_NO_DUTY_CYCLE

  device:set_field(BASE_FUNCTIONS.ALARM_LAST_DURATION, warning_duration, {persist = true})

  local siren_configuration

  if (device:get_field(BASE_FUNCTIONS.SIREN_ENDIAN) == "reverse") then
    -- Old frient firmware, the endian format is reversed
    log.warn("Reverse endian format detected")
    local siren_config_value = (warning_siren_level << 6) | (strobe_active << 4) | warning_mode
    siren_configuration = SirenConfiguration(siren_config_value)
  else
    siren_configuration = SirenConfiguration(0x00)
    siren_configuration:set_warning_mode(warning_mode)
    siren_configuration:set_strobe(strobe_active)
    siren_configuration:set_siren_level(warning_siren_level)
  end

  device:send(
      IASWD.server.commands.StartWarning(
          device,
          siren_configuration,
          data_types.Uint16(warning_duration),
          data_types.Uint8(duty_cycle),
          data_types.Enum8(strobe_level)
      )
  )
end

--- @param device st.zigbee.Device The device this message was received from containing identifying information
--- @param squawk_mode st.zigbee.zcl.clusters.IASWD.types.SquawkMode Warning mode for siren
--- @param squawk_siren_level st.zigbee.zcl.clusters.IASWD.types.IaswdLevel Siren level
--- @param strobe_active st.zigbee.zcl.clusters.IASWD.types.Strobe Strobe level
local function send_squawk_command(device, squawk_mode, squawk_siren_level, strobe_active)
  -- Check if we have the software version first
  local sw_version = device:get_field(BASE_FUNCTIONS.PRIMARY_SW_VERSION)
  if ((sw_version == nil) or (sw_version == "")) then
    log.warn("Squawk: Firmware version not detected, checking software version")
    device:send(cluster_base.read_manufacturer_specific_attribute(device, Basic.ID, BASE_FUNCTIONS.DEVELCO_BASIC_PRIMARY_SW_VERSION_ATTR, BASE_FUNCTIONS.DEVELCO_MANUFACTURER_CODE))
  end

  local squawk_configuration

  if (device:get_field(BASE_FUNCTIONS.SIREN_ENDIAN) == "reverse") then
    -- Old frient firmware, the endian format is reversed
    log.warn("Reverse endian format detected")
    local squawk_config_value = (squawk_siren_level << 6) | (strobe_active << 4)  | squawk_mode
    squawk_configuration = SquawkConfiguration(squawk_config_value)
  else
    squawk_configuration = SquawkConfiguration(0x00)
    squawk_configuration:set_squawk_mode(squawk_mode)
    squawk_configuration:set_squawk_strobe_active(strobe_active)
    squawk_configuration:set_squawk_level(squawk_siren_level)
  end

  device:send(
      IASWD.server.commands.Squawk(
          device,
          squawk_configuration
      )
  )
end

--- @param driver ZigbeeDriver The current driver running containing necessary context for execution
--- @param device st.zigbee.Device The device this message was received from containing identifying information
--- @param zb_rx st.zigbee.ZigbeeMessageRx the full message this report came in
local function default_response_handler(driver, device, zb_rx)
  local is_success = zb_rx.body.zcl_body.status.value
  local command = zb_rx.body.zcl_body.cmd.value
  local alarm_ev = device:get_field(BASE_FUNCTIONS.ALARM_COMMAND)

  if command == IASWD.server.commands.StartWarning.ID and is_success == Status.SUCCESS then
    if alarm_ev ~= alarm_command.OFF then
      emit_alarm_event(device, alarm_ev)
      local lastDuration = device:get_field(BASE_FUNCTIONS.ALARM_LAST_DURATION)
      device.thread:call_with_delay(lastDuration, function(d)
        device:emit_event(capabilities.alarm.alarm.off())
        device:emit_event(capabilities.switch.switch.off())
      end)
    else
      emit_alarm_event(device,alarm_command.OFF)
    end
  end
end

--- @param driver ZigbeeDriver The current driver running containing necessary context for execution
--- @param device st.zigbee.Device The device this message was received from containing identifying information
--- @param max_duration st.zigbee.data_types.Uint8 the value of the attribute
local function attr_max_duration_handler(driver, device, max_duration)
  device:set_field(BASE_FUNCTIONS.ALARM_MAX_DURATION, max_duration.value, {persist = true})
end

--- @param driver ZigbeeDriver The current driver running containing necessary context for execution
--- @param device st.zigbee.Device The device this message was received from containing identifying information
--- @param command string Command parameters if applicable
local function siren_switch_both_handler(driver, device, command)
  log.debug("Starting Siren + Strobe")
  device:set_field(BASE_FUNCTIONS.ALARM_COMMAND, alarm_command.BOTH, {persist = true})
  send_siren_command(device, device.preferences.warningSound == nil and WarningMode.BURGLAR or WarningMode[device.preferences.warningSound], device.preferences.warningLevel == nil and IaswdLevel.VERY_HIGH_LEVEL or IaswdLevel[device.preferences.warningLevel], Strobe.USE_STROBE, IaswdLevel.VERY_HIGH_LEVEL)
end

--- @param driver ZigbeeDriver The current driver running containing necessary context for execution
--- @param device st.zigbee.Device The device this message was received from containing identifying information
--- @param command string Command parameters if applicable
local function siren_alarm_siren_handler(driver, device, command)
  log.debug("Starting Siren")
  device:set_field(BASE_FUNCTIONS.ALARM_COMMAND, alarm_command.SIREN, {persist = true})
  send_siren_command(device, device.preferences.warningSound == nil and WarningMode.BURGLAR or WarningMode[device.preferences.warningSound], device.preferences.warningLevel == nil and IaswdLevel.VERY_HIGH_LEVEL or IaswdLevel[device.preferences.warningLevel], Strobe.NO_STROBE, IaswdLevel.LOW_LEVEL)
end

--- @param driver ZigbeeDriver The current driver running containing necessary context for execution
--- @param device st.zigbee.Device The device this message was received from containing identifying information
--- @param command string Command parameters if applicable
local function siren_alarm_strobe_handler(driver, device, command)
  log.debug("Starting Strobe")
  device:set_field(BASE_FUNCTIONS.ALARM_COMMAND, alarm_command.STROBE, {persist = true})
  send_siren_command(device, WarningMode.STOP, IaswdLevel.LOW_LEVEL, Strobe.USE_STROBE, IaswdLevel.VERY_HIGH_LEVEL)
end

--- @param driver ZigbeeDriver The current driver running containing necessary context for execution
--- @param device st.zigbee.Device The device this message was received from containing identifying information
--- @param command string Command parameters if applicable
local function siren_tone_beep_handler(driver, device, command)
  log.debug("Starting Squawk")
  send_squawk_command(device, device.preferences.squawkSound == nil and SquawkMode.SOUND_FOR_SYSTEM_IS_ARMED or SquawkMode[device.preferences.squawkSound], device.preferences.warningLevel == nil and IaswdLevel.VERY_HIGH_LEVEL or IaswdLevel[device.preferences.warningLevel], Strobe.NO_STROBE)
end

--- @param driver ZigbeeDriver The current driver running containing necessary context for execution
--- @param device st.zigbee.Device The device this message was received from containing identifying information
--- @param command string Command parameters if applicable
local function siren_switch_on_handler(driver, device, command)
  log.debug("Starting Switch On")
  siren_switch_both_handler(driver, device, command)
end

--- @param driver ZigbeeDriver The current driver running containing necessary context for execution
--- @param device st.zigbee.Device The device this message was received from containing identifying information
--- @param command string Command parameters if applicable
local function siren_switch_off_handler(driver, device, command)
  device:set_field(BASE_FUNCTIONS.ALARM_COMMAND, alarm_command.OFF, {persist = true})
  log.debug("Starting Switch Off")
  send_siren_command(device, WarningMode.STOP, IaswdLevel.LOW_LEVEL, Strobe.NO_STROBE, IaswdLevel.LOW_LEVEL)
end

--- @param driver ZigbeeDriver The current driver running containing necessary context for execution
--- @param device st.zigbee.Device The device this message was received from containing identifying information
--- @param value st.zigbee.data_types.StringABC the value of the Attribute
--- @param zb_rx st.zigbee.ZigbeeMessageRx the full message this report came in
local function primary_sw_version_attr_handler(driver, device, value, zb_rx)
  --log.warn("Manufacturer Primary Software Version Attribute report: 0x"..string.format("%x", zb_rx.body.zcl_body.attr_records[1].attr_id.value).."=0x"..value.value)
  local primary_sw_version = value.value:gsub('.', function (c) return string.format('%02x', string.byte(c)) end)
  log.debug("Manufacturer Primary Software Version firmware: 0x"..primary_sw_version)
  device:set_field(BASE_FUNCTIONS.PRIMARY_SW_VERSION, primary_sw_version, {persist = true})
end

--- @param driver ZigbeeDriver The current driver running containing necessary context for execution
--- @param device st.zigbee.Device The device this message was received from containing identifying information
local function do_refresh(driver, device)
  log.trace("Refreshing device")--..util.stringify_table(device, nil, true))
  BASE_FUNCTIONS.do_refresh(driver, device)
end

--- @param driver ZigbeeDriver The current driver running containing necessary context for execution
--- @param device st.zigbee.Device The device this message was received from containing identifying information
--- @param event string The lifecycle event name
--- @param args table Table containing information relevant to the lifecycle event
local function do_configure(driver, device, event, args)
  log.trace("Configuring device:"..event)--..", "..util.stringify_table(args, nil, true))
  if ((event == "doConfigure") or (args and args.old_st_store)) then -- Only if we got a parameter update then reinitialize, infoChanged could be called periodically also
    BASE_FUNCTIONS.do_configure(driver, device, event, args)
  end

  device.thread:call_with_delay(5, function()
    do_refresh(driver, device)
  end)
end

--- @param driver ZigbeeDriver The current driver running containing necessary context for execution
--- @param device st.zigbee.Device The device this message was received from containing identifying information
local function device_added(driver, device)
  log.trace "Added device"
  BASE_FUNCTIONS.added(driver, device)
end

--- @param driver ZigbeeDriver The current driver running containing necessary context for execution
--- @param device st.zigbee.Device The device this message was received from containing identifying information
local function device_init(driver, device)
  log.trace "Initializing device"
  BASE_FUNCTIONS.init(driver, device)
end

local zigbee_smoke_siren_driver_template = {
  NAME = "frient Smoke Siren driver",
  supported_capabilities = {
    capabilities.alarm,
    capabilities.waterSensor,
    capabilities.tone,
    capabilities.switch,
    capabilities.smokeDetector,
    capabilities.temperatureAlarm,
    capabilities.temperatureMeasurement,
    capabilities.battery,
    capabilities.tamperAlert,
    capabilities.powerSource,
  },
  sub_drivers = {
    require("frient-smoke")
   },
  ias_zone_configuration_method = constants.IAS_ZONE_CONFIGURE_TYPE.AUTO_ENROLL_RESPONSE,
  lifecycle_handlers = {
    added = device_added,
    init = device_init,
    doConfigure = do_configure,
    infoChanged = do_configure,
  },
  zigbee_handlers = {
    global = {
      [IASWD.ID] = {
            [zcl_global_commands.DEFAULT_RESPONSE_ID] = default_response_handler
        }
    },
    attr = {
      [Basic.ID] = {
        [BASE_FUNCTIONS.DEVELCO_BASIC_PRIMARY_SW_VERSION_ATTR] = primary_sw_version_attr_handler,
      },
      [IASWD.ID] = {
        [IASWD.attributes.MaxDuration.ID] = attr_max_duration_handler
      }
    }
  },
  capability_handlers = {
    [capabilities.alarm.ID] = {
      [capabilities.alarm.commands.both.NAME] = siren_switch_both_handler,
      [capabilities.alarm.commands.off.NAME] = siren_switch_off_handler,
      [capabilities.alarm.commands.siren.NAME] = siren_alarm_siren_handler,
      [capabilities.alarm.commands.strobe.NAME] = siren_alarm_strobe_handler
    },
    [capabilities.tone.ID] = {
      [capabilities.tone.commands.beep.NAME] = siren_tone_beep_handler,
    },
    [capabilities.switch.ID] = {
      [capabilities.switch.commands.on.NAME] = siren_switch_on_handler,
      [capabilities.switch.commands.off.NAME] = siren_switch_off_handler
    },
    [capabilities.refresh.ID] = {
      [capabilities.refresh.commands.refresh.NAME] = do_refresh,
    },
  },
  cluster_configurations = {
    [capabilities.alarm.ID] = {
      {
        cluster = IASZone.ID,
        attribute = IASZone.attributes.ZoneStatus.ID,
        minimum_interval = 0,
        maximum_interval = 180,
        data_type = IASZone.attributes.ZoneStatus.base_type
      }
    }
  },
}

defaults.register_for_default_handlers(zigbee_smoke_siren_driver_template, zigbee_smoke_siren_driver_template.supported_capabilities)
local zigbee_smoke_siren_driver = ZigbeeDriver("frient-smoke-siren-detector", zigbee_smoke_siren_driver_template)
zigbee_smoke_siren_driver:run()

