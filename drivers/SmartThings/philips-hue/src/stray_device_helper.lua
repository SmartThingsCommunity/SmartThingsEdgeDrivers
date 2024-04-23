---@class StrayDeviceHelper
local StrayDeviceHelper = {}

---@enum MessageTypes
local MessageTypes = {
  FoundBridge = "FOUND_BRIDGE",
  NewStrayLight = "NEW_STRAY_LIGHT",
}
StrayDeviceHelper.MessageTypes = MessageTypes

return StrayDeviceHelper
