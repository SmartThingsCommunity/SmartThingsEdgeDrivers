local lazy_load = require "lazy_load_subdriver"

return {
    lazy_load("qubino-switches.qubino-relays"),
    lazy_load("qubino-switches.qubino-dimmer"),
}