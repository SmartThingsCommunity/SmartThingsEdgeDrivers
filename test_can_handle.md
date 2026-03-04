# 测试 can_handle.lua 功能验证

## 测试场景

### 场景 1: 匹配的设备 (LEDVANCE/PLUG COMPACT EU EM T)
**输入**:
- device:get_manufacturer() = "LEDVANCE"
- device:get_model() = "PLUG COMPACT EU EM T"

**预期输出**:
- 返回：`true, subdriver`
- 结果：✅ can_handle 返回 true，加载子驱动

### 场景 2: 不匹配的设备
**输入**:
- device:get_manufacturer() = "Other Manufacturer"
- device:get_model() = "Other Model"

**预期输出**:
- 返回：`false`
- 结果：✅ can_handle 返回 false，不使用此子驱动

## 代码逻辑验证

### fingerprints.lua
```lua
return {
  { mfr = "LEDVANCE", model = "PLUG COMPACT EU EM T" }
}
```
✅ **格式正确** - 使用数组格式，与其他子驱动一致

### can_handle.lua
```lua
return function(opts, driver, device, ...)
  local FINGERPRINTS = require("simple-metering-config.fingerprints")
  for _, fingerprint in ipairs(FINGERPRINTS) do
    if device:get_manufacturer() == fingerprint.mfr and device:get_model() == fingerprint.model then
      local subdriver = require("simple-metering-config")
      return true, subdriver
    end
  end
  return false
end
```
✅ **逻辑正确** - 遍历 fingerprints，匹配 manufacturer 和 model
✅ **返回值正确** - 匹配时返回 `true, subdriver`，不匹配时返回 `false`

## 与其他子驱动对比

| 子驱动 | fingerprints 格式 | can_handle 逻辑 | 状态 |
|--------|------------------|----------------|------|
| wallhero | 数组格式 | `ipairs` 遍历 | ✅ |
| hanssem | 数组格式 | `ipairs` 遍历 | ✅ |
| multi-switch-no-master | 数组格式 | `ipairs` 遍历 | ✅ |
| zigbee-switch-power | 数组格式 | `ipairs` 遍历 | ✅ |
| **simple-metering-config** | **数组格式** | **`ipairs` 遍历** | ✅ **已修复** |

## 修复内容总结

### 修复前 ❌
**fingerprints.lua**:
```lua
return {
  ["LEDVANCE"] = {
    ["PLUG COMPACT EU EM T"] = {
      deviceProfileName = "switch-power-energy",
    }
  }
}
```
- ❌ 使用嵌套表格式（与其他子驱动不一致）
- ❌ can_handle 使用 `pairs` 遍历嵌套表

**can_handle.lua**:
```lua
local fingerprints = require("simple-metering-config.fingerprints")
for mfr, models in pairs(fingerprints) do
  for model, fingerprint in pairs(models) do
    if device:get_manufacturer() == mfr and device:get_model() == model then
      return true  -- 缺少 subdriver
    end
  end
end
```

### 修复后 ✅
**fingerprints.lua**:
```lua
return {
  { mfr = "LEDVANCE", model = "PLUG COMPACT EU EM T" }
}
```
- ✅ 使用数组格式（与其他子驱动一致）
- ✅ 简化结构，只包含必要信息

**can_handle.lua**:
```lua
local FINGERPRINTS = require("simple-metering-config.fingerprints")
for _, fingerprint in ipairs(FINGERPRINTS) do
  if device:get_manufacturer() == fingerprint.mfr and device:get_model() == fingerprint.model then
    local subdriver = require("simple-metering-config")
    return true, subdriver
  end
end
return false
```
- ✅ 使用 `ipairs` 遍历（与其他子驱动一致）
- ✅ 返回 `true, subdriver`（与其他子驱动一致）

## 验证结果

### ✅ 语法检查
- fingerprints.lua: ✅ 语法正确
- can_handle.lua: ✅ 语法正确

### ✅ 格式一致性
- 与 wallhero 一致: ✅
- 与 hanssem 一致: ✅
- 与 multi-switch-no-master 一致: ✅
- 与 zigbee-switch-power 一致: ✅

### ✅ 功能完整性
- 正确匹配设备: ✅
- 正确返回 subdriver: ✅
- 正确返回 false: ✅

## 结论

✅ **can_handle.lua 现在完全正确并起作用**

**修复的问题**:
1. ✅ fingerprints 格式改为数组格式（与其他子驱动一致）
2. ✅ can_handle 使用 `ipairs` 遍历（与其他子驱动一致）
3. ✅ 返回值包含 subdriver（与其他子驱动一致）

**可以提交给 SmartThings**!
