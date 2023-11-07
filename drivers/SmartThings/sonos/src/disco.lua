local log = require "log"
local cosock = require "cosock"
local ssdp = require "ssdp"

--- @module 'sonos.Discovery'
local Discovery = {}

--- @param driver SonosDriver
--- @param ssdp_group_info SonosSSDPInfo
--- @param known_devices_dnis table<string,boolean>
--- @param found_ip_addrs table<string,boolean>
local ssdp_discovery_callback = function(driver, ssdp_group_info, known_devices_dnis, found_ip_addrs)
  if not found_ip_addrs[ssdp_group_info.ip] then
    found_ip_addrs[ssdp_group_info.ip] = true

    local function add_device_callback(dni, inner_ssdp_group_info, player_info, group_info)
      if not known_devices_dnis[dni] then
        local name = player_info.device.name or player_info.device.modelDisplayName or "Unknown Sonos Player"
        local model = player_info.device.modelDisplayName or "Unknown Sonos Model"

        local field_cache = {
          household_id = inner_ssdp_group_info.household_id,
          player_id = player_info.playerId,
          wss_url = player_info.websocketUrl
        }

        driver._field_cache[dni] = field_cache

        driver.sonos:update_household_info(player_info.householdId, group_info)

        local create_device_msg = {
          type = "LAN",
          device_network_id = dni,
          manufacturer = "Sonos",
          label = name,
          profile = 'sonos-player',
          model = model,
          vendor_provided_label = player_info.device.model
        }

        driver:try_create_device(create_device_msg)
      end
    end

    driver:handle_ssdp_discovery(ssdp_group_info, add_device_callback)
  end
end

function Discovery.discover(driver, _, should_continue)
  log.info("Starting Sonos discovery")
  driver.found_ips = {}

  while should_continue() do
    local known_devices_dnis = {}
    local device_list = driver:get_devices()
    for _, device in ipairs(device_list) do
      local id = device.device_network_id
      known_devices_dnis[id] = true
    end

    ssdp.search(SONOS_SSDP_SEARCH_TERM, function(group_info)
      ssdp_discovery_callback(driver, group_info, known_devices_dnis, driver.found_ips)
    end)
    cosock.socket.sleep(0.1)
  end
  log.info("Ending Sonos discovery")
end

return Discovery
