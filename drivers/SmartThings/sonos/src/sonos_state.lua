local capabilities = require "st.capabilities"
local log = require "log"
local st_utils = require "st.utils"
local swGenCapability = capabilities["stus.softwareGeneration"]

local utils = require "utils"

local CapEventHandlers = require "api.event_handlers"
local PlayerFields = require "fields".SonosPlayerFields
local SonosConnection = require "api.sonos_connection"

-- state singleton
local _STATE = {
  ---@type table<HouseholdId,SonosHousehold>
  households = {},
  ---@type table<string, {player: SonosPlayerObject, group: SonosGroupObject, household: SonosHousehold}>
  device_record_map = {},
}

--- Sonos systems local state
--- @class SonosState
local SonosState = {}
SonosState.__index = SonosState

---@param device SonosDevice
---@param info { ssdp_info: SonosSSDPInfo, discovery_info: SonosDiscoveryInfo }
function SonosState:associate_device_record(device, info)
  local household_id = info.ssdp_info.household_id
  local group_id = info.ssdp_info.group_id
  local player_id = info.discovery_info.playerId

  local household = _STATE.households[household_id]
  if not household then
    log.error(
      string.format("No record of Sonos household for device %s", (device.label or device.id or "<unknown device>"))
    )
    return
  end

  local group = household.groups[group_id]

  if not group then
    log.error(
      string.format("No record of Sonos group for device %s", (device.label or device.id or "<unknown device>"))
    )
    return
  end

  local player = household.players[player_id]

  if not player then
    log.error(
      string.format("No record of Sonos player for device %s", (device.label or device.id or "<unknown device>"))
    )
    return
  end

  household.st_devices = household.st_devices or {}
  household.st_devices[player.id] = device.id

  _STATE.device_record_map = _STATE.device_record_map or {}
  _STATE.device_record_map[device.id] = { group = group, player = player, household = household }

  local group_role
  if player_id == group.coordinatorId then
    if #household.groups[group_id].playerIds > 1 then
      group_role = "primary"
    else
      group_role = "ungrouped"
    end
  else
    group_role = "auxilary"
  end

  device:set_field(PlayerFields.SW_GEN, info.discovery_info.device.swGen, { persist = true })
  device:emit_event(swGenCapability.generation(string.format("%s", info.discovery_info.device.swGen)))

  device:set_field(PlayerFields.REST_URL, info.discovery_info.restUrl, { persist = true })

  local sonos_conn = device:get_field(PlayerFields.CONNECTION)
  local connected = sonos_conn ~= nil
  local websocket_url_changed =
    utils.update_field_if_changed(device, PlayerFields.WSS_URL, info.ssdp_info.wss_url, { persist = true })

  if websocket_url_changed and connected then
    sonos_conn:stop()
    sonos_conn = nil
    device:set_field(PlayerFields.CONNECTION, nil)
  end

  local household_id_changed =
    utils.update_field_if_changed(device, PlayerFields.HOUSEHOLD_ID, household.id, { persist = true })

  local player_id_changed = utils.update_field_if_changed(device, PlayerFields.PLAYER_ID, player.id, { persist = true })

  local need_refresh = connected and (websocket_url_changed or household_id_changed or player_id_changed)

  if sonos_conn == nil then
    sonos_conn = SonosConnection.new(device.driver, device)
    device:set_field(PlayerFields.CONNECTION, sonos_conn)
    sonos_conn:start()
    need_refresh = false
  end

  if need_refresh and sonos_conn then
    sonos_conn:refresh_subscriptions()
  end

  local field_changed = device:set_field(PlayerFields.GROUP_ID, group.id, { persist = true })
  if field_changed then
    CapEventHandlers.handle_group_id_update(device, group.id)
  end

  field_changed = utils.update_field_if_changed(device, PlayerFields.GROUP_ROLE, group_role, { persist = true })
  if field_changed then
    CapEventHandlers.handle_group_role_update(device, group_role)
  end

  field_changed =
    utils.update_field_if_changed(device, PlayerFields.COORDINATOR_ID, group.coordinatorId, { persist = true })
  if field_changed then
    CapEventHandlers.handle_group_coordinator_update(device, group.coordinatorId)
  end
end

function SonosState:remove_device_record_association(device)
  _STATE.device_record_map[device.id] = nil
end

---@param household_id HouseholdId
---@param player_id PlayerId
---@return string? device_id
function SonosState:get_device_id_for_player(household_id, player_id)
  local household = _STATE.households[household_id]
  if not household then
    log.error(string.format("No record of Sonos household with id %s", household_id))
    return
  end
  return household.st_devices[player_id]
end

---@param id HouseholdId
---@return SonosHousehold
function SonosState:get_household(id)
  return _STATE.households[id]
end

--- @param id HouseholdId
--- @param favorites SonosFavorites
function SonosState:update_household_favorites(id, favorites)
  local household = _STATE.households[id] or {}
  household.favorites = favorites or {}
end

--- @param id HouseholdId
--- @param groups_event SonosGroupsResponseBody
function SonosState:update_household_info(id, groups_event)
  local household = _STATE.households[id] or {}
  household.groups = {}
  household.players = {}
  household.player_to_group = {}
  household.st_devices = household.st_devices or {}

  local groups, players = groups_event.groups, groups_event.players

  for _, group in ipairs(groups) do
    household.groups[group.id] = group
    for _, player in ipairs(group.playerIds) do
      household.player_to_group[player] = group.id

      local maybe_device_id = household.st_devices[player]
      if maybe_device_id then
        _STATE.device_record_map[maybe_device_id] = _STATE.device_record_map[maybe_device_id] or {}
        _STATE.device_record_map[maybe_device_id].group = group
        _STATE.device_record_map[maybe_device_id].household = household
      end
    end
  end

  for _, player in ipairs(players) do
    household.players[player.id] = player
    local maybe_device_id = household.st_devices[player.id]
    if maybe_device_id then
      _STATE.device_record_map[maybe_device_id] = _STATE.device_record_map[maybe_device_id] or {}
      _STATE.device_record_map[maybe_device_id].player = player
    end
  end

  household.id = id
  _STATE.households[id] = household
end

--- @param household_id HouseholdId
--- @param player_id PlayerId
--- @return GroupId? group ID, nil for an invalid household ID
--- @return string? error nil on success
function SonosState:get_group_for_player(household_id, player_id)
  log.debug_with(
    { hub_logs = true },
    st_utils.stringify_table({ household_id = household_id, player_id = player_id }, "Get Group For Player", true)
  )
  local household = _STATE.households[household_id]
  if household == nil then
    log.error(st_utils.stringify_table({ household = household }, "Get group for invalid household", false))
    return nil, st_utils.stringify_table({ household = household }, "Get group for invalid household", false)
  end
  return household.player_to_group[player_id]
end

--- @param household_id HouseholdId
--- @param player_id PlayerId
--- @return PlayerId?,string?
function SonosState:get_coordinator_for_player(household_id, player_id)
  log.debug_with(
    { hub_logs = true },
    st_utils.stringify_table({ household_id = household_id, player_id = player_id }, "Get Coordinator For Player", true)
  )
  return self:get_coordinator_for_group(household_id, self:get_group_for_player(household_id, player_id))
end

--- @param household_id HouseholdId
--- @param group_id GroupId
--- @return PlayerId?,string?
function SonosState:get_coordinator_for_group(household_id, group_id)
  log.debug_with(
    { hub_logs = true },
    st_utils.stringify_table({ household_id = household_id, group_id = group_id }, "Get Coordinator For Group", true)
  )
  local household = _STATE.households[household_id]
  if household == nil then
    log.error(st_utils.stringify_table({ household = household }, "Get coordinator for invalid household", false))
    return nil, st_utils.stringify_table({ household = household }, "Get coordinator for invalid household", false)
  end
  return household.groups[group_id].coordinatorId
end

--- @param device SonosDevice
--- @return HouseholdId|nil household_id nil on error
--- @return GroupId|nil group_id nil on error
--- @return PlayerId|nil player_id nil on error
--- @return nil|string error nil on success
function SonosState:get_sonos_ids_for_device(device)
  local household_id, group_id, player_id =
    device:get_field(PlayerFields.HOUSEHOLD_ID),
    device:get_field(PlayerFields.GROUP_ID),
    device:get_field(PlayerFields.PLAYER_ID)

  if household_id and group_id and player_id then
    return household_id, group_id, player_id
  end

  local sonos_objects = _STATE.device_record_map[device.id]
  if not sonos_objects then
    return nil,
      nil,
      nil,
      string.format("No mapping to Sonos State for Device %s", (device.label or device.id or "<unknown device>"))
  end

  -- household id *should* be stable
  if not household_id then
    household_id = sonos_objects.household.id
    device:set_field(PlayerFields.HOUSEHOLD_ID, household_id, { persist = true })
  end

  -- player id *should* be stable
  if not player_id then
    player_id = sonos_objects.player.id
    device:set_field(PlayerFields.PLAYER_ID, player_id, { persist = true })
  end

  -- group id is ephemeral so we always update it here if it wasn't cached.
  group_id = sonos_objects.group.id
  device:set_field(PlayerFields.GROUP_ID, group_id, { persist = true })

  return household_id, group_id, player_id
end

--- @param device SonosDevice
--- @return HouseholdId|nil household_id nil on error
--- @return PlayerId|nil player_id nil on error
--- @return nil|string error nil on success
function SonosState:get_player_for_device(device)
  local household_id, _, player_id, err = self:get_sonos_ids_for_device(device)
  if err then
    return nil, nil, err
  end
  return household_id, player_id, nil
end

--- @param device SonosDevice
--- @return HouseholdId|nil household_id nil on error
--- @return GroupId|nil group_id nil on error
--- @return nil|string error nil on success
function SonosState:get_group_for_device(device)
  local household_id, group_id, _, err = self:get_sonos_ids_for_device(device)
  if err then
    return nil, nil, err
  end
  return household_id, group_id, nil
end

--- @param device SonosDevice
--- @return HouseholdId|nil household_id nil on error
--- @return PlayerId|nil coordinator_id nil on error
--- @return nil|string error nil on success
function SonosState:get_coordinator_for_device(device)
  local household_id, group_id, _, err = self:get_sonos_ids_for_device(device)
  if err then
    return nil, nil, err
  end
  local household = _STATE.households[household_id]
  if not household then
    return nil,
      nil,
      string.format(
        "Couldn't determine Sonos Household for device %s",
        (device.label or device.id or "<unknown device>")
      )
  end
  local group = household.groups[group_id]
  if not group then
    return nil,
      nil,
      string.format("Couldn't determine Sonos Group for device %s", (device.label or device.id or "<unknown device>"))
  end

  return household_id, group.coordinatorId, nil
end

---@return SonosState
function SonosState.instance()
  return setmetatable({}, SonosState)
end

return SonosState
