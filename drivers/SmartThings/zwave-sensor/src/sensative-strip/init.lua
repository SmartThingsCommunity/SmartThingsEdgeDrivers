-- Copyright 2025 SmartThings, Inc.
-- Licensed under the Apache License, Version 2.0

  lifecycle_handlers = {
    doConfigure = do_configure
  },
  NAME = "sensative_strip",
  can_handle = require("sensative-strip.can_handle"),
}

return sensative_strip
