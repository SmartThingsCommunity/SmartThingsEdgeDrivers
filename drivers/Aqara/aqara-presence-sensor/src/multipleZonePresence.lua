local capabilities = require "st.capabilities"
local mzp = {}

mzp.capability = capabilities["multipleZonePresence"]
mzp.id = "multipleZonePresence"
mzp.commands = {}

mzp.present = "present"
mzp.notPresent = "not present"

local ZONE_INFO_KEY = "zoneInfo"

function mzp.findZoneById(driver, device, id)
  local zoneInfoTable = device:get_field(ZONE_INFO_KEY) or {}
  for index, zoneInfo in pairs(zoneInfoTable) do
    if zoneInfo.id == id then
      return zoneInfo, index
    end
  end
  return nil, nil
end

function mzp.findNewZoneId(driver, device)
  local maxId = 0
  local zoneInfoTable = device:get_field(ZONE_INFO_KEY) or {}
  for _, zoneInfo in pairs(zoneInfoTable) do
    local intId = tonumber(zoneInfo.id)
    if intId and intId > maxId then
      maxId = intId
    end
  end
  return tostring(maxId + 1)
end

function mzp.createZone(driver, device, name, id)
  local err, createdId = nil, nil
  local zoneInfo = {}
  local zoneInfoTable = device:get_field(ZONE_INFO_KEY) or {}
  if id == nil then
    id = mzp.findNewZoneId(driver, device)
  end
  if mzp.findZoneById(driver, device, id) then
    err = string.format("id %s already exists", id)
    return err, createdId
  end
  zoneInfo.id = id
  zoneInfo.name = name
  zoneInfo.state = mzp.notPresent
  zoneInfoTable["zone"..id] = zoneInfo
  createdId = id

  device:set_field(ZONE_INFO_KEY, zoneInfoTable, { persist = true })

  return err, createdId
end

function mzp.deleteZone(driver, device, id)
  local err, deletedId = nil, nil
  local _, index = mzp.findZoneById(driver, device, id)
  if index then
    local zoneInfoTable = device:get_field(ZONE_INFO_KEY) or {}
    zoneInfoTable[index] = nil
    deletedId = id
    device:set_field(ZONE_INFO_KEY, zoneInfoTable, { persist = true })
  else
    err = string.format("id %s doesn't exist", id)
  end
  return err, deletedId
end

function mzp.renameZone(driver, device, id, name)
  local err, changedId = nil, nil
  local _, index = mzp.findZoneById(driver, device, id)
  if index then
    local zoneInfoTable = device:get_field(ZONE_INFO_KEY) or {}
    zoneInfoTable[index].name = name
    changedId = id
    device:set_field(ZONE_INFO_KEY, zoneInfoTable, { persist = true })
  else
    err = string.format("id %s doesn't exist", id)
  end
  return err, changedId
end

function mzp.changeState(driver, device, id, state)
  local err, changedId = nil, nil
  local zoneInfo, index = mzp.findZoneById(driver, device, id)
  if zoneInfo then
    local zoneInfoTable = device:get_field(ZONE_INFO_KEY) or {}
    zoneInfoTable[index].state = state
    changedId = id
    device:set_field(ZONE_INFO_KEY, zoneInfoTable, { persist = true })
  else
    err = string.format("id %s doesn't exist", id)
  end
  return err, changedId
end

function mzp.setZoneInfo(driver, device, inputZoneInfoTable)
  --prevents overwriting with a default name ("zone%d").
  local zoneInfoTable = device:get_field(ZONE_INFO_KEY) or {}
  for __, inputZoneInfo in pairs(inputZoneInfoTable) do
    local zoneInfo, index = mzp.findZoneById(driver, device, inputZoneInfo.id)
    if zoneInfo then
      if inputZoneInfo.name ~= "zone" .. inputZoneInfo.id then
        zoneInfoTable[index].name = inputZoneInfo.name
      end
    else
      local newZoneInfo = {}
      newZoneInfo.id = inputZoneInfo.id
      newZoneInfo.name = inputZoneInfo.name
      newZoneInfo.state = mzp.notPresent
      table.insert(zoneInfoTable, newZoneInfo)
    end
  end
  device:set_field(ZONE_INFO_KEY, zoneInfoTable, { persist = true })
end

mzp.commands.updateZoneName = {}
mzp.commands.updateZoneName.name = "updateZoneName"
function mzp.commands.updateZoneName.handler(driver, device, args)
  local name = args.args.name
  local id = args.args.id
  mzp.renameZone(driver, device, id, name)
  mzp.updateAttribute(driver, device)
end

mzp.commands.deleteZone = {}
mzp.commands.deleteZone.name = "deleteZone"
function mzp.commands.deleteZone.handler(driver, device, args)
  local id = args.args.id
  mzp.deleteZone(driver, device, id)
  mzp.updateAttribute(driver, device)
end

mzp.commands.createZone = {}
mzp.commands.createZone.name = "createZone"
function mzp.commands.createZone.handler(driver, device, args)
  local name = args.args.name
  local id = args.args.id
  mzp.createZone(driver, device, name, id)
  mzp.updateAttribute(driver, device)
end

function mzp.updateAttribute(driver, device)
  local zoneInfoTable = device:get_field(ZONE_INFO_KEY) or {}
  local zoneStatePayload = {}
  for _, zoneInfo in pairs(zoneInfoTable) do
    table.insert(zoneStatePayload, zoneInfo)
  end
  device:emit_event(mzp.capability.zoneState({ value = zoneStatePayload }))
end

return mzp
