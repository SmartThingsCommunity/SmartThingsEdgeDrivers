local Driver = require "st.driver"

local capabilities = require "st.capabilities"
local cosock = require "cosock"
local log = require "log"

local Discovery = require "disco"
local Fields = require "fields"
local HueApi = require "hue.api"
local StrayDeviceHelper = require "stray_device_helper"

local command_handlers = require "handlers.commands"
local lifecycle_handlers = require "handlers.lifecycle_handlers"

local bridge_utils = require "utils.hue_bridge_utils"
local utils = require "utils"

---@param driver HueDriver
---@param device HueDevice
local function _remove(driver, device)
  driver.datastore.dni_to_device_id[device.device_network_id] = nil
  if utils.determine_device_type(device) == "bridge" then
    local api_instance = device:get_field(Fields.BRIDGE_API) --[[@as PhilipsHueApi]]
    if api_instance then
      api_instance:shutdown()
      device:set_field(Fields.BRIDGE_API, nil)
    end

    local event_source = device:get_field(Fields.EVENT_SOURCE)
    if event_source then
      event_source:close()
      device:set_field(Fields.EVENT_SOURCE, nil)
    end


    -- This operation will be committed to the datastore
    -- immediately, see the note in init.lua#L57
    Discovery.api_keys[device.device_network_id] = nil
  end
end


-- Discovery Handler
local disco = Discovery.discover

-- Lifecycle Handlers
local added = utils.safe_wrap_handler(lifecycle_handlers.initialize_device)
local init = utils.safe_wrap_handler(lifecycle_handlers.initialize_device)
local removed = utils.safe_wrap_handler(_remove)

-- Capability Command Handlers
local refresh_handler = utils.safe_wrap_handler(command_handlers.refresh_handler)
local switch_on_handler = utils.safe_wrap_handler(command_handlers.switch_on_handler)
local switch_off_handler = utils.safe_wrap_handler(command_handlers.switch_off_handler)
local switch_level_handler = utils.safe_wrap_handler(command_handlers.switch_level_handler)
local set_color_handler = utils.safe_wrap_handler(command_handlers.set_color_handler)
local set_hue_handler = utils.safe_wrap_handler(command_handlers.set_hue_handler)
local set_saturation_handler = utils.safe_wrap_handler(command_handlers.set_saturation_handler)
local set_color_temp_handler = utils.safe_wrap_handler(command_handlers.set_color_temp_handler)

--- @class HueDriverDatastore
--- @field public bridge_netinfo table<string,HueBridgeInfo>
--- @field public dni_to_device_id table<string,string>
--- @field public api_keys table<string,string>
--- @field public commit fun(self: HueDriverDatastore)|nil
--- @field public save fun(self: HueDriverDatastore)

--- @class HueDriver:Driver
--- @field public ignored_bridges table<string,boolean>
--- @field public joined_bridges table<string,boolean>
--- @field public hue_identifier_to_device_record table<string,HueChildDevice>
--- @field public services_for_device_rid table<string,table<string,string>> Map the device resource ID to another map that goes from service rid to service rtype
--- @field public waiting_grandchildren table<string,{ waiting_resource_info: HueResourceInfo, join_callback: fun(driver: HueDriver, waiting_resource_info: HueResourceInfo, parent_device: HueChildDevice)}[]>?
--- @field public stray_device_tx table cosock channel
--- @field public datastore HueDriverDatastore persistent store
--- @field public api_key_to_bridge_id table<string,string>
--- @field public _devices_pending_refresh table<string,HueChildDevice>
--- @field public get_devices fun(self: HueDriver): HueChildDevice[]
--- @field public get_device_info fun(self: HueDriver, device_id: string, force_refresh: boolean?): HueDevice?
local HueDriver = {}

function HueDriver.new_driver_template(dbg_config)
  local stray_device_tx = StrayDeviceHelper.spawn()
  local template = {
    discovery = disco,
    lifecycle_handlers = { added = added, init = init, removed = removed },
    capability_handlers = {
      [capabilities.refresh.ID] = {
        [capabilities.refresh.commands.refresh.NAME] = refresh_handler,
      },
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
    },
    ignored_bridges = {},
    joined_bridges = {},
    hue_identifier_to_device_record = {},
    services_for_device_rid = {},
    -- the only real way we have to know which bridge a bulb wants to use at migration time
    -- is by looking at the stored api key so we will make a map to look up bridge IDs with
    -- the API key as the map key.
    api_key_to_bridge_id = {},
    stray_device_tx = stray_device_tx,
    _devices_pending_refresh = {}
  }

  -- What's going on here is that a driver template can't utilize metatables, because the metatable
  -- won't get reflected in to the driver. But if you want to attach custom functionality to a driver,
  -- such as custom methods, you won't get proper IDE support to go to the definition. We've defined the
  -- custom behavior here on this "class", and then attach the customizations directly to the template like
  -- this so that we get the best of both worlds; you can jump to definition on a function in this file, and
  -- it gets attached to the driver built out of the template returned here.
  for k, v in pairs(HueDriver) do
    template[k] = v
  end

  if type(dbg_config) == "table" and dbg_config.enable_debug then
    local hue_debug = require "hue_debug"
    hue_debug.enable_dbg_config(template, dbg_config)
  end

  return template
end

function HueDriver:run()
  self.__running = true
  Driver.run(self)
end

---@param grandchild_devices { waiting_resource_info: HueResourceInfo, join_callback: fun(driver: HueDriver, waiting_resource_info: HueResourceInfo, parent_device: HueChildDevice)}[]
---@param waiting_for string
function HueDriver:queue_grandchild_device_for_join(grandchild_devices, waiting_for)
  self.waiting_grandchildren = self.waiting_grandchildren or {}

  for _, waiting_info in ipairs(grandchild_devices) do
    self.waiting_grandchildren[waiting_for] = self.waiting_grandchildren[waiting_for] or {}
    table.insert(self.waiting_grandchildren[waiting_for], waiting_info)
  end
end

---@param new_device HueChildDevice
function HueDriver:check_waiting_grandchildren_for_device(new_device)
  if not self.waiting_grandchildren then
    return
  end
  local rid = utils.get_hue_rid(new_device)
  for _, waiting in pairs(self.waiting_grandchildren[rid or ""] or {}) do
    local waiting_info = waiting.waiting_resource_info
    local join_callback = waiting.join_callback
    if type(join_callback) == "function" then
      cosock.spawn(function()
        join_callback(self, waiting_info, new_device)
      end)
    end
  end
end

---@param bridge_network_id string
---@param bridge_info HueBridgeInfo
function HueDriver:update_bridge_netinfo(bridge_network_id, bridge_info)
  if self.joined_bridges[bridge_network_id] then
    local bridge_device = self:get_device_by_dni(bridge_network_id) --[[@as HueBridgeDevice]]
    if not bridge_device then
      log.warn_with({ hub_logs = true },
        string.format(
          "Couldn't locate bridge device for joined bridge with DNI %s",
          bridge_network_id
        )
      )
      return
    end

    if bridge_info.ip ~= bridge_device:get_field(Fields.IPV4) then
      bridge_utils.update_bridge_fields_from_info(self, bridge_info, bridge_device)
      local maybe_api_client = bridge_device:get_field(Fields.BRIDGE_API) --[[@as PhilipsHueApi]]
      local maybe_api_key = bridge_device:get_field(HueApi.APPLICATION_KEY_HEADER) or Discovery.api_keys[bridge_network_id]
      local maybe_event_source = bridge_device:get_field(Fields.EVENT_SOURCE)
      local bridge_url = "https://" .. bridge_info.ip

      if maybe_api_key then
        if maybe_api_client then
          maybe_api_client:update_connection(bridge_url, maybe_api_key)
        end

        if maybe_event_source then
          maybe_event_source:close()
          bridge_device:set_field(Fields.EVENT_SOURCE, nil)
          bridge_utils.do_bridge_network_init(self, bridge_device, bridge_url, maybe_api_key)
        end
      end
    end
  end
end

---@param dni string
---@param force_refresh boolean?
---@return HueDevice?
function HueDriver:get_device_by_dni(dni, force_refresh)
  local device_uuid = self.datastore.dni_to_device_id[dni]
  if not device_uuid then return nil end
  return self:get_device_info(device_uuid, force_refresh)
end

---@param device HueDevice
function HueDriver:do_hue_child_delete(device)
  if type(self.try_delete_device) ~= "function" then
    local _log = device.log or log
    _log.warn("Requesting device delete on API version that doesn't support it. Marking device offline.")
    device:offline()
    return
  end

  self:try_delete_device(device.id)
end

local function supports_switch(hue_repr)
  return
      hue_repr.on ~= nil
      and type(hue_repr.on) == "table"
      and type(hue_repr.on.on) == "boolean"
end

local function supports_switch_level(hue_repr)
  return
      hue_repr.dimming ~= nil
      and type(hue_repr.dimming) == "table"
      and type(hue_repr.dimming.brightness) == "number"
end

local function supports_color_temp(hue_repr)
  return
      hue_repr.color_temperature ~= nil
      and type(hue_repr.color_temperature) == "table"
      and next(hue_repr.color_temperature) ~= nil
end

local function supports_color_control(hue_repr)
  return
      hue_repr.color ~= nil
      and type(hue_repr.color) == "table"
      and type(hue_repr.color.xy) == "table"
      and type(hue_repr.color.gamut) == "table"
end

---@type table<string,fun(hue_repr: table): boolean>
local support_check_handlers = {
  [capabilities.switch.ID] = supports_switch,
  [capabilities.switchLevel.ID] = supports_switch_level,
  [capabilities.colorControl.ID] = supports_color_control,
  [capabilities.colorTemperature.ID] = supports_color_temp
}

---@param hue_repr table
---@param capability_id string
---@return boolean
function HueDriver.check_hue_repr_for_capability_support(hue_repr, capability_id)
  local handler = support_check_handlers[capability_id]
  if type(handler) == "function" then
    return handler(hue_repr)
  else
    return false
  end
end

return HueDriver
