local clusters = require "st.zigbee.zcl.clusters"
local capabilities = require "st.capabilities"

local OnOff = clusters.OnOff

local FINGERPRINTS = {
  { mfr = "LUMI", model = "lumi.switch.b2laus01" },
  { mfr = "LUMI", model = "lumi.switch.b1laus01" },
  { mfr = "LUMI", model = "lumi.plug.maeu01" }
}

local is_aqara_products = function(opts, driver, device)
  for _, fingerprint in ipairs(FINGERPRINTS) do
      if device:get_manufacturer() == fingerprint.mfr and device:get_model() == fingerprint.model then
          return true
      end
  end
  return false
end

local function do_refresh(driver, device)
  local attributes = {
    OnOff.attributes.OnOff,
  }
  for _, attribute in pairs(attributes) do
    local count = 0
    for _ in pairs(device.profile.components) do
      count = count + 1
    end

    if count > 1 then
      device:send(attribute:read(device):to_endpoint(0x01))
      device:send(attribute:read(device):to_endpoint(0x02))
    else
      device:send(attribute:read(device))
    end
  end
end

local function do_configure(self, device)
  device:configure()

  do_refresh(self, device)
end

local function on_switch_handler(driver, device, command)
  device:send_to_component(command.component, OnOff.server.commands.On(device))
end

local function off_switch_handler(driver, device, command)
  device:send_to_component(command.component, OnOff.server.commands.Off(device))
end

local aqara_switch_handler = {
  NAME = "Aqara Switch Handler",
  lifecycle_handlers = {
    doConfigure = do_configure
  },
  capability_handlers = {
    [capabilities.switch.ID] = {
      [capabilities.switch.commands.on.NAME] = on_switch_handler,
      [capabilities.switch.commands.off.NAME] = off_switch_handler
    },
    [capabilities.refresh.ID] = {
      [capabilities.refresh.commands.refresh.NAME] = do_refresh,
    }
  },
  can_handle = is_aqara_products
}

return aqara_switch_handler
