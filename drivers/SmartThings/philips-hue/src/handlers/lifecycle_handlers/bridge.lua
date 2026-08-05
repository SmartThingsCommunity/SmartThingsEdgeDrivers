local cosock = require "cosock"
local log = require "log"

local Discovery = require "disco"
local Fields = require "fields"
local HueApi = require "hue.api"
local bridge_utils = require "utils.hue_bridge_utils"
local utils = require "utils"

local BridgeLifecycleHandlers = {}

---@param driver HueDriver
---@param device HueBridgeDevice
function BridgeLifecycleHandlers.added(driver, device)
  log.info_with({ hub_logs = true },
    string.format("Bridge Added for device %s", (device.label or device.id or "unknown device")))
  local device_bridge_id = device.device_network_id
  local bridge_info = driver.datastore.bridge_netinfo[device_bridge_id]

  if not bridge_info then
    cosock.spawn(
      function()
        local backoff_generator = utils.backoff_builder(10, 0.1, 0.1)
        local sleep_time = 0.1
        local bridge_found = false

        while true do
          log.info(
            string.format(
              "[BridgeAdded] Scanning the network for Hue Bridge matching device %s",
              (device.label or device.id or "unknown device")
            )
          )
          Discovery.search_for_bridges(driver, function(driver, bridge_ip, bridge_id)
            if bridge_id ~= device_bridge_id then return end

            log.info(string.format(
              "[BridgeAdded] Found Hue Bridge on the network for %s, querying configuration values",
              (device.label or device.id or "unknown device")
            )
            )
            bridge_info = driver.datastore.bridge_netinfo[bridge_id]

            if not bridge_info then
              log.debug(string.format("Bridge info for %s not yet available", bridge_id))
              return
            end

            if tonumber(bridge_info.swversion or "0", 10) < HueApi.MIN_CLIP_V2_SWVERSION then
              log.warn("Found bridge that does not support CLIP v2 API, ignoring")
              driver.ignored_bridges[bridge_id] = true
              return
            end

            driver.joined_bridges[bridge_id] = true
            bridge_utils.update_bridge_fields_from_info(driver, bridge_info, device)
            device:set_field(Fields._ADDED, true, { persist = true })
            bridge_found = true
          end)
          if bridge_found then return end

          if sleep_time < 10 then
            sleep_time = backoff_generator()
          end
          log.warn(
            string.format(
              "[BridgeAdded] Failed to find bridge info for device %s, waiting %s seconds then trying again",
              (device.label or device.id or "unknown device"),
              sleep_time
            )
          )
          cosock.socket.sleep(sleep_time)
        end
      end,
      "bridge added re-scan"
    )
  else
    bridge_utils.update_bridge_fields_from_info(driver, bridge_info, device)
    device:set_field(Fields._ADDED, true, { persist = true })
  end

  if not Discovery.api_keys[device_bridge_id] then
    log.error_with({ hub_logs = true },
      string.format(
        "Received `added` lifecycle event for bridge %s with unknown API key, " ..
        "please press the Link Button on your Hue Bridge(s).",
        (device.label or device.device_network_id or device.id or "unknown bridge")
      )
    )
    -- we have to do a long poll here to give the user a chance to hit the link button on the
    -- hue bridge, so in this specific pathological case we start a new coroutine and complete
    -- the handling of the device add on a different task to free up the driver task
    bridge_utils.spawn_bridge_add_api_key_task(driver, device)
    return
  end
end

---@param driver HueDriver
---@param device HueBridgeDevice
function BridgeLifecycleHandlers.init(driver, device)
  log.info(
    string.format("Init Bridge for device %s", (device.label or device.id or "unknown device")))
  local device_bridge_id = device:get_field(Fields.BRIDGE_ID)
  ---@type PhilipsHueApi
  local bridge_manager = device:get_field(Fields.BRIDGE_API) or Discovery.disco_api_instances[device_bridge_id]

  local ip = device:get_field(Fields.IPV4)
  local api_key = device:get_field(HueApi.APPLICATION_KEY_HEADER)
  local bridge_url = "https://" .. ip

  if not Discovery.api_keys[device_bridge_id] then
    log.debug(string.format(
      "init_bridge for %s, caching API key", (device.label or device.id or "unknown device")
    ))
    Discovery.api_keys[device_bridge_id] = api_key
  end

  if not bridge_manager then
    log.debug(string.format(
      "init_bridge for %s, creating bridge manager", (device.label or device.id or "unknown device")
    ))
    bridge_manager = HueApi.new_bridge_manager(
      bridge_url,
      api_key,
      utils.labeled_socket_builder((device.label or device_bridge_id or device.id or "unknown bridge"))
    )
    Discovery.disco_api_instances[device_bridge_id] = bridge_manager
  end
  device:set_field(Fields.BRIDGE_API, bridge_manager, { persist = false })

  if not driver.api_key_to_bridge_id[api_key] then
    log.debug(string.format(
      "init_bridge for %s, mapping API key to Bridge DNI", (device.label or device.id or "unknown device")
    ))
    driver.api_key_to_bridge_id[api_key] = device_bridge_id
  end

  if not driver.joined_bridges[device_bridge_id] then
    log.debug(string.format(
      "init_bridge for %s, cacheing bridge info", (device.label or device.id or "unknown device")
    ))
    cosock.spawn(
      function()
        local bridge_info
        -- create a very slow backoff
        local backoff_generator = utils.backoff_builder(10, 0.1, 0.1)
        local sleep_time = 0.1
        while true do
          log.info(
            string.format(
              "[BridgeInit] Querying bridge %s for configuration values",
              (device.label or device.id or "unknown device")
            )
          )
          bridge_info = driver.datastore.bridge_netinfo[device_bridge_id]

          if not bridge_info then
            log.debug(string.format("Bridge info for %s not yet available", device_bridge_id))
            goto continue
          else
            if tonumber(bridge_info.swversion or "0", 10) < HueApi.MIN_CLIP_V2_SWVERSION then
              log.warn("Found bridge that does not support CLIP v2 API, ignoring")
              driver.ignored_bridges[device_bridge_id] = true
              return
            end

            log.info(string.format("Bridge info for %s received, initializing network configuration", device_bridge_id))
            driver.joined_bridges[device_bridge_id] = true
            bridge_utils.do_bridge_network_init(driver, device, bridge_url, api_key)
            return
          end

          ::continue::
          if sleep_time < 10 then
            sleep_time = backoff_generator()
          end
          log.warn(
            string.format(
              "[BridgeInit] Failed to find bridge info for device %s, waiting %s seconds then trying again",
              (device.label or device.id or "unknown device"),
              sleep_time
            )
          )
          cosock.socket.sleep(sleep_time)
        end
      end,
      "bridge init"
    )
  else
    bridge_utils.do_bridge_network_init(driver, device, bridge_url, api_key)
  end
end

return BridgeLifecycleHandlers
