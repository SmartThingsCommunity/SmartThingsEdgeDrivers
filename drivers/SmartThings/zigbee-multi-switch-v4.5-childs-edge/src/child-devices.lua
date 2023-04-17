-- M. Colmenarejo 2022
-- Modified to use EDGE_CHILD type

local child_devices = {}

-- Create child device
function child_devices.create_new_device(driver, device, component, profile_type)

    local label = component.. "-"..device.label
      if not device:get_child_by_parent_assigned_key(component) then
        if component == "main" then label = "All Switch On-Off".. "-".. device.label end
        local metadata = {
            type = "EDGE_CHILD", 
            label = label,                              -- Initial Label for Child device
            profile = profile_type,                     -- Profile assigned to Child device created
            parent_device_id = device.id,               -- used to save parent device ID
            parent_assigned_child_key = component,      -- used as libraries parent_assigned_child_key
            vendor_provided_label = profile_type        -- used to save profile_type to easy recovery with device.vendor_provided_label
        }
        
        -- Create new device
        driver:try_create_device(metadata)

      end

end

  return child_devices