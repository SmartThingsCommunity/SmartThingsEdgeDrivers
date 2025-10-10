return function(opts, driver, device)
    local GE_LINK_BULB_FINGERPRINTS = {
  ["GE_Appliances"] = {
    ["ZLL Light"] = true,
  },
  ["GE"] = {
    ["Daylight"] = true,
    ["SoftWhite"] = true
  }
}

  local can_handle = (GE_LINK_BULB_FINGERPRINTS[device:get_manufacturer()] or {})[device:get_model()]
  if can_handle then
    local subdriver = require("ge-link-bulb")
    return true, subdriver
  else
    return false
  end
end
