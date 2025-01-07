local log = require "log"
local st_utils = require "st.utils"
-- trick to fix the VS Code Lua Language Server typechecking
---@type fun(val: any?, name: string?, multi_line: boolean?): string
st_utils.stringify_table = st_utils.stringify_table

local logjam = {}

logjam.real_log = log.log

logjam.enabled_modules = {}

function logjam.inject_global()
  for field_key, level_key in pairs(log) do
    if
        string.find(field_key, "LOG_LEVEL_") and
        type(level_key) == "string" and
        type(log[level_key]) == "function"
    then
      log[level_key] = logjam[level_key]
      local level_with_key = string.format("%s_with", level_key)
      if type(log[level_with_key]) == "function" then
        log[level_with_key] = logjam[level_with_key]
      end
    end
  end
  log.log = logjam.log
end

function logjam.enable_passthrough()
  logjam.passthrough = true
end

function logjam.disable_passthrough()
  logjam.passthrough = false
end

function logjam.enable(module)
  logjam.enabled_modules[module] = true
end

function logjam.disable(module)
  logjam.enabled_modules[module] = nil
end

function logjam.log(opts, level, ...)
  local call_info
  if not opts.call_info then
    call_info = debug.getinfo(2)
  else
    call_info = opts.call_info
  end
  opts.call_info = nil

  local module_name = nil
  if type(call_info.source) == "string" then
    module_name =
    call_info.source
      :gsub("%.lua", "")
      :gsub("/init", "")
      :gsub("/", ".")
      :gsub("^init$", "philips-hue")
  end

  local module_enabled = false
  local module_prefix = ""
  if type(module_name) == "string" and module_name:len() > 0 then
    module_enabled = logjam.enabled_modules[module_name]
    module_prefix = string.format("[%s] ", module_name)
  end

  -- explicit on/off log option takes precedence, so that we can allow
  -- `false` to override passthrough/module_enabled flags.
  if type(opts.on) == "boolean" then
    if opts.on then
      logjam.real_log(opts, level, module_prefix, ...)
    end
    return
  end
  if logjam.passthrough or module_enabled then
    logjam.real_log(opts, level, module_prefix, ...)
  end
end

for field_key, level_key in pairs(log) do
  if
      string.find(field_key, "LOG_LEVEL_") and
      type(level_key) == "string" and
      type(log[level_key]) == "function"
  then
    local level_with_key = string.format("%s_with", level_key)
    logjam[level_key] = function(...)
      local first_arg = select(1, ...)
      local opts = {}
      local log_args_start_idx = 1
      if type(first_arg) == "boolean" then
        opts.on = first_arg
        log_args_start_idx = 2
      elseif type(first_arg) == "table" then
        opts = first_arg
        log_args_start_idx = 2
      end
      local info = debug.getinfo(2)
      opts.call_info = info
      logjam.log(opts, level_key, select(log_args_start_idx, ...))
    end

    logjam[level_with_key] = function(opts, ...)
      local log_opts = {}
      local log_args = table.pack(...)
      if type(opts) == "table" then
        for k, v in pairs(opts) do
          log_opts[k] = v
        end
      elseif type(opts) == "boolean" then
        log_opts.on = opts
      elseif opts ~= nil then
        log_args.insert(log_args, 1, opts)
      end
      local info = debug.getinfo(2)
      log_opts.call_info = info
      logjam.log(log_opts, level_key, table.unpack(log_args))
    end
  end
end

return logjam
