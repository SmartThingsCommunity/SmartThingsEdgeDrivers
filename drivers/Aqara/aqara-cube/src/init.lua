local ZigbeeDriver = require "st.zigbee"
local capabilities = require "st.capabilities"
local data_types = require "st.zigbee.data_types"
local cluster_base = require "st.zigbee.cluster_base"
local battery_defaults = require "st.zigbee.defaults.battery_defaults"
local clusters = require "st.zigbee.zcl.clusters"
local PowerConfiguration = clusters.PowerConfiguration

local PRI_CLU = 0xFCC0
local PRI_ATTR = 0x0009
local MFG_CODE = 0x115F

local ROTATE_CLU = 0x000C
local EVENT_CLU = 0x0012
local FACE_ATTR = 0x0149
local ACTION_ATTR = 0x0055
local CUBE_MODE = 0x0148

local cubeAction = capabilities["stse.cubeAction"]
local cubeFace = capabilities["stse.cubeFace"]
local cubeFaceVal = { "face1Up", "face2Up", "face3Up", "face4Up", "face5Up", "face6Up" }
local cubeFlipToSideVal = { "flipToSide1", "flipToSide2", "flipToSide3", "flipToSide4", "flipToSide5", "flipToSide6" }

local CUBEACTION_TIMER = "cubeAction_timer"
local CUBEACTION_TIME = 3

local callback_timer = function(device)
  return function()
    device:emit_event(cubeAction.cubeAction("noAction"))
  end
end

local function reset_thread(device)
  local timer = device:get_field(CUBEACTION_TIMER)
  if timer then
    device.thread:cancel_timer(timer)
    device:set_field(CUBEACTION_TIMER, nil)
  end
  device:set_field(CUBEACTION_TIMER, device.thread:call_with_delay(CUBEACTION_TIME, callback_timer(device)))
end

local function data_handler(driver, device, value, zb_rx)
  local val = value.value
  if val == 0x0000 then -- Shake
    reset_thread(device)
    device:emit_event(cubeAction.cubeAction("shake"))
  elseif val == 0x0004 then -- hold
    reset_thread(device)
    device:emit_event(cubeAction.cubeAction("pickUpAndHold"))
  elseif val & 0x0400 == 0x0400 then -- Flip to side
    local faceNum = val & 0x0007
    reset_thread(device)
    device:emit_event(cubeAction.cubeAction(cubeFlipToSideVal[faceNum + 0x1]))
  end
end

local function rotate_handler(driver, device, value, zb_rx)
  -- Rotation
  reset_thread(device)
  device:emit_event(cubeAction.cubeAction("rotate"))
end

local function face_handler(driver, device, value, zb_rx)
  local faceNum = value.value
  device:emit_event(cubeFace.cubeFace(cubeFaceVal[faceNum + 1]))
end

local function do_refresh(driver, device)
  -- refresh
  device:send(PowerConfiguration.attributes.BatteryVoltage:read(device))
end

local function device_init(driver, device)
  local power_configuration = {
    cluster = PowerConfiguration.ID,
    attribute = PowerConfiguration.attributes.BatteryVoltage.ID,
    minimum_interval = 30,
    maximum_interval = 3600,
    data_type = PowerConfiguration.attributes.BatteryVoltage.base_type,
    reportable_change = 1
  }

  battery_defaults.build_linear_voltage_init(2.6, 3.0)(driver, device)

  device:add_configured_attribute(power_configuration)
  device:add_monitored_attribute(power_configuration)
end

local function device_added(self, device)
  -- Set private attribute
  device:send(cluster_base.write_manufacturer_specific_attribute(device,
    PRI_CLU, PRI_ATTR, MFG_CODE, data_types.Uint8, 1))

  device:send(cluster_base.write_manufacturer_specific_attribute(device,
    PRI_CLU, CUBE_MODE, MFG_CODE, data_types.Uint8, 1))
  device:emit_event(cubeAction.cubeAction("noAction"))
  device:emit_event(cubeFace.cubeFace("face1Up"))
  do_refresh(self, device)
end

-- [[ register ]]
local aqara_cube_t1_pro_handler = {
  NAME = "Aqara Cube T1 Pro",
  capability_handlers = {
    [capabilities.refresh.ID] = {
      [capabilities.refresh.commands.refresh.NAME] = do_refresh
    }
  },
  zigbee_handlers = {
    attr = {
      [EVENT_CLU] = {
        [ACTION_ATTR] = data_handler
      },
      [ROTATE_CLU] = {
        [ACTION_ATTR] = rotate_handler,
      },
      [PRI_CLU] = {
        [FACE_ATTR] = face_handler
      },
      [PowerConfiguration.ID] = {
        [PowerConfiguration.attributes.BatteryVoltage.ID] = battery_defaults.battery_volt_attr_handler
      }
    }
  },
  lifecycle_handlers = {
    init = device_init,
    added = device_added
  }
}

local aqara_cube_t1_pro_driver = ZigbeeDriver("aqara_cube_t1_pro", aqara_cube_t1_pro_handler)
aqara_cube_t1_pro_driver:run()

