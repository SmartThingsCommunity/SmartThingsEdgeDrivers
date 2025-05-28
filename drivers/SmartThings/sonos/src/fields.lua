--- @class Fields
local Fields = {}

---@enum SonosPlayerFields
Fields.SonosPlayerFields = {
  _IS_INIT = "init",
  _IS_SCANNING = "scanning",
  CONNECTION = "conn",
  UNIQUE_KEY = "unique_key",
  HOUSEHOLD_ID = "householdId",
  PLAYER_ID = "playerId",
  GROUP_ID = "groupId",
  GROUP_ROLE = "groupRole",
  COORDINATOR_ID = "coordinatorId",
  WSS_URL = "wss_url",
  REST_URL = "rest_url",
  SW_GEN = "sw_gen",
}

return Fields
