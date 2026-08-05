---@generic T
---@class Ok<T>: { is_ok: (fun(self): true), is_err: (fun(self): false), unwrap: (fun(self): T ) }

---@generic E
---@class Err<E>: { is_ok: (fun(self): false), is_err: (fun(self): true), unwrap: (fun(self): nil,E ) }

---@generic T,E
---@alias Result<T,E>
---| Ok<T>
---| Err<E>

local Result = {}

local fallback = setmetatable({}, { __metatable = { variant = "N/A", _discriminant = false } })

local _value_mt

_value_mt = {
  __newindex = function() end
}


function _value_mt:is_ok()
  return getmetatable(self).variant == "ok"
end

function _value_mt:is_err()
  return not self:is_ok()
end

function _value_mt:unwrap()
  local hidden = getmetatable(self)
  if hidden.variant == "ok" then
    return hidden._inner_ok
  end

  return nil, hidden._inner_err
end

_value_mt.__index = _value_mt

local function _get_variant_mt(tbl)
  return getmetatable(tbl or {}) or getmetatable(fallback)
end

local function _get_variant(tbl)
  return _get_variant_mt(tbl).variant
end

local function _is_result(tbl)
  local variant_mt = _get_variant_mt(tbl)
  local maybe_value_mt = getmetatable(variant_mt)
  return variant_mt.variant ~= "N/A" and maybe_value_mt == _value_mt
end

_value_mt.__tostring = function(self)
  local maybe_ok, maybe_err = self:unwrap()
  if type(maybe_ok) == "string" then
    maybe_ok = string.format("\"%s\"", maybe_ok)
  end
  if type(maybe_err) == "string" then
    maybe_err = string.format("\"%s\"", maybe_err)
  end
  return string.format("%s(%s)", _get_variant(self):gsub("^%l", string.upper), maybe_ok or maybe_err)
end

---@generic T,E
---@param variant "ok"|"err"
---@param other T|E
---@return Result<T,E>
local __enum_call = function(variant, other)
  assert(other ~= nil, debug.traceback())
  local inner_key = string.format("_inner_%s", variant)
  local inner = {
    variant = variant,
    [inner_key] = other
  }
  return setmetatable({},
    { __index = _value_mt, __tostring = _value_mt.__tostring, __metatable = setmetatable(inner, _value_mt) })
end

---@generic T
---@param other T
---@return Ok<T>
function Result.Ok(other) return __enum_call("ok", other) end

---@generic E
---@param other E
---@return Err<E>
function Result.Err(other) return __enum_call("err", other) end

---@generic T, E
---@param let_tbl { ["Ok"]: Result<T,E> } | { ["Err"]: Result<T,E> }
---@return fun(): T|E|nil
Result.let = function(let_tbl)
  local variant_key, result = next(let_tbl)
  assert(variant_key == "Ok" or variant_key == "Err")

  local type_variant = variant_key:lower()
  local value_variant = _get_variant(result)
  local is_result = _is_result(result)

  if type_variant == value_variant and result and is_result then
    local done = false
    return function()
      if done then return nil end

      done = true
      local maybe_ok, maybe_err = result:unwrap()
      if maybe_ok then return maybe_ok end
      return maybe_err
    end
  end

  return function()
    return nil
  end
end

local _mod_mt = {
  __metatable = "Result",
  __index = Result,
  __call = function(mod_tbl, kwargs)
    if type(kwargs) == "table" and kwargs.register_globals == true then
      _G["Ok"] = Result.Ok
      _G["Err"] = Result.Err
      _G["let"] = Result.let
    end
  end,
  __tostring = function(mod_tbl)
    return "Lua Result Type"
  end
}

return setmetatable(Result, _mod_mt)
