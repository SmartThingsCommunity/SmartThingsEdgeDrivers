-- Copyright 2025 SmartThings
--
-- Licensed under the Apache License, Version 2.0 (the "License");
-- you may not use this file except in compliance with the License.
-- You may obtain a copy of the License at
--
--     http://www.apache.org/licenses/LICENSE-2.0
--
-- Unless required by applicable law or agreed to in writing, software
-- distributed under the License is distributed on an "AS IS" BASIS,
-- WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
-- See the License for the specific language governing permissions and
-- limitations under the License.

local test = require "integration_test"
test.set_rpc_version(5)
local t_utils = require "integration_test.utils"
local capabilities = require "st.capabilities"
local clusters = require "st.matter.clusters"
local version = require "version"

if version.api < 10 then
  clusters.TemperatureControl = require "TemperatureControl"
end

if version.api < 12 then
  clusters.OvenMode = require "OvenMode"
end

local dishwasher_ep = 1
local washer_ep = 1
local dryer_ep = 1
local oven_ep = 1
local oven_tcc_one_ep = 2
local oven_tcc_two_ep = 3
local cook_top_ep = 4
local cook_surface_one_ep = 5
local cook_surface_two_ep = 6
local refrigerator_ep = 1
local freezer_ep = 2

local mock_device_dishwasher = test.mock_device.build_test_matter_device({
  profile = t_utils.get_profile_definition("dishwasher-tn-tl.yml"),
  manufacturer_info = {
    vendor_id = 0x0000,
    product_id = 0x0000,
  },
  endpoints = {
    {
      endpoint_id = 0,
      clusters = {
        { cluster_id = clusters.Basic.ID, cluster_type = "SERVER" },
      },
      device_types = {
        { device_type_id = 0x0016, device_type_revision = 1 }, -- RootNode
      }
    },
    {
      endpoint_id = dishwasher_ep,
      clusters = {
        {
          cluster_id = clusters.OnOff.ID,
          cluster_type = "SERVER",
          cluster_revision = 1,
        },
        { cluster_id = clusters.DishwasherAlarm.ID,  cluster_type = "SERVER" },
        { cluster_id = clusters.DishwasherMode.ID,  cluster_type = "SERVER" },
        { cluster_id = clusters.OperationalState.ID,   cluster_type = "SERVER" },
        { cluster_id = clusters.TemperatureControl.ID, cluster_type = "SERVER", feature_map = 3},
      },
      device_types = {
        { device_type_id = 0x0075, device_type_revision = 1 } -- Dishwasher
      }
    }
  }
})

local mock_device_washer = test.mock_device.build_test_matter_device({
  profile = t_utils.get_profile_definition("laundry-washer-tn-tl.yml"),
  manufacturer_info = {
    vendor_id = 0x0000,
    product_id = 0x0000,
  },
  endpoints = {
    {
      endpoint_id = 0,
      clusters = {
        { cluster_id = clusters.Basic.ID, cluster_type = "SERVER" },
      },
      device_types = {
        { device_type_id = 0x0016, device_type_revision = 1 }, -- RootNode
      }
    },
    {
      endpoint_id = washer_ep,
      clusters = {
        {
          cluster_id = clusters.OnOff.ID,
          cluster_type = "SERVER",
          cluster_revision = 1,
        },
        { cluster_id = clusters.LaundryWasherMode.ID,  cluster_type = "SERVER" },
        { cluster_id = clusters.OperationalState.ID,   cluster_type = "SERVER" },
        { cluster_id = clusters.TemperatureControl.ID, cluster_type = "SERVER", feature_map = 3},
      },
      device_types = {
        { device_type_id = 0x0073, device_type_revision = 1 } -- LaundryWasher
      }
    }
  }
})

local mock_device_dryer = test.mock_device.build_test_matter_device({
  profile = t_utils.get_profile_definition("laundry-dryer-tn-tl.yml"),
  manufacturer_info = {
    vendor_id = 0x0000,
    product_id = 0x0000,
  },
  endpoints = {
    {
      endpoint_id = 0,
      clusters = {
        { cluster_id = clusters.Basic.ID, cluster_type = "SERVER" },
      },
      device_types = {
        { device_type_id = 0x0016, device_type_revision = 1 }, -- RootNode
      }
    },
    {
      endpoint_id = dryer_ep,
      clusters = {
        {
          cluster_id = clusters.OnOff.ID,
          cluster_type = "SERVER",
          cluster_revision = 1,
        },
        { cluster_id = clusters.LaundryWasherMode.ID,  cluster_type = "SERVER" },
        { cluster_id = clusters.OperationalState.ID,   cluster_type = "SERVER" },
        { cluster_id = clusters.TemperatureControl.ID, cluster_type = "SERVER", feature_map = 3},
      },
      device_types = {
        { device_type_id = 0x007C, device_type_revision = 1 } -- LaundryDryer
      }
    }
  }
})

local mock_device_oven = test.mock_device.build_test_matter_device({
  profile = t_utils.get_profile_definition("oven-cabinet-one-tn-cabinet-two-tl-cook-top-cook-surface-one-tl-cook-surface-two-tl.yml"),
  manufacturer_info = {
    vendor_id = 0x0000,
    product_id = 0x0000,
  },
  endpoints = {
    {
      endpoint_id = 0,
      clusters = {
        { cluster_id = clusters.Basic.ID, cluster_type = "SERVER" },
      },
      device_types = {
        { device_type_id = 0x0016, device_type_revision = 1 }, -- RootNode
      }
    },
    {
      endpoint_id = oven_ep,
      clusters = {},
      device_types = {
        { device_type_id = 0x007B, device_type_revision = 1 } -- Oven
      }
    },
    {
      endpoint_id = oven_tcc_one_ep,
      clusters = {
        { cluster_id = clusters.OvenMode.ID,               cluster_type = "SERVER" },
        { cluster_id = clusters.TemperatureMeasurement.ID, cluster_type = "SERVER" },
        { cluster_id = clusters.TemperatureControl.ID,     cluster_type = "SERVER", feature_map = 1 }, --Temperature Number
      },
      device_types = {
        { device_type_id = 0x0071, device_type_revision = 1 } -- Oven TCC
      }
    },
    {
      endpoint_id = oven_tcc_two_ep,
      clusters = {
        { cluster_id = clusters.OvenMode.ID,               cluster_type = "SERVER" },
        { cluster_id = clusters.TemperatureMeasurement.ID, cluster_type = "SERVER" },
        { cluster_id = clusters.TemperatureControl.ID,     cluster_type = "SERVER", feature_map = 2 }, --Temperature Level
      },
      device_types = {
        { device_type_id = 0x0071, device_type_revision = 1 } -- Oven TCC
      }
    },
    {
      endpoint_id = cook_top_ep,
      clusters = {
        { cluster_id = clusters.OnOff.ID, cluster_type = "SERVER", feature_map = 4 }, --OffOnly feature
      },
      device_types = {
        { device_type_id = 0x0078, device_type_revision = 1 } -- Cook Top
      }
    },
    {
      endpoint_id = cook_surface_one_ep,
      clusters = {
        { cluster_id = clusters.TemperatureControl.ID,     cluster_type = "SERVER", feature_map = 2 },
        { cluster_id = clusters.TemperatureMeasurement.ID, cluster_type = "SERVER" },
      },
      device_types = {
        { device_type_id = 0x0077, device_type_revision = 1 } -- Cook Surface
      }
    },
    {
      endpoint_id = cook_surface_two_ep,
      clusters = {
        { cluster_id = clusters.TemperatureControl.ID,     cluster_type = "SERVER", feature_map = 2 },
        { cluster_id = clusters.TemperatureMeasurement.ID, cluster_type = "SERVER" },
      },
      device_types = {
        { device_type_id = 0x0077, device_type_revision = 1 } -- Cook Surface
      }
    }
  }
})

local mock_device_refrigerator = test.mock_device.build_test_matter_device({
  profile = t_utils.get_profile_definition("refrigerator-freezer-tn.yml"),
  manufacturer_info = {
    vendor_id = 0x0000,
    product_id = 0x0000,
  },
  endpoints = {
    {
      endpoint_id = 0,
      clusters = {
        { cluster_id = clusters.Basic.ID, cluster_type = "SERVER" },
      },
      device_types = {
        { device_type_id = 0x0016, device_type_revision = 1 }, -- RootNode
      }
    },
    {
      endpoint_id = refrigerator_ep,
      clusters = {
        { cluster_id = clusters.RefrigeratorAlarm.ID,  cluster_type = "SERVER" },
        { cluster_id = clusters.RefrigeratorAndTemperatureControlledCabinetMode.ID,  cluster_type = "SERVER" },
        { cluster_id = clusters.TemperatureControl.ID, cluster_type = "SERVER", feature_map = 3},
        { cluster_id = clusters.TemperatureMeasurement.ID, cluster_type = "SERVER", feature_map = 3},
      },
      device_types = {
        { device_type_id = 0x0070, device_type_revision = 1 }, -- Refrigerator
        { device_type_id = 0x0071, device_type_revision = 1 } -- Temperature Controlled Cabinet
      }
    },
    {
      endpoint_id = freezer_ep,
      clusters = {
        { cluster_id = clusters.RefrigeratorAlarm.ID,  cluster_type = "SERVER" },
        { cluster_id = clusters.RefrigeratorAndTemperatureControlledCabinetMode.ID,  cluster_type = "SERVER" },
        { cluster_id = clusters.TemperatureControl.ID, cluster_type = "SERVER", feature_map = 3},
        { cluster_id = clusters.TemperatureMeasurement.ID, cluster_type = "SERVER", feature_map = 3},
      },
      device_types = {
        { device_type_id = 0x0070, device_type_revision = 1 }, -- Refrigerator
        { device_type_id = 0x0071, device_type_revision = 1 } -- Temperature Controlled Cabinet
      }
    }
  }
})

local function test_init_dishwasher()
  test.disable_startup_messages()
  test.mock_device.add_test_device(mock_device_dishwasher)
  local cluster_subscribe_list = {
    clusters.OnOff.attributes.OnOff,
    clusters.DishwasherMode.attributes.CurrentMode,
    clusters.DishwasherMode.attributes.SupportedModes,
    clusters.DishwasherAlarm.attributes.State,
    clusters.OperationalState.attributes.OperationalState,
    clusters.OperationalState.attributes.OperationalError,
    clusters.OperationalState.attributes.AcceptedCommandList,
    clusters.TemperatureControl.attributes.TemperatureSetpoint,
    clusters.TemperatureControl.attributes.MaxTemperature,
    clusters.TemperatureControl.attributes.MinTemperature,
    clusters.TemperatureControl.attributes.SelectedTemperatureLevel,
    clusters.TemperatureControl.attributes.SupportedTemperatureLevels
  }
  local subscribe_request = cluster_subscribe_list[1]:subscribe(mock_device_dishwasher)
  for i, cluster in ipairs(cluster_subscribe_list) do
    if i > 1 then
      subscribe_request:merge(cluster:subscribe(mock_device_dishwasher))
    end
  end
  test.socket.matter:__expect_send({ mock_device_dishwasher.id, subscribe_request })
  test.socket.device_lifecycle:__queue_receive({ mock_device_dishwasher.id, "added" })
  test.socket.device_lifecycle:__queue_receive({ mock_device_dishwasher.id, "init" })
  test.socket.matter:__expect_send({ mock_device_dishwasher.id, subscribe_request })
  local read_req = clusters.TemperatureControl.attributes.MinTemperature:read()
  read_req:merge(clusters.TemperatureControl.attributes.MaxTemperature:read())
  test.socket.matter:__expect_send({mock_device_dishwasher.id, read_req})
  test.socket.device_lifecycle:__queue_receive({ mock_device_dishwasher.id, "doConfigure"})
  mock_device_dishwasher:expect_metadata_update({ profile = "dishwasher-tn-tl" })
  mock_device_dishwasher:expect_metadata_update({ provisioning_state = "PROVISIONED" })
end

local function test_init_dryer()
  test.disable_startup_messages()
  test.socket.matter:__set_channel_ordering("relaxed")
  test.mock_device.add_test_device(mock_device_dryer)
  local cluster_subscribe_list = {
    clusters.OnOff.attributes.OnOff,
    clusters.LaundryWasherMode.attributes.CurrentMode,
    clusters.LaundryWasherMode.attributes.SupportedModes,
    clusters.OperationalState.attributes.OperationalState,
    clusters.OperationalState.attributes.OperationalError,
    clusters.OperationalState.attributes.AcceptedCommandList,
    clusters.TemperatureControl.attributes.TemperatureSetpoint,
    clusters.TemperatureControl.attributes.MaxTemperature,
    clusters.TemperatureControl.attributes.MinTemperature,
    clusters.TemperatureControl.attributes.SelectedTemperatureLevel,
    clusters.TemperatureControl.attributes.SupportedTemperatureLevels
  }
  local subscribe_request = cluster_subscribe_list[1]:subscribe(mock_device_dryer)
  for i, cluster in ipairs(cluster_subscribe_list) do
    if i > 1 then
      subscribe_request:merge(cluster:subscribe(mock_device_dryer))
    end
  end
  test.socket.matter:__expect_send({ mock_device_dryer.id, subscribe_request })
  test.socket.device_lifecycle:__queue_receive({ mock_device_dryer.id, "added" })
  test.socket.device_lifecycle:__queue_receive({ mock_device_dryer.id, "init" })
  test.socket.matter:__expect_send({ mock_device_dryer.id, subscribe_request })
  test.socket.device_lifecycle:__queue_receive({ mock_device_dryer.id, "doConfigure"})
  local read_req = clusters.TemperatureControl.attributes.MinTemperature:read()
  read_req:merge(clusters.TemperatureControl.attributes.MaxTemperature:read())
  test.socket.matter:__expect_send({mock_device_dryer.id, read_req})
  mock_device_dryer:expect_metadata_update({ profile = "laundry-dryer-tn-tl" })
  mock_device_dryer:expect_metadata_update({ provisioning_state = "PROVISIONED" })
end

local function test_init_washer()
  test.disable_startup_messages()
  test.socket.matter:__set_channel_ordering("relaxed")
  test.mock_device.add_test_device(mock_device_washer)
  local cluster_subscribe_list = {
    clusters.OnOff.attributes.OnOff,
    clusters.LaundryWasherMode.attributes.CurrentMode,
    clusters.LaundryWasherMode.attributes.SupportedModes,
    clusters.OperationalState.attributes.OperationalState,
    clusters.OperationalState.attributes.OperationalError,
    clusters.OperationalState.attributes.AcceptedCommandList,
    clusters.TemperatureControl.attributes.TemperatureSetpoint,
    clusters.TemperatureControl.attributes.MaxTemperature,
    clusters.TemperatureControl.attributes.MinTemperature,
    clusters.TemperatureControl.attributes.SelectedTemperatureLevel,
    clusters.TemperatureControl.attributes.SupportedTemperatureLevels
  }
  local subscribe_request = cluster_subscribe_list[1]:subscribe(mock_device_washer)
  for i, cluster in ipairs(cluster_subscribe_list) do
    if i > 1 then
      subscribe_request:merge(cluster:subscribe(mock_device_washer))
    end
  end
  test.socket.matter:__expect_send({ mock_device_washer.id, subscribe_request })
  test.socket.device_lifecycle:__queue_receive({ mock_device_washer.id, "added" })
  test.socket.device_lifecycle:__queue_receive({ mock_device_washer.id, "init" })
  test.socket.matter:__expect_send({ mock_device_washer.id, subscribe_request })
  test.socket.device_lifecycle:__queue_receive({ mock_device_washer.id, "doConfigure"})
  local read_req = clusters.TemperatureControl.attributes.MinTemperature:read()
  read_req:merge(clusters.TemperatureControl.attributes.MaxTemperature:read())
  test.socket.matter:__expect_send({mock_device_washer.id, read_req})
  mock_device_washer:expect_metadata_update({ profile = "laundry-washer-tn-tl" })
  mock_device_washer:expect_metadata_update({ provisioning_state = "PROVISIONED" })
end

local function test_init_oven()
  test.disable_startup_messages()
  test.mock_device.add_test_device(mock_device_oven)
  local cluster_subscribe_list = {
    clusters.OnOff.attributes.OnOff,
    clusters.TemperatureMeasurement.attributes.MeasuredValue,
    clusters.TemperatureControl.attributes.TemperatureSetpoint,
    clusters.TemperatureControl.attributes.MaxTemperature,
    clusters.TemperatureControl.attributes.MinTemperature,
    clusters.TemperatureControl.attributes.SelectedTemperatureLevel,
    clusters.TemperatureControl.attributes.SupportedTemperatureLevels,
    clusters.OvenMode.attributes.CurrentMode,
    clusters.OvenMode.attributes.SupportedModes,
  }
  local subscribe_request = cluster_subscribe_list[1]:subscribe(mock_device_oven)
  for i, cluster in ipairs(cluster_subscribe_list) do
    if i > 1 then
      subscribe_request:merge(cluster:subscribe(mock_device_oven))
    end
  end
  test.socket.matter:__expect_send({ mock_device_oven.id, subscribe_request })
  test.socket.device_lifecycle:__queue_receive({ mock_device_oven.id, "added" })
  test.socket.device_lifecycle:__queue_receive({ mock_device_oven.id, "init" })
  test.socket.matter:__expect_send({ mock_device_oven.id, subscribe_request })
  test.socket.device_lifecycle:__queue_receive({ mock_device_oven.id, "doConfigure"})
  mock_device_oven:expect_metadata_update({ provisioning_state = "PROVISIONED" })
end

local function test_init_refrigerator()
  test.disable_startup_messages()
  test.mock_device.add_test_device(mock_device_refrigerator)
  local cluster_subscribe_list = {
    clusters.RefrigeratorAlarm.attributes.State,
    clusters.RefrigeratorAndTemperatureControlledCabinetMode.attributes.CurrentMode,
    clusters.RefrigeratorAndTemperatureControlledCabinetMode.attributes.SupportedModes,
    clusters.TemperatureControl.attributes.TemperatureSetpoint,
    clusters.TemperatureControl.attributes.MaxTemperature,
    clusters.TemperatureControl.attributes.MinTemperature,
    clusters.TemperatureMeasurement.attributes.MeasuredValue
  }
  local subscribe_request = cluster_subscribe_list[1]:subscribe(mock_device_refrigerator)
  for i, cluster in ipairs(cluster_subscribe_list) do
    if i > 1 then
      subscribe_request:merge(cluster:subscribe(mock_device_refrigerator))
    end
  end
  test.socket.matter:__expect_send({ mock_device_refrigerator.id, subscribe_request })
  test.socket.device_lifecycle:__queue_receive({ mock_device_refrigerator.id, "added" })
  test.socket.device_lifecycle:__queue_receive({ mock_device_refrigerator.id, "init" })
  test.socket.matter:__expect_send({ mock_device_refrigerator.id, subscribe_request })
  test.socket.device_lifecycle:__queue_receive({ mock_device_refrigerator.id, "doConfigure"})
  local read_req = clusters.TemperatureControl.attributes.MinTemperature:read()
  read_req:merge(clusters.TemperatureControl.attributes.MaxTemperature:read())
  test.socket.matter:__expect_send({mock_device_refrigerator.id, read_req})
  mock_device_refrigerator:expect_metadata_update({ profile = "refrigerator-freezer-tn-tl" })
  mock_device_refrigerator:expect_metadata_update({ provisioning_state = "PROVISIONED" })
end

test.register_coroutine_test(
  "temperatureSetpoint command should send appropriate commands for dishwasher", function()
    test.socket.matter:__queue_receive(
      {
        mock_device_dishwasher.id,
        clusters.TemperatureControl.attributes.MinTemperature:build_test_report_data(mock_device_dishwasher, dishwasher_ep, 0)
      }
    )
    test.socket.matter:__queue_receive(
      {
        mock_device_dishwasher.id,
        clusters.TemperatureControl.attributes.MaxTemperature:build_test_report_data(mock_device_dishwasher, dishwasher_ep, 10000)
      }
    )
    test.socket.matter:__queue_receive(
      {
        mock_device_dishwasher.id,
        clusters.TemperatureControl.attributes.TemperatureSetpoint:build_test_report_data(mock_device_dishwasher, dishwasher_ep, 9000)
      }
    )
    test.socket.capability:__expect_send(
      mock_device_dishwasher:generate_test_message("main", capabilities.temperatureSetpoint.temperatureSetpointRange({value = {minimum=33.0,maximum=90.0,step=0.1}, unit = "C"}, {visibility = {displayed = false}}))
    )
    test.socket.capability:__expect_send(
      mock_device_dishwasher:generate_test_message("main", capabilities.temperatureSetpoint.temperatureSetpoint({value = 90.0, unit = "C"}))
    )
    test.socket.capability:__queue_receive(
      {
        mock_device_dishwasher.id,
        { capability = "temperatureSetpoint", component = "main", command = "setTemperatureSetpoint", args = {40.0} }
      }
    )
    test.socket.matter:__expect_send(
      { mock_device_dishwasher.id, clusters.TemperatureControl.commands.SetTemperature(mock_device_dishwasher, dishwasher_ep, 40 * 100, nil) }
    )
  end,
  { test_init = test_init_dishwasher }
)

test.register_coroutine_test(
  "temperatureSetpoint command should send appropriate commands for dishwasher, temp bounds out of range and temp setpoint converted from F to C", function()
    test.socket.matter:__queue_receive(
      {
        mock_device_dishwasher.id,
        clusters.TemperatureControl.attributes.MinTemperature:build_test_report_data(mock_device_dishwasher, dishwasher_ep, 0)
      }
    )
    test.socket.matter:__queue_receive(
      {
        mock_device_dishwasher.id,
        clusters.TemperatureControl.attributes.MaxTemperature:build_test_report_data(mock_device_dishwasher, dishwasher_ep, 10000)
      }
    )
    test.socket.matter:__queue_receive(
      {
        mock_device_dishwasher.id,
        clusters.TemperatureControl.attributes.TemperatureSetpoint:build_test_report_data(mock_device_dishwasher, dishwasher_ep, 9000)
      }
    )
    test.socket.capability:__expect_send(
      mock_device_dishwasher:generate_test_message("main", capabilities.temperatureSetpoint.temperatureSetpointRange({value = {minimum=33.0,maximum=90.0,step=0.1}, unit = "C"}, {visibility = {displayed = false}}))
    )
    test.socket.capability:__expect_send(
      mock_device_dishwasher:generate_test_message("main", capabilities.temperatureSetpoint.temperatureSetpoint({value = 90.0, unit = "C"}))
    )
    test.socket.capability:__queue_receive(
      {
        mock_device_dishwasher.id,
        { capability = "temperatureSetpoint", component = "main", command = "setTemperatureSetpoint", args = {122.0} }
      }
    )
    test.socket.matter:__expect_send(
      { mock_device_dishwasher.id, clusters.TemperatureControl.commands.SetTemperature(mock_device_dishwasher, dishwasher_ep, 50 * 100, nil) }
    )
  end,
  { test_init = test_init_dishwasher }
)

test.register_coroutine_test(
  "temperatureSetpoint command should send appropriate commands for laundry washer", function()
    test.socket.matter:__queue_receive(
      {
        mock_device_washer.id,
        clusters.TemperatureControl.attributes.MinTemperature:build_test_report_data(mock_device_washer, washer_ep, 2000)
      }
    )
    test.socket.matter:__queue_receive(
      {
        mock_device_washer.id,
        clusters.TemperatureControl.attributes.MaxTemperature:build_test_report_data(mock_device_washer, washer_ep, 4000)
      }
    )
    test.socket.matter:__queue_receive(
      {
        mock_device_washer.id,
        clusters.TemperatureControl.attributes.TemperatureSetpoint:build_test_report_data(mock_device_washer, washer_ep, 3500)
      }
    )
    test.socket.capability:__expect_send(
      mock_device_washer:generate_test_message("main", capabilities.temperatureSetpoint.temperatureSetpointRange({value = {minimum=20.0,maximum=40.0,step=0.1}, unit = "C"}, {visibility = {displayed = false}}))
    )
    test.socket.capability:__expect_send(
      mock_device_washer:generate_test_message("main", capabilities.temperatureSetpoint.temperatureSetpoint({value = 35.0, unit = "C"}))
    )
    test.socket.capability:__queue_receive(
      {
        mock_device_washer.id,
        { capability = "temperatureSetpoint", component = "main", command = "setTemperatureSetpoint", args = {28.0} }
      }
    )
    test.socket.matter:__expect_send(
      { mock_device_washer.id, clusters.TemperatureControl.commands.SetTemperature(mock_device_washer, washer_ep, 28 * 100, nil) }
    )
  end,
  { test_init = test_init_washer }
)

test.register_coroutine_test(
  "temperatureSetpoint command should send appropriate commands for laundry washer, temp bounds out of range and temp setpoint converted from F to C", function()
    test.socket.matter:__queue_receive(
      {
        mock_device_washer.id,
        clusters.TemperatureControl.attributes.MinTemperature:build_test_report_data(mock_device_washer, washer_ep, 0)
      }
    )
    test.socket.matter:__queue_receive(
      {
        mock_device_washer.id,
        clusters.TemperatureControl.attributes.MaxTemperature:build_test_report_data(mock_device_washer, washer_ep, 10000)
      }
    )
    test.socket.matter:__queue_receive(
      {
        mock_device_washer.id,
        clusters.TemperatureControl.attributes.TemperatureSetpoint:build_test_report_data(mock_device_washer, washer_ep, 3000)
      }
    )
    test.socket.capability:__expect_send(
      mock_device_washer:generate_test_message("main", capabilities.temperatureSetpoint.temperatureSetpointRange({value = {minimum=13.0,maximum=55.0,step=0.1}, unit = "C"}, {visibility = {displayed = false}}))
    )
    test.socket.capability:__expect_send(
      mock_device_washer:generate_test_message("main", capabilities.temperatureSetpoint.temperatureSetpoint({value = 30.0, unit = "C"}))
    )
    test.socket.capability:__queue_receive(
      {
        mock_device_washer.id,
        { capability = "temperatureSetpoint", component = "main", command = "setTemperatureSetpoint", args = {122.0} }
      }
    )
    test.socket.matter:__expect_send(
      { mock_device_washer.id, clusters.TemperatureControl.commands.SetTemperature(mock_device_washer, washer_ep, 50 * 100, nil) }
    )
  end,
  { test_init = test_init_washer }
)

test.register_coroutine_test(
  "temperatureSetpoint command should send appropriate commands for laundry dryer", function()
    test.socket.matter:__queue_receive(
      {
        mock_device_dryer.id,
        clusters.TemperatureControl.attributes.MinTemperature:build_test_report_data(mock_device_dryer, dryer_ep, 3000)
      }
    )
    test.socket.matter:__queue_receive(
      {
        mock_device_dryer.id,
        clusters.TemperatureControl.attributes.MaxTemperature:build_test_report_data(mock_device_dryer, dryer_ep, 7000)
      }
    )
    test.socket.matter:__queue_receive(
      {
        mock_device_dryer.id,
        clusters.TemperatureControl.attributes.TemperatureSetpoint:build_test_report_data(mock_device_dryer, dryer_ep, 6000)
      }
    )
    test.socket.capability:__expect_send(
      mock_device_dryer:generate_test_message("main", capabilities.temperatureSetpoint.temperatureSetpointRange({value = {minimum=30.0,maximum=70.0,step=0.1}, unit = "C"}, {visibility = {displayed = false}}))
    )
    test.socket.capability:__expect_send(
      mock_device_dryer:generate_test_message("main", capabilities.temperatureSetpoint.temperatureSetpoint({value = 60.0, unit = "C"}))
    )
    test.socket.capability:__queue_receive(
      {
        mock_device_dryer.id,
        { capability = "temperatureSetpoint", component = "main", command = "setTemperatureSetpoint", args = {40.0} }
      }
    )
    test.socket.matter:__expect_send(
      { mock_device_dryer.id, clusters.TemperatureControl.commands.SetTemperature(mock_device_dryer, dryer_ep, 40 * 100, nil) }
    )
  end,
  { test_init = test_init_dryer }
)

test.register_coroutine_test(
  "temperatureSetpoint command should send appropriate commands for laundry dryer, temp bounds out of range and temp setpoint converted from F to C", function()
    test.socket.matter:__queue_receive(
      {
        mock_device_dryer.id,
        clusters.TemperatureControl.attributes.MinTemperature:build_test_report_data(mock_device_dryer, dryer_ep, 0)
      }
    )
    test.socket.matter:__queue_receive(
      {
        mock_device_dryer.id,
        clusters.TemperatureControl.attributes.MaxTemperature:build_test_report_data(mock_device_dryer, dryer_ep, 10000)
      }
    )
    test.socket.matter:__queue_receive(
      {
        mock_device_dryer.id,
        clusters.TemperatureControl.attributes.TemperatureSetpoint:build_test_report_data(mock_device_dryer, dryer_ep, 5000)
      }
    )
    test.socket.capability:__expect_send(
      mock_device_dryer:generate_test_message("main", capabilities.temperatureSetpoint.temperatureSetpointRange({value = {minimum=27.0,maximum=80.0,step=0.1}, unit = "C"}, {visibility = {displayed = false}}))
    )
    test.socket.capability:__expect_send(
      mock_device_dryer:generate_test_message("main", capabilities.temperatureSetpoint.temperatureSetpoint({value = 50.0, unit = "C"}))
    )
    test.socket.capability:__queue_receive(
      {
        mock_device_dryer.id,
        { capability = "temperatureSetpoint", component = "main", command = "setTemperatureSetpoint", args = {104.0} }
      }
    )
    test.socket.matter:__expect_send(
      { mock_device_dryer.id, clusters.TemperatureControl.commands.SetTemperature(mock_device_dryer, dryer_ep, 40 * 100, nil) }
    )
  end,
  { test_init = test_init_dryer }
)

test.register_coroutine_test(
  "temperatureSetpoint command should send appropriate commands for oven", function()
    test.socket.matter:__queue_receive(
      {
        mock_device_oven.id,
        clusters.TemperatureControl.attributes.MinTemperature:build_test_report_data(mock_device_oven, oven_tcc_one_ep, 12800)
      }
    )
    test.socket.matter:__queue_receive(
      {
        mock_device_oven.id,
        clusters.TemperatureControl.attributes.MaxTemperature:build_test_report_data(mock_device_oven, oven_tcc_one_ep, 20000)
      }
    )
    test.socket.matter:__queue_receive(
      {
        mock_device_oven.id,
        clusters.TemperatureControl.attributes.TemperatureSetpoint:build_test_report_data(mock_device_oven, oven_tcc_one_ep, 13000)
      }
    )
    test.socket.capability:__expect_send(
      mock_device_oven:generate_test_message("tccOne", capabilities.temperatureSetpoint.temperatureSetpointRange({value = {minimum=128.0,maximum=200.0,step=0.1}, unit = "C"}, {visibility = {displayed = false}}))
    )
    test.socket.capability:__expect_send(
      mock_device_oven:generate_test_message("tccOne", capabilities.temperatureSetpoint.temperatureSetpoint({value = 130.0, unit = "C"}))
    )
    test.socket.capability:__queue_receive(
      {
        mock_device_oven.id,
        { capability = "temperatureSetpoint", component = "tccOne", command = "setTemperatureSetpoint", args = {140.0} }
      }
    )
    test.socket.matter:__expect_send(
      { mock_device_oven.id, clusters.TemperatureControl.commands.SetTemperature(mock_device_oven, oven_tcc_one_ep, 140 * 100, nil) }
    )
  end,
  { test_init = test_init_oven }
)

test.register_coroutine_test(
  "temperatureSetpoint command should send appropriate commands for oven, temp bounds out of range and temp setpoint converted from F to C", function()
    test.socket.matter:__queue_receive(
      {
        mock_device_oven.id,
        clusters.TemperatureControl.attributes.MinTemperature:build_test_report_data(mock_device_oven, oven_tcc_one_ep, 10000)
      }
    )
    test.socket.matter:__queue_receive(
      {
        mock_device_oven.id,
        clusters.TemperatureControl.attributes.MaxTemperature:build_test_report_data(mock_device_oven, oven_tcc_one_ep, 30000)
      }
    )
    test.socket.matter:__queue_receive(
      {
        mock_device_oven.id,
        clusters.TemperatureControl.attributes.TemperatureSetpoint:build_test_report_data(mock_device_oven, oven_tcc_one_ep, 13000)
      }
    )
    test.socket.capability:__expect_send(
      mock_device_oven:generate_test_message("tccOne", capabilities.temperatureSetpoint.temperatureSetpointRange({value = {minimum=127.0,maximum=260.0,step=0.1}, unit = "C"}, {visibility = {displayed = false}}))
    )
    test.socket.capability:__expect_send(
      mock_device_oven:generate_test_message("tccOne", capabilities.temperatureSetpoint.temperatureSetpoint({value = 130.0, unit = "C"}))
    )
    test.socket.capability:__queue_receive(
      {
        mock_device_oven.id,
        { capability = "temperatureSetpoint", component = "tccOne", command = "setTemperatureSetpoint", args = {284.0} }
      }
    )
    test.socket.matter:__expect_send(
      { mock_device_oven.id, clusters.TemperatureControl.commands.SetTemperature(mock_device_oven, oven_tcc_one_ep, 140 * 100, nil) }
    )
  end,
  { test_init = test_init_oven }
)

test.register_coroutine_test(
  "temperatureSetpoint command should send appropriate commands for refrigerator endpoint", function()
    test.socket.matter:__queue_receive(
      {
        mock_device_refrigerator.id,
        clusters.TemperatureControl.attributes.MinTemperature:build_test_report_data(mock_device_refrigerator, refrigerator_ep, 0)
      }
    )
    test.socket.matter:__queue_receive(
      {
        mock_device_refrigerator.id,
        clusters.TemperatureControl.attributes.MaxTemperature:build_test_report_data(mock_device_refrigerator, refrigerator_ep, 1500)
      }
    )
    test.socket.matter:__queue_receive(
      {
        mock_device_refrigerator.id,
        clusters.TemperatureControl.attributes.TemperatureSetpoint:build_test_report_data(mock_device_refrigerator, refrigerator_ep, 700)
      }
    )
    test.socket.capability:__expect_send(
      mock_device_refrigerator:generate_test_message("refrigerator", capabilities.temperatureSetpoint.temperatureSetpointRange({value = {minimum=0.0,maximum=15.0,step=0.1}, unit = "C"}, {visibility = {displayed = false}}))
    )
    test.socket.capability:__expect_send(
      mock_device_refrigerator:generate_test_message("refrigerator", capabilities.temperatureSetpoint.temperatureSetpoint({value = 7.0, unit = "C"}))
    )
    test.socket.capability:__queue_receive(
      {
        mock_device_refrigerator.id,
        { capability = "temperatureSetpoint", component = "refrigerator", command = "setTemperatureSetpoint", args = {4.0} }
      }
    )
    test.socket.matter:__expect_send(
      { mock_device_refrigerator.id, clusters.TemperatureControl.commands.SetTemperature(mock_device_refrigerator, refrigerator_ep, 4 * 100, nil) }
    )
  end,
  { test_init = test_init_refrigerator }
)

test.register_coroutine_test(
  "temperatureSetpoint command should send appropriate commands for refrigerator endpoint, temp bounds out of range and temp setpoint converted from F to C", function()
    test.socket.matter:__queue_receive(
      {
        mock_device_refrigerator.id,
        clusters.TemperatureControl.attributes.MinTemperature:build_test_report_data(mock_device_refrigerator, refrigerator_ep, -1000)
      }
    )
    test.socket.matter:__queue_receive(
      {
        mock_device_refrigerator.id,
        clusters.TemperatureControl.attributes.MaxTemperature:build_test_report_data(mock_device_refrigerator, refrigerator_ep, 2500)
      }
    )
    test.socket.matter:__queue_receive(
      {
        mock_device_refrigerator.id,
        clusters.TemperatureControl.attributes.TemperatureSetpoint:build_test_report_data(mock_device_refrigerator, refrigerator_ep, 700)
      }
    )
    test.socket.capability:__expect_send(
      mock_device_refrigerator:generate_test_message("refrigerator", capabilities.temperatureSetpoint.temperatureSetpointRange({value = {minimum=-6.0,maximum=20.0,step=0.1}, unit = "C"}, {visibility = {displayed = false}}))
    )
    test.socket.capability:__expect_send(
      mock_device_refrigerator:generate_test_message("refrigerator", capabilities.temperatureSetpoint.temperatureSetpoint({value = 7.0, unit = "C"}))
    )
    test.socket.capability:__queue_receive(
      {
        mock_device_refrigerator.id,
        { capability = "temperatureSetpoint", component = "refrigerator", command = "setTemperatureSetpoint", args = {50.0} }
      }
    )
    test.socket.matter:__expect_send(
      { mock_device_refrigerator.id, clusters.TemperatureControl.commands.SetTemperature(mock_device_refrigerator, refrigerator_ep, 10 * 100, nil) }
    )
  end,
  { test_init = test_init_refrigerator }
)

test.register_coroutine_test(
  "temperatureSetpoint command should send appropriate commands for freezer endpoint", function()
    test.socket.matter:__queue_receive(
      {
        mock_device_refrigerator.id,
        clusters.TemperatureControl.attributes.MinTemperature:build_test_report_data(mock_device_refrigerator, freezer_ep, -2200)
      }
    )
    test.socket.matter:__queue_receive(
      {
        mock_device_refrigerator.id,
        clusters.TemperatureControl.attributes.MaxTemperature:build_test_report_data(mock_device_refrigerator, freezer_ep, -1400)
      }
    )
    test.socket.matter:__queue_receive(
      {
        mock_device_refrigerator.id,
        clusters.TemperatureControl.attributes.TemperatureSetpoint:build_test_report_data(mock_device_refrigerator, freezer_ep, -1700)
      }
    )
    test.socket.capability:__expect_send(
      mock_device_refrigerator:generate_test_message("freezer", capabilities.temperatureSetpoint.temperatureSetpointRange({value = {minimum=-22.0,maximum=-14.0,step=0.1}, unit = "C"}, {visibility = {displayed = false}}))
    )
    test.socket.capability:__expect_send(
      mock_device_refrigerator:generate_test_message("freezer", capabilities.temperatureSetpoint.temperatureSetpoint({value = -17.0, unit = "C"}))
    )
    test.socket.capability:__queue_receive(
      {
        mock_device_refrigerator.id,
        { capability = "temperatureSetpoint", component = "freezer", command = "setTemperatureSetpoint", args = {-15.0} }
      }
    )
    test.socket.matter:__expect_send(
      { mock_device_refrigerator.id, clusters.TemperatureControl.commands.SetTemperature(mock_device_refrigerator, freezer_ep, -15 * 100, nil) }
    )
  end,
  { test_init = test_init_refrigerator }
)

test.register_coroutine_test(
  "temperatureSetpoint command should send appropriate commands for freezer endpoint, temp bounds out of range and temp setpoint converted from F to C", function()
    test.socket.matter:__queue_receive(
      {
        mock_device_refrigerator.id,
        clusters.TemperatureControl.attributes.MinTemperature:build_test_report_data(mock_device_refrigerator, freezer_ep, -2700)
      }
    )
    test.socket.matter:__queue_receive(
      {
        mock_device_refrigerator.id,
        clusters.TemperatureControl.attributes.MaxTemperature:build_test_report_data(mock_device_refrigerator, freezer_ep, -500)
      }
    )
    test.socket.matter:__queue_receive(
      {
        mock_device_refrigerator.id,
        clusters.TemperatureControl.attributes.TemperatureSetpoint:build_test_report_data(mock_device_refrigerator, freezer_ep, -1500)
      }
    )
    test.socket.capability:__expect_send(
      mock_device_refrigerator:generate_test_message("freezer", capabilities.temperatureSetpoint.temperatureSetpointRange({value = {minimum=-24.0,maximum=-12.0,step=0.1}, unit = "C"}, {visibility = {displayed = false}}))
    )
    test.socket.capability:__expect_send(
      mock_device_refrigerator:generate_test_message("freezer", capabilities.temperatureSetpoint.temperatureSetpoint({value = -15.0, unit = "C"}))
    )
    test.socket.capability:__queue_receive(
      {
        mock_device_refrigerator.id,
        { capability = "temperatureSetpoint", component = "freezer", command = "setTemperatureSetpoint", args = {-4.0} }
      }
    )
    test.socket.matter:__expect_send(
      { mock_device_refrigerator.id, clusters.TemperatureControl.commands.SetTemperature(mock_device_refrigerator, freezer_ep, -20 * 100, nil) }
    )
  end,
  { test_init = test_init_refrigerator }
)

test.run_registered_tests()
