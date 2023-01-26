local capabilities = require "st.capabilities"
local clusters = require "st.zigbee.zcl.clusters"

local OnOff = clusters.OnOff
local Basic = clusters.Basic
local AnalogInput = clusters.AnalogInput

local ENDPOINT_POWER_METER = 0x15
local ENDPOINT_ENERGY_METER = 0x1F

local APPLICATION_VERSION = "application_version"

local function is_aqara_version(opts, driver, device)
  local softwareVersion = device:get_field(APPLICATION_VERSION)
  return softwareVersion and softwareVersion == 32
end

local function on_off_handler(driver, device, value, zb_rx)
  if value.value == true then
    device:emit_event(capabilities.switch.switch.on())
    device:send(AnalogInput.attributes.PresentValue:read(device):to_endpoint(ENDPOINT_POWER_METER))
    device:send(AnalogInput.attributes.PresentValue:read(device):to_endpoint(ENDPOINT_ENERGY_METER))
  else
    device:emit_event(capabilities.switch.switch.off())
  end
end

local function do_refresh(self, device)
  device:send(OnOff.attributes.OnOff:read(device))
  device:send(AnalogInput.attributes.PresentValue:read(device):to_endpoint(ENDPOINT_POWER_METER))
  device:send(AnalogInput.attributes.PresentValue:read(device):to_endpoint(ENDPOINT_ENERGY_METER))
end

local function do_configure(self, device)
  device:configure()
  device:send(Basic.attributes.ApplicationVersion:read(device))
  do_refresh(self, device)
end

local aqara_smart_plug_version_handler = {
  NAME = "Aqara Smart Plug Version Handler",
  lifecycle_handlers = {
    doConfigure = do_configure,
  },
  capability_handlers = {
    [capabilities.refresh.ID] = {
      [capabilities.refresh.commands.refresh.NAME] = do_refresh,
    }
  },
  zigbee_handlers = {
    attr = {
      [OnOff.ID] = {
        [OnOff.attributes.OnOff.ID] = on_off_handler
      }
    }
  },
  can_handle = is_aqara_version,
}

return aqara_smart_plug_version_handler
