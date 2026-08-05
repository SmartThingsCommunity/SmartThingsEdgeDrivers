-- Copyright 2025 SmartThings, Inc.
-- Licensed under the Apache License, Version 2.0

local lazy_load = require "lazy_load_subdriver"
return {
    lazy_load("qubino-switches.qubino-relays.qubino-flush-1-relay"),
    lazy_load("qubino-switches.qubino-relays.qubino-flush-1d-relay"),
    lazy_load("qubino-switches.qubino-relays.qubino-flush-2-relay"),
}
