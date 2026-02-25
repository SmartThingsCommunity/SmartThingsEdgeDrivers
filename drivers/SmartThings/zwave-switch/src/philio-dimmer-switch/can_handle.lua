-- can_handle.lua
-- 判斷是否為 Philio PAD19 裝置

local subdriver = require("philio-dimmer-switch")

local function can_handle_pad19(opts, driver, device, ...)
  local fingerprint_list = {
    {mfr = 0x013C, prod_type = 0x0005, prod_id = 0x008A}, -- Philio PAD19
  }

  for _, fingerprint in ipairs(fingerprint_list) do
    if device:id_match(fingerprint.mfr, fingerprint.prod_type, fingerprint.prod_id) then
      return true, subdriver
    end
  end

  return false
end

return can_handle_pad19
