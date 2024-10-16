local handlers = require "api.event_handlers"
local log = require "log"
local st_utils = require "st.utils"

local PlayerFields = require "fields".SonosPlayerFields

--- @module 'sonos.types'
local Types = {}

--- @enum SonosCapabilities
Types.SonosCapabilities = {
  PLAYBACK = "PLAYBACK",                   --- The player can produce audio. You can target it for playback.
  CLOUD = "CLOUD",                         --- The player can send commands and receive events over the internet.
  HT_PLAYBACK = "HT_PLAYBACK",             --- The player is a home theater source. It can reproduce the audio from a home theater system, typically delivered by S/PDIF or HDMI.
  HT_POWER_STATE = "HT_POWER_STATE",       --- The player can control the home theater power state. For example, it can switch a connected TV on or off.
  AIRPLAY = "AIRPLAY",                     --- The player can host AirPlay streams. This capability is present when the device is advertising AirPlay support.
  LINE_IN = "LINE_IN",                     --- The player has an analog line-in.
  AUDIO_CLIP = "AUDIO_CLIP",               ---  The device is capable of playing audio clip notifications.
  VOICE = "VOICE",                         --- The device supports the voice namespace (not yet implemented by Sonos).
  SPEAKER_DETECTION = "SPEAKER_DETECTION", --- The component device is capable of detecting connected speaker drivers.
  FIXED_VOLUME = "FIXED_VOLUME"            --- The device supports fixed volume.
}

--- @alias PlayerId string
--- @alias HouseholdId string
--- @alias GroupId string

--- Lua representation of the Sonos `deviceInfo` JSON Object: https://developer.sonos.com/build/control-sonos-players-lan/discover-lan/#deviceInfo-object
--- @class SonosDeviceInfo
--- @field public id PlayerId The playerId. Also known as the deviceId. Used to address Sonos devices in the control API.
--- @field public primaryDeviceId string Identifies the primary device in bonded sets. Primary devices leave the value blank, which omits the key from the message. The field is expected for secondary devices in stereo pairs and satellites in home theater configurations.
--- @field public serialNumber string The device serial number printed on the device.
--- @field public model string An opaque string the uniquely identifies the device model. Should not be presented to customers. If you must present something, present the modelDisplayName as instead.
--- @field public modelDisplayName string A human readable version of the model string. Present this value to customers if you must present a model name.
--- @field public color string The primary device color. Older products that did not encode this information digitally may not include this value
--- @field public capabilities SonosCapabilities[] An array summarizing device capabilities. Generally, capabilities are derived from hardware features. See the groups object for details.
--- @field public apiVersion string The latest API version supported by the player.
--- @field public minApiVersion string Stores the oldest API version supported by the player.
--- @field public name string Stores the human-readable player name. This field is not strictly immutable, but we don’t expect the value to change often in people’s homes. The name is assigned early in the device setup and expected to remain constant.
--- @field public softwareVersion string Stores the software version the player is running.
--- @field public hwVersion string Stores the hardware version the player is running. The format is: `{vendor}.{model}.{submodel}.{revision}-{region}.`
--- @field public swGen integer Stores the software generation that the player is running.

--- Lua representation of the Sonos `discoveryInfo` JSON object: https://developer.sonos.com/build/control-sonos-players-lan/discover-lan/#discoveryInfo-object
--- @class SonosDiscoveryInfo
--- @field public device SonosDeviceInfo The device object. This object presents immutable data that describes a Sonos device. Use this object to uniquely identify any Sonos device. See below for details.
--- @field public householdId HouseholdId An opaque identifier assigned to the device during registration. This field may be missing prior to registration.
--- @field public playerId PlayerId The identifier used to address this particular device in the control API.
--- @field public groupId GroupId The currently assigned groupId, an ephemeral opaque identifier. This value is always correct, including for group members.
--- @field public websocketUrl string The URL to the WebSocket server. Use this interface to receive real time updates from the device.
--- @field public restUrl string The base URL for REST commands using the control API. You can use the same format as REST commands sent to the Sonos cloud. Sonos exposes all REST commands relative to this URL.

--- Lua representation of the Sonos LAN API response's header structure
--- @class SonosResponseHeader
--- @field public namespace string
--- @field public command? string The command value for a command. A header will have this or `type` but not both
--- @field public type? string The type value for an event. A header will have this or `command` but not both
--- @field public cmdId? string Optional command ID for tracing purposes
--- @field public sessionId? string ID of the target if the target was a session. A header will have one of `sessionId`, `groupId`, or `playerId`
--- @field public groupId? GroupId ID of the target if the target was a group. A header will have one of `sessionId`, `groupId`, or `playerId`,
--- @field public playerId? PlayerId ID of the target if the target was a player. A header will have one of `sessionId`, `groupId`, or `playerId`,
--- @field public householdId HouseholdId the Household ID

--- Lua representation of the Sonos `groups` (note the plural) JSON object: https://developer.sonos.com/reference/control-api/groups/groups/
--- @class SonosGroupsResponseBody
--- @field public groups SonosGroupObject[]
--- @field public players SonosPlayerObject[]

--- Lua representation of the Sonos `group` (note the singular) JSON object: https://developer.sonos.com/reference/control-api/groups/groups/#group
--- @class SonosGroupObject
--- @field public coordinatorId PlayerId
--- @field public id GroupId
--- @field public playbackState string
--- @field public playerIds PlayerId[]
--- @field public name string

--- Lua representation of the Sonos `player` JSON object: https://developer.sonos.com/reference/control-api/groups/groups/#player
--- @class SonosPlayerObject
--- @field public apiVersion string
--- @field public deviceIds PlayerId[]
--- @field public icon string
--- @field public id PlayerId
--- @field public minApiVersion string
--- @field public name string
--- @field public softwareVersion string
--- @field public websocketUrl string
--- @field public capabilities SonosCapabilities[]

--- Sonos player local state
--- @class PlayerDiscoveryState
--- @field public info_cache SonosDiscoveryInfo Table representation of the JSON returned by the player REST API info endpoint
--- @field public ipv4 string the ipv4 address of the player on the local network
--- @field public is_coordinator boolean whether or not the player was a coordinator (at time of discovery)

--- @class SonosSSDPInfo
--- Information parsed from Sonos SSDP reply. Contains most of what is needed to uniquely
--- connect to a player *except* for its standalone player id; though this can be determined
--- by making REST calls using the information included below. That will also provide the rest
--- of the information needed to classify and identify the properties of a player.
---
--- @field public ip string IP address of the player
--- @field public is_group_coordinator boolean whether or not the player is a group coordinator
--- @field public group_id GroupId
--- @field public group_name string
--- @field public household_id HouseholdId
--- @field public wss_url string

--- @alias SonosFavorites { id: string, name: string }[]
--- @class SonosHousehold
--- Information on an entire Sonos system ("household"), such as its current groups, list of players, etc.
--- @field public groups table<GroupId,SonosGroupObject> All of the current groups in the system
--- @field public players table<PlayerId,SonosPlayerObject> All of the current players in the system
--- @field public favorites SonosFavorites all of the favorites/presets in the system

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
    joined_players = {}
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
    log.debug_with({ hub_logs = true },
      st_utils.stringify_table(
        {name = (device or { label = "<no device>" }).label, event = groups_event },
        string.format("Update household info for household %s", id),
        true
      )
    )
    if device and device.label then
      log.debug(string.format("Household update triggered by device %s to update capabilities", device.label))
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
    log.debug_with({ hub_logs = true },
      st_utils.stringify_table(
        { household_id = household_id, player_id = player_id }, "Get Group For Player", true
      )
    )
    local household = private.households[household_id]
    if household == nil then
      log.error(st_utils.stringify_table({ household = household }, "Get group for invalid household", false))
      return nil, st_utils.stringify_table({ household = household }, "Get group for invalid household", false)
    end
    return household.player_to_group_map[player_id]
  end

  --- @param self SonosState
  --- @param household_id HouseholdId
  --- @param group_id GroupId
  --- @return PlayerId?,string?
  ret.get_coordinator_for_group = function(self, household_id, group_id)
    log.debug_with({ hub_logs = true },
      st_utils.stringify_table(
        { household_id = household_id, group_id = group_id }, "Get Coordinator For Group", true
      )
    )
    local household = private.households[household_id]
    if household == nil then
      log.error(st_utils.stringify_table({ household = household }, "Get coordinator for invalid household", false))
      return nil, st_utils.stringify_table({ household = household }, "Get coordinator for invalid household", false)
    end
    return household.group_to_coordinator_map[group_id]
  end

  --- @param self SonosState
  --- @param household_id HouseholdId
  --- @param player_id PlayerId
  --- @return PlayerId?,string?
  ret.get_coordinator_for_player = function(self, household_id, player_id)
    log.debug_with({ hub_logs = true },
      st_utils.stringify_table(
        { household_id = household_id, player_id = player_id }, "Get Coordinator For Player", true
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
    local household_id, player_id = device:get_field(PlayerFields.HOUSEHOULD_ID),
      device:get_field(PlayerFields.PLAYER_ID)
    log.debug_with({ hub_logs = true },
      st_utils.stringify_table(
        { name = (device or {label = "<no device>"}).label, household_id = household_id, player_id = player_id },
        "Get Player For Device",
        true
      )
    )

    if not (device:get_field(PlayerFields._IS_INIT) or household_id or player_id) then
      return nil, nil,
          "Player not fully initialized: " .. device.label
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
    log.debug_with({ hub_logs = true },
      st_utils.stringify_table(
        { name = (device or {label = "<no device>"}).label, household_id = household_id, player_id = player_id },
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
    log.debug_with({ hub_logs = true },
      st_utils.stringify_table(
        { name = (device or {label = "<no device>"}).label, household_id = household_id, player_id = player_id },
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

Types.SonosState = SonosState

--- @alias DiscoCallback fun(dni: string, ssdp_group_info: SonosSSDPInfo, player_info: SonosDiscoveryInfo, group_info: SonosGroupsResponseBody)

--- Sonos Edge Driver extensions
--- @class SonosDriver : Driver
--- @field public sonos SonosState Local state related to the sonos systems
--- @field private _player_id_to_device table<string,SonosDevice>
--- @field public update_group_state fun(self: SonosDriver, header: SonosResponseHeader, body: SonosGroupsResponseBody)
--- @field public handle_ssdp_discovery fun(self: SonosDriver, ssdp_group_info: SonosSSDPInfo, callback?: DiscoCallback)
--- @field public is_same_mac_address fun(dni: string, other: string): boolean

--- Sonos Player device
--- @class SonosDevice : st.Device
--- @field public label string Device label set at `try_create_device`
--- @field public device_network_id string the DNI of the device
--- @field public type string Network type. Should be "LAN".
--- @field public manufacturer string Descripting Manufacturer string ("Sonos")
--- @field public profile table The device's profile
--- @field public model string The user-facing model name string
--- @field public vendor_provided_label string The vendor's model string
--- @field public get_field fun(self: SonosDevice, key: string):any
--- @field public set_field fun(self: SonosDevice, key: string, value: any, args?: table)

--- Sonos JSON commands
--- @class SonosCommand

return Types
