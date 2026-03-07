-- Copyright 2025 SmartThings, Inc.
-- Licensed under the Apache License, Version 2.0


local zcl_clusters = require "st.zigbee.zcl.clusters"
local cluster_base = require "st.zigbee.cluster_base"
local capabilities = require "st.capabilities"
local battery_defaults = require "st.zigbee.defaults.battery_defaults"
local data_types = require "st.zigbee.data_types"
local button_utils = require "button_utils"
local BasicInput = zcl_clusters.BasicInput
local PowerConfiguration = zcl_clusters.PowerConfiguration
local OnOff = zcl_clusters.OnOff
local panicAlarm = capabilities.panicAlarm
local IASZone = zcl_clusters.IASZone

local DEVELCO_MANUFACTURER_CODE = 0x1015
local BUTTON_LED_COLOR = 0x8002
local BUTTON_PRESS_DELAY = 0x8001
local PANIC_BUTTON = 0x8000

local battery_table = {
    [2.90] = 100,
    [2.80] = 80,
    [2.75] = 60,
    [2.70] = 50,
    [2.65] = 40,
    [2.60] = 30,
    [2.50] = 20,
    [2.40] = 15,
    [2.20] = 10,
    [2.00] = 1,
    [1.90] = 0,
    [0.00] = 0
}

local CONFIGURATIONS = {
  {
    cluster = BasicInput.ID,
    attribute = BasicInput.attributes.PresentValue.ID,
    minimum_interval = 0,
    maximum_interval = 21600,
    data_type = BasicInput.attributes.PresentValue.base_type,
    reportable_change = 1,
    endpoint = 0x20
  },
  {
    cluster = PowerConfiguration.ID,
    attribute = PowerConfiguration.attributes.BatteryVoltage.ID,
    minimum_interval = 30,
    maximum_interval = 21600,
    reportable_change = 1,
  }
}

local PREFERENCE_TABLES = {
  ledColor = {
    clusterId = OnOff.ID,
    attributeId = BUTTON_LED_COLOR,
    dataType = data_types.Enum8,
    mfg_code =  DEVELCO_MANUFACTURER_CODE,
    endpoint = 0x20,
    frame_ctrl = 0x0C
  },
  buttonDelay = {
    clusterId = OnOff.ID,
    attributeId = BUTTON_PRESS_DELAY,
    dataType = data_types.Uint16,
    mfg_code =  DEVELCO_MANUFACTURER_CODE,
    endpoint = 0x20,
    frame_ctrl = 0x0C
  },
  panicButton = {
    clusterId = BasicInput.ID,
    attributeId = PANIC_BUTTON,
    dataType = data_types.Uint16,
    mfg_code = DEVELCO_MANUFACTURER_CODE,
    endpoint = 0x20,
    frame_ctrl = 0x04
  },
  buttonAlarmDelay = {
    clusterId = IASZone.ID,
    attributeId = 0x8002,
    dataType = data_types.Uint16,
    mfg_code = DEVELCO_MANUFACTURER_CODE,
    endpoint = 0x23,
    frame_ctrl = 0x04
  },
  buttonCancelDelay = {
    clusterId = IASZone.ID,
    attributeId = 0x8003,
    dataType= data_types.Uint16,
    mfg_code = DEVELCO_MANUFACTURER_CODE,
    endpoint = 0x23,
    frame_ctrl = 0x04
  },
  autoCancel = {
    clusterId = IASZone.ID,
    attributeId = 0x8004,
    dataType = data_types.Uint16,
    mfg_code = DEVELCO_MANUFACTURER_CODE,
    endpoint = 0x23,
    frame_ctrl = 0x04
  },
  alarmBehavior = {
    clusterId = IASZone.ID,
    attributeId = 0x8005,
    dataType = data_types.Enum8,
    mfg_code = DEVELCO_MANUFACTURER_CODE,
    endpoint = 0x23,
    frame_ctrl = 0x04
  },
}

local function generate_event_from_zone_status(driver, device, zone_status, zigbee_message)
  if device:supports_capability(panicAlarm) then
    if zone_status:is_alarm2_set() then
      device:emit_event(panicAlarm.panicAlarm.panic({state_change = true}))
    else
      device:emit_event(panicAlarm.panicAlarm.clear({state_change = true}))
    end
  end
end

local function configure_ias_zone_settings(driver, device)
  device:send(cluster_base.write_manufacturer_specific_attribute(device, IASZone.ID, 0x8002, DEVELCO_MANUFACTURER_CODE, data_types.Uint16, 2000):to_endpoint(0x23))
  device:send(cluster_base.write_manufacturer_specific_attribute(device, IASZone.ID, 0x8003, DEVELCO_MANUFACTURER_CODE, data_types.Uint16, 2000):to_endpoint(0x23))
  device:send(cluster_base.write_manufacturer_specific_attribute(device, IASZone.ID, 0x8004, DEVELCO_MANUFACTURER_CODE, data_types.Uint16, 10):to_endpoint(0x23))
  device:send(cluster_base.write_manufacturer_specific_attribute(device, IASZone.ID, 0x8005, DEVELCO_MANUFACTURER_CODE, data_types.Enum8,  0):to_endpoint(0x23))
end

local function present_value_attr_handler(driver, device, value, zb_rx)
  if value.value == true then
    device:emit_event(capabilities.button.button.pushed({state_change = true}))
  end
end

local function ias_zone_status_attr_handler(driver, device, zone_status, zb_rx)
  generate_event_from_zone_status(driver, device, zone_status, zb_rx)
end

local function ias_zone_status_change_handler(driver, device, zb_rx)
  local zone_status = zb_rx.body.zcl_body.zone_status
  generate_event_from_zone_status(driver, device, zone_status, zb_rx)
end

local function init_handler(self, device)
  for _,attribute in ipairs(CONFIGURATIONS) do
    device:add_configured_attribute(attribute)
  end
  battery_defaults.enable_battery_voltage_table(device, battery_table)
end

local function added_handler(self, device)
  device:emit_event(capabilities.button.supportedButtonValues({"pushed"}, {visibility = { displayed = false }}))
  device:emit_event(capabilities.button.numberOfButtons({value = 1}))
  button_utils.emit_event_if_latest_state_missing(device, "main", capabilities.button, capabilities.button.button.NAME, capabilities.button.button.pushed({state_change = false}))
end

local function do_configure(driver, device, event, args)
  device:configure()
  device:send(cluster_base.write_manufacturer_specific_attribute(device, OnOff.ID, BUTTON_LED_COLOR, DEVELCO_MANUFACTURER_CODE, data_types.Enum8, 2):to_endpoint(0x20))
  device:send(cluster_base.write_manufacturer_specific_attribute(device, OnOff.ID, BUTTON_PRESS_DELAY, DEVELCO_MANUFACTURER_CODE, data_types.Uint16, 100):to_endpoint(0x20))
  device:send(cluster_base.write_manufacturer_specific_attribute(device, BasicInput.ID, PANIC_BUTTON, DEVELCO_MANUFACTURER_CODE, data_types.Uint16, 0xFFFF):to_endpoint(0x20))
end

local function info_changed(driver, device, event, args)
  for name, info in pairs(PREFERENCE_TABLES) do
    if (device.preferences[name] ~= nil and args.old_st_store.preferences[name] ~= device.preferences[name]) then
      local input = device.preferences[name]
      local payload = tonumber(input)

      if (name == "panicButton") then
        if (input == "0x002C")then
          device:try_update_metadata({profile = "button-profile-panic-frient"})
          device.thread:call_with_delay(5, function()
            device:emit_event(panicAlarm.panicAlarm.clear({state_change = true}))
            configure_ias_zone_settings(driver,device)
          end)
        else
          device:try_update_metadata({profile = "button-profile-frient"})
        end
      end

      if (payload ~= nil) then
        local message = cluster_base.write_manufacturer_specific_attribute(
          device,
          info.clusterId,
          info.attributeId,
          info.mfg_code,
          info.dataType,
          payload
        )
        message.address_header.dest_endpoint.value = info.endpoint
        message.body.zcl_header.frame_ctrl.value  =  info.frame_ctrl
        device:send(message)
      end
    end
  end
end

local frient_button = {
  NAME = "Frient Button Handler",
  lifecycle_handlers = {
    added = added_handler,
    doConfigure = do_configure,
    init = init_handler,
    infoChanged = info_changed
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
      [BasicInput.ID] = {
        [BasicInput.attributes.PresentValue.ID] = present_value_attr_handler
      }
    }
  },
  can_handle = require("frient.can_handle"),
}
return frient_button
