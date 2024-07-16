local net_helpers = require "test.helpers.net"

local function make_edge_device(_faker_args, bridge_info)
  return {
    device_network_id = bridge_info.mac or net_helpers.random_mac_address(),
    label = bridge_info.name or "Philips Hue Bridge",
    model = bridge_info.modelid or "BSB002"
  }
end

local function make_migrated_device(faker_args, bridge_info)
  local bridge = make_edge_device(faker_args, bridge_info)
  bridge.data = {
    ip = bridge_info.ip or net_helpers.random_private_ip_address(),
    mac = bridge.device_network_id,
    username = faker_args.bridge_key
  }

  return bridge
end

return function(faker_args, bridge_info)
  bridge_info = bridge_info or {}
  faker_args.name = faker_args.name or "Fake Hue Bridge"
  if faker_args.migrated == true then
    return make_migrated_device(faker_args, bridge_info)
  else
    return make_edge_device(faker_args, bridge_info)
  end
end
