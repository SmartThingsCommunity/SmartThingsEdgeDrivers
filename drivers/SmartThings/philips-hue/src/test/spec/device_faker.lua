local utils = require "utils"
local lazy_fakers = utils.lazy_handler_loader("fakers")

local st_utils = require "st.utils"
-- trick to fix the VS Code Lua Language Server typechecking
---@type fun(val: any?, name: string?, multi_line: boolean?): string
st_utils.stringify_table = st_utils.stringify_table

local test_helpers = require "test_helpers"

local fake_device_mt = {
  set_field = function(device, key, val, _opts) (device.fields or {})[key] = val end,
  get_field = function(device, key) return (device.fields or {})[key] end
}
fake_device_mt.__index = fake_device_mt

---Make a fake device
---@param args table args for the faker
---@param bridge_info table? the hue bridge info for the faker to pull from, will be randomly generated if absent
---@return table fake_device faked device
---@return HueBridgeInfo bridge_info the bridge info used for this fake device
local function device_faker(args, bridge_info)
  local faker = string.format("%s_faker", args.device_type)
  bridge_info = bridge_info or test_helpers.random_bridge_info()
  args.bridge_key = args.bridge_key or test_helpers.random_hue_bridge_key()

  local faked_device = lazy_fakers[faker](args, bridge_info)
  assert(faked_device, string.format("No faking available for device type %s", args.device_type))

  faked_device.label = args.name or "Fake Hue Device"
  if args.migrated == true and type(args.data) == "table" then
    faked_device.data = faked_device.data or {}
    for k, v in pairs(args.data) do
      rawset(faked_device.data, k, v)
    end
  end

  if type(args.fields) == "table" then
    faked_device.fields = faked_device.fields or {}
    for k, v in pairs(args.fields) do
      rawset(faked_device.fields, k, v)
    end
  end

  faked_device.id = args.id or st_utils.generate_uuid_v4()

  return setmetatable(faked_device, fake_device_mt), bridge_info
end

return device_faker
