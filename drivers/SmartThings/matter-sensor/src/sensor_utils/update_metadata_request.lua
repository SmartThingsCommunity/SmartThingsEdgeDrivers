-- Copyright 2026 SmartThings, Inc.
-- Licensed under the Apache License, Version 2.0

local UpdateMetadataRequest = {}
UpdateMetadataRequest.__index = UpdateMetadataRequest

function UpdateMetadataRequest.init()
  local self = setmetatable({}, UpdateMetadataRequest)
  self.profile = nil
  self.enabled_components = {}
  return self
end

function UpdateMetadataRequest:add_capabilities_to_component(component_id, capability_ids)
  if not self.enabled_components[component_id] then
    self.enabled_components[component_id] = {}
  end
  for _, capability_id in ipairs(capability_ids) do
    table.insert(self.enabled_components[component_id], capability_id)
  end
  return self
end

function UpdateMetadataRequest:add_profile(profile)
  self.profile = profile
  return self
end

function UpdateMetadataRequest:formatted_enabled_components()
  local formatted_enabled_components = {}
  for component_id, capability_ids in pairs(self.enabled_components) do
    table.insert(formatted_enabled_components, { component_id, capability_ids })
  end
  return formatted_enabled_components
end

function UpdateMetadataRequest:format()
  local formatted_request = {
    profile = self.profile,
    optional_component_capabilities = self:formatted_enabled_components()
  }
  return formatted_request
end

return UpdateMetadataRequest
