local capabilities = require "st.capabilities"
local Driver = require "st.driver"
local log = require "log"
local security = require "st.security"
local ds = require "datastore"

my_ds = ds.init()

function dump(data)
  if type(data) == "table" then
    local s = '{ '
    for k,v in pairs(data) do
      if type(k) ~= 'number' then k = '"'..k..'"' end
      s = s .. '['..k..'] = ' .. dump(v) .. ','
    end
    return s .. '}'
  else
    return tostring(data)
  end
end

local function my_secret_data_handler(data)
  log.info(dump(data))
  if data.result == "success" then
    --do successful things
  else
    --do failure things
  end
end

local function discovery_handler(driver, _, should_continue)
  log.info("starting_discovery")
  local available_ciphers = security.available_ciphers()
  log.info("available ciphers")
  for _, cipher in pairs(available_ciphers) do
    log.info(cipher)
  end
  example_aes_128_ecb()
  example_aes_256_ecb()
  example_errors()
  local device_list = driver:get_devices()
  local zigbee_id = "\x01\x02\x03\x04\x05\x06\x07\x08";
  local res, err = security.get_aqara_secret(zigbee_id, "encrypted_pub_key", "model_name", "test_mn_id", "test_setup_id", "test_product_id")
  if res then
    print(res)
  else
    print(err)
  end
end

function example_errors()
  local input_data = "oh wow, here is some test data"
  -- incorrect key length
  local key = "\x00\x01\x02\x03\x04\x05\x06\x07\x08\x09\x0A\x0B\x0C\x0D\x0E"
  local opts = {cipher = "aes128-ecb"}
  local result, err = security.encrypt_bytes(input_data, key, opts)
  if not result then
    print(err)
  else
    print("incorrect key length was not an error")
  end
  -- incorrect iv length
  local key = "\x00\x01\x02\x03\x04\x05\x06\x07\x08\x09\x0A\x0B\x0C\x0D\x0E\x0F"
  local opts = {
    iv = "\xde\xad\xbe\xef\xbe\xef\xbe\xef\xbe\xef\xbe\xef\xbe\xef\xbe",
    cipher = "aes128-cbc",
    }
  local result, err = security.encrypt_bytes(input_data, key, opts)
  print(err)
  -- non-supported cipher
  local opts = {cipher = "aes128-beef"}
  local result, err = security.encrypt_bytes(input_data, key, opts)
  print(err)
  -- incorrect block length
  local input_data = "0123456789abcde"
  local opts = {cipher = "aes128-ecb", padding = false}
  local result, err = security.encrypt_bytes(input_data, key, opts)
  print(err)
end

function example_aes_128_ecb() 
  log.info("AES128 testing...")
  local input_data = "oh wow, here is some test data"
  local expected_result = "\xE1\x9D\x5E\x19\x7F\x43\xD2\x98\x9C\x92\x99\xF5\xF7\xF3\x97\x3B\x0F\x19\xDA\x4D\x5B\xD1\x9C\x11\x55\xC2\xF3\x0A\xE7\xE8\x12\x13"
  local key = "\x00\x01\x02\x03\x04\x05\x06\x07\x08\x09\x0A\x0B\x0C\x0D\x0E\x0F"
  local opts = {cipher = "aes128-ecb"}
  local result, err = security.encrypt_bytes(input_data, key, opts)
  assert(result == expected_result)
  local final_result, err = security.decrypt_bytes(result, key, opts)
  assert(final_result == input_data)
  log.info("AES128 passed!")
end

function example_aes_256_ecb() 
  log.info("AES256 testing...")
  local input_data = "oh wow, here is some test data"
  local expected_result = "\x03\x61\xF6\xBE\x3B\xD4\x8E\x6E\x80\x44\x83\x5A\xEB\x07\x22\xDD\x0B\x54\xAC\x4D\x20\x5E\x54\xF6\xB0\xA0\x14\xEA\x9E\xED\xCA\x29"
  local key = "\x00\x01\x02\x03\x04\x05\x06\x07\x08\x09\x0A\x0B\x0C\x0D\x0E\x0F\x00\x01\x02\x03\x04\x05\x06\x07\x08\x09\x0A\x0B\x0C\x0D\x0E\x0F"
  local opts = {cipher = "aes256-ecb"}
  local result, err = security.encrypt_bytes(input_data, key, opts)
  assert(result == expected_result)
  local final_result, err = security.decrypt_bytes(result, key, opts)
  assert(final_result == input_data)
  log.info("AES256 passed!")
end

local aqara_security_demo = Driver("aqara_security_demo", {
  discovery = discovery_handler,
  supported_capabilities = {
    capabilities.refresh,
  },
  sub_drivers = {
    require("child"),
  },
  secret_data_handlers = {
    [security.SECRET_KIND_AQARA] = my_secret_data_handler,
  }
})

if aqara_security_demo.datastore and type(aqara_security_demo.datastore.cnt) == "number" then
  my_ds.cnt = aqara_security_demo.datastore.cnt + 1
  my_ds:save()
else
  my_ds.cnt = 1
  my_ds:save()
end
log.info("my_ds.cnt = "..my_ds.cnt)

log.info("Demo running!")
aqara_security_demo:run()
