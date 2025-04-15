local log = require "log"
local Fields = require "fields"

--- Room or zone with the children translated from their hue device id or light resource id to
--- their SmartThings represented device object. The grouped light resource id is also moved into
--- a separate field from the list of services for ease of use.
--- @class HueLightGroup:HueGroupInfo
--- @field public devices HueDevice[]
--- @field public grouped_light_rid string?

local grouped_utils = {}

grouped_utils.GROUP_TYPES = {room = true, zone = true}

--- Build up mapping of hue device id to SmartThings device record
---@param bridge_device HueBridgeDevice
---@return table
local function build_hue_id_to_device_map(bridge_device)
  local hue_id_to_device = {}
  local children = bridge_device:get_child_list()
  for _, device_record in ipairs(children) do
    local hue_device_id = device_record:get_field(Fields.HUE_DEVICE_ID)
    if hue_device_id ~= nil then
      hue_id_to_device[hue_device_id] = device_record
    end
  end
  return hue_id_to_device
end

--- Search services to find grouped_light service of a room/zone
---@param group HueGroupInfo
---@return string?
local function find_grouped_light_rid(group)
  local services = group.services or {}
  for _, service in ipairs(services) do
    if service.rtype == "grouped_light" then
      return service.rid
    end
  end
  return nil
end

--- Take the children services in the group and transform them to smartthings device records.
--- This will be helpful when determining if a command batch matches a group and avoids having to
--- deal with hue specific ids for multiple services.
---
--- If we don't have a device record for the child, then clear out the entire device map so
--- we don't interact with a device through groups that we don't have a record for.
---@param group HueGroupInfo|HueLightGroup
---@param hue_id_to_device table Mapping of hue ID to device record, for rooms.
---@param light_id_to_device table Mapping of light resource ID to device record, for zones.
---@return table
local function build_group_device_table(group, hue_id_to_device, light_id_to_device)
  local devices = {}
  local seen = {}
  for _, child in ipairs(group.children) do
    if child.rtype == "light" then
      local device = light_id_to_device[child.rid]
      if not device then
        return {}
      end
      if not seen[device] then
        seen[device] = true
        table.insert(devices, device)
      end
    elseif child.rtype == "device" then
      local device = hue_id_to_device[child.rid]
      if not device then
        return {}
      end
      if device:get_field(Fields.DEVICE_TYPE) == "light" and not seen[device] then
        seen[device] = true
        table.insert(devices, device)
      end
    end
  end
  return devices
end

---@param group HueGroupInfo
---@param hue_id_to_device table
---@param light_id_to_device table
---@return HueLightGroup
local function build_hue_light_group(group, hue_id_to_device, light_id_to_device)
  local light_group = group --[[@as HueLightGroup]]
  light_group.devices = {}

  local grouped_light_id = find_grouped_light_rid(group)
  -- If there is no way to control the lights then don't bother adding in the device records
  if grouped_light_id == nil then
    return light_group
  end
  light_group.grouped_light_rid = grouped_light_id
  light_group.devices = build_group_device_table(light_group, hue_id_to_device, light_id_to_device)

  return light_group
end

---@param group_kind string room or zone
---@param driver HueDriver
---@param hue_id_to_device table
---@param resp table?
---@param err any?
---@return HueLightGroup[]?
local function handle_group_scan_response(group_kind, driver, hue_id_to_device, resp, err)
  if err or not resp then
    log.error(string.format("Failed to scan for %s: %s", group_kind, err or "unknown error"))
    return nil
  end
  if resp.errors and #resp.errors > 0 then
    log.warn(string.format("Bridge replied with %d errors when scanning for %s",
      #resp.errors, group_kind))
    return nil
  end
  if not resp.data then
    log.warn(string.format("Bridge replied with no errors or data when scanning for %s",
      group_kind))
    return nil
  end

  log.info(string.format("Successfully got %d %s", #resp.data, group_kind))
  for _, group in ipairs(resp.data) do
    build_hue_light_group(group, hue_id_to_device, driver.hue_identifier_to_device_record)
    log.info(string.format("Found light group %s with %d device records", group.id, #group.devices))
  end

  return resp.data
end

--- @param driver HueDriver
--- @param bridge_device HueBridgeDevice
--- @param api PhilipsHueApi
--- @param hue_id_to_device table
function grouped_utils.scan_groups(driver, bridge_device, api, hue_id_to_device)
  local rooms, zones
  while not (rooms and zones) do -- TODO: Should this be one and done? Timeout?
    if not rooms then
      rooms = handle_group_scan_response("rooms", driver, hue_id_to_device, api:get_rooms())
    end
    if not zones then
      zones = handle_group_scan_response("zones", driver, hue_id_to_device, api:get_zones())
    end
  end
  -- Combine rooms and zones.
  for _, zone in ipairs(zones) do
    table.insert(rooms, zone)
  end
  -- Sort from most devices to least for efficiency when checking batched commands.
  table.sort(rooms, function (a, b) return #a.devices > #b.devices end)
  bridge_device:set_field(Fields.GROUPS, rooms)
end

--- Find group in known groups and return the index and group.
---@param groups HueLightGroup[]
---@param id string
---@param type string
---@return integer?, HueLightGroup?
local function find(groups, id, type)
  for i, group in ipairs(groups) do
    if group.id == id and group.type == type then
      return i, group
    end
  end
  return nil, nil
end

--- Insert a group into the list of groups in correct index based off device count.
--- @param groups HueLightGroup[]
--- @param to_insert HueLightGroup
local function insert(groups, to_insert)
  -- 1 if no other entries
  -- last element if smallest group according to loop below
  local index = #groups + 1

  for i, group in ipairs(groups) do
    if #group.devices <= #to_insert.devices then
        -- if this is bigger or equal to the current index then insert here
        index = i
        break
    end
  end
  table.insert(groups, index, to_insert)
end

--- Handle room or zone update from SSE stream.
---@param driver HueDriver
---@param bridge_device HueBridgeDevice
---@param to_update table
function grouped_utils.group_update(driver, bridge_device, to_update)
  local groups = bridge_device:get_field(Fields.GROUPS)
  if groups == nil then
    log.warn("Received group update before groups on bridge were initialized. Not handling.")
    return
  end

  local index, group = find(groups, to_update.id, to_update.type)
  if not index or not group then
    log.warn("Received update for group with no record. Not handling")
    return
  end

  local update_index = false
  if to_update.children then
    local devices =
      build_group_device_table(
        to_update, build_hue_id_to_device_map(bridge_device), driver.hue_identifier_to_device_record
      )
    -- check if number of children has changed and if we need to move it
    update_index = #devices ~= #group.devices
    group.devices = devices
  end
  if to_update.services then
    group.grouped_light_rid = find_grouped_light_rid(to_update)
    if group.grouped_light_rid == nil then
      group.devices = {}
      update_index = true
    end
  end

  for key, value in pairs(to_update) do
    group[key] = value
  end
  if update_index then
    -- Move to the new correct index
    table.remove(groups, index)
    insert(groups, group)
  end
  log.info(string.format("Updating group %s, %d devices", group.id, #group.devices))
  bridge_device:set_field(Fields.GROUPS, groups)
end

--- Handle new room or zone from SSE stream.
---@param driver HueDriver
---@param bridge_device HueBridgeDevice
---@param to_add table
function grouped_utils.group_add(driver, bridge_device, to_add)
  local groups = bridge_device:get_field(Fields.GROUPS)
  if groups == nil then
    log.warn("Received group add before groups on bridge were initialized. Not handling.")
  end
  local hue_light_group =
    build_hue_light_group(
      to_add, build_hue_id_to_device_map(bridge_device), driver.hue_identifier_to_device_record
    )
  insert(groups, hue_light_group)
  log.info(string.format("Adding group %s, %d devices",
    hue_light_group.id, #hue_light_group.devices))
  bridge_device:set_field(Fields.GROUPS, groups)
end

--- Handle room or zone delete from SSE stream.
---@param driver HueDriver
---@param bridge_device HueBridgeDevice
---@param to_delete table
function grouped_utils.group_delete(driver, bridge_device, to_delete)
  local groups = bridge_device:get_field(Fields.GROUPS) or {}
  local index, group = find(groups, to_delete.id, to_delete.type)
  if index and group then
    log.info(string.format("Deleting group %s, %d devices", group.id, #group.devices))
    table.remove(groups, index)
    bridge_device:set_field(Fields.GROUPS, groups)
  else
    log.warn("Received delete for group with no record.")
  end
end

function grouped_utils.set_field_on_group_devices(group, field, v)
  for _, device in ipairs(group.devices) do
    device:set_field(field, v)
  end
end


return grouped_utils
