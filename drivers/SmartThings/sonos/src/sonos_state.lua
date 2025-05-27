local st_utils = require "st.utils"

local handlers = require "api.event_handlers"
local log = require "log"
local PlayerFields = require "fields".SonosPlayerFields

--- Sonos systems local state
--- @class SonosState
--- @field public get_household fun(self: SonosState, id: HouseholdId): SonosHousehold
--- @field public update_household_info fun(self: SonosState, id: HouseholdId, groups_event: SonosGroupsResponseBody, device: SonosDevice|nil)
--- @field public update_household_favorites fun(self: SonosState, id: HouseholdId, favorites: SonosFavorites)
--- @field public get_group_for_player fun(self: SonosState, household_id: HouseholdId, player_id: PlayerId): GroupId
--- @field public get_coordinator_for_player fun(self: SonosState, household_id: HouseholdId, player_id: PlayerId): PlayerId
--- @field public get_coordinator_for_group fun(self: SonosState, household_id: HouseholdId, group_id: GroupId): PlayerId
--- @field public get_player_for_device fun(self: SonosState, device: SonosDevice): HouseholdId,PlayerId,string
--- @field public get_coordinator_for_device fun(self: SonosState, device: SonosDevice): HouseholdId,PlayerId,string
--- @field public get_group_for_device fun(self: SonosState, device: SonosDevice): HouseholdId,GroupId,string
--- @field public mark_player_as_joined fun(self: SonosState, player_id: PlayerId)
--- @field public mark_player_as_removed fun(self: SonosState, player_id: PlayerId)
--- @field public is_player_joined fun(self: SonosState, household_id_or_dni: HouseholdId|string, player_id?: PlayerId): boolean
local SonosState = {}
SonosState.__index = SonosState

function SonosState.new()
  local ret = setmetatable({}, SonosState)

  local private = {
    households = {},
    joined_players = {},
  }

  ret.mark_player_as_joined = function(self, player_id)
    log.debug(string.format("Marking Player ID %s as joined", player_id))
    private.joined_players[player_id] = true
  end

  ret.mark_player_as_removed = function(self, player_id)
    log.debug(string.format("Marking Player ID %s as removed", player_id))
    private.joined_players[player_id] = false
  end

  ret.is_player_joined = function(self, dni)
    return private.joined_players[dni] ~= nil and private.joined_players[dni] -- we want a boolean return, not nil
  end

  ret.get_household = function(self, id)
    return private.households[id]
  end

  --- @param self SonosState
  --- @param id HouseholdId
  --- @param favorites SonosFavorites
  ret.update_household_favorites = function(self, id, favorites)
    local household = private.households[id] or {} --- @type SonosHousehold
    household.favorites = favorites or {}
  end

  --- @param self SonosState
  --- @param id HouseholdId
  --- @param groups_event SonosGroupsResponseBody
  --- @param device SonosDevice|nil
  ret.update_household_info = function(self, id, groups_event, device)
    log.debug_with(
      { hub_logs = true },
      st_utils.stringify_table(
        { name = (device or { label = "<no device>" }).label, event = groups_event },
        string.format("Update household info for household %s", id),
        true
      )
    )
    if device and device.label then
      log.debug(
        string.format(
          "Household update triggered by device %s to update capabilities",
          device.label
        )
      )
    end
    local household = private.households[id] or {}
    local groups, players = groups_event.groups, groups_event.players

    -- We create these maps to avoid having to constantly iterate
    -- when performing lookups. We use the various ID's as keys.
    household.groups = {}
    household.players = {}
    household.player_to_group_map = {}
    household.group_to_coordinator_map = {}

    for _, group in ipairs(groups) do
      household.groups[group.id] = group
      household.group_to_coordinator_map[group.id] = group.coordinatorId
      for _, playerId in ipairs(group.playerIds) do
        household.player_to_group_map[playerId] = group.id
      end
    end

    for _, player in ipairs(players) do
      household.players[player.id] = player
    end

    household.player_to_group_map.__newindex = function(_, _, _)
      log.warn("Attempted to modify read-only look-up map")
    end

    household.group_to_coordinator_map.__newindex = function(_, _, _)
      log.warn("Attempted to modify read-only look-up map")
    end

    private.households[id] = household

    -- emit group info update [groupId, groupRole, groupPrimaryDeviceId]
    if device ~= nil then
      log.debug(string.format("Emitting group info update for Device %s", device.label))
      local device_player_id = device:get_field(PlayerFields.PLAYER_ID)
      local group_id = self:get_group_for_player(id, device_player_id)
      local coordinator_id = self:get_coordinator_for_player(id, device_player_id)

      local role
      if device_player_id == coordinator_id then
        if #household.groups[group_id].playerIds > 1 then
          role = "primary"
        else
          role = "ungrouped"
        end
      else
        role = "auxilary"
      end

      local group_update_payload = { role, coordinator_id, group_id }
      if type(coordinator_id) == "string" and type(group_id) == "string" then
        handlers.handle_group_update(device, group_update_payload)
      else
        log.warn(
          st_utils.stringify_table(
            { household = household, group_update_payload = group_update_payload },
            "Household update with invalid data",
            false
          )
        )
      end
    end
  end

  --- @param self SonosState
  --- @param household_id HouseholdId
  --- @param player_id PlayerId
  --- @return GroupId?,string?
  ret.get_group_for_player = function(self, household_id, player_id)
    log.debug_with(
      { hub_logs = true },
      st_utils.stringify_table(
        { household_id = household_id, player_id = player_id },
        "Get Group For Player",
        true
      )
    )
    local household = private.households[household_id]
    if household == nil then
      log.error(
        st_utils.stringify_table(
          { household = household },
          "Get group for invalid household",
          false
        )
      )
      return nil,
        st_utils.stringify_table(
          { household = household },
          "Get group for invalid household",
          false
        )
    end
    return household.player_to_group_map[player_id]
  end

  --- @param self SonosState
  --- @param household_id HouseholdId
  --- @param group_id GroupId
  --- @return PlayerId?,string?
  ret.get_coordinator_for_group = function(self, household_id, group_id)
    log.debug_with(
      { hub_logs = true },
      st_utils.stringify_table(
        { household_id = household_id, group_id = group_id },
        "Get Coordinator For Group",
        true
      )
    )
    local household = private.households[household_id]
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
    return household.group_to_coordinator_map[group_id]
  end

  --- @param self SonosState
  --- @param household_id HouseholdId
  --- @param player_id PlayerId
  --- @return PlayerId?,string?
  ret.get_coordinator_for_player = function(self, household_id, player_id)
    log.debug_with(
      { hub_logs = true },
      st_utils.stringify_table(
        { household_id = household_id, player_id = player_id },
        "Get Coordinator For Player",
        true
      )
    )
    return self:get_coordinator_for_group(
      household_id,
      self:get_group_for_player(household_id, player_id)
    )
  end

  --- @param self SonosState
  --- @param device SonosDevice
  --- @return HouseholdId|nil household_id nil on error
  --- @return PlayerId|nil player_id nil on error
  --- @return nil|string error nil on success
  ret.get_player_for_device = function(self, device)
    local household_id, player_id =
      device:get_field(PlayerFields.HOUSEHOLD_ID), device:get_field(PlayerFields.PLAYER_ID)
    log.debug_with(
      { hub_logs = true },
      st_utils.stringify_table(
        {
          name = (device or { label = "<no device>" }).label,
          household_id = household_id,
          player_id = player_id,
        },
        "Get Player For Device",
        true
      )
    )

    if not (device:get_field(PlayerFields._IS_INIT) or household_id or player_id) then
      return nil, nil, "Player not fully initialized: " .. device.label
    end

    return household_id, player_id, nil
  end

  --- @param self SonosState
  --- @param device SonosDevice
  --- @return HouseholdId|nil household_id nil on error
  --- @return PlayerId|nil coordinator_id nil on error
  --- @return nil|string error nil on success
  ret.get_coordinator_for_device = function(self, device)
    local household_id, player_id, err = self:get_player_for_device(device)
    log.debug_with(
      { hub_logs = true },
      st_utils.stringify_table(
        {
          name = (device or { label = "<no device>" }).label,
          household_id = household_id,
          player_id = player_id,
        },
        "Get Coordinator For Device",
        true
      )
    )
    if err then
      return nil, nil, err
    end

    local coordinator_id = self:get_coordinator_for_player(household_id, player_id)

    if not coordinator_id then
      return nil, nil, "Couldn't find coordinator ID for device " .. device.label
    end

    return household_id, coordinator_id, nil
  end

  --- @param self SonosState
  --- @param device SonosDevice
  --- @return HouseholdId|nil household_id nil on error
  --- @return GroupId|nil group_id nil on error
  --- @return nil|string error nil on success
  ret.get_group_for_device = function(self, device)
    local household_id, player_id, err = self:get_player_for_device(device)
    log.debug_with(
      { hub_logs = true },
      st_utils.stringify_table(
        {
          name = (device or { label = "<no device>" }).label,
          household_id = household_id,
          player_id = player_id,
        },
        "Get Group For Device",
        true
      )
    )
    if err then
      return nil, nil, err
    end

    local group_id = self:get_group_for_player(household_id, player_id)

    if not group_id then
      return nil, nil, "Couldn't find group ID for device " .. device.label
    end

    return household_id, group_id, nil
  end

  return ret
end

return SonosState
