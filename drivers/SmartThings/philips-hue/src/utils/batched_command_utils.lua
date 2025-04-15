local utils = require "utils"
local Fields = require "fields"
local command_handlers = require "handlers.grouped_light_commands"
local capabilities = require "st.capabilities"
local KVCounter = require "utils.kv_counter"

--- Alias for clearer documentation.
---@alias CommandName string
--- Alias for clearer documentation.
---@alias DeviceUuid string

--- Capability command before being normalized via st.capabilities
---@class RawCapCommand
---@field public capability string
---@field public component string
---@field public command CommandName
---@field public args any[]
---@field public named_args table?

--- Serialized batched command from receive_batch.
--- This is already in a table format unlike the normal receive function.
---@class BatchedCommand
---@field public device_uuid DeviceUuid
---@field public capability_command RawCapCommand
---@field public auxilary_command_data table?

--- Table where all commands match by args and any additional data needed for the command.
---@alias MatchingCommands table<DeviceUuid, BatchedCommand>

--- Table sorted by the command name.
---@alias SortedCommandNames table<CommandName, MatchingCommands[]>

--- Sorted command batched. First sorted by the hue bridge.
---@alias SortedCommandBatch table<HueBridgeDevice, SortedCommandNames>

--- A matching group that covers some portion of a command batch.
---@alias MatchingGroups table<HueLightGroup, BatchedCommand>


local batched_command_utils = {}

local switch_on_handler = command_handlers.switch_on_handler
local switch_off_handler = command_handlers.switch_off_handler
local switch_level_handler = command_handlers.switch_level_handler
local set_color_handler = command_handlers.set_color_handler
local set_hue_handler = command_handlers.set_hue_handler
local set_saturation_handler = command_handlers.set_saturation_handler
local set_color_temp_handler = command_handlers.set_color_temp_handler

local capability_handlers = {
  [capabilities.switch.ID] = {
    [capabilities.switch.commands.on.NAME] = switch_on_handler,
    [capabilities.switch.commands.off.NAME] = switch_off_handler,
  },
  [capabilities.switchLevel.ID] = {
    [capabilities.switchLevel.commands.setLevel.NAME] = switch_level_handler,
  },
  [capabilities.colorControl.ID] = {
    [capabilities.colorControl.commands.setColor.NAME] = set_color_handler,
    [capabilities.colorControl.commands.setHue.NAME] = set_hue_handler,
    [capabilities.colorControl.commands.setSaturation.NAME] = set_saturation_handler,
  },
  [capabilities.colorTemperature.ID] = {
    [capabilities.colorTemperature.commands.setColorTemperature.NAME] = set_color_temp_handler,
  },
}

-- Mapping for fields on the device that must also match for the commands to be handled in a group.
local command_name_to_aux_fields = {
  [capabilities.colorControl.commands.setColor.NAME] = {
    Fields.GAMUT
  },
  [capabilities.colorControl.commands.setHue.NAME] = {
    Fields.GAMUT,
    Fields.COLOR_SATURATION,
  },
  [capabilities.colorControl.commands.setSaturation.NAME] = {
    Fields.GAMUT,
    Fields.COLOR_HUE,
  },
  [capabilities.colorTemperature.commands.setColorTemperature.NAME] = {
    Fields.MIN_KELVIN,
  }
}

---@param cmd BatchedCommand
---@return function?
function batched_command_utils.get_handler(cmd)
  local capability = cmd.capability_command.capability
  local command = cmd.capability_command.command
  return capability_handlers[capability] and capability_handlers[capability][command]
end

--- Sort the table by bridge, command, and matching args + any auxilary data needed for the command.
---
--- The sorted batch is first sorted in to a table with the bridge device as a key and an inner
--- table as the value.
---
--- The inner table is sorted by command name as the key and an inner array as the value.
---
--- The inner array contains tables with the device id as the key and the BatchedCommand as the
--- value where all of the BatchedCommands have matching arguments and auxilary data.
---
--- See SortedCommandBatch.
---
---@param driver HueDriver
---@param batch BatchedCommand[]
---@return SortedCommandBatch
---@return BatchedCommand[] misfits Commands that cannot be attempted to handle in a batch
function batched_command_utils.sort_batch(driver, batch)
  local sorted_batch = KVCounter()
  local misfits = {}

  for _, to_inspect in ipairs(batch) do
    -- Check if we can handle this in a batch
    if not batched_command_utils.get_handler(to_inspect) then
      misfits.insert(to_inspect)
      goto continue
    end

    -- First key off bridge.
    local device = driver:get_device_info(to_inspect.device_uuid)
    if not device then
      misfits.insert(to_inspect)
      goto continue
    end
    local parent_id = device.parent_device_id or device:get_field(Fields.PARENT_DEVICE_ID)
    local bridge_device = utils.get_hue_bridge_for_device(driver, device, parent_id, true)
    if not bridge_device then
      misfits.insert(to_inspect)
      goto continue
    end
    sorted_batch[bridge_device] = sorted_batch[bridge_device] or KVCounter()
    local by_bridge = sorted_batch[bridge_device]

    -- Next, key off the command name.
    -- Commands are unique across the capabilities supported here so avoid nesting another table
    -- with capability name.
    local command_name = to_inspect.capability_command.command
    by_bridge[command_name] = by_bridge[command_name] or KVCounter()
    local by_command = by_bridge[command_name]

    -- Add extra data that must match for the commands to be handled in a group
    to_inspect.auxilary_command_data = {}
    for _, field in ipairs(command_name_to_aux_fields[command_name] or {}) do
      to_inspect.auxilary_command_data[field] = device:get_field(field)
    end

    -- Initialize the index to the last position.
    -- This will be updated if a matching command group is found.
    local index = #by_command + 1
    -- Finally, group commands with matching bridge and command name by matching arguments
    -- and auxilary command data.
    for match_idx, matching_table in ipairs(by_command) do
      -- Grab first command, all the arguments in this table are the same so it doesn't matter.
      -- next is a defined function on KVCounter that uses a similar implementation as the default Lua next.
      local _, to_match = matching_table.next(matching_table, nil)

      if utils.deep_table_eq(to_match.capability_command.args, to_inspect.capability_command.args) and
        utils.deep_table_eq(to_match.auxilary_command_data, to_inspect.auxilary_command_data) then
        -- These commands match
        index = match_idx
        break
      end
    end
    if not by_command[index] then
      table.insert(by_command, index, KVCounter())
    end
    by_command[index][device.id] = to_inspect

    ::continue::
  end
  return sorted_batch, misfits
end

--- Find groups that the matching commands can use.
--- Larger groups are prefered and overlap is not allowed.
--- Removes commands from the provided matching commands as they are handled by matching groups.
---@param bridge_device HueBridgeDevice
---@param commands MatchingCommands
---@return MatchingGroups
function batched_command_utils.find_matching_groups(bridge_device, commands)
  local groups = bridge_device:get_field(Fields.GROUPS) or {}
  local matching_groups = {}
  -- Groups are sortered from most to least children
  for _, group in ipairs(groups) do
    if #group.devices == 0 or #group.devices > #commands then
      -- Can't match if the group has no light children or if it has more light children
      -- than is in the command
      goto continue
    end
    for _, device in ipairs(group.devices) do
      if not commands[device.id] then
        -- The commands didn't contain one of the light children for this group
        goto continue
      end
    end
    -- If we get here then we have a match. Save one of the commands for the handler
    matching_groups[group] = commands[group.devices[1].id]
    for _, device in ipairs(group.devices) do
      -- clear out commands handled by the group
      commands[device.id] = nil
    end
    if #commands == 0 then
      -- Nothing else to handle
      break
    end
    ::continue::
  end
  return matching_groups
end

return batched_command_utils


