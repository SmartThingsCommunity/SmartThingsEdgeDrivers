import requests, subprocess, os, sys, json, time, yaml, csv


ENVIRONMENT = os.environ.get('ENVIRONMENT')
DRY_RUN = os.environ.get('DRY_RUN')
TOKEN = os.environ.get('TOKEN')
ENVIRONMENT_URL = os.environ.get('ENVIRONMENT_URL')
PROD_CHANNEL_ID = os.environ.get('PROD_CHANNEL_ID')
BRANCH = os.environ.get("BRANCH")

UPLOAD_URL = ENVIRONMENT_URL+"/drivers/package"

BOSE_APPKEY = os.environ.get("BOSE_AUDIONOTIFICATION_APPKEY")
SONOS_API_KEY = os.environ.get("SONOS_API_KEY") or "N/A"
SONOS_OAUTH_API_KEY = os.environ.get("SONOS_OAUTH_API_KEY") or "N/A"
SONOS_API_KEY_LUA_TEMPLATE = f"""return {{
  s1_key = "{SONOS_API_KEY}",
  oauth_key = "{SONOS_OAUTH_API_KEY}",
}}
"""

GIT_URL = "https://github.com/SmartThingsCommunity/SmartThingsEdgeDrivers"

DRIVERID = "driverId"
VERSION = "version"
PACKAGEKEY = "packageKey"


# Pulls repo, changes directory into and checks out production branch
def pull_prod():
    result = subprocess.run(
        f"git clone {GIT_URL}",
        shell=True,
    )
    if result.returncode != 0:
        print("Failed to clone SmartThingsEdgeDrivers repo", file=sys.stderr)
        exit(1)

    print("Changing directory into: SmartThingsEdgeDrivers")
    os.chdir("SmartThingsEdgeDrivers")
    print(f"New cwd: {os.getcwd()}")

    result = subprocess.run("git checkout origin/production", shell=True)
    if result.returncode != 0:
        print("Failed to checkout origin/production", file=sys.stderr)
        exit(1)

def create_and_push_git_branch(new_branch):
    # Valid name for the branch?
    result = subprocess.run(
        f"git check-ref-format --branch '{new_branch}'",
        shell=True
    )
    if result.returncode != 0:
        print(f"Invalid branch name: {new_branch}", file=sys.stderr)
        exit(1)

    # Does the branch already exist at origin?
    result = subprocess.run(
        f"git ls-remote --exit-code --heads origin '{new_branch}'",
        shell=True
    )
    if result.returncode != 0:
        print(f"Branch '{new_branch}' already exists at origin", file=sys.stderr)
        exit(1)

    result = subprocess.run(
        f"git checkout -b {new_branch}",
        shell=True,
    )
    if result.returncode != 0:
        print(f"Failed to create new git branch: {new_branch}", file=sys.stderr)
        exit(1)

    if DRY_RUN:
        result = subprocess.run(
            f"git push origin {new_branch}",
            shell=True,
        )
        if result.returncode != 0:
            print(f"Failed to push {new_branch} to origin", file=sys.stderr)
            exit(1)
    else:
        print(f"Dry run: Skipping push of {new_branch} to origin")

def create_new_channel():
    response = requests.post(
        url='https://api.smartthings.com/distchannels/',
        headers={
            "Accept": "application/vnd.smartthings+json;v=20200810",
            "Authorization": "Bearer "+TOKEN,
            "X-ST-LOG-LEVEL": "DEBUG"
        },
        json={
            "name": "SmartThings Drivers",
            "description": "Production driver channel",
            "type": "DRIVER",
            "termsOfServiceUrl": f"{GIT_URL}/tree/production"
        }
    )
    if response.status_code != 200:
        print(f"Failed to create new channel:", file=sys.stderr)
        print(f"Request: {response.request}", file=sys.stderr)
        print(f"Status Code: {response.status_code}", file=sys.stderr)
        print(f"Response: {json.dumps(response.json(),indent=2)}", file=sys.stderr)
        exit(1)
    new_channel_id = response.json["channelId"]
    print(f"New channel created: {new_channel_id}")
    return new_channel_id

def update_old_channel(channel_name):
    if DRY_RUN:
        print("Skipping update of old PROD channel")
        return
    
    response = requests.put(
        url=f'https://api.smartthings.com/distchannels/{PROD_CHANNEL_ID}',
        headers={
            "Accept": "application/vnd.smartthings+json;v=20200810",
            "Authorization": "Bearer "+TOKEN,
            "X-ST-LOG-LEVEL": "DEBUG"
        },
        json={
            "name": "SmartThings Drivers - {channel_name}",
            "description": f"Driver support channel: {channel_name}",
            "termsOfServiceUrl": f"{GIT_URL}/tree/{channel_name}"
        }
    )
    if response.status_code != 200:
        print(f"Failed to update old production channel:", file=sys.stderr)
        print(f"Request: {response.request}", file=sys.stderr)
        print(f"Status Code: {response.status_code}", file=sys.stderr)
        print(f"Response: {json.dumps(response.json(),indent=2)}", file=sys.stderr)
        exit(1)



def upload_drivers(channel_id):

    driver_updates = []
    drivers_updated = []
    uploaded_drivers = {}

    DRIVERID = "driverId"
    VERSION = "version"
    PACKAGEKEY = "packageKey"

    UPDATE_URL = f"{ENVIRONMENT_URL}/channels/{channel_id}/drivers/bulk"
    FAILURE_FILE = "failures.log"

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
                    if len(row) > 1:
                        print("en: "+row[0]+" "+LOCALE+": "+row[1])
                        subprocess.run(
                            "find . -name 'fingerprints.yml' | xargs sed -i -E 's/deviceLabel ?: \"?"+row[0].translate(slash_escape)+"\"?/deviceLabel: "+row[1].translate(slash_escape)+"/g'",
                            shell=True,
                            cwd=os.path.dirname(current_path)
                        )

            subprocess.run("git status", shell=True)
    #end LOCALE

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
            package_key = ""
            with open(driver+"/config.yml", 'r') as config_file:
                package_key = yaml.safe_load(config_file)["packageKey"]
                print(package_key)
            if package_key == "bose" and BOSE_APPKEY:
                # write the app key into a app_key.lua (overwrite if exists already)
                subprocess.run(["touch -a ./src/app_key.lua && echo \'return \"" + BOSE_APPKEY +  "\"\n\' > ./src/app_key.lua"], cwd=driver, shell=True, capture_output=True)
            if package_key == "sonos":
                subprocess.run(
                    [f"echo -n '{SONOS_API_KEY_LUA_TEMPLATE}' > ./src/app_key.lua"],
                    cwd=driver,
                    shell=True,
                    capture_output=True,
                )
            retries = 0
            while not os.path.exists(driver+".zip") and retries < 5:
                try:
                    subprocess.run(["zip -r ../"+driver+".zip config.yml fingerprints.yml search-parameters.y*ml $(find . -name \"*.pem\") $(find . -name \"*.crt\") $(find profiles -name \"*.y*ml\") $(find . -name \"*.lua\") -x \"*test*\""], cwd=driver, shell=True, capture_output=True, check=True)
                except subprocess.CalledProcessError as error:
                    print(error.stderr, file=sys.stderr)
                retries += 1
            if retries >= 5:
                print("5 zip failures, skipping "+package_key+" and continuing.", file=sys.stderr)
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
                        "X-ST-LOG-LEVEL": "DEBUG"},
                    data=data)
                    if response.status_code != 200:
                        print("Failed to upload driver "+driver, file=sys.stderr)
                        print("Error code: "+str(response.status_code), file=sys.stderr)
                        print("Error response: "+response.text, file=sys.stderr)
                        if response.status_code == 500 or response.status_code == 429:
                            retries = retries + 1
                            if retries > 3:
                                with open("../../"+FAILURE_FILE, 'a') as f: # go up to the root directory to output, since we've changed dirs to the partner directory
                                    f.write("Failed to upload driver to "+ENVIRONMENT+": "+driver)
                                    f.write("Error code: "+str(response.status_code))
                                    f.write("Error response: "+response.text)
                                    f.write('\n')
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

    if DRY_RUN:
        print("Dry Run, skipping bulk upload to " + UPDATE_URL)
    else:
        response = requests.put(
            UPDATE_URL,
            headers={
                "Accept": "application/vnd.smartthings+json;v=20200810",
                "Authorization": "Bearer "+TOKEN,
                "Content-Type": "application/json",
                "X-ST-LOG-LEVEL": "DEBUG",
                "X-ST-CORRELATION": "driver-deployment-PROD-"+ENVIRONMENT+"-"+str(time.time())
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
        print("\nDrivers currently deployed: ")
        print(uploaded_drivers.keys())

'''
1) Clone production head locally
2) Create new Channel that will become the new production'
*3) Upload packaged drivers to the newly created PROD channel
2) Create $NEW_BRANCH name (support-27.1) from production head
3) (Only from production node) Push to $NEW_BRANCH
6) Rename PROD_CHANNEL_ID to $NEW_BRANCH

Manually:
Update Jenkins CHANNEL_IDs 
'''
def main():

    # Creating new prod steps
    pull_prod()
    new_prod_channel_id = create_new_channel()
    upload_drivers(new_prod_channel_id)

    # Cutting over old prod into support
    if ENVIRONMENT == 'PROD':
        create_and_push_git_branch(BRANCH)
    else:
        print("Skipping push to origin. Environment not production")
    update_old_channel(BRANCH)

    print(f"\n\nNew production channel ID: {new_prod_channel_id}\n\n")
    
