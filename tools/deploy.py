import os, subprocess, requests, json, time, yaml, csv

BRANCH = os.environ.get('BRANCH')
ENVIRONMENT = os.environ.get('ENVIRONMENT')
CHANGED_DRIVERS = os.environ.get('CHANGED_DRIVERS')
# configurable from Jenkins to override and manually set the drivers to be uploaded
DRIVERS_OVERRIDE = os.environ.get('DRIVERS_OVERRIDE') or "[]"
print(BRANCH)
print(ENVIRONMENT)
print(CHANGED_DRIVERS)
branch_environment = "{}_{}_".format(BRANCH, ENVIRONMENT)
ENVIRONMENT_URL = os.environ.get(ENVIRONMENT+'_ENVIRONMENT_URL')
if not ENVIRONMENT_URL:
  print("No environment url specified, aborting.")
  exit(0)

UPLOAD_URL = ENVIRONMENT_URL+"/drivers/package"
CHANNEL_ID = os.environ.get(branch_environment+'CHANNEL_ID')
if not CHANNEL_ID:
  print("No channel id specified, aborting.")
  exit(0)

UPDATE_URL = ENVIRONMENT_URL+"/channels/"+CHANNEL_ID+"/drivers/bulk"
TOKEN = os.environ.get(ENVIRONMENT+'_TOKEN')
DRIVERID = "driverId"
VERSION = "version"
PACKAGEKEY = "packageKey"

BOSE_APPKEY = os.environ.get("BOSE_AUDIONOTIFICATION_APPKEY")
SONOS_API_KEY = os.environ.get("SONOS_API_KEY")

print(ENVIRONMENT_URL)

driver_updates = []
drivers_updated = []
uploaded_drivers = {}

## do translations here
LOCALE = os.environ.get('LOCALE')
if LOCALE:
  LOCALE = LOCALE.lower()

  current_path = os.path.dirname(__file__)
  localization_dir = os.path.join(current_path, "localizations")
  localization_file = os.path.join(localization_dir, LOCALE+".csv")
  slash_escape = str.maketrans({"/": r"\/", "(": r"\(", ")": r"\)"})
  if os.path.isfile(localization_file):
    print("Localizing from english to "+LOCALE+" using "+str(localization_file))
    with open(localization_file) as csvfile:
      reader = csv.reader(csvfile)
      for row in reader:
        print("en: "+row[0]+" "+LOCALE+": "+row[1])
        subprocess.run(
          "find . -name 'fingerprints.yml' | xargs sed -i -E 's/deviceLabel ?: \"?"+row[0].translate(slash_escape)+"\"?/deviceLabel: "+row[1].translate(slash_escape)+"/g'",
          shell=True,
          cwd=os.path.dirname(current_path)
        )

    subprocess.run("git status", shell=True)

# Get drivers currently on the channel
response = requests.get(
  ENVIRONMENT_URL+"/channels/"+CHANNEL_ID+"/drivers",
  headers={
    "Accept": "application/vnd.smartthings+json;v=20200810",
    "Authorization": "Bearer "+TOKEN,
    "X-ST-LOG-LEVEL": "TRACE"
  }
)
if response.status_code != 200:
  print("Failed to retrieve channel's current drivers")
  print("Error code: "+str(response.status_code))
  print("Error response: "+response.text)
else:
  response_json = json.loads(response.text)["items"]
  for driver in response_json:
    # get detailed driver info for currently-uploaded drivers
    driver_info_response = requests.post(
      ENVIRONMENT_URL+"/drivers/search",
      headers = {
        "Accept": "application/vnd.smartthings+json;v=20200810",
        "Authorization": "Bearer "+TOKEN,
        "X-ST-LOG-LEVEL": "TRACE"
      },
      json = {
        DRIVERID: driver[DRIVERID],
        "driverVersion": driver[VERSION]
      }
    )
    driver_info_response_json = json.loads(driver_info_response.text)["items"][0]
    if PACKAGEKEY in driver_info_response_json:
      packageKey = driver_info_response_json[PACKAGEKEY]
      if VERSION in driver.keys() and DRIVERID in driver.keys():
        uploaded_drivers[packageKey] = {DRIVERID: driver[DRIVERID], VERSION: driver[VERSION]}

# Make sure we're running in the root of the drivers directory
a = subprocess.run(["git", "rev-parse", "--show-toplevel"], capture_output=True)
os.chdir(a.stdout.decode().strip()+"/drivers/")

# Get list of all partner folders
partners = [partner.name for partner in os.scandir('.') if partner.is_dir()]
for partner in partners:
  os.chdir(os.getcwd()+'/'+partner)
  # get a list of all drivers from this partner
  drivers = [driver.name for driver in os.scandir('.') if driver.is_dir()]

  # For each driver, first package the driver locally, then upload it
  # after it's been uploaded, hold on to the driver id and version
  for driver in drivers:
    if driver in CHANGED_DRIVERS or driver in DRIVERS_OVERRIDE:
      package_key = ""
      with open(driver+"/config.yml", 'r') as config_file:
        package_key = yaml.safe_load(config_file)["packageKey"]
        print(package_key)
      if package_key == "bose" and BOSE_APPKEY:
        # write the app key into a app_key.lua (overwrite if exists already)
        subprocess.run(["touch -a ./src/app_key.lua && echo \'return \"" + BOSE_APPKEY +  "\"\n\' > ./src/app_key.lua"], cwd=driver, shell=True, capture_output=True)
      if package_key == "sonos" and SONOS_API_KEY:
        subprocess.run(["echo \'return \"" + SONOS_API_KEY +  "\"\n\' > ./src/app_key.lua"], cwd=driver, shell=True, capture_output=True)
      retries = 0
      while not os.path.exists(driver+".zip") and retries < 5:
        try:
          subprocess.run(["zip -r ../"+driver+".zip config.yml fingerprints.yml search-parameters.y*ml $(find . -name \"*.pem\") $(find . -name \"*.crt\") $(find profiles -name \"*.y*ml\") $(find . -name \"*.lua\") -x \"*test*\""], cwd=driver, shell=True, capture_output=True, check=True)
        except subprocess.CalledProcessError as error:
          print(error.stderr)
        retries += 1
      if retries >= 5:
        print("5 zip failires, skipping "+package_key+" and continuing.")
        continue
      with open(driver+".zip", 'rb') as driver_package:
        data = driver_package.read()
        response = None
        retries = 0
        while response == None or (response.status_code == 500 or response.status_code == 429):
          response = requests.post(
            UPLOAD_URL,
            headers={
              "Content-Type": "application/zip",
              "Accept": "application/vnd.smartthings+json;v=20200810",
              "Authorization": "Bearer "+TOKEN,
              "X-ST-LOG-LEVEL": "TRACE"},
            data=data)
          if response.status_code != 200:
            print("Failed to upload driver "+driver)
            print("Error code: "+str(response.status_code))
            print("Error response: "+response.text)
            if response.status_code == 500 or response.status_code == 429:
              retries = retries + 1
              if retries > 3:
                break # give up
              if response.status_code == 429:
                time.sleep(10)
          else:
            print("Uploaded package successfully: "+driver)
            drivers_updated.append(driver)
            response_json = json.loads(response.text)
            uploaded_drivers[package_key] = {DRIVERID: response_json[DRIVERID], VERSION: response_json[VERSION]}
      subprocess.run(["rm", driver+".zip"], capture_output=True)


  # go back up to the root 'drivers' directory after completing each partner's drivers uploads
  os.chdir("..")

for package_key, driver_info in uploaded_drivers.items():
  print("Uploading package: {} driver id: {} version: {}".format(package_key, driver_info[DRIVERID], driver_info[VERSION]))
  driver_updates.append({DRIVERID: driver_info[DRIVERID], VERSION: driver_info[VERSION]})

response = requests.put(
  UPDATE_URL,
  headers={
    "Accept": "application/vnd.smartthings+json;v=20200810",
    "Authorization": "Bearer "+TOKEN,
    "Content-Type": "application/json",
    "X-ST-LOG-LEVEL": "TRACE"
  },
  data=json.dumps(driver_updates)
)
if response.status_code != 204:
  print("Failed to bulk update drivers")
  print("Error code: "+str(response.status_code))
  print("Error response: "+response.text)
  exit(1)

print("Update drivers: ")
print(drivers_updated)
print("\nDrivers currently deplpyed: ")
print(uploaded_drivers.keys())
