local cosock = require "cosock"
local log = require "log"
local st_utils = require "st.utils"
-- trick to fix the VS Code Lua Language Server typechecking
---@type fun(val: any?, name: string?, multi_line: boolean?): string
st_utils.stringify_table = st_utils.stringify_table

local Discovery = require "disco"
local Fields = require "fields"
local HueApi = require "hue.api"
local HueDeviceTypes = require "hue_device_types"

local utils = require "utils"

---@type { lifecycle_handlers: LifecycleHandlers }
local lazy_handlers = utils.lazy_handler_loader("handlers")

---@type { [string]: DiscoveredChildDeviceHandler }
local lazy_disco_handlers = utils.lazy_handler_loader("disco")

---@class StrayDeviceHelper
local StrayDeviceHelper = {}

---@enum MessageTypes
local MessageTypes = {
  FoundBridge = "FOUND_BRIDGE",
  NewStrayDevice = "NEW_STRAY_DEVICE",
}
StrayDeviceHelper.MessageTypes = MessageTypes

--- The bridge a stray device belongs to: its parent (or, for the extra services of a compound
--- device, its grandparent), or for a light migrated from the DTH integration, which has no parent,
--- the bridge its DTH API key belongs to.
---
--- A stray is only ever resolved by its own bridge. A Hue Bridge Pro keeps the resource IDs of the
--- devices migrated to it, so the records created for the old bridge share resource IDs with the
--- new bridge's records; resolving them against the new bridge would have them take over those
--- devices. They wait for their own bridge instead.
---@param driver HueDriver
---@param stray_device HueChildDevice
---@return HueBridgeDevice?
function StrayDeviceHelper.bridge_for_stray(driver, stray_device)
  if utils.is_dth_light(stray_device) then
    local api_key = stray_device.data and stray_device.data.username
    local bridge_dni = api_key and driver.api_key_to_bridge_id[api_key]
    return bridge_dni and driver:get_device_by_dni(bridge_dni) or nil
  end
  return utils.get_hue_bridge_for_device(driver, stray_device, nil, true)
end

--- Whether the stray device belongs to the bridge `bridge_device_uuid` (see `bridge_for_stray`).
---@param driver HueDriver
---@param stray_device HueChildDevice
---@param bridge_device_uuid string?
---@return boolean
function StrayDeviceHelper.stray_belongs_to_bridge(driver, stray_device, bridge_device_uuid)
  local bridge = StrayDeviceHelper.bridge_for_stray(driver, stray_device)
  return bridge ~= nil and bridge_device_uuid ~= nil and bridge.id == bridge_device_uuid
end

--- Whether any queued stray belongs to the bridge `bridge_device_uuid`.
---@param driver HueDriver
---@param stray_devices table<string,HueChildDevice>
---@param bridge_device_uuid string
---@return boolean
function StrayDeviceHelper.bridge_has_strays(driver, stray_devices, bridge_device_uuid)
  for _, stray_device in pairs(stray_devices) do
    if StrayDeviceHelper.stray_belongs_to_bridge(driver, stray_device, bridge_device_uuid) then
      return true
    end
  end
  return false
end

local function check_strays_for_match(hue_driver, api_instance, stray_devices, bridge_device_uuid, device_data, svc_info)
  for _, stray_device in pairs(stray_devices) do
    -- Only this bridge's own strays can match (see `bridge_for_stray`).
    local matching_v1_id, matching_uuid = false, false
    if StrayDeviceHelper.stray_belongs_to_bridge(hue_driver, stray_device, bridge_device_uuid) then
      matching_v1_id = stray_device.data and stray_device.data.bulbId and
          stray_device.data.bulbId == (device_data.id_v1 or ""):gsub("/lights/", "")
      matching_uuid = utils.get_hue_rid(stray_device) == svc_info.rid or
          stray_device.device_network_id == svc_info.rid
    end

    if matching_v1_id or matching_uuid then
      stray_device:set_field(Fields.RESOURCE_ID, svc_info.rid, { persist = true })
      local api_key_extracted = api_instance.headers["hue-application-key"]
      log.info_with({ hub_logs = true }, " ", (stray_device.label or stray_device.id or "unknown device"),
        ", re-adding")
      log.info_with({ hub_logs = true }, string.format(
        'Found Bridge for stray device %s, retrying onboarding flow.\n' ..
        '\tMatching v1 id? %s\n' ..
        '\tMatching uuid? %s\n' ..
        '\tdevice DNI: %s\n' ..
        '\tdevice Parent Assigned Key: %s\n' ..
        '\tdevice parent device id: %s\n' ..
        '\tProvided bridge_device_id: %s\n' ..
        '\tAPI key cached for given bridge_device_id? %s\n' ..
        '\tCached bridge device for given API key: %s\n'
        ,
        stray_device.label,
        matching_v1_id,
        matching_uuid,
        stray_device.device_network_id,
        stray_device.parent_assigned_child_key,
        stray_device.parent_device_id,
        bridge_device_uuid,
        (Discovery.api_keys[hue_driver:get_device_info(bridge_device_uuid).device_network_id] ~= nil),
        hue_driver.api_key_to_bridge_id[api_key_extracted]
      ))
      break
    end
  end
end

---@param driver HueDriver
---@param strays table<string,HueChildDevice>
---@param bridge_device_uuid string
function StrayDeviceHelper.process_strays(driver, strays, bridge_device_uuid)
  local bridge_device = driver:get_device_info(bridge_device_uuid)
  local bridge_state_cache = bridge_device and Discovery.state_cache_for_bridge(bridge_device.device_network_id)
  if not bridge_state_cache then return end
  ---@type string[]
  local dnis_to_remove = {}
  for _, device in pairs(strays) do
    -- Strays belonging to other bridges wait for their own bridge (see `bridge_for_stray`).
    if not StrayDeviceHelper.stray_belongs_to_bridge(driver, device, bridge_device_uuid) then
      goto continue
    end
    do
      local device_rid, err = utils.get_hue_rid(device)
      if err or not device_rid then
        log.warn(tostring(err) or "could not determine device resource ID, continuing")
        goto continue
      end
      if bridge_state_cache[device_rid] then
        table.insert(dnis_to_remove, device.device_network_id)
        lazy_handlers.lifecycle_handlers.initialize_device(
          driver, device, "added", nil, bridge_device_uuid, device_rid
        )
      end
    end
    ::continue::
  end

  for _, dni in ipairs(dnis_to_remove) do
    strays[dni] = nil
  end
end

---@param hue_driver HueDriver
---@param bridge_network_id string
---@param api_instance PhilipsHueApi
---@param primary_services HueServiceInfo
---@param device_data HueDeviceInfo
---@param msg_device HueDevice
---@param bridge_device_uuid string
---@param stray_devices table<string,HueChildDevice>
function StrayDeviceHelper.discovery_callback(
    hue_driver, bridge_network_id, api_instance, primary_services,
    device_data, msg_device, bridge_device_uuid, stray_devices
)
  -- `primary_services` maps each service type to the list of the device's services of that type.
  for rtype, services in pairs(primary_services) do
    if not (HueDeviceTypes.can_join_device_for_service(rtype)) then goto next_rtype end
    do
      -- The disco handler builds the state for all of a device's services of its type at once.
      local state_cached = false
      for _, svc_info in ipairs(services) do
        local service_resource, rest_err, _ = api_instance:get_rtype_by_rid(svc_info.rtype, svc_info.rid)
        if rest_err ~= nil or not service_resource then
          log.error_with({ hub_logs = true }, string.format(
            "Error getting device info info while processing new bridge %s: %s",
            (msg_device.label or msg_device.id or "unknown device"), rest_err
          ))
          return
        end

        if service_resource.errors and #service_resource.errors > 0 then
          log.error_with({ hub_logs = true }, "Errors found in API response:")
          for idx, resource_err in ipairs(service_resource.errors) do
            log.error_with({ hub_logs = true }, string.format(
              "Error Number %s in get_rtype_by_rid response while onboarding bridge %s: %s",
              idx,
              (msg_device.label or msg_device.id or "unknown device"),
              st_utils.stringify_table(resource_err)
            ))
          end
          return
        end

        if service_resource.data and #service_resource.data > 0 then
          if not state_cached then
            lazy_disco_handlers[rtype].handle_discovered_device(
              hue_driver,
              bridge_network_id,
              api_instance,
              primary_services,
              device_data,
              Discovery.state_cache_for_bridge(bridge_network_id),
              nil
            )
            state_cached = true
          end

          check_strays_for_match(
            hue_driver,
            api_instance,
            stray_devices,
            bridge_device_uuid,
            device_data,
            svc_info
          )
        end
      end
    end
    ::next_rtype::
  end

end

--- Spawn the stray device resolution task, returning a handle to the tx side of the
--- channel for controlling it.
function StrayDeviceHelper.spawn()
  local stray_device_tx, stray_device_rx = cosock.channel.new()
  stray_device_rx:settimeout(30)

  cosock.spawn(function()
    ---@type table<string,HueChildDevice>
    local stray_devices = {}
    ---@type table<string,HueBridgeDevice>
    local found_bridges = {}
    ---@type HueDriver?
    local thread_local_driver = nil

    while true do
      local msg, err = stray_device_rx:receive()
      if err and err ~= "timeout" then
        log.error_with({ hub_logs = true }, "Cosock Receive Error: ", err)
        goto continue
      end

      if err == "timeout" then
        if next(stray_devices) ~= nil and next(found_bridges) ~= nil and thread_local_driver ~= nil then
          -- Only rescan the bridges that have strays of their own; a stray whose bridge hasn't been
          -- found (e.g. one replaced by a Hue Bridge Pro) waits for it.
          for _, bridge in pairs(found_bridges) do
            if StrayDeviceHelper.bridge_has_strays(thread_local_driver, stray_devices, bridge.id) then
              log.info_with({ hub_logs = true }, string.format(
                "No new stray devices received but some remain in queue for bridge %s, attempting to resolve them",
                (bridge.label or bridge.device_network_id or bridge.id or "unknown bridge")
              ))
              stray_device_tx:send({
                type = StrayDeviceHelper.MessageTypes.FoundBridge,
                driver = thread_local_driver,
                device = bridge
              })
            end
          end
        end
        goto continue
      end

      do
        local msg_device = msg.device
        thread_local_driver = msg.driver
        if msg.type == StrayDeviceHelper.MessageTypes.FoundBridge then
          local bridge_ip = msg_device:get_field(Fields.IPV4)
          local api_instance =
              msg_device:get_field(Fields.BRIDGE_API) --[[@as PhilipsHueApi]]
              or Discovery.disco_api_instances[msg_device.device_network_id]

          if not api_instance then
            api_instance = HueApi.new_bridge_manager(
              "https://" .. bridge_ip,
              msg_device:get_field(HueApi.APPLICATION_KEY_HEADER),
              utils.labeled_socket_builder((msg_device.label or msg_device.device_network_id or msg_device.id or "unknown bridge"))
            )
            Discovery.disco_api_instances[msg_device.device_network_id] = api_instance
          end

          found_bridges[msg_device.id] = msg.device
          local bridge_device_uuid = msg_device.id

          if StrayDeviceHelper.bridge_has_strays(thread_local_driver, stray_devices, bridge_device_uuid) then
            log.info(
              string.format(
                "Stray devices handler notified of new bridge %s, scanning bridge",
                (msg.device.label or msg.device.device_network_id or msg.device.id or "unknown bridge")
              )
            )
            Discovery.search_bridge_for_supported_devices(thread_local_driver,
              msg_device:get_field(Fields.BRIDGE_ID),
              api_instance,
              function(driver, bridge_network_id, primary_services, device_data)
                StrayDeviceHelper.discovery_callback(
                  driver,
                  bridge_network_id,
                  api_instance,
                  primary_services,
                  device_data,
                  msg_device,
                  bridge_device_uuid,
                  stray_devices
                )
              end,
              "[process_strays]"
            )
            log.info(string.format(
              "Finished querying bridge %s for devices from stray devices handler",
              (msg.device.label or msg.device.device_network_id or msg.device.id or "unknown bridge")
            )
            )
            StrayDeviceHelper.process_strays(thread_local_driver, stray_devices, msg_device.id)
          end
        elseif msg.type == StrayDeviceHelper.MessageTypes.NewStrayDevice then
          stray_devices[msg_device.device_network_id] = msg_device

          local maybe_bridge = utils.get_hue_bridge_for_device(thread_local_driver, msg_device)

          if maybe_bridge ~= nil then
            local bridge_ip = maybe_bridge:get_field(Fields.IPV4)
            local api_instance =
                maybe_bridge:get_field(Fields.BRIDGE_API) --[[@as PhilipsHueApi]]
                or Discovery.disco_api_instances[maybe_bridge.device_network_id]

            if not api_instance and bridge_ip then
              api_instance = HueApi.new_bridge_manager(
                "https://" .. bridge_ip,
                maybe_bridge:get_field(HueApi.APPLICATION_KEY_HEADER),
                utils.labeled_socket_builder((maybe_bridge.label or maybe_bridge.device_network_id or maybe_bridge.id or "unknown bridge"))
              )
              Discovery.disco_api_instances[maybe_bridge.device_network_id] = api_instance
            end

            if api_instance then
              StrayDeviceHelper.process_strays(thread_local_driver, stray_devices, maybe_bridge.id)
            end
          end
        end
      end
      ::continue::
      if next(stray_devices) ~= nil then
        local stray_devices_pseudo_json = "{\"stray_devices\":["
        for _, device in pairs(stray_devices) do
          stray_devices_pseudo_json = stray_devices_pseudo_json ..
              string.format(
                [[{"label":"%s","dni":"%s","device_id":"%s"},]],
                (device.label or device.id or "unknown device"),
                device.device_network_id,
                device.id
              )
        end
        -- strip trailing comma and close array/root object
        stray_devices_pseudo_json = stray_devices_pseudo_json:sub(1, -2) .. "]}"
        log.info_with({ hub_logs = true },
          string.format("Stray device loop end, unprocessed devices: %s", stray_devices_pseudo_json))
      end
    end
  end, "Stray Hue Device Resolution Task")
  return stray_device_tx
end

return StrayDeviceHelper
