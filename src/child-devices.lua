-- M. Colmenarejo 2022

local child_devices = {}

-- Global variable type table to save all child devices (device variable value) created indexed by Parent device ID (phisical device) and component name: Child_devices_created[device.parent_device_id .. component] = device
Child_devices_created = {}
-- Global variable type table to save all Parent devices (device variable value) that have child devices created, indexed by Parent device ID (phisical device): Parent_devices[device.id] = device
Parent_devices = {}

-- Create child device
function child_devices.create_new(driver, device, component)

    local label = device.label.."-"..component
    --local label = device.label..component

    if Child_devices_created[device.id .. component] == nil then
        -- save device parent table
        if Parent_devices[device.id] == nil then 
          Parent_devices[device.id] = device
        end
        print("Parent_devices[" .. device.id .."]>>>>>>", Parent_devices[device.id])
        
        if component == "main" then label = device.label.."-All Switch On-Off" end
        local metadata = {
            type = "LAN",
            device_network_id = component .. os.time(), -- DNI for Child device 
            label = label,                              -- Initial Label for Child device
            profile = "child-switch",                   -- Profile assigned to Child device created
            parent_device_id = device.id,               -- used to save parent device ID
            manufacturer = "child-device",              -- used to save type of device (need to identify if message come from Child or Parent Device)
            model = component,                          -- used to save component name of the parent device
            vendor_provided_label = device.id           -- used to save parent device ID (do not need now)
        }
        
        -- Create new device
        driver:try_create_device(metadata)

      end

end

  return child_devices