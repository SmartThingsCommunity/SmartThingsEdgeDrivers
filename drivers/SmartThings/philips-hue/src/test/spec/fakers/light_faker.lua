local st_utils = require "st.utils"
-- trick to fix the VS Code Lua Language Server typechecking
---@type fun(val: any?, name: string?, multi_line: boolean?): string
st_utils.stringify_table = st_utils.stringify_table

local function make_migrated_device(faker_args, bridge_info)
  local device_network_id = faker_args.dni or st_utils.generate_uuid_v4()
  local v1_bulb_id = faker_args.v1_bulb_id or math.random(255)
  local pack = string.format("%s/%d", bridge_info.bridgeid, v1_bulb_id)
  return {
    parent_assigned_child_key = pack,
    device_network_id = device_network_id,
    data = {
      ip = bridge_info.ip,
      mac = bridge_info.mac,
      username = faker_args.bridge_key,
      bulbId = v1_bulb_id
    }
  }
end

local function make_edge_device(faker_args, bridge_info)
  local hue_id = faker_args.hue_id or st_utils.generate_uuid_v4()
  local device_network_id = faker_args.dni or st_utils.generate_uuid_v4()

  local parent_assigned_child_key
  if faker_args.uuid_only_parent_assigned_key == true then
    parent_assigned_child_key = hue_id
  else
    parent_assigned_child_key = string.format("light:%s", hue_id)
  end

  return {
    parent_assigned_child_key = parent_assigned_child_key,
    device_network_id = device_network_id
  }
end

return function(faker_args, bridge_info)
  faker_args.name = faker_args.name or "Fake Hue Bulb"
  if faker_args.migrated == true then
    return make_migrated_device(faker_args, bridge_info)
  else
    return make_edge_device(faker_args, bridge_info)
  end
end
