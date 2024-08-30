describe("utility functions", function()
  local Fields
  local HueDeviceTypes
  local st_utils
  local utils

  setup(function()
    Fields = require "fields"
    HueDeviceTypes = require "hue_device_types"
    utils = require "utils"
    st_utils = require "st.utils"
  end)

  describe("that handle raw data will handle their input correctly:", function()
    local test_mac_addr
    local test_cisco_mac_addr
    local test_hue_uuid

    before_each(function()
      test_mac_addr = "CA:FE:C0:FF:EE:00"
      test_cisco_mac_addr = "CAFE.C0FF.EE00"
      test_hue_uuid = st_utils.generate_uuid_v4()
    end)

    it("is_hue_id_string accepts a UUIDv4", function()
      assert.True(utils.is_hue_id_string(test_hue_uuid), string.format("Failed with value %s", test_hue_uuid))
    end)
    it("is_hue_id_string rejects strings that aren't a UUIDv4", function()
      assert.False(utils.is_hue_id_string("foo"))
    end)
    it("is_hue_id_string rejects values that aren't strings", function()
      assert.False(utils.is_hue_id_string(42))
      assert.False(utils.is_hue_id_string(nil))
      assert.False(utils.is_hue_id_string(true))
      assert.False(utils.is_hue_id_string(false))
      assert.False(utils.is_hue_id_string({ "foo" }))
      assert.False(utils.is_hue_id_string({ test_hue_uuid }))
      assert.False(utils.is_hue_id_string(print))
      assert.False(utils.is_hue_id_string())
    end)
    it("is_valid_mac_addr_string accepts normal MAC address with colon separators", function()
      assert.True(utils.is_valid_mac_addr_string(test_mac_addr), string.format("Failed with value %s", test_mac_addr))
      assert.True(utils.is_valid_mac_addr_string(string.lower(test_mac_addr)),
        string.format("Failed with value %s", test_mac_addr))
    end)
    it("is_valid_mac_addr_string accepts normal MAC address with hyphen separators", function()
      test_mac_addr = string.gsub(test_mac_addr, ':', '-')
      assert.True(utils.is_valid_mac_addr_string(test_mac_addr), string.format("Failed with value %s", test_mac_addr))
      assert.True(utils.is_valid_mac_addr_string(string.lower(test_mac_addr)),
        string.format("Failed with value %s", test_mac_addr))
    end)
    it("is_valid_mac_addr_string accepts normal MAC address with dot separators", function()
      test_mac_addr = string.gsub(test_mac_addr, ':', '.')
      assert.True(utils.is_valid_mac_addr_string(test_mac_addr), string.format("Failed with value %s", test_mac_addr))
      assert.True(utils.is_valid_mac_addr_string(string.lower(test_mac_addr)),
        string.format("Failed with value %s", test_mac_addr))
    end)
    it("is_valid_mac_addr_string accepts Cisco MAC address with dot separators", function()
      assert.True(utils.is_valid_mac_addr_string(test_cisco_mac_addr))
      assert.True(utils.is_valid_mac_addr_string(string.lower(test_cisco_mac_addr)),
        string.format("Failed with value %s", test_cisco_mac_addr))
    end)
    it("is_valid_mac_addr_string accepts Cisco MAC address with colon separators", function()
      test_cisco_mac_addr = string.gsub(test_cisco_mac_addr, '%.', ':')
      assert.True(utils.is_valid_mac_addr_string(test_cisco_mac_addr),
        string.format("Failed with value %s", test_cisco_mac_addr))
      assert.True(utils.is_valid_mac_addr_string(string.lower(test_cisco_mac_addr)),
        string.format("Failed with value %s", test_cisco_mac_addr))
    end)
    it("is_valid_mac_addr_string accepts Cisco MAC address with hyphen separators", function()
      test_cisco_mac_addr = string.gsub(test_cisco_mac_addr, '%.', '-')
      assert.True(utils.is_valid_mac_addr_string(test_cisco_mac_addr),
        string.format("Failed with value %s", test_cisco_mac_addr))
      assert.True(utils.is_valid_mac_addr_string(string.lower(test_cisco_mac_addr)),
        string.format("Failed with value %s", test_cisco_mac_addr))
    end)
    it("is_valid_mac_addr_string accepts MAC addresses with no separators", function()
      test_mac_addr = string.gsub(test_mac_addr, ':', '')
      assert.True(utils.is_valid_mac_addr_string(test_mac_addr), string.format("Failed with value %s", test_mac_addr))
      assert.True(utils.is_valid_mac_addr_string(string.lower(test_mac_addr)),
        string.format("Failed with value %s", test_mac_addr))

      test_cisco_mac_addr = string.gsub(test_cisco_mac_addr, '%.', '')
      assert.True(utils.is_valid_mac_addr_string(test_cisco_mac_addr),
        string.format("Failed with value %s", test_cisco_mac_addr))
      assert.True(utils.is_valid_mac_addr_string(string.lower(test_cisco_mac_addr)),
        string.format("Failed with value %s", test_cisco_mac_addr))
    end)
  end)

  describe("that handle devices will handle their metadata correctly:", function()
    local driver_faker
    local device_faker

    setup(function()
      driver_faker = require "fakers.driver_faker"
      device_faker = require "device_faker"
    end)

    it("parse_parent_assigned_child_key parses an Edge Light", function()
      local hue_id = st_utils.generate_uuid_v4()
      local fake_light = device_faker {
        migrated = false,
        device_type = HueDeviceTypes.LIGHT,
        hue_id = hue_id
      }
      local _, rid, rtype = assert.True(utils.parse_parent_assigned_key(fake_light))
      assert.are.equal(hue_id, rid)
      assert.are.equal(HueDeviceTypes.LIGHT, rtype)
    end)

    it("parse_parent_assigned_key does NOT parse migrated child light", function()
      local fake_light = device_faker {
        migrated = true,
        device_type = HueDeviceTypes.LIGHT
      }
      assert.False(utils.parse_parent_assigned_key(fake_light))
    end)

    it("parse_parent_assigned_key does NOT parse migrated child light", function()
      local fake_light = device_faker {
        migrated = true,
        device_type = HueDeviceTypes.LIGHT
      }
      assert.False(utils.parse_parent_assigned_key(fake_light))
    end)

    it("get_hue_rid gets the rid from the RESOURCE_ID field", function()
      local hue_id = st_utils.generate_uuid_v4()
      local fake_light = device_faker {
        device_type = HueDeviceTypes.LIGHT,
        migrated = true,
        fields = {
          [Fields.RESOURCE_ID] = hue_id
        }
      }

      assert.are.equal(hue_id, utils.get_hue_rid(fake_light))

      hue_id = st_utils.generate_uuid_v4()
      fake_light = device_faker {
        device_type = HueDeviceTypes.LIGHT,
        migrated = false,
        fields = {
          [Fields.RESOURCE_ID] = hue_id
        }
      }

      assert.are.equal(hue_id, utils.get_hue_rid(fake_light))
    end)

    it("get_hue_rid gets the rid from the parent-assigned key of a non-migrated light", function()
      local hue_id = st_utils.generate_uuid_v4()
      local fake_light = device_faker {
        device_type = HueDeviceTypes.LIGHT,
        migrated = false,
        hue_id = hue_id
      }

      assert.are.equal(hue_id, utils.get_hue_rid(fake_light))
    end)

    it("get_hue_rid fails to get the rid of a migrated light without a RESOURCE_ID field", function()
      local hue_id = st_utils.generate_uuid_v4()
      local fake_light = device_faker {
        device_type = HueDeviceTypes.LIGHT,
        migrated = true,
        hue_id = hue_id
      }

      local _, err_msg = assert.is_nil(utils.get_hue_rid(fake_light))
      assert.String(err_msg)
    end)

    it(
      "determine_device_type gets the device type of a non-migrated light WITH the type in the parent-assigned child key",
      function()
        local hue_id = st_utils.generate_uuid_v4()
        local fake_light = device_faker {
          device_type = HueDeviceTypes.LIGHT,
          migrated = false,
          hue_id = hue_id,
          uuid_only_parent_assigned_key = false
        }

        local expected_parent_assigned_child_key = string.format("light:%s", hue_id)
        assert.are.same(expected_parent_assigned_child_key, fake_light.parent_assigned_child_key)

        local rtype, err_msg = assert(utils.determine_device_type(fake_light))
        assert.are.same(HueDeviceTypes.LIGHT, rtype)
        assert.is_nil(err_msg)
      end)

    it(
      "determine_device_type gets the device type of a non-migrated light WITHOUT the type in the parent-assigned child key",
      function()
        local hue_id = st_utils.generate_uuid_v4()
        local fake_light = device_faker {
          device_type = HueDeviceTypes.LIGHT,
          migrated = false,
          hue_id = hue_id,
          uuid_only_parent_assigned_key = true
        }

        local expected_parent_assigned_child_key = hue_id
        assert.are.same(expected_parent_assigned_child_key, fake_light.parent_assigned_child_key)

        local rtype, err_msg = assert(utils.determine_device_type(fake_light))
        assert.are.same(HueDeviceTypes.LIGHT, rtype)
        assert.is_nil(err_msg)
      end)

    it("determine_device_type gets the device type of a migrated light", function()
      local fake_light = device_faker {
        device_type = HueDeviceTypes.LIGHT,
        migrated = true,
      }

      local rtype, err_msg = assert(utils.determine_device_type(fake_light))
      assert.are.same(HueDeviceTypes.LIGHT, rtype)
      assert.is_nil(err_msg)
    end)

    it("determine_device_type gets the device type of a migrated bridge", function()
      local fake_bridge = device_faker {
        device_type = HueDeviceTypes.BRIDGE,
        migrated = true,
      }

      local rtype, err_msg = assert(utils.determine_device_type(fake_bridge))
      assert.are.same(HueDeviceTypes.BRIDGE, rtype)
      assert.is_nil(err_msg)
    end)

    it("determine_device_type gets the device type of a non-migrated light", function()
      local fake_light = device_faker {
        device_type = HueDeviceTypes.LIGHT,
        migrated = false,
      }

      local rtype, err_msg = assert(utils.determine_device_type(fake_light))
      assert.are.same(HueDeviceTypes.LIGHT, rtype)
      assert.is_nil(err_msg)
    end)

    it("determine_device_type gets the device type of a non-migrated bridge", function()
      local fake_bridge = device_faker {
        device_type = HueDeviceTypes.BRIDGE,
        migrated = false,
      }

      local rtype, err_msg = assert(utils.determine_device_type(fake_bridge))
      assert.are.same(HueDeviceTypes.BRIDGE, rtype)
      assert.is_nil(err_msg)
    end)

    it("is_bridge returns true for a migrated bridge without DEVICE_TYPE field set, with cached bridge info", function()
      local bridge_faker_args = {
        device_type = HueDeviceTypes.BRIDGE,
        migrated = true,
      }
      local fake_bridge, bridge_info = device_faker(bridge_faker_args)

      local fake_driver = driver_faker {
        bridges = {
          {
            device = fake_bridge,
            info = bridge_info,
            key = bridge_faker_args.bridge_key,
            add_info_to_datastore = true,
            add_key_to_datastore = true,
            map_dni_to_device = true
          }
        }
      }

      assert.True(utils.is_bridge(fake_driver, fake_bridge))
    end)

    it("is_bridge returns true for a migrated bridge without DEVICE_TYPE field set, without cached bridge info",
      function()
        local bridge_faker_args = {
          device_type = HueDeviceTypes.BRIDGE,
          migrated = true,
        }
        local fake_bridge, bridge_info = device_faker(bridge_faker_args)

        local fake_driver = driver_faker {
          bridges = {
            {
              device = fake_bridge,
              info = bridge_info,
              key = bridge_faker_args.bridge_key,
              add_info_to_datastore = false,
              add_key_to_datastore = false,
              map_dni_to_device = false
            }
          }
        }

        assert.True(utils.is_bridge(fake_driver, fake_bridge))
      end)

    it("is_bridge returns true for a non-migrated bridge without DEVICE_TYPE field set, with cached bridge info",
      function()
        local bridge_faker_args = {
          device_type = HueDeviceTypes.BRIDGE,
          migrated = true,
        }
        local fake_bridge, bridge_info = device_faker(bridge_faker_args)

        local fake_driver = driver_faker {
          bridges = {
            {
              device = fake_bridge,
              info = bridge_info,
              key = bridge_faker_args.bridge_key,
              add_info_to_datastore = true,
              add_key_to_datastore = true,
              map_dni_to_device = true
            }
          }
        }

        assert.True(utils.is_bridge(fake_driver, fake_bridge))
      end)

    it("is_bridge returns true for a non-migrated bridge without DEVICE_TYPE field set, without cached bridge info",
      function()
        local bridge_faker_args = {
          device_type = HueDeviceTypes.BRIDGE,
          migrated = true,
        }
        local fake_bridge, bridge_info = device_faker(bridge_faker_args)

        local fake_driver = driver_faker {
          bridges = {
            {
              device = fake_bridge,
              info = bridge_info,
              key = bridge_faker_args.bridge_key,
              add_info_to_datastore = false,
              add_key_to_datastore = false,
              map_dni_to_device = false
            }
          }
        }

        assert.True(utils.is_bridge(fake_driver, fake_bridge))
      end)

    it("is_bridge returns false for a migrated light without DEVICE_TYPE field set, with cached bridge info", function()
      local light_faker_args = {
        device_type = HueDeviceTypes.LIGHT,
        migrated = true,
      }
      local fake_light, _ = device_faker(light_faker_args)

      local fake_driver = driver_faker {}

      assert.False(utils.is_bridge(fake_driver, fake_light))
    end)

    it("is_bridge returns false for a migrated light without DEVICE_TYPE field set, without cached bridge info",
      function()
        local light_faker_args = {
          device_type = HueDeviceTypes.LIGHT,
          migrated = true,
        }
        local fake_light, _ = device_faker(light_faker_args)

        local fake_driver = driver_faker {}

        assert.False(utils.is_bridge(fake_driver, fake_light))
      end)

    it("is_bridge returns false for a non-migrated light without DEVICE_TYPE field set, with cached bridge info",
      function()
        local light_faker_args = {
          device_type = HueDeviceTypes.LIGHT,
          migrated = false,
        }
        local fake_light, _ = device_faker(light_faker_args)

        local fake_driver = driver_faker {}

        assert.False(utils.is_bridge(fake_driver, fake_light))
      end)

    it("is_bridge returns false for a non-migrated light without DEVICE_TYPE field set, without cached bridge info",
      function()
        local light_faker_args = {
          device_type = HueDeviceTypes.LIGHT,
          migrated = false,
        }
        local fake_light, _ = device_faker(light_faker_args)

        local fake_driver = driver_faker {}

        assert.False(utils.is_bridge(fake_driver, fake_light))
      end)

    it("is_edge_bridge and is_dth_bridge behave as expected for a migrated bridge", function()
      local bridge_faker_args = {
        device_type = HueDeviceTypes.BRIDGE,
        migrated = true,
      }
      local fake_bridge, _ = device_faker(bridge_faker_args)

      assert.True(utils.is_dth_bridge(fake_bridge))
      assert.False(utils.is_edge_bridge(fake_bridge))
    end)

    it("is_edge_bridge and is_dth_bridge behave as expected for a non-migrated bridge", function()
      local bridge_faker_args = {
        device_type = HueDeviceTypes.BRIDGE,
        migrated = false,
      }
      local fake_bridge, _ = device_faker(bridge_faker_args)

      assert.True(utils.is_edge_bridge(fake_bridge))
      assert.False(utils.is_dth_bridge(fake_bridge))
    end)

    it("is_dth_light behaves as expected for a migrated light", function()
      local light_faker_args = {
        device_type = HueDeviceTypes.LIGHT,
        migrated = true,
      }
      local fake_bridge, _ = device_faker(light_faker_args)

      assert.True(utils.is_dth_light(fake_bridge))
    end)

    it("is_dth_light behaves as expected for a non-migrated light", function()
      local light_faker_args = {
        device_type = HueDeviceTypes.LIGHT,
        migrated = false,
      }
      local fake_bridge, _ = device_faker(light_faker_args)

      assert.False(utils.is_dth_light(fake_bridge))
    end)

    it("get_hue_bridge_for_device returns the passed in bridge for a migrated bridge when bridge info is not cached",
      function()
        local bridge_faker_args = {
          device_type = HueDeviceTypes.BRIDGE,
          migrated = true,
        }
        local fake_bridge, bridge_info = device_faker(bridge_faker_args)
        local fake_driver = driver_faker {
          bridges = {
            {
              device = fake_bridge,
              info = bridge_info,
              key = bridge_faker_args.bridge_key,
            }
          }
        }

        assert.are.same(fake_bridge, utils.get_hue_bridge_for_device(fake_driver, fake_bridge))
      end)

    it("get_hue_bridge_for_device returns the passed in bridge for a non-migrated bridge when bridge info is not cached",
      function()
        local bridge_faker_args = {
          device_type = HueDeviceTypes.BRIDGE,
          migrated = false,
        }
        local fake_bridge, bridge_info = device_faker(bridge_faker_args)
        local fake_driver = driver_faker {
          bridges = {
            {
              device = fake_bridge,
              info = bridge_info,
              key = bridge_faker_args.bridge_key,
            }
          }
        }
        assert.are.same(fake_bridge, utils.get_hue_bridge_for_device(fake_driver, fake_bridge))
      end)

    it("get_hue_bridge_for_device returns the passed in bridge for a migrated bridge when bridge info is cached",
      function()
        local bridge_faker_args = {
          device_type = HueDeviceTypes.BRIDGE,
          migrated = true,
        }
        local fake_bridge, bridge_info = device_faker(bridge_faker_args)
        local fake_driver = driver_faker {
          bridges = {
            {
              device = fake_bridge,
              info = bridge_info,
              key = bridge_faker_args.bridge_key,
              add_info_to_datastore = true,
              add_key_to_datastore = true,
              map_dni_to_device = true
            }
          }
        }

        assert.are.same(fake_bridge, utils.get_hue_bridge_for_device(fake_driver, fake_bridge))
      end)

    it("get_hue_bridge_for_device returns the passed in bridge for a non-migrated bridge when bridge info is cached",
      function()
        local bridge_faker_args = {
          device_type = HueDeviceTypes.BRIDGE,
          migrated = false,
        }
        local fake_bridge, bridge_info = device_faker(bridge_faker_args)
        local fake_driver = driver_faker {
          bridges = {
            {
              device = fake_bridge,
              info = bridge_info,
              key = bridge_faker_args.bridge_key,
              add_info_to_datastore = true,
              add_key_to_datastore = true,
              map_dni_to_device = true
            }
          }
        }
        assert.are.same(fake_bridge, utils.get_hue_bridge_for_device(fake_driver, fake_bridge))
      end)

    it("get_hue_bridge_for_device returns the parent bridge for a migrated light when bridge info is not cached",
      function()
        local bridge_faker_args = {
          device_type = HueDeviceTypes.BRIDGE,
          migrated = true,
        }
        local fake_bridge, bridge_info = device_faker(bridge_faker_args)

        local light_faker_args = {
          device_type = HueDeviceTypes.LIGHT,
          migrated = true
        }
        local fake_light = device_faker(light_faker_args, bridge_info)

        local fake_driver = driver_faker {
          bridges = {
            {
              device = fake_bridge,
              info = bridge_info,
              key = bridge_faker_args.bridge_key,
            }
          },
          child_devices = {
            {
              device = fake_light,
              parent_bridge_info = bridge_info
            }
          }
        }

        assert.are.same(fake_bridge, utils.get_hue_bridge_for_device(fake_driver, fake_light))
      end)

    it("get_hue_bridge_for_device returns the parent bridge for a non-migrated light when bridge info is not cached",
      function()
        local bridge_faker_args = {
          device_type = HueDeviceTypes.BRIDGE,
          migrated = false,
        }
        local fake_bridge, bridge_info = device_faker(bridge_faker_args)

        local light_faker_args = {
          device_type = HueDeviceTypes.LIGHT,
          migrated = false
        }
        local fake_light = device_faker(light_faker_args, bridge_info)

        local fake_driver = driver_faker {
          bridges = {
            {
              device = fake_bridge,
              info = bridge_info,
              key = bridge_faker_args.bridge_key,
            }
          },
          child_devices = {
            {
              device = fake_light,
              parent_bridge_info = bridge_info
            }
          }
        }

        assert.are.same(fake_bridge, utils.get_hue_bridge_for_device(fake_driver, fake_light))
      end)

    it("get_hue_bridge_for_device returns the parent bridge for a migrated light when bridge info is cached", function()
      local bridge_faker_args = {
        device_type = HueDeviceTypes.BRIDGE,
        migrated = true,
      }
      local fake_bridge, bridge_info = device_faker(bridge_faker_args)

      local light_faker_args = {
        device_type = HueDeviceTypes.LIGHT,
        migrated = true
      }
      local fake_light = device_faker(light_faker_args, bridge_info)

      local fake_driver = driver_faker {
        bridges = {
          {
            device = fake_bridge,
            info = bridge_info,
            key = bridge_faker_args.bridge_key,
            add_info_to_datastore = true,
            add_key_to_datastore = true,
            map_dni_to_device = true
          }
        },
        child_devices = {
          {
            device = fake_light,
            parent_bridge_info = bridge_info
          }
        }
      }

      assert.are.same(fake_bridge, utils.get_hue_bridge_for_device(fake_driver, fake_light))
    end)

    it("get_hue_bridge_for_device returns the parent bridge for a non-migrated light when bridge info is cached",
      function()
        local bridge_faker_args = {
          device_type = HueDeviceTypes.BRIDGE,
          migrated = false,
        }
        local fake_bridge, bridge_info = device_faker(bridge_faker_args)

        local light_faker_args = {
          device_type = HueDeviceTypes.LIGHT,
          migrated = false
        }
        local fake_light = device_faker(light_faker_args, bridge_info)

        local fake_driver = driver_faker {
          bridges = {
            {
              device = fake_bridge,
              info = bridge_info,
              key = bridge_faker_args.bridge_key,
              add_info_to_datastore = true,
              add_key_to_datastore = true,
              map_dni_to_device = true
            }
          },
          child_devices = {
            {
              device = fake_light,
              parent_bridge_info = bridge_info
            }
          }
        }

        assert.are.same(fake_bridge, utils.get_hue_bridge_for_device(fake_driver, fake_light))
      end)
  end)
end)
