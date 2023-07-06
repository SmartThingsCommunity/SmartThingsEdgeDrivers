--- @module 'fields'
local Fields = {}

---@enum SonosPlayerFields
Fields.SonosPlayerFields = {
  _IS_INIT = "init",
  _IS_SCANNING = "scanning",
  CONNECTION = "conn",
  HOUSEHOULD_ID = "householdId",
  PLAYER_ID = "playerId",
  WSS_URL = "wss_url",
}

return Fields
