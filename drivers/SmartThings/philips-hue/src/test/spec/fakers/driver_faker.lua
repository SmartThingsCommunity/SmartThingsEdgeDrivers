local fake_driver_mt = {}
fake_driver_mt.__index = fake_driver_mt

function fake_driver_mt:get_device_info(device_id)
  return self.devices[device_id]
end

local function driver_faker(faker_args)
  faker_args = faker_args or {}
  faker_args.bridges = faker_args.bridges or {}
  faker_args.child_devices = faker_args.child_devices or {}

  local fake_driver = { devices = {} }
  fake_driver.datastore = faker_args.datastore or {}
  fake_driver.datastore.bridge_netinfo = fake_driver.datastore.bridge_netinfo or {}
  fake_driver.datastore.dni_to_device_id = fake_driver.datastore.dni_to_device_id or {}
  fake_driver.datastore.api_keys = fake_driver.datastore.api_keys or {}

  fake_driver._bridges = {}
  fake_driver._child_devices = {}

  for _, bridge_details in ipairs(faker_args.bridges) do
    local device = bridge_details.device
    local bridge_netinfo = bridge_details.info
    local api_key = bridge_details.key

    fake_driver.devices[device.id] = device

    if bridge_details.add_info_to_datastore == true then
      fake_driver.datastore.bridge_netinfo[device.device_network_id] = bridge_netinfo
    end

    if bridge_details.map_dni_to_device then
      fake_driver.datastore.dni_to_device_id[device.device_network_id] = device.id
    end

    if bridge_details.add_key_to_datastore then
      fake_driver.datastore.api_keys[device.device_network_id] = api_key
    end

    fake_driver._bridges[bridge_netinfo] = device
  end

  for _, child_details in ipairs(faker_args.child_devices) do
    local device = child_details.device
    local parent_bridge = fake_driver._bridges[child_details.parent_bridge_info]

    device.parent_device_id = parent_bridge.id
    fake_driver.devices[device.id] = device
  end

  return setmetatable(fake_driver, fake_driver_mt)
end

return driver_faker
