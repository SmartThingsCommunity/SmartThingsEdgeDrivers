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
local t_utils = require "integration_test.utils"
local clusters = require "st.matter.clusters"

test.disable_startup_messages()

local mock_device_onoff = test.mock_device.build_test_matter_device({
  profile = t_utils.get_profile_definition("matter-thing.yml"),
  manufacturer_info = {
    vendor_id = 0x0000,
    product_id = 0x0000,
  },
  endpoints = {
    {
      endpoint_id = 0,
      clusters = {
        {cluster_id = clusters.Basic.ID, cluster_type = "SERVER"},
      },
      device_types = {
        {device_type_id = 0x0016, device_type_revision = 1} -- RootNode
      }
    },
    {
      endpoint_id = 1,
      clusters = {
        {cluster_id = clusters.OnOff.ID, cluster_type = "SERVER", cluster_revision = 1, feature_map = 0},
      },
      device_types = {
        {device_type_id = 0x0103, device_type_revision = 1} -- On/Off Light Switch
      }
    }
  }
})

local mock_device_onoff_client = test.mock_device.build_test_matter_device({
  profile = t_utils.get_profile_definition("matter-thing.yml"),
  manufacturer_info = {
    vendor_id = 0x0000,
    product_id = 0x0000,
  },
  endpoints = {
    {
      endpoint_id = 0,
      clusters = {
        {cluster_id = clusters.Basic.ID, cluster_type = "SERVER"},
      },
      device_types = {
        {device_type_id = 0x0016, device_type_revision = 1} -- RootNode
      }
    },
    {
      endpoint_id = 1,
      clusters = {
        {cluster_id = clusters.OnOff.ID, cluster_type = "CLIENT", cluster_revision = 1, feature_map = 0},
      },
      device_types = {
        {device_type_id = 0x0103, device_type_revision = 1} -- On/Off Light Switch
      }
    }
  }
})

local mock_device_dimmer = test.mock_device.build_test_matter_device({
  profile = t_utils.get_profile_definition("matter-thing.yml"),
  manufacturer_info = {
    vendor_id = 0x0000,
    product_id = 0x0000,
  },
  endpoints = {
    {
      endpoint_id = 5,
      clusters = {
        {cluster_id = clusters.Basic.ID, cluster_type = "SERVER"},
      },
      device_types = {
        {device_type_id = 0x0016, device_type_revision = 1} -- RootNode
      }
    },
    {
      endpoint_id = 1,
      clusters = {
        {cluster_id = clusters.OnOff.ID, cluster_type = "SERVER", cluster_revision = 1, feature_map = 0},
        {cluster_id = clusters.LevelControl.ID, cluster_type = "SERVER", feature_map = 2}
      },
      device_types = {
        {device_type_id = 0x0104, device_type_revision = 1} -- Dimmer Switch
      }
    }
  }
})

local mock_device_color_dimmer = test.mock_device.build_test_matter_device({
  profile = t_utils.get_profile_definition("matter-thing.yml"),
  manufacturer_info = {
    vendor_id = 0x0000,
    product_id = 0x0000,
  },
  endpoints = {
    {
      endpoint_id = 0,
      clusters = {
        {cluster_id = clusters.Basic.ID, cluster_type = "SERVER"},
      },
      device_types = {
        {device_type_id = 0x0016, device_type_revision = 1} -- RootNode
      }
    },
    {
      endpoint_id = 7,
      clusters = {
        {cluster_id = clusters.OnOff.ID, cluster_type = "SERVER", cluster_revision = 1, feature_map = 0},
        {cluster_id = clusters.LevelControl.ID, cluster_type = "CLIENT", feature_map = 2},
        {cluster_id = clusters.ColorControl.ID, cluster_type = "CLIENT", feature_map = 31},

      },
      device_types = {
        {device_type_id = 0x0105, device_type_revision = 1} -- Color Dimmer Switch
      }
    }
  }
})

local mock_device_mounted_on_off_control = test.mock_device.build_test_matter_device({
  profile = t_utils.get_profile_definition("switch-binary.yml"),
  manufacturer_info = {
    vendor_id = 0x0000,
    product_id = 0x0000,
  },
  endpoints = {
    {
      endpoint_id = 0,
      clusters = {
        {cluster_id = clusters.Basic.ID, cluster_type = "SERVER"},
      },
      device_types = {
        {device_type_id = 0x0016, device_type_revision = 1} -- RootNode
      }
    },
    {
      endpoint_id = 7,
      clusters = {
        {cluster_id = clusters.OnOff.ID, cluster_type = "SERVER", cluster_revision = 1, feature_map = 0},
        {cluster_id = clusters.LevelControl.ID, cluster_type = "CLIENT", feature_map = 2},

      },
      device_types = {
        {device_type_id = 0x010F, device_type_revision = 1} -- Mounted On/Off Control
      }
    }
  }
})

local mock_device_mounted_dimmable_load_control = test.mock_device.build_test_matter_device({
  profile = t_utils.get_profile_definition("switch-level.yml"),
  manufacturer_info = {
    vendor_id = 0x0000,
    product_id = 0x0000,
  },
  endpoints = {
    {
      endpoint_id = 0,
      clusters = {
        {cluster_id = clusters.Basic.ID, cluster_type = "SERVER"},
      },
      device_types = {
        {device_type_id = 0x0016, device_type_revision = 1} -- RootNode
      }
    },
    {
      endpoint_id = 7,
      clusters = {
        {cluster_id = clusters.OnOff.ID, cluster_type = "SERVER", cluster_revision = 1, feature_map = 0},
        {cluster_id = clusters.LevelControl.ID, cluster_type = "CLIENT", feature_map = 2},

      },
      device_types = {
        {device_type_id = 0x0110, device_type_revision = 1} -- Mounted Dimmable Load Control
      }
    }
  }
})

local mock_device_water_valve = test.mock_device.build_test_matter_device({
  profile = t_utils.get_profile_definition("matter-thing.yml"),
  manufacturer_info = {
    vendor_id = 0x0000,
    product_id = 0x0000,
  },
  endpoints = {
    {
      endpoint_id = 0,
      clusters = {
        {cluster_id = clusters.Basic.ID, cluster_type = "SERVER"},
      },
      device_types = {
        {device_type_id = 0x0016, device_type_revision = 1} -- RootNode
      }
    },
    {
      endpoint_id = 1,
      clusters = {
        {cluster_id = clusters.ValveConfigurationAndControl.ID, cluster_type = "SERVER", cluster_revision = 1, feature_map = 2},
      },
      device_types = {
        {device_type_id = 0x0042, device_type_revision = 1} -- Water Valve
      }
    }
  }
})

local mock_device_parent_client_child_server = test.mock_device.build_test_matter_device({
  profile = t_utils.get_profile_definition("matter-thing.yml"),
  manufacturer_info = {
    vendor_id = 0x0000,
    product_id = 0x0000,
  },
  endpoints = {
    {
      endpoint_id = 0,
      clusters = {
        {cluster_id = clusters.Basic.ID, cluster_type = "SERVER", cluster_revision = 1, feature_map = 0},
      },
      device_types = {
        {device_type_id = 0x0016, device_type_revision = 1} -- RootNode
      }
    },
    {
      endpoint_id = 7,
      clusters = {
        {cluster_id = clusters.OnOff.ID, cluster_type = "SERVER", cluster_revision = 1, feature_map = 0},
      },
      device_types = {
        {device_type_id = 0x0103, device_type_revision = 1} -- OnOff Switch
      }
    },
    {
      endpoint_id = 10,
      clusters = {
        {cluster_id = clusters.OnOff.ID, cluster_type = "CLIENT", cluster_revision = 1, feature_map = 0},
      },
      device_types = {
        {device_type_id = 0x0103, device_type_revision = 1} -- OnOff Switch
      }
    },
  }
})

local mock_device_parent_child_switch_types = test.mock_device.build_test_matter_device({
  label = "Matter Switch",
  profile = t_utils.get_profile_definition("matter-thing.yml"),
  manufacturer_info = {
    vendor_id = 0x0000,
    product_id = 0x0000,
  },
  endpoints = {
    {
      endpoint_id = 0,
      clusters = {
        {cluster_id = clusters.Basic.ID, cluster_type = "SERVER", cluster_revision = 1, feature_map = 0},
      },
      device_types = {
        {device_type_id = 0x0016, device_type_revision = 1} -- RootNode
      }
    },
    {
      endpoint_id = 7,
      clusters = {
        {cluster_id = clusters.OnOff.ID, cluster_type = "SERVER", cluster_revision = 1, feature_map = 0},
        {cluster_id = clusters.LevelControl.ID, cluster_type = "SERVER", feature_map = 2}
      },
      device_types = {
        {device_type_id = 0x0104, device_type_revision = 1} -- Dimmer Switch
      }
    },
    {
      endpoint_id = 10,
      clusters = {
        {cluster_id = clusters.OnOff.ID, cluster_type = "SERVER", cluster_revision = 1, feature_map = 0},
      },
      device_types = {
        {device_type_id = 0x0103, device_type_revision = 1} -- OnOff Switch
      }
    },
  }
})

local mock_device_parent_child_different_types = test.mock_device.build_test_matter_device({
  label = "Matter Switch",
  profile = t_utils.get_profile_definition("switch-binary.yml"),
  manufacturer_info = {
    vendor_id = 0x0000,
    product_id = 0x0000,
  },
  endpoints = {
    {
      endpoint_id = 0,
      clusters = {
        {cluster_id = clusters.Basic.ID, cluster_type = "SERVER", cluster_revision = 1, feature_map = 0},
      },
      device_types = {
        {device_type_id = 0x0016, device_type_revision = 1} -- RootNode
      }
    },
    {
      endpoint_id = 7,
      clusters = {
        {cluster_id = clusters.OnOff.ID, cluster_type = "SERVER", cluster_revision = 1, feature_map = 0},
      },
      device_types = {
        {device_type_id = 0x0103, device_type_revision = 1} -- OnOff Switch
      }
    },
    {
      endpoint_id = 10,
      clusters = {
        {cluster_id = clusters.OnOff.ID, cluster_type = "SERVER"},
        {cluster_id = clusters.LevelControl.ID, cluster_type = "SERVER", feature_map = 2},
        {cluster_id = clusters.ColorControl.ID, cluster_type = "BOTH", feature_map = 30},
      },
      device_types = {
        {device_type_id = 0x010D, device_type_revision = 2} -- Extended Color Light
      }
    }
  }
})

local mock_device_parent_child_unsupported_device_type = test.mock_device.build_test_matter_device({
  label = "Matter Switch",
  profile = t_utils.get_profile_definition("matter-thing.yml"),
  manufacturer_info = {
    vendor_id = 0x0000,
    product_id = 0x0000,
  },
  endpoints = {
    {
      endpoint_id = 0,
      clusters = {
        {cluster_id = clusters.Basic.ID, cluster_type = "SERVER", cluster_revision = 1, feature_map = 0},
      },
      device_types = {
        {device_type_id = 0x0016, device_type_revision = 1} -- RootNode
      }
    },
    {
      endpoint_id = 7,
      clusters = {
        {cluster_id = clusters.OnOff.ID, cluster_type = "SERVER", cluster_revision = 1, feature_map = 0},
      },
      device_types = {
        {device_type_id = 0x0103, device_type_revision = 1} -- OnOff Switch
      }
    },
    {
      endpoint_id = 10,
      clusters = {
        {cluster_id = clusters.OnOff.ID, cluster_type = "SERVER", cluster_revision = 1, feature_map = 0},
        {cluster_id = clusters.LevelControl.ID, cluster_type = "SERVER", feature_map = 2}
      },
      device_types = {
        {device_type_id = 0x0304, device_type_revision = 2} -- Pump Controller
      }
    }
  }
})

local mock_device_light_level_motion = test.mock_device.build_test_matter_device({
  profile = t_utils.get_profile_definition("light-level-motion.yml"),
  manufacturer_info = {
    vendor_id = 0x0000,
    product_id = 0x0000,
  },
  endpoints = {
    {
      endpoint_id = 0,
      clusters = {
        {cluster_id = clusters.Basic.ID, cluster_type = "SERVER"},
      },
      device_types = {
        {device_type_id = 0x0016, device_type_revision = 1}  -- RootNode
      }
    },
    {
      endpoint_id = 1,
      clusters = {
        {
          cluster_id = clusters.OnOff.ID,
          cluster_type = "SERVER",
          cluster_revision = 1,
          feature_map = 0, --u32 bitmap
        },
        {cluster_id = clusters.LevelControl.ID, cluster_type = "SERVER"}
      },
      device_types = {
        {device_type_id = 0x0101, device_type_revision = 1}  -- Dimmable Light
      }
    },
    {
      endpoint_id = 2,
      clusters = {
        {cluster_id = clusters.OccupancySensing.ID, cluster_type = "SERVER"},
      },
      device_types = {
        {device_type_id = 0x0107, device_type_revision = 1}  -- Occupancy Sensor
      }
    }
  }
})

local function test_init_parent_child_switch_types()
  test.mock_device.add_test_device(mock_device_parent_child_switch_types)
  local subscribe_request = clusters.OnOff.attributes.OnOff:subscribe(mock_device_parent_child_switch_types)

  test.socket.device_lifecycle:__queue_receive({ mock_device_parent_child_switch_types.id, "added" })
  test.socket.matter:__expect_send({mock_device_parent_child_switch_types.id, subscribe_request})

  test.socket.device_lifecycle:__queue_receive({ mock_device_parent_child_switch_types.id, "init" })
  test.socket.matter:__expect_send({mock_device_parent_child_switch_types.id, subscribe_request})

  test.socket.device_lifecycle:__queue_receive({ mock_device_parent_child_switch_types.id, "doConfigure" })
  mock_device_parent_child_switch_types:expect_metadata_update({ profile = "switch-level" })
  mock_device_parent_child_switch_types:expect_metadata_update({ provisioning_state = "PROVISIONED" })

  mock_device_parent_child_switch_types:expect_device_create({
    type = "EDGE_CHILD",
    label = "Matter Switch 2",
    profile = "switch-binary",
    parent_device_id = mock_device_parent_child_switch_types.id,
    parent_assigned_child_key = string.format("%d", 10)
  })
end

local function test_init_onoff()
  test.mock_device.add_test_device(mock_device_onoff)
  test.socket.device_lifecycle:__queue_receive({ mock_device_onoff.id, "added" })
  test.socket.device_lifecycle:__queue_receive({ mock_device_onoff.id, "init" })
  test.socket.device_lifecycle:__queue_receive({ mock_device_onoff.id, "doConfigure" })
  mock_device_onoff:expect_metadata_update({ profile = "switch-binary" })
  mock_device_onoff:expect_metadata_update({ provisioning_state = "PROVISIONED" })
end

local function test_init_onoff_client()
  test.mock_device.add_test_device(mock_device_onoff_client)
end

local function test_init_parent_client_child_server()
  test.mock_device.add_test_device(mock_device_parent_client_child_server)
  local subscribe_request = clusters.OnOff.attributes.OnOff:subscribe(mock_device_parent_client_child_server)

  test.socket.device_lifecycle:__queue_receive({ mock_device_parent_client_child_server.id, "added" })
  test.socket.matter:__expect_send({mock_device_parent_client_child_server.id, subscribe_request})

  test.socket.device_lifecycle:__queue_receive({ mock_device_parent_client_child_server.id, "init" })
  test.socket.matter:__expect_send({mock_device_parent_client_child_server.id, subscribe_request})

  test.socket.device_lifecycle:__queue_receive({ mock_device_parent_client_child_server.id, "doConfigure" })
  mock_device_parent_client_child_server:expect_metadata_update({ profile = "switch-binary" })
  mock_device_parent_client_child_server:expect_metadata_update({ provisioning_state = "PROVISIONED" })
end

local function test_init_dimmer()
  test.mock_device.add_test_device(mock_device_dimmer)
  test.socket.device_lifecycle:__queue_receive({ mock_device_dimmer.id, "doConfigure" })
  mock_device_dimmer:expect_metadata_update({ profile = "switch-level" })
  mock_device_dimmer:expect_metadata_update({ provisioning_state = "PROVISIONED" })
end

local function test_init_color_dimmer()
  test.mock_device.add_test_device(mock_device_color_dimmer)
  test.socket.device_lifecycle:__queue_receive({ mock_device_color_dimmer.id, "added" })
  test.socket.device_lifecycle:__queue_receive({ mock_device_color_dimmer.id, "init" })
  test.socket.device_lifecycle:__queue_receive({ mock_device_color_dimmer.id, "doConfigure" })
  mock_device_color_dimmer:expect_metadata_update({ profile = "switch-color-level" })
  mock_device_color_dimmer:expect_metadata_update({ provisioning_state = "PROVISIONED" })
end

local function test_init_mounted_on_off_control()
  test.mock_device.add_test_device(mock_device_mounted_on_off_control)
  local cluster_subscribe_list = {
    clusters.OnOff.attributes.OnOff,
  }
  local subscribe_request = cluster_subscribe_list[1]:subscribe(mock_device_mounted_on_off_control)
  for i, cluster in ipairs(cluster_subscribe_list) do
    if i > 1 then
      subscribe_request:merge(cluster:subscribe(mock_device_mounted_on_off_control))
    end
  end
  test.socket.device_lifecycle:__queue_receive({ mock_device_mounted_on_off_control.id, "added" })
  test.socket.matter:__expect_send({mock_device_mounted_on_off_control.id, subscribe_request})

  test.socket.device_lifecycle:__queue_receive({ mock_device_mounted_on_off_control.id, "init" })
  test.socket.matter:__expect_send({mock_device_mounted_on_off_control.id, subscribe_request})

  test.socket.device_lifecycle:__queue_receive({ mock_device_mounted_on_off_control.id, "doConfigure" })
  mock_device_mounted_on_off_control:expect_metadata_update({ provisioning_state = "PROVISIONED" })
end

local function test_init_mounted_dimmable_load_control()
  test.mock_device.add_test_device(mock_device_mounted_dimmable_load_control)
  local cluster_subscribe_list = {
    clusters.OnOff.attributes.OnOff,
  }
  local subscribe_request = cluster_subscribe_list[1]:subscribe(mock_device_mounted_dimmable_load_control)
  for i, cluster in ipairs(cluster_subscribe_list) do
    if i > 1 then
      subscribe_request:merge(cluster:subscribe(mock_device_mounted_dimmable_load_control))
    end
  end
  test.socket.device_lifecycle:__queue_receive({ mock_device_mounted_dimmable_load_control.id, "added" })
  test.socket.matter:__expect_send({mock_device_mounted_dimmable_load_control.id, subscribe_request})

  test.socket.device_lifecycle:__queue_receive({ mock_device_mounted_dimmable_load_control.id, "init" })
  test.socket.matter:__expect_send({mock_device_mounted_dimmable_load_control.id, subscribe_request})

  test.socket.device_lifecycle:__queue_receive({ mock_device_mounted_dimmable_load_control.id, "doConfigure" })
  mock_device_mounted_dimmable_load_control:expect_metadata_update({ provisioning_state = "PROVISIONED" })
end

local function test_init_water_valve()
  test.mock_device.add_test_device(mock_device_water_valve)
  test.socket.device_lifecycle:__queue_receive({ mock_device_water_valve.id, "added" })
  test.socket.device_lifecycle:__queue_receive({ mock_device_water_valve.id, "init" })
  test.socket.device_lifecycle:__queue_receive({ mock_device_water_valve.id, "doConfigure" })
  mock_device_water_valve:expect_metadata_update({ profile = "water-valve-level" })
  mock_device_water_valve:expect_metadata_update({ provisioning_state = "PROVISIONED" })
end

local function test_init_parent_child_different_types()
  test.mock_device.add_test_device(mock_device_parent_child_different_types)
  local cluster_subscribe_list = {
    clusters.OnOff.attributes.OnOff,
    clusters.LevelControl.attributes.CurrentLevel,
    clusters.LevelControl.attributes.MaxLevel,
    clusters.LevelControl.attributes.MinLevel,
    clusters.ColorControl.attributes.ColorTemperatureMireds,
    clusters.ColorControl.attributes.ColorTempPhysicalMaxMireds,
    clusters.ColorControl.attributes.ColorTempPhysicalMinMireds,
    clusters.ColorControl.attributes.CurrentHue,
    clusters.ColorControl.attributes.CurrentSaturation,
    clusters.ColorControl.attributes.CurrentX,
    clusters.ColorControl.attributes.CurrentY
  }
  local subscribe_request = cluster_subscribe_list[1]:subscribe(mock_device_parent_child_different_types)
  for i, cluster in ipairs(cluster_subscribe_list) do
    if i > 1 then
      subscribe_request:merge(cluster:subscribe(mock_device_parent_child_different_types))
    end
  end
  test.socket.device_lifecycle:__queue_receive({ mock_device_parent_child_different_types.id, "added" })
  test.socket.matter:__expect_send({mock_device_parent_child_different_types.id, subscribe_request})

  test.socket.device_lifecycle:__queue_receive({ mock_device_parent_child_different_types.id, "init" })
  test.socket.matter:__expect_send({mock_device_parent_child_different_types.id, subscribe_request})

  test.socket.device_lifecycle:__queue_receive({ mock_device_parent_child_different_types.id, "doConfigure" })
  mock_device_parent_child_different_types:expect_metadata_update({ provisioning_state = "PROVISIONED" })

  mock_device_parent_child_different_types:expect_device_create({
    type = "EDGE_CHILD",
    label = "Matter Switch 2",
    profile = "light-color-level",
    parent_device_id = mock_device_parent_child_different_types.id,
    parent_assigned_child_key = string.format("%d", 10)
  })
end

local function test_init_parent_child_unsupported_device_type()
  test.mock_device.add_test_device(mock_device_parent_child_unsupported_device_type)
  test.socket.device_lifecycle:__queue_receive({ mock_device_parent_child_unsupported_device_type.id, "added" })
  test.socket.device_lifecycle:__queue_receive({ mock_device_parent_child_unsupported_device_type.id, "init" })
  test.socket.device_lifecycle:__queue_receive({ mock_device_parent_child_unsupported_device_type.id, "doConfigure" })
  mock_device_parent_child_unsupported_device_type:expect_metadata_update({ profile = "switch-binary" })
  mock_device_parent_child_unsupported_device_type:expect_metadata_update({ provisioning_state = "PROVISIONED" })

  mock_device_parent_child_unsupported_device_type:expect_device_create({
    type = "EDGE_CHILD",
    label = "Matter Switch 2",
    profile = "switch-binary",
    parent_device_id = mock_device_parent_child_unsupported_device_type.id,
    parent_assigned_child_key = string.format("%d", 10)
  })
end

local function test_init_light_level_motion()
  test.mock_device.add_test_device(mock_device_light_level_motion)
  local cluster_subscribe_list = {
    clusters.OnOff.attributes.OnOff,
    clusters.LevelControl.attributes.CurrentLevel,
    clusters.LevelControl.attributes.MaxLevel,
    clusters.LevelControl.attributes.MinLevel,
    clusters.OccupancySensing.attributes.Occupancy
  }
  local subscribe_request = cluster_subscribe_list[1]:subscribe(mock_device_light_level_motion)
  for i, cluster in ipairs(cluster_subscribe_list) do
    if i > 1 then
      subscribe_request:merge(cluster:subscribe(mock_device_light_level_motion))
    end
  end

  test.socket.device_lifecycle:__queue_receive({ mock_device_light_level_motion.id, "added" })
  test.socket.matter:__expect_send({mock_device_light_level_motion.id, subscribe_request})

  test.socket.device_lifecycle:__queue_receive({ mock_device_light_level_motion.id, "init" })
  test.socket.matter:__expect_send({mock_device_light_level_motion.id, subscribe_request})

  test.socket.device_lifecycle:__queue_receive({ mock_device_light_level_motion.id, "doConfigure" })
  mock_device_light_level_motion:expect_metadata_update({ provisioning_state = "PROVISIONED" })
end

test.register_coroutine_test(
  "Test profile change on init for onoff parent cluster as server",
  function()
  end,
  { test_init = test_init_onoff }
)

test.register_coroutine_test(
  "Test profile change on init for dimmer parent cluster as server",
  function()
  end,
  { test_init = test_init_dimmer }
)

test.register_coroutine_test(
  "Test profile change on init for color dimmer parent cluster as server",
  function()
  end,
  { test_init = test_init_color_dimmer }
)

test.register_coroutine_test(
  "Test init for onoff parent cluster as client",
  function()
  end,
  { test_init = test_init_onoff_client }
)

test.register_coroutine_test(
  "Test init for mounted onoff control parent cluster as server",
  function()
  end,
  { test_init = test_init_mounted_on_off_control }
)

test.register_coroutine_test(
  "Test init for mounted dimmable load control parent cluster as server",
  function()
  end,
  { test_init = test_init_mounted_dimmable_load_control }
)

test.register_coroutine_test(
  "Test profile change on init for water valve parent cluster as server",
  function()
  end,
  { test_init = test_init_water_valve }
)

test.register_coroutine_test(
  "Test profile change on init for onoff parent cluster as client and onoff child as server",
  function()
  end,
  { test_init = test_init_parent_client_child_server }
)

test.register_coroutine_test(
  "Test profile change on init for onoff device when parent and child are both server",
  function()
  end,
  { test_init = test_init_parent_child_switch_types }
)

test.register_coroutine_test(
  "Test child device attribute subscriptions when parent device has clusters that are not a superset of child device clusters",
  function()
  end,
  { test_init = test_init_parent_child_different_types }
)

test.register_coroutine_test(
  "Test child device attributes not subscribed to for unsupported device type for child device",
  function()
  end,
  { test_init = test_init_parent_child_unsupported_device_type }
)

test.register_coroutine_test(
  "Test init for light with motion sensor",
  function()
  end,
  { test_init = test_init_light_level_motion }
)

test.run_registered_tests()
