local log = require("log")

-- Local imports
local utils = require("utils")
local fields = require("fields")
local api = require("abb.api")
local device_refresher = require("abb.device_refresher")

-- Device manager methods
local device_manager = {}

-- Method for checking if connection is valid
function device_manager.is_valid_connection(driver, device, conn_info)
    local dni = utils.get_dni_from_device(device)

    if not conn_info then
        log.error("device_manager.is_valid_connection(): Failed to find conn_info, dni = " .. dni)
        return false
    end

    local bridge_ip = utils.get_device_ip_address(device)
    local thing_infos = api.get_thing_infos(bridge_ip, dni)

    if thing_infos and thing_infos.devices then
        return true
    else
        log.error("device_manager.is_valid_connection(): Failed to get thing infos, dni = " .. dni)
        return false
    end
end

-- Method for getting bridge connection info
function device_manager.get_bridge_connection_info(driver, bridge_dni, bridge_ip)
    local bridge_conn_info = api.new_bridge_manager(bridge_ip, bridge_dni)

    if bridge_conn_info == nil then
        log.error("device_manager.get_bridge_connection_info(): No bridge connection info")
    end

    return bridge_conn_info
end

-- Method for handling JSON status
function device_manager.handle_device_json(driver, device, device_json)
    local dni = utils.get_dni_from_device(device)
    if dni == nil then
        log.error("device_manager.handle_device_json(): dni is nil, the device has been probably deleted")
        return
    end

    if not device_json then
        log.error("device_manager.handle_device_json(): device_json is nil, dni = " .. dni)
        return
    end

    log.debug("device_manager.handle_device_json(): dni: " .. dni .. " device_json = " .. utils.dump(device_json))

    local status = device_json.status
    if status ~= nil then
        if status == "offline" then
            log.info("device_manager.handle_device_json(): status is offline, dni = " .. dni)

            device:offline()
            return
        elseif status == "online" then
            device:online()
        end
    end

    local values = device_json.values
    if values == nil then
        log.error("device_manager.handle_device_json(): values is nil, dni = " .. dni)
        return
    end

    device_refresher.refresh_device(driver, device, values)
end

-- Method for refreshing device
function device_manager.refresh(driver, device)
    local dni = utils.get_dni_from_device(device)
    local communication_device = device:get_parent_device() or device
    local conn_info = communication_device:get_field(fields.CONN_INFO)

    if not conn_info then
        log.warn("device_manager.refresh(): Failed to find conn_info, dni = " .. dni)
        return
    end

    local response, err, status = conn_info:get_device_by_id(dni)

    if err or status ~= 200 then
        status = status or "nil"
        log.error("device_manager.refresh(): Failed to get device by id, dni = " .. dni .. ", err = " .. err .. ", status = " .. status)

        if status == 404 then
            log.info("device_manager.refresh(): Deleted, dni = " .. dni)

            device:offline()
        end

        return
    end

    device_manager.handle_device_json(driver, device, response)
end

-- Method for monitoring the connection of the bridge devices
function device_manager.bridge_monitor(driver, device, bridge_info)
    local child_devices = device:get_child_list()
    
    for _, thing_device in ipairs(child_devices) do
        device.thread:call_with_delay(0, function()  -- Run within bridge thread to use the same connection
            device_manager.refresh(driver, thing_device)
        end)
    end
end

return device_manager