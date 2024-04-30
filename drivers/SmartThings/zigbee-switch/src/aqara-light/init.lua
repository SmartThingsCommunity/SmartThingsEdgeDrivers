local clusters = require "st.zigbee.zcl.clusters"
local cluster_base = require "st.zigbee.cluster_base"
local data_types = require "st.zigbee.data_types"
local capabilities = require "st.capabilities"

local OnOff = clusters.OnOff
local Level = clusters.Level
local ColorControl = clusters.ColorControl

local PRIVATE_CLUSTER_ID = 0xFCC0
local PRIVATE_ATTRIBUTE_ID = 0x0009
local MFG_CODE = 0x115F

local FINGERPRINTS = {
  { mfr = "LUMI", model = "lumi.light.acn004" },
  { mfr = "Aqara", model = "lumi.light.acn014" }
}

local function is_aqara_products(opts, driver, device)
  for _, fingerprint in ipairs(FINGERPRINTS) do
    if device:get_manufacturer() == fingerprint.mfr and device:get_model() == fingerprint.model then
      local subdriver = require("aqara-light")
      return true, subdriver
    end
  end
  return false
end

local function do_refresh(self, device)
  device:send(OnOff.attributes.OnOff:read(device))
  device:send(Level.attributes.CurrentLevel:read(device))
  device:send(ColorControl.attributes.ColorTemperatureMireds:read(device))
end

local function do_configure(self, device)
  device:configure()
  device:send(cluster_base.write_manufacturer_specific_attribute(device,
    PRIVATE_CLUSTER_ID, PRIVATE_ATTRIBUTE_ID, MFG_CODE, data_types.Uint8, 1)) -- private

  device:send(Level.attributes.OnTransitionTime:write(device, 0))
  device:send(Level.attributes.OffTransitionTime:write(device, 0))
  device:send(ColorControl.commands.MoveToColorTemperature(device, 200, 0x0000))

  do_refresh(self, device)
end

local function set_level_handler(driver, device, cmd)
  local level = math.floor(cmd.args.level / 100.0 * 254)
  local dimming_rate = 0x0000

  device:send(Level.commands.MoveToLevelWithOnOff(device, level, dimming_rate))
end

local aqara_light_handler = {
  NAME = "Aqara Light Handler",
  lifecycle_handlers = {
    doConfigure = do_configure
  },
  capability_handlers = {
    [capabilities.switchLevel.ID] = {
      [capabilities.switchLevel.commands.setLevel.NAME] = set_level_handler
        }
  },
  can_handle = is_aqara_products
}

return aqara_light_handler
