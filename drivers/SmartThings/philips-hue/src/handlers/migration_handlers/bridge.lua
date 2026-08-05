local cosock = require "cosock"
local log = require "log"

local Discovery = require "disco"
local HueApi = require "hue.api"
local utils = require "utils"

---@class BridgeMigrationHandler
local BridgeMigrationHandler = {}

---comment
---@param driver HueDriver
---@param device HueBridgeDevice
---@param lifecycle_handlers LifecycleHandlers
function BridgeMigrationHandler.migrate(driver, device, lifecycle_handlers)
  log.info_with({ hub_logs = true },
    string.format("Migrate Bridge for device %s", (device.label or device.id or "unknown device")))
  local api_key = device.data.username
  local device_dni = device.device_network_id

  log.info(
    string.format("Rediscovering bridge for migrated device %s", (device.label or device.id or "unknown device")))
  cosock.spawn(
    function()
      local bridge_found = false
      local backoff_generator = utils.backoff_builder(10, 0.1, 0.1)
      local sleep_time = 0.1
      while true do
        log.info(
          string.format(
            "[MigrateBridge] Scanning for Hue Bridge info for migrated device %s",
            (device.label or device.id or "unknown device")
          )
        )
        Discovery.search_for_bridges(driver, function(hue_driver, bridge_ip, bridge_id)
          if bridge_id ~= device_dni then return end

          log.info(
            string.format(
              "[MigrateBridge] Matching Hue Bridge for migrated device %s found, querying configuration values",
              (device.label or device.id or "unknown device")
            )
          )

          local bridge_info = driver.datastore.bridge_netinfo[bridge_id]

          if not bridge_info then
            log.debug(string.format("Bridge info for %s not yet available", bridge_id))
            return
          end

          if tonumber(bridge_info.swversion or "0", 10) < HueApi.MIN_CLIP_V2_SWVERSION then
            log.warn("Found bridge that does not support CLIP v2 API, ignoring")
            hue_driver.ignored_bridges[bridge_id] = true
            return
          end

          hue_driver.joined_bridges[bridge_id] = true
          Discovery.api_keys[bridge_id] = api_key

          local new_metadata = {
            profile = "hue-bridge",
            manufacturer = "Signify Netherlands B.V.",
            model = bridge_info.modelid or "BSB002",
            vendor_provided_label = (bridge_info.name or "Philips Hue Bridge"),
          }

          device:try_update_metadata(new_metadata)
          log.info_with({ hub_logs = true },
            string.format("Bridge %s Migrated, re-adding", (device.label or device.id or "unknown device")))
          log.debug(string.format(
            "Re-requesting added handler for %s after migrating", (device.label or device.id or "unknown device")
          ))
          lifecycle_handlers.device_added(hue_driver, device)
          log.debug(string.format(
            "Re-requesting init handler for %s after migrating", (device.label or device.id or "unknown device")
          ))
          lifecycle_handlers.device_init(hue_driver, device)
          bridge_found = true
        end)
        if bridge_found then return end

        if sleep_time < 10 then
          sleep_time = backoff_generator()
        end
        log.warn(
          string.format(
            "[MigrateBridge] Failed to find bridge info for device %s, waiting %s seconds then trying again",
            (device.label or device.id or "unknown device"),
            sleep_time
          )
        )
        cosock.socket.sleep(sleep_time)
      end
    end,
    string.format("bridge migration thread for %s", device.label)
  )
end

return BridgeMigrationHandler
