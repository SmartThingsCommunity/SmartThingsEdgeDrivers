--- We use this as a quick way to silence the logging in
--- `lustre`, as it has a high volume of trace and debug
--- logging.

return {
  trace = function(...) end,
  debug = function(...) end,
  info = function(...) end,
  warn = function(...) end,
  error = function(...) end,
}
