---@diagnostic disable: undefined-field, duplicate-set-field, invisible
local test = require "integration_test.cosock_runner"
local test_utils = require "integration_test.utils"

local helpers = require "test.helpers"
local mock_hue_bridge = require "test.mock_hue_bridge"

local Discovery = require "disco"
local Fields = require "fields"
local HueApi = require "hue.api"

local m = {
  mock_hue_bridge = nil,
  driver_under_test = nil
}

local raw_get_resource = HueApi.get_rtype_by_rid
HueApi.get_rtype_by_rid = function(self, rtype, rid)
  local ret, err
  repeat
    ret, err = raw_get_resource(self, rtype, rid)
  until ret ~= nil or (type(err) == "string" and err ~= "timeout")
  return ret, err
end

local raw_get_all = HueApi.get_all_reprs_for_rtype
HueApi.get_all_reprs_for_rtype = function(self, rtype)
  local ret, err
  repeat
    ret, err = raw_get_all(self, rtype)
  until ret ~= nil or (type(err) == "string" and err ~= "timeout")
  return ret, err
end

local original_try_create
function m.driver_env_init(driver)
  original_try_create = original_try_create or driver.try_create_device
  driver.try_create_device = function(self, metadata)
    local ret = original_try_create(self, metadata)
    test.wait_for_events()
    return ret
  end
end

function m.testenv_init()
  test.socket:set_time_advance_per_select(1)
  test.mock_devices_api._create_mock_devices = true
  m.create_mock_hue_bridge()
end

function m.testenv_cleanup()
  if m.mock_hue_bridge and m.mock_hue_bridge.mock_server then
    m.mock_hue_bridge:stop()
    m.mock_hue_bridge = nil
  end

  if m.driver_under_test then
    m.driver_under_test.datastore["bridge_netinfo"] = {}
    m.driver_under_test.datastore["dni_to_device_id"] = {}
    m.driver_under_test.datastore["api_keys"] = {}
  end

  Discovery.disco_api_instances = {}
  Discovery.api_keys = {}
end

function m.generate_mock_bridge_info()
  return helpers.hue_bridge.random_bridge_info()
end

function m.create_mock_hue_bridge(mock_bridge_info)
  if not mock_bridge_info then
    mock_bridge_info = m.generate_mock_bridge_info()
  end
  m.mock_hue_bridge = mock_hue_bridge.new(mock_bridge_info)
end

-- Luxure servers expect a connection-per-request behavior,
-- and by default the Hue driver tries to keep its client
-- connection open forever. We use Luxure to create the mock
-- REST server, so this is a convenience function for resetting
-- the bridge's API client if a test needs to make multiple requests.
function m.reset_api_client(mock_bridge_device)
  local existing_api_instance =
      mock_bridge_device:get_field(Fields.BRIDGE_API) or
      Discovery.disco_api_instances[mock_bridge_device.device_network_id]

  mock_bridge_device:set_field(Fields.BRIDGE_API, nil, { persist = false })
  Discovery.disco_api_instances[mock_bridge_device.device_network_id] = nil
  if existing_api_instance then
    existing_api_instance:shutdown()
    test.wait_for_events()

    local api_instance = HueApi.new_bridge_manager(
      "https://" .. mock_bridge_device:get_field(Fields.IPV4),
      mock_bridge_device:get_field(Fields.APPLICATION_KEY_HEADER),
      helpers.socket.mock_labeled_socket_builder('[Hue Bridge API Instance] ')
    )

    mock_bridge_device:set_field(Fields.BRIDGE_API, api_instance, { persist = false })
    Discovery.disco_api_instances[mock_bridge_device.device_network_id] = api_instance
  end
end

function m.create_already_onboarded_bridge_device(driver_under_test)
  local mock_bridge_info
  if not m.mock_hue_bridge then
    mock_bridge_info = m.generate_mock_bridge_info()
    m.create_mock_hue_bridge(mock_bridge_info)
    assert(m.mock_hue_bridge)
  else
    mock_bridge_info = m.mock_hue_bridge.bridge_info
  end

  local mock_bridge_device = test.mock_device.build_test_lan_device({
    profile = test_utils.get_profile_definition("hue-bridge.yml"),
    device_network_id = mock_bridge_info.bridgeid,
    label = mock_bridge_info.name,
    manufacturer = "Signify Netherlands B.V.",
    model = mock_bridge_info.modelid,
    vendor_provided_label = mock_bridge_info.name
  })


  local bridge_api_key = helpers.hue_bridge.random_hue_bridge_key()
  m.mock_hue_bridge:set_hue_application_key(bridge_api_key)

  mock_bridge_device:set_field(Fields._ADDED, true, { persist = true })
  mock_bridge_device:set_field(Fields._REFRESH_AFTER_INIT, false, { persist = true })
  mock_bridge_device:set_field(Fields.DEVICE_TYPE, "bridge", { persist = true })
  mock_bridge_device:set_field(Fields.MODEL_ID, mock_bridge_info.modelid, { persist = true })
  mock_bridge_device:set_field(Fields.BRIDGE_ID, mock_bridge_device.device_network_id,
    { persist = true })
  mock_bridge_device:set_field(Fields.BRIDGE_SW_VERSION,
    tonumber(mock_bridge_info.swversion or "0", 10), { persist = true })
  mock_bridge_device:set_field(Fields.IPV4, mock_bridge_info.ip, { persist = true })
  mock_bridge_device:set_field(HueApi.APPLICATION_KEY_HEADER, bridge_api_key, { persist = true })
  -- TODO: This should be a table, not a boolean. Need to mock the event source first
  mock_bridge_device:set_field(Fields.EVENT_SOURCE, true, { persist = false })

  local api_instance = HueApi.new_bridge_manager(
    "https://" .. mock_bridge_info.ip,
    bridge_api_key,
    helpers.socket.mock_labeled_socket_builder('[Hue Bridge API Instance] ')
  )

  mock_bridge_device:set_field(Fields.BRIDGE_API, api_instance, { persist = false })

  Discovery.api_keys[mock_bridge_device.device_network_id] = bridge_api_key
  Discovery.disco_api_instances[mock_bridge_device.device_network_id] = api_instance

  local bridge_id = mock_bridge_device.device_network_id

  driver_under_test.datastore.bridge_netinfo[bridge_id] = mock_bridge_info
  driver_under_test.datastore.dni_to_device_id[bridge_id] = mock_bridge_device.id
  driver_under_test.datastore.api_keys[bridge_id] = bridge_api_key
  m.driver_under_test = driver_under_test

  mock_bridge_device:set_field(Fields._INIT, true, { persist = false })

  return mock_bridge_device
end

return m
