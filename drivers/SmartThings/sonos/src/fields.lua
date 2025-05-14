--- @class Fields
local Fields = {}

---@enum SonosPlayerFields
Fields.SonosPlayerFields = {
  _IS_INIT = "init",
  _IS_SCANNING = "scanning",
  CONNECTION = "conn",
  HOUSEHOLD_ID = "householdId",
  PLAYER_ID = "playerId",
  GROUP_ID = "groupId",
  GROUP_ROLE = "groupRole",
  COORDINATOR_ID = "coordinatorId",
  WSS_URL = "wss_url",
  SW_GEN = "sw_gen",
}

return Fields
