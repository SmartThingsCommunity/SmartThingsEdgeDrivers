---@meta

--- @alias UniqueKey string unique identifier composed of the form `${HouseholdId}/${PlayerId}`
--- @alias PlayerId string
--- @alias HouseholdId string
--- @alias GroupId string

--------- #region Sonos API Types; the following defintions are from the Sonos API
---------         In particular, anything ending in `Object` is an API object.

--- @alias SonosCapabilities
---| "PLAYBACK" # The player can produce audio. You can target it for playback.
---| "CLOUD" # The player can send commands and receive events over the internet.
---| "HT_PLAYBACK" # The player is a home theater source. It can reproduce the audio from a home theater system, typically delivered by S/PDIF or HDMI.
---| "HT_POWER_STATE" # The player can control the home theater power state. For example, it can switch a connected TV on or off.
---| "AIRPLAY" # The player can host AirPlay streams. This capability is present when the device is advertising AirPlay support.
---| "LINE_IN" # The player has an analog line-in.
---| "AUDIO_CLIP" #  The device is capable of playing audio clip notifications.
---| "VOICE" # The device supports the voice namespace (not yet implemented by Sonos).
---| "SPEAKER_DETECTION" # The component device is capable of detecting connected speaker drivers.
---| "FIXED_VOLUME" # The device supports fixed volume.

--- @class SonosFeatureInfoObject
--- @field public _objectType "feature"
--- @field public name string

---@class SonosVersionsInfoObject
---@field public _objectType "sdkVersions"
---@field public audioTxProtocol { [1]: integer }
---@field public trueplaySdk { [1]: string }
---@field public controlApi { [1]: string }

--- Lua representation of the Sonos `deviceInfo` JSON Object: https://developer.sonos.com/build/control-sonos-players-lan/discover-lan/#deviceInfo-object
--- @class SonosDeviceInfoObject
--- @field public _objectType "deviceInfo"
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
--- @field public versions SonosVersionsInfoObject
--- @field public features SonosFeatureInfoObject[]

--- Lua representation of the Sonos `discoveryInfo` JSON object: https://developer.sonos.com/build/control-sonos-players-lan/discover-lan/#discoveryInfo-object
--- @class SonosDiscoveryInfoObject
--- @field public _objectType "discoveryInfo"
--- @field public device SonosDeviceInfoObject The device object. This object presents immutable data that describes a Sonos device. Use this object to uniquely identify any Sonos device. See below for details.
--- @field public householdId HouseholdId An opaque identifier assigned to the device during registration. This field may be missing prior to registration.
--- @field public playerId PlayerId The identifier used to address this particular device in the control API.
--- @field public groupId GroupId The currently assigned groupId, an ephemeral opaque identifier. This value is always correct, including for group members.
--- @field public websocketUrl string The URL to the WebSocket server. Use this interface to receive real time updates from the device.
--- @field public restUrl string The base URL for REST commands using the control API. You can use the same format as REST commands sent to the Sonos cloud. Sonos exposes all REST commands relative to this URL.
--- @field public allowGuestAccess boolean whether guest access is enabled
--- @field public credentialTypeAllowed string

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

--- Lua representation of a Sonos error body
--- @class SonosErrorResponse
--- @field public _objectType "globalError"
--- @field public errorCode "ERROR_NOT_CAPABLE"|"ERROR_COMMAND_FAILED"|"ERROR_INVALID_OBJECT_ID"|"ERROR_INVALID_PARAMETER"|"ERROR_UNSUPPORTED_COMMAND"|"ERROR_UNSUPPORTED_NAMESPACE"|"ERROR_INVALID_SYNTAX"|"ERROR_MISSING_PARAMETERS"|"ERROR_NOT_AUTHORIZED"
--- @field public wwwAuthenticate string? Used with `errorCode` is `ERROR_NOT_AUTHORIZED`
--- @field public reason string? Used with `ERROR_MISSING_PARAMETER`

--- Lua representation of the Sonos `groups` (note the plural) JSON object: https://developer.sonos.com/reference/control-api/groups
--- @class SonosGroupsResponseBody
--- @field public _objectType "groups"
--- @field public groups SonosGroupObject[]
--- @field public players SonosPlayerObject[]
--- @field public partial boolean will be `true` if the API response excluded players/groups because it considered them "invalid"

--- Lua representation of the Sonos `favorites` (note the plural) JSON object: https://developer.sonos.com/reference/control-api/favorites
--- @class SonosFavoritesResponseBody
--- @field public _objectType "favoritesList"
--- @field public version string
--- @field public items any[]

--- Lua representation of a Sonos `favorite` (note the singular) JSON object: https://developer.sonos.com/reference/control-api/favorites
--- @class SonosFavoriteObject
--- @field public _objectType "favorite"
--- @field public id string
--- @field public name string
--- @field public description string
--- @field public imageUrl string? deprecated, the `images` array parameter is preferred
--- @field public images SonosImageObject[]
--- @field public service SonosServiceObject
--- @field public resource SonosContentResourceObject

--- @class SonosImageObject
--- @field public _objectType "image"
--- @field public url string

--- @class SonosServiceObject
--- @field public _objectType "service"
--- @field public name string
--- @field public id string
--- @field public images SonosImageObject[]

--- @class SonosContentResourceObject
--- @field public _objectType "contentResource"
--- @field public type string
--- @field public name string
--- @field public images SonosImageObject[]

--- @class SonosMusicObjectId
--- @field public _objectType "universalMusicObjectId"
--- @field public serviceId string
--- @field public objectId string
--- @field public accountId string

--- Lua representation of the Sonos `group` (note the singular) JSON object: https://developer.sonos.com/reference/control-api/groups
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
--- @field public devices SonosDeviceInfoObject[]

--------- #endregion Sonos API Types

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
--- @field public player_id PlayerId extracted from the USN
--- @field public wss_url string
--- @field public expires_at integer

--- @alias SonosFavorites { id: string, name: string }[]
--- @alias DiscoCallback fun(dni: string, ssdp_group_info: SonosSSDPInfo, player_info: SonosDiscoveryInfoObject, group_info: SonosGroupsResponseBody): boolean?

--- Sonos Player device
--- @class SonosDevice : st.Device
--- @field public id string
--- @field public log table device-scoped logging module
--- @field public label string Device label set at `try_create_device`
--- @field public device_network_id string the DNI of the device
--- @field public type string Network type. Should be "LAN".
--- @field public manufacturer string Descripting Manufacturer string ("Sonos")
--- @field public profile table The device's profile
--- @field public model string The user-facing model name string
--- @field public vendor_provided_label string The vendor's model string
--- @field public get_field fun(self: SonosDevice, key: string):any
--- @field public set_field fun(self: SonosDevice, key: string, value: any, args?: table)
--- @field public emit_event fun(self: SonosDevice, event: any)
--- @field public driver SonosDriver

--- @class SonosGroupInfo
--- @field public id GroupId
--- @field public coordinator_id PlayerId
--- @field public player_ids PlayerId[]

--- @class SonosDeviceInfo
--- @field public id PlayerId
--- @field public primary_device_id PlayerId?

--- @class SonosPlayerInfo
--- @field public id PlayerId
--- @field public websocket_url string

--- Sonos JSON commands
--- @class SonosCommand
