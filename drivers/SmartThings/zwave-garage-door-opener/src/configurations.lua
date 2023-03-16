local devices = {
    ECOLINK_GARAGE_DOOR_OPENER = {
      MATCHING_MATRIX = {
        mfrs = 0x014A,
        product_types = 0x0007,
        product_ids = 0x4731
      },
      CONFIGURATION = {
        -- Inititalizing to hard coded defaults until we ask unit what actual values
        {parameter_number = 1, size = 1, configuration_value = 5}, -- "Unattended close operation wait period in seconds." 5 <= 5 <=60
        {parameter_number = 2, size = 2, configuration_value = 2000}, -- Relay close time / Wireless Activation transmit time in milliseconds 100 <= 2000 <= 5000
        {parameter_number = 3, size = 1, configuration_value = 30}, -- "Seconds allowed for garage door to open until timeout." 5 <= 30 <= 60
        {parameter_number = 4, size = 1, configuration_value = 30}, -- "Seconds allowed for garage door to close until timeout." 5 <= 30 <= 60
        {parameter_number = 5, size = 1, configuration_value = 92}, -- "Accelerometer vibration detection sensitivity: 1 is least sensitive, 100 is most sensitive." 1 <= 92 <= 100 
        {parameter_number = 6, size = 1, configuration_value = 3}, -- "Number of attempts on top of the stack-level retries to try to reach the controller/hub with Z-Wave messages." 0 <= 3 <= 10 
      },
      ASSOCIATION = {
        {grouping_identifier = 1}
      }
    }
  }
  



local configurations = {}
  
configurations.get_device_configuration = function(zw_device)
  for _, device in pairs(devices) do
    if zw_device:id_match(
      device.MATCHING_MATRIX.mfrs,
      device.MATCHING_MATRIX.product_types,
      device.MATCHING_MATRIX.product_ids) then
      return device.CONFIGURATION
    end
  end
  return nil
end

return configurations
