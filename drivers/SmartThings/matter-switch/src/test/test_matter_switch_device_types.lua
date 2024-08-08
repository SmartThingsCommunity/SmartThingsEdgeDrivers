local test = require "integration_test"
local t_utils = require "integration_test.utils"

local clusters = require "st.matter.clusters"

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

local function test_init_parent_child_switch_types()
  test.mock_device.add_test_device(mock_device_parent_child_switch_types)
  mock_device_parent_child_switch_types:expect_metadata_update({ profile = "switch-level" })

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
  mock_device_onoff:expect_metadata_update({ profile = "switch-binary" })
end

local function test_init_onoff_client()
  test.mock_device.add_test_device(mock_device_onoff_client)
end

local function test_init_parent_client_child_server()
  test.mock_device.add_test_device(mock_device_parent_client_child_server)
  mock_device_parent_client_child_server:expect_metadata_update({ profile = "switch-binary" })
end

local function test_init_dimmer()
  test.mock_device.add_test_device(mock_device_dimmer)
  mock_device_dimmer:expect_metadata_update({ profile = "switch-level" })
end

local function test_init_color_dimmer()
  test.mock_device.add_test_device(mock_device_color_dimmer)
  mock_device_color_dimmer:expect_metadata_update({ profile = "switch-color-level" })
end

local function test_init_water_valve()
  test.mock_device.add_test_device(mock_device_water_valve)
  mock_device_water_valve:expect_metadata_update({ profile = "water-valve-level" })
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
  "Test profile change on init for onoff parent cluster as client",
  function()
  end,
  { test_init = test_init_onoff_client }
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

test.run_registered_tests()
