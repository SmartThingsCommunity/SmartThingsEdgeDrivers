local security = require "st.security"

local function my_secret_data_handler(driver, device, secret_data)
  print("Hello from the child!")
end

local demo_child = {
  secret_data_handlers = {
    [security.SECRET_KIND_AQARA] = my_secret_data_handler,
  }
}

return demo_child
