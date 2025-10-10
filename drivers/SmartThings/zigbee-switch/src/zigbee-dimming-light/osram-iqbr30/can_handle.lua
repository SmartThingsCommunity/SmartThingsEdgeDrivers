return function(opts, driver, device, ...)
  local res = device:get_manufacturer() == "OSRAM SYLVANIA" and device:get_model() == "iQBR30"
  if res then
    return res, require("zigbee-dimming-light.osram-iqbr30")
  end
  return res
end
