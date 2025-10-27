local log = require "log"
local st_utils = require "st.utils"

local utils = require "utils"

local CapEventHandlers = require "api.event_handlers"
local PlayerFields = require "fields".SonosPlayerFields
local SonosConnection = require "api.sonos_connection"

--- @class SonosHousehold
--- Information on an entire Sonos system ("household"), such as its current groups, list of players, etc.
--- @field public id HouseholdId
--- @field public groups table<GroupId,SonosGroupInfo> All of the current groups in the system
--- @field public players table<PlayerId,{player: SonosPlayerInfo, device: SonosDeviceInfo?}> All of the current players in the system
--- @field public bonded_players table<PlayerId,boolean> PlayerID's in this map that map to true are non-primary bonded players, and not controllable.
--- @field public player_to_group table<PlayerId,GroupId> quick lookup from Player ID -> Group ID
--- @field public st_devices table<PlayerId,string> Player ID -> ST Device Record UUID information for the household
--- @field public favorites SonosFavorites all of the favorites/presets in the system
local _household_mt = {}

function _household_mt:reset()
  self.groups = utils.new_case_insensitive_table()
  self.players = utils.new_case_insensitive_table()
  self.player_to_group = utils.new_case_insensitive_table()
  -- previously bonded devices should not be un-bonded after a reset since these should
  -- not be treated as distinct devices
  if not self.bonded_players then
    self.bonded_players = utils.new_case_insensitive_table()
  end
end

_household_mt.__index = _household_mt
_household_mt.__metatable = "SonosHousehold"

local function make_sonos_household(id)
  local ret = setmetatable({
    id = id,
    st_devices = utils.new_case_insensitive_table(),
    favorites = {},
  }, _household_mt)
  ret:reset()
  return ret
end

--- @class Households: { [HouseholdId]: SonosHousehold }
--- @field public get_or_init fun(self: Households, id: HouseholdId): SonosHousehold

---@return Households
local function make_households_table()
  local households_table_inner = utils.new_case_insensitive_table()

  local households_table = setmetatable({}, {
    __index = function(_, key)
      return households_table_inner[key]
    end,
    __newindex = function(_, key, value)
      households_table_inner[key] = value
    end,
    __metatable = "SonosHouseholds",
  })

  function households_table:get_or_init(id)
    local household = self[id]
    if household then
      return household
    end

    household = make_sonos_household(id)
    self[id] = household
    return household
  end

  return households_table
end

-- state singleton
local _STATE = {
  ---@type Households
  households = make_households_table(),
  ---@type table<string, {sonos_device_id: PlayerId, player: SonosPlayerInfo, group: SonosGroupInfo, household: SonosHousehold, sonos_device: SonosDeviceInfo?}>
  device_record_map = {},
}

--- Sonos systems local state
--- @class SonosState
local SonosState = {}
SonosState.__index = SonosState
SonosState.EMPTY_HOUSEHOLD = _STATE.households:get_or_init("__EMPTY")

---@param device SonosDevice
---@param info SpeakerDiscoveryInfo
function SonosState:associate_device_record(device, info)
  local household_id = info.household_id
  local group_id = info.group_id
  -- This is the device id even if the device is a seondary in a bonded set
  local player_id = info.player_id

  local household = _STATE.households[household_id]
  if not household then
    log.error(
      string.format(
        "No record of Sonos household for device %s",
        (device.label or device.id or "<unknown device>")
      )
    )
    return
  end

  if not group_id or #group_id == 0 then
    group_id = household.player_to_group[player_id or ""] or ""
  end

  local group = household.groups[group_id]
  if not group then
    log.error(
      string.format(
        "No record of Sonos group for device %s",
        (device.label or device.id or "<unknown device>")
      )
    )
    return
  end

  local player_tbl = household.players[player_id]
  local player = (player_tbl or {}).player
  local sonos_device = (player_tbl or {}).device

  if not player then
    log.error(
      string.format(
        "No record of Sonos player for device %s",
        (device.label or device.id or "<unknown device>")
      )
    )
    return
  end

  household.st_devices[player_id] = device.id

  _STATE.device_record_map[device.id] = {
    sonos_device_id = player_id,
    group = group,
    player = player,
    household = household,
    sonos_device = sonos_device,
  }

  local bonded = household.bonded_players[player_id] and true or false

  local sw_gen_changed =
    utils.update_field_if_changed(device, PlayerFields.SW_GEN, info.sw_gen, { persist = true })

  if sw_gen_changed then
    CapEventHandlers.handle_sw_gen(device, info.sw_gen)
  end

  device:set_field(PlayerFields.REST_URL, info.rest_url:build(), { persist = true })

  local sonos_conn = device:get_field(PlayerFields.CONNECTION)
  local connected = sonos_conn ~= nil
  local websocket_url_changed = utils.update_field_if_changed(
    device,
    PlayerFields.WSS_URL,
    info.wss_url:build(),
    { persist = true }
  )

  local should_stop_conn = connected and (bonded or websocket_url_changed)

  if should_stop_conn then
    sonos_conn:stop()
    sonos_conn = nil
    device:set_field(PlayerFields.CONNECTION, nil)
  end

  local household_id_changed = utils.update_field_if_changed(
    device,
    PlayerFields.HOUSEHOLD_ID,
    household.id,
    { persist = true }
  )

  local player_id_changed =
    utils.update_field_if_changed(device, PlayerFields.PLAYER_ID, player_id, { persist = true })

  local need_refresh = connected
    and (websocket_url_changed or household_id_changed or player_id_changed)

  if not bonded and sonos_conn == nil then
    sonos_conn = SonosConnection.new(device.driver, device)
    device:set_field(PlayerFields.CONNECTION, sonos_conn)
    sonos_conn:start()
    need_refresh = false
  end

  if need_refresh and sonos_conn then
    sonos_conn:refresh_subscriptions()
  end

  self:update_device_record_group_info(household, group, device)

  -- device can't be controlled, mark the device as being offline.
  if bonded then
    device:offline()
  end
end

---@param household SonosHousehold
---@param group SonosGroupInfo
---@param device SonosDevice
function SonosState:update_device_record_group_info(household, group, device)
  local player_id = device:get_field(PlayerFields.PLAYER_ID)
  local bonded = ((household or {}).bonded_players or {})[player_id] and true or false
  local group_role
  if bonded then
    group_role = "auxilary"
  elseif
    (
      type(household) == "table"
      and type(household.groups) == "table"
      and player_id
      and group
      and group.id
      and group.coordinator_id
    ) and player_id == group.coordinator_id
  then
    local player_ids_list = (household.groups[group.id] or {}).player_ids or {}
    if #player_ids_list > 1 then
      group_role = "primary"
    else
      group_role = "ungrouped"
    end
  else
    group_role = "auxilary"
  end

  local field_changed =
    utils.update_field_if_changed(device, PlayerFields.GROUP_ID, group.id, { persist = true })
  if not bonded and field_changed then
    CapEventHandlers.handle_group_id_update(device, group.id)
  end

  field_changed =
    utils.update_field_if_changed(device, PlayerFields.GROUP_ROLE, group_role, { persist = true })
  if not bonded and field_changed then
    CapEventHandlers.handle_group_role_update(device, group_role)
  end

  field_changed = utils.update_field_if_changed(
    device,
    PlayerFields.COORDINATOR_ID,
    group.coordinator_id,
    { persist = true }
  )
  if not bonded and field_changed then
    CapEventHandlers.handle_group_coordinator_update(device, group.coordinator_id)
  end

  if bonded then
    device:offline()
  end
end

function SonosState:remove_device_record_association(device)
  _STATE.device_record_map[device.id] = nil
end

---@param household_id HouseholdId
---@param player_id PlayerId
---@return string? device_id
function SonosState:get_device_id_for_player(household_id, player_id)
  if type(player_id) ~= "string" then
    log.error(string.format("invalid player id provided: %s", player_id))
    return nil
  end
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
  if type(id) ~= "string" then
    log.error(string.format("invalid household id provided: %s", id))
    return nil
  end
  return _STATE.households[id]
end

--- @param id HouseholdId
--- @param favorites SonosFavorites
function SonosState:update_household_favorites(id, favorites)
  local household = _STATE.households:get_or_init(id)
  household.favorites = favorites or {}
end

--- @param household_id HouseholdId
--- @param device SonosDevice
function SonosState:update_device_record_from_state(household_id, device)
  local current_mapping = _STATE.device_record_map[device.id] or {}
  local household = _STATE.households:get_or_init(household_id)
  self:update_device_record_group_info(household, current_mapping.group, device)
end

--- Helper function for when updating household info
---@param driver SonosDriver
---@param player SonosPlayerObject
---@param household SonosHousehold
---@param known_bonded_players table<PlayerId,boolean>
---@param sonos_device_id PlayerId
local function update_device_info(driver, player, household, known_bonded_players, sonos_device_id)
  ---@type SonosDeviceInfo
  local device_info = { id = sonos_device_id, primary_device_id = player.id }
  ---@type SonosPlayerInfo
  local player_info = { id = player.id, websocket_url = player.websocketUrl }
  household.players[sonos_device_id] = {
    player = player_info,
    device = device_info,
  }
  local previously_bonded = known_bonded_players[sonos_device_id] and true or false
  local currently_bonded
  local group_id

  -- The primary bonded player will have the same id as the top level player id
  if sonos_device_id == player.id then
    currently_bonded = false
  else
    currently_bonded = true
  end
  group_id = household.player_to_group[player.id]
  household.player_to_group[sonos_device_id] = group_id
  household.bonded_players[sonos_device_id] = currently_bonded

  local maybe_device_id = household.st_devices[sonos_device_id]
  if maybe_device_id then
    _STATE.device_record_map[maybe_device_id] = _STATE.device_record_map[maybe_device_id] or {}
    _STATE.device_record_map[maybe_device_id].household = household
    _STATE.device_record_map[maybe_device_id].group = household.groups[group_id]
    _STATE.device_record_map[maybe_device_id].player = player_info
    _STATE.device_record_map[maybe_device_id].sonos_device = device_info
    if previously_bonded ~= currently_bonded then
      local target_device = driver:get_device_info(maybe_device_id)
      if target_device then
        target_device:set_field(PlayerFields.BONDED, currently_bonded, { persist = false })
        driver:update_bonded_device_tracking(target_device)
      end
    end
  end
end

--- @param id HouseholdId
--- @param groups_event SonosGroupsResponseBody
--- @param driver SonosDriver
function SonosState:update_household_info(id, groups_event, driver)
  local household = _STATE.households:get_or_init(id)
  local known_bonded_players = household.bonded_players or {}
  household:reset()

  local groups, players = groups_event.groups, groups_event.players

  for _, group in ipairs(groups or {}) do
    household.groups[group.id] =
      { id = group.id, coordinator_id = group.coordinatorId, player_ids = group.playerIds }
    for _, playerId in ipairs(group.playerIds or {}) do
      household.player_to_group[playerId] = group.id
    end
  end

  -- Iterate through the players and track all the devices associated with them
  -- for bonded set tracking.
  local log_devices_error = false
  for _, player in ipairs(players or {}) do
    -- Prefer devices because deviceIds is deprecated but all we care about is
    -- the ID so either way is fine.
    if type(player.devices) == "table" then
      for _, device in ipairs(player.devices or {}) do
        update_device_info(driver, player, household, known_bonded_players, device.id)
      end
    elseif type(player.deviceIds) == "table" then
      for _, device_id in ipairs(player.deviceIds or {}) do
        update_device_info(driver, player, household, known_bonded_players, device_id)
      end
    else
      log_devices_error = true
      -- We can still track the primary player in this case
      update_device_info(driver, player, household, known_bonded_players, player.id)
    end
  end
  if log_devices_error then
    log.warn_with(
      { hub_logs = true },
      "Group event contained neither devices nor deviceIds in player"
    )
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
    { hub_logs = false },
    st_utils.stringify_table(
      { household_id = household_id, player_id = player_id },
      "Get Group For Player",
      true
    )
  )
  if type(player_id) ~= "string" then
    log.error(string.format("invalid player id provided: %s", player_id))
    return nil
  end
  local household = _STATE.households[household_id]
  if household == nil then
    log.error(
      st_utils.stringify_table({ household = household }, "Get group for invalid household", false)
    )
    return nil,
      st_utils.stringify_table({ household = household }, "Get group for invalid household", false)
  end
  return household.player_to_group[player_id]
end

--- @param household_id HouseholdId
--- @param player_id PlayerId
--- @return PlayerId?,string?
function SonosState:get_coordinator_for_player(household_id, player_id)
  log.debug_with(
    { hub_logs = false },
    st_utils.stringify_table(
      { household_id = household_id, player_id = player_id },
      "Get Coordinator For Player",
      true
    )
  )
  if type(player_id) ~= "string" then
    log.error(string.format("invalid player id provided: %s", player_id))
    return nil
  end
  return self:get_coordinator_for_group(
    household_id,
    self:get_group_for_player(household_id, player_id)
  )
end

--- @param household_id HouseholdId
--- @param group_id GroupId
--- @return PlayerId?,string?
function SonosState:get_coordinator_for_group(household_id, group_id)
  log.debug_with(
    { hub_logs = false },
    st_utils.stringify_table(
      { household_id = household_id, group_id = group_id },
      "Get Coordinator For Group",
      true
    )
  )
  if type(group_id) ~= "string" then
    log.error(string.format("invalid group id provided: %s", group_id))
    return nil
  end
  local household = _STATE.households[household_id]
  if household == nil then
    log.error(
      st_utils.stringify_table(
        { household = household },
        "Get coordinator for invalid household",
        false
      )
    )
    return nil,
      st_utils.stringify_table(
        { household = household },
        "Get coordinator for invalid household",
        false
      )
  end

  local group = (household.groups or {})[group_id]
  if type(group) ~= "table" then
    log.error(string.format("No known group for id %s in household %s", group_id, household_id))
    return
  end

  return group.coordinator_id
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
      string.format(
        "No mapping to Sonos State for Device %s",
        (device.label or device.id or "<unknown device>")
      )
  end

  -- household id *should* be stable
  if not household_id then
    household_id = sonos_objects.household.id
    device:set_field(PlayerFields.HOUSEHOLD_ID, household_id, { persist = true })
  end

  -- player id *should* be stable
  if not player_id then
    player_id = sonos_objects.sonos_device_id
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
  if type(device) ~= "table" then
    return nil, string.format("Invalid device argument for get_player_for_device: %s", device)
  end
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
  if type(device) ~= "table" then
    return nil, string.format("Invalid device argument for get_group_for_device: %s", device)
  end
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
  if type(device) ~= "table" then
    return nil, string.format("Invalid device argument for get_coordinator_for_device: %s", device)
  end
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
      string.format(
        "Couldn't determine Sonos Group for device %s",
        (device.label or device.id or "<unknown device>")
      )
  end

  return household_id, group.coordinator_id, nil
end

---@return SonosState
function SonosState.instance()
  return setmetatable({}, SonosState)
end

return SonosState
