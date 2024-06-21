-- Copyright 2024 Inovelli
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

local clusters = require "st.zigbee.zcl.clusters"
local capabilities = require "st.capabilities"
local FanControl = clusters.FanControl
local Level = clusters.Level
local OnOff = clusters.OnOff
local log = require "log"
local LATEST_CLOCK_SET_TIMESTAMP = "latest_clock_set_timestamp"
local cluster_base = require "st.zigbee.cluster_base"
local device_management = require "st.zigbee.device_management"
local data_types = require "st.zigbee.data_types"
local st_device = require "st.device"

local INOVELLI_VZM35_SN_FINGERPRINTS = {
    { mfr = "Inovelli", model = "VZM35-SN" },
    { mfr = "Inovelli", model = "VZM35-SN-MG24" }
}

local is_inovelli_vzm35_sn = function(opts, driver, device)
  for _, fingerprint in ipairs(INOVELLI_VZM35_SN_FINGERPRINTS) do
    if device:get_manufacturer() == fingerprint.mfr and device:get_model() == fingerprint.model then
      return true
    end
  end
  return false
end

local levels_for_4_speed = {
  [0] = 0,
  [1] = 25,
  [2] = 50,
  [3] = 75,
  [4] = 100,
  [5] = 1,
}

local function level_to_speed(level)
  local speed = 4
  if level == 0 then
    speed = 0
  elseif level == 1 then
    speed = 5
  else
    for spd=4,1,-1 do
      if level <= levels_for_4_speed[spd] then
        speed = spd
      end
    end
  end
  return speed
end

local fan_speed_helper  = {
  --capability_handlers = capability_handlers,
  fan_speed = {
    OFF = 0,
    LOW = 1,
    MEDIUM = 2,
    HIGH = 3,
    MAX = 4
  },
  levels_for_3_speed = {
    OFF = 0,
    LOW = 33, -- 3-Speed Fan Controller treat 33 as medium
    MEDIUM = 66,
    HIGH = 100,
    MAX = 100,
  },
  levels_for_4_speed = {
    OFF = 0,
    LOW = 25,
    MEDIUM = 50,
    HIGH = 75,
    MAX = 100,
  }
}

local function map_fan_3_speed_to_switch_level (speed)
    log.info(fan_speed_helper.fan_speed.OFF)
    if speed == fan_speed_helper.fan_speed.OFF then
      return fan_speed_helper.levels_for_3_speed.OFF -- off
    elseif speed == fan_speed_helper.fan_speed.LOW then
      return fan_speed_helper.levels_for_3_speed.LOW -- low
    elseif speed == fan_speed_helper.fan_speed.MEDIUM then
      return fan_speed_helper.levels_for_3_speed.MEDIUM -- medium
    elseif speed == fan_speed_helper.fan_speed.HIGH or speed == fan_speed_helper.fan_speed.MAX then
      return fan_speed_helper.levels_for_3_speed.HIGH -- high and max
    else
      log.error (string.format("3 speed fan driver: invalid speed: %d", speed))
    end
  end
  
  local function map_switch_level_to_fan_3_speed (level)
    if (level == fan_speed_helper.levels_for_3_speed.OFF) then
      return fan_speed_helper.fan_speed.OFF
    elseif (fan_speed_helper.levels_for_3_speed.OFF < level and level <= fan_speed_helper.levels_for_3_speed.LOW) then
      return fan_speed_helper.fan_speed.LOW
    elseif (fan_speed_helper.levels_for_3_speed.LOW < level and level <= fan_speed_helper.levels_for_3_speed.MEDIUM) then
      return fan_speed_helper.fan_speed.MEDIUM
    elseif (fan_speed_helper.levels_for_3_speed.MEDIUM < level and level <= fan_speed_helper.levels_for_3_speed.MAX) then
      return fan_speed_helper.fan_speed.HIGH
    else
      log.error (string.format("3 speed fan driver: invalid level: %d", level))
    end
  end

-- CAPABILITY HANDLERS

--local function on_handler(driver, device, command)
--    device:send(OnOff.server.commands.On(device))
--end

--local function off_handler(driver, device, command)
--    device:send(OnOff.server.commands.Off(device))
--end

--local function switch_level_handler(driver, device, command)

--  local level = math.floor(command.args.level/100.0 * 254)

--  if(level == 0) then
--    device:send(OnOff.server.commands.Off(device))
--  else
--    device:send(Level.server.commands.MoveToLevelWithOnOff(device, level, command.args.rate or 0xFFFF))
--  end
--end

local function fan_speed_handler(driver, device, command)
  if command.args.speed == 5 then command.args.speed = 6 end

  local level = math.floor(map_fan_3_speed_to_switch_level(command.args.speed)/100.0 * 254)

  if(level == 0) then
    device:send(OnOff.server.commands.Off(device))
  else
    device:send(Level.server.commands.MoveToLevelWithOnOff(device, level, command.args.rate or 0xFFFF))
  end
end

-- ZIGBEE HANDLERS

local function zb_fan_control_handler(driver, device, value, zb_rx)
  if value.value == 6 then value.value = 5 end
  if levels_for_4_speed[value.value] then
    device:emit_event(capabilities.fanSpeed.fanSpeed(value.value))
  end
  local evt = capabilities.switch.switch(value.value > 0 and 'on' or 'off', { visibility = { displayed = false } })
  device:emit_component_event(device.profile.components.main,evt)
  device:emit_component_event(device.profile.components.main,capabilities.switchLevel.level(levels_for_4_speed[value.value], { visibility = { displayed = false } }))
end

local function zb_level_handler(driver, device, value, zb_rx)
  local fan_speed = map_switch_level_to_fan_3_speed(math.floor((value.value / 254.0 * 100) + 0.5))

  if (value.value > 0) then
    device:set_field('LAST_FAN_SPD', fan_speed, {persist = true})
    device:set_field('LAST_FAN_LVL', value.value, {persist = true})
  end

  local query_configuration = function()
    if device:get_latest_state("main", capabilities.switch.ID, capabilities.switch.switch.NAME) == "off" then
      device:emit_event(capabilities.fanSpeed.fanSpeed(0))
    else
      device:emit_event(capabilities.fanSpeed.fanSpeed(fan_speed))
      device:emit_event(capabilities.switchLevel.level(math.floor((value.value / 254.0 * 100) + 0.5)))
    end
  end
  device.thread:call_with_delay(1, query_configuration)
end

local function zb_onoff_handler(driver, device, value, zb_rx)
  device:emit_event(capabilities.switch.switch(value.value and 'on' or 'off'))
  
  local last_speed = device:get_field('LAST_FAN_SPD') or 1
  local last_level = device:get_field('LAST_FAN_LVL') or 1

  if (value.value) then
    device:emit_event(capabilities.fanSpeed.fanSpeed(last_speed))
    device:emit_event(capabilities.switchLevel.level(math.floor((last_level / 254.0 * 100) + 0.5)))

  else
    device:emit_event(capabilities.fanSpeed.fanSpeed(0))
    device:emit_event(capabilities.switchLevel.level(0))
  end
end

local function initialize(device, driver)
    log.info("inovelli-vzm35-sn - initialize")
    if device:get_latest_state("main", capabilities.switchLevel.ID, capabilities.switchLevel.level.NAME) == nil and device:supports_capability(capabilities.switchLevel)then
      log.info("No Switch Level event received. Initializing value")
      device:emit_event(capabilities.switchLevel.level(0))
    end
    if device:get_latest_state("main", capabilities.fanSpeed.ID, capabilities.fanSpeed.fanSpeed.NAME) == nil and device:supports_capability(capabilities.fanSpeed) then
      log.info("No fan event received. Initializing value")
      device:emit_event(capabilities.fanSpeed.fanSpeed(0))
    end

    for _, component in pairs(device.profile.components) do
      for _, capability in pairs(component.capabilities) do
        --log.info(capability.id)
      end
      if string.find(component.id, "button") ~= nil then
        if device:get_latest_state(component.id, capabilities.button.ID, capabilities.button.supportedButtonValues.NAME) == nil then
          device:emit_component_event(
            component,
            capabilities.button.supportedButtonValues(
              {"pushed","held","down_hold","pushed_2x","pushed_3x","pushed_4x","pushed_5x"},
              { visibility = { displayed = false } }
            )
          )
        end
        if device:get_latest_state(component.id, capabilities.button.ID, capabilities.button.numberOfButtons.NAME) == nil then
          device:emit_component_event(
            component,
            capabilities.button.numberOfButtons({value = 1}, { visibility = { displayed = false } })
          )
        end
      end
    end
    device:send(cluster_base.read_attribute(device, data_types.ClusterId(0x0000), 0x4000))
end

local device_init = function(self, device)
  log.info("inovelli-vzm35-sn - device_init")
  if device.network_type ~= st_device.NETWORK_TYPE_CHILD then
  device:set_field(LATEST_CLOCK_SET_TIMESTAMP, os.time())
  initialize(device, self)
  end
end

local do_configure = function(self, device)
  log.info("inovelli-vzm35-sn - do_configure")
  if device.network_type ~= st_device.NETWORK_TYPE_CHILD then
    device:refresh()
    device:configure()

    device:send(device_management.build_bind_request(device, 0xFC31, self.environment_info.hub_zigbee_eui, 2)) -- Bind device for button presses. 

    -- Retrieve Neutral Setting "Parameter 21"
    device:send(cluster_base.read_manufacturer_specific_attribute(device, 0xFC31, 21, 0x122F))
    device:send(cluster_base.read_attribute(device, data_types.ClusterId(0x0000), 0x4000))
  end
end

local inovelli_vzm35_sn = {
  NAME = "inovelli vzm35-sn handler",
  lifecycle_handlers = {
    init = device_init,
    doConfigure = do_configure
  },
  zigbee_handlers = {
    attr = {
      [FanControl.ID] = {
        [FanControl.attributes.FanMode.ID] = zb_fan_control_handler
      },
      [Level.ID] = {
        [Level.attributes.CurrentLevel.ID] = zb_level_handler
      },
      [OnOff.ID] = {
        [OnOff.attributes.OnOff.ID] = zb_onoff_handler
      }
    }
  },
  capability_handlers = {
--    [capabilities.switch.ID] = {
--      [capabilities.switch.commands.on.NAME] = on_handler,
--      [capabilities.switch.commands.off.NAME] = off_handler,
--    },
--    [capabilities.switchLevel.ID] = {
--      [capabilities.switchLevel.commands.setLevel.NAME] = switch_level_handler
--    },
    [capabilities.fanSpeed.ID] = {
      [capabilities.fanSpeed.commands.setFanSpeed.NAME] = fan_speed_handler
    }
  },
  can_handle = is_inovelli_vzm35_sn
}

return inovelli_vzm35_sn