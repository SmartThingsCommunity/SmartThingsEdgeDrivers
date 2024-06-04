-- require st provided libraries
local capabilities = require "st.capabilities"
local clusters = require "st.zigbee.zcl.clusters"
local window_preset_defaults = require "st.zigbee.defaults.windowShadePreset_defaults"
local device_management = require "st.zigbee.device_management"
local cluster_base = require "st.zigbee.cluster_base"
local data_types = require "st.zigbee.data_types"
local utils = require "st.utils"

local Basic = clusters.Basic
local WindowCovering = clusters.WindowCovering
local PowerConfiguration = clusters.PowerConfiguration
local ShadeConfiguration = clusters.ShadeConfiguration

-- manufacturer specific cluster details
local MFG_CODE = 0x1228
local CUS_CLU = 0xFCCC
local RUN_DIR_ATTR = 0x0012


local motor_states = {
  IDLE = 0,
  OPENING = 1,
  CLOSING = 2
}
local running_direction = motor_states.IDLE

-----------------------------------------------------------------
-- local functions
-----------------------------------------------------------------

-- this is update_device_info
local function update_device_info (device)
  device:send(WindowCovering.attributes.CurrentPositionLiftPercentage:read(device))
  device:send(PowerConfiguration.attributes.BatteryPercentageRemaining:read(device))
  device:send(Basic.attributes.PowerSource:read(device))
end

-- this is window_shade_level_cmd
local function window_shade_level_cmd(driver, device, command)
  local go_to_level = command.args.shadeLevel
  -- send levels without inverting as: 0% closed (i.e., open) to 100% closed (Bug #16054)
  device:send_to_component(command.component, WindowCovering.server.commands.GoToLiftPercentage(device, go_to_level))
end

-- this is window_shade_preset_cmd
local function window_shade_preset_cmd(driver, device, command)
  local go_to_level = device.preferences.presetPosition or device:get_field(window_preset_defaults.PRESET_LEVEL_KEY) or window_preset_defaults.PRESET_LEVEL
  -- send levels without inverting as: 0% closed (i.e., open) to 100% closed (Bug #16054)
  device:send_to_component(command.component, WindowCovering.server.commands.GoToLiftPercentage(device, go_to_level))
end

-- this is device_added
local function device_added(driver, device)
  device:emit_event(capabilities.windowShade.supportedWindowShadeCommands({ "open", "close", "pause" }, {visibility = {displayed = false}}))
  device.thread:call_with_delay(3, function(d)
    update_device_info(device)
  end)
end

-- this is current_position_attr_handler
local function current_position_attr_handler(driver, device, value, zb_rx)
  local level = value.value --Bug #16054
  local event = nil

  -- when the device is in action
  if running_direction == motor_states.OPENING then
    event = capabilities.windowShade.windowShade.opening()
  end

  if running_direction == motor_states.CLOSING then
    event = capabilities.windowShade.windowShade.closing()
  end

  -- when the device is in idle
  if running_direction == motor_states.IDLE then
    if level == 0 then
      event = capabilities.windowShade.windowShade.open() --Bug #16054 
    elseif level == 100 then
      event = capabilities.windowShade.windowShade.closed() --Bug #16054
    else
      event = capabilities.windowShade.windowShade.partially_open()
    end  
  end

  -- update status
  if event ~= nil then
    device:emit_event(event)
  end

  -- update level
  device:emit_event(capabilities.windowShadeLevel.shadeLevel(level))
end

-- this is motor running_direction_attr_handler
local function running_direction_attr_handler(driver, device, value, zb_rx)
  local status = value.value
  if status == 1 then
    running_direction = motor_states.OPENING
  elseif status == 2 then 
    running_direction = motor_states.CLOSING
  else
    running_direction = motor_states.IDLE
  end
end

-- this is do_configure
local function do_configure(self, device)
  -- configure elements
  device:configure()
  device:send(device_management.build_bind_request(device, WindowCovering.ID, self.environment_info.hub_zigbee_eui))
  device:send(WindowCovering.attributes.CurrentPositionLiftPercentage:configure_reporting(device, 1, 3600, 1))
  device:send(device_management.build_bind_request(device, PowerConfiguration.ID, self.environment_info.hub_zigbee_eui))
  device:send(PowerConfiguration.attributes.BatteryPercentageRemaining:configure_reporting(device, 1, 3600, 1))
  device:send(device_management.build_bind_request(device, Basic.ID, self.environment_info.hub_zigbee_eui))
  device:send(Basic.attributes.PowerSource:configure_reporting(device, 1, 3600))

  -- read elements
  device.thread:call_with_delay(3, function(d)
    device:send(Basic.attributes.ApplicationVersion:read(device))
    update_device_info(device)
  end)
end

-- this is do_refresh
local do_refresh = function(self, device)
  update_device_info(device)
end

-- this is battery_perc_attr_handler
local function battery_perc_attr_handler(driver, device, value, zb_rx)
  local converted_value = value.value / 2
  converted_value = utils.round(converted_value)
  -- update battery percentage only motor is in idle state --Bug #16055
  if running_direction == motor_states.IDLE then
    device:emit_event_for_endpoint(zb_rx.address_header.src_endpoint.value, 
      capabilities.battery.battery(utils.clamp_value(converted_value, 0, 100)))
  end
end

-- create the handler object
local screeninnovations_roller_shade_handler = {
  NAME = "screeninnovations_roller_shade_handler",
  lifecycle_handlers = {
    added = device_added,
    doConfigure = do_configure
  },
  capability_handlers = {
    [capabilities.windowShadeLevel.ID] = {
      [capabilities.windowShadeLevel.commands.setShadeLevel.NAME] = window_shade_level_cmd
    },
    [capabilities.windowShadePreset.ID] = {
      [capabilities.windowShadePreset.commands.presetPosition.NAME] = window_shade_preset_cmd
    },
    [capabilities.refresh.ID] = {
      [capabilities.refresh.commands.refresh.NAME] = do_refresh,
    }
  },
  zigbee_handlers = {
    attr = {
      [WindowCovering.ID] = {
        [WindowCovering.attributes.CurrentPositionLiftPercentage.ID] = current_position_attr_handler,
      },
      [PowerConfiguration.ID] = {
        [PowerConfiguration.attributes.BatteryPercentageRemaining.ID] = battery_perc_attr_handler,
      },
      [CUS_CLU] = {
        [RUN_DIR_ATTR] = running_direction_attr_handler,
      }
    }
  },
  can_handle = function(opts, driver, device, ...)
    return device:get_model() == "WM25/L-Z"
  end
}

-- return the handler
return screeninnovations_roller_shade_handler
