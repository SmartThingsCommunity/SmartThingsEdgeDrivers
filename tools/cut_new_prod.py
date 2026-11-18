import requests, subprocess, os, sys, json, time

ENVIRONMENT = os.environ.get('ENVIRONMENT')
DRY_RUN = bool(os.environ.get('DRY_RUN'))
TOKEN = os.environ.get('TOKEN')
ENVIRONMENT_URL = os.environ.get('ENVIRONMENT_URL')
PROD_CHANNEL_ID = os.environ.get('PROD_CHANNEL_ID')
NEW_BRANCH = os.environ.get("NEW_BRANCH")

print(f"Environment: {ENVIRONMENT}")
print(f"Dry Run: {DRY_RUN}")
print(f"Token Present: {TOKEN != None}")
print(f"Environment URL: {ENVIRONMENT_URL}")
print(f"Production Channel ID: {PROD_CHANNEL_ID}")
print(f"New Branch Channel Name: {NEW_BRANCH}")

GIT_URL = "https://github.com/SmartThingsCommunity/SmartThingsEdgeDrivers"

DRIVERID = "driverId"
VERSION = "version"

# checks out production branch
def checkout_prod():
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
    if result.returncode == 0:
        print(f"Branch '{new_branch}' already exists at origin", file=sys.stderr)
        exit(1)

    # Check out the new branch
    result = subprocess.run(
        f"git checkout -b {new_branch}",
        shell=True,
    )
    if result.returncode != 0:
        print(f"Failed to create new git branch: {new_branch}", file=sys.stderr)
        exit(1)

    if ENVIRONMENT == 'PROD' and not DRY_RUN:
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
    response = requests.request(
        "POST",
        url=f"{ENVIRONMENT_URL}/channels",
        headers={
            "Accept": "application/vnd.smartthings+json;v=20200810",
            "Authorization": "Bearer "+TOKEN,
            "Content-Type": "application/json",
            "X-ST-LOG-LEVEL": "DEBUG"
        },
        data=json.dumps({
            "name": "SmartThings Drivers",
            "description": "Production driver channel",
            "type": "DRIVER",
            "termsOfServiceUrl": f"{GIT_URL}"
        })
    )
    if response.status_code != 200:
        print(f"Failed to create new channel:", file=sys.stderr)
        print(f"Request:", file=sys.stderr)
        print(f"- URL: {response.request.url}", file=sys.stderr)
        print(f"- Method: {response.request.method}", file=sys.stderr)
        print(f"- Body: {response.request.body}", file=sys.stderr)
        print(f"Status Code: {response.status_code}", file=sys.stderr)
        print(f"Response: {json.dumps(response.text,indent=2)}", file=sys.stderr)
        exit(1)
    new_channel_id = response.json()["channelId"]
    print(f"New channel created: {new_channel_id}")
    return new_channel_id

def update_old_channel(channel_name):
    if DRY_RUN:
        print("Skipping update of old PROD channel")
        return
    
    response = requests.put(
        url=f'{ENVIRONMENT_URL}/channels/{PROD_CHANNEL_ID}',
        headers={
            "Accept": "application/vnd.smartthings+json;v=20200810",
            "Authorization": "Bearer "+TOKEN,
            "Content-Type": "application/json",
            "X-ST-LOG-LEVEL": "DEBUG"
        },
        json={
            "name": f"SmartThings Drivers - {channel_name}",
            "description": f"SmartThings Driver - {channel_name}",
            "termsOfServiceUrl": f"{GIT_URL}/tree/{channel_name}"
        }
    )
    if response.status_code != 200:
        print(f"Failed to update old production channel:", file=sys.stderr)
        print(f"Request:", file=sys.stderr)
        print(f"- URL: {response.request.url}", file=sys.stderr)
        print(f"- Method: {response.request.method}", file=sys.stderr)
        print(f"- Body: {response.request.body}", file=sys.stderr)
        print(f"Status Code: {response.status_code}", file=sys.stderr)
        print(f"Response: {json.dumps(response.json(),indent=2)}", file=sys.stderr)
        exit(1)

def clone_drivers_from_channel(source_channel_id, dest_channel_id):

    # Get drivers currently on the source channel
    response = requests.get(
        f"{ENVIRONMENT_URL}/channels/{source_channel_id}/drivers",
        headers={
            "Accept": "application/vnd.smartthings+json;v=20200810",
            "Authorization": "Bearer "+TOKEN,
            "Content-Type": "application/json",
            "X-ST-LOG-LEVEL": "DEBUG"
        }
    )
    if response.status_code != 200:
        print("Failed to retrieve channel's current drivers", file=sys.stderr)
        print(f"Request:", file=sys.stderr)
        print(f"- URL: {response.request.url}", file=sys.stderr)
        print(f"- Method: {response.request.method}", file=sys.stderr)
        print(f"- Body: {response.request.body}", file=sys.stderr)
        print(f"Status Code: {response.status_code}", file=sys.stderr)
        print(f"Response: {json.dumps(response.json(),indent=2)}", file=sys.stderr)
        exit(1)
    print(json.dumps(response.text, indent=3))
    response_json = json.loads(response.text)["items"]

    # Upload the driver ID and version to the destination channel
    failures = {}
    for driver in response_json:
        driverId = driver[DRIVERID]
        version = driver[VERSION]
        print(f"Posting driverID: {driverId}-v{version}")
        response = requests.post(
            f"{ENVIRONMENT_URL}/channels/{dest_channel_id}/drivers",
            headers = {
                "Accept": "application/vnd.smartthings+json;v=20200810",
                "Authorization": "Bearer "+TOKEN,
                "Content-Type": "application/json",
                "X-ST-LOG-LEVEL": "DEBUG",
                "X-ST-CORRELATION": "driver-legacy-deployment-PROD-"+ENVIRONMENT+"-"+str(time.time())
            },
            json={
                "driverId": driverId,
                "version": version
            }
        )
        if response.status_code != 200:
            print(f"Failed to post driver to new channel: {driverId}: v{version}", file=sys.stderr)
            failures[driverId] = json.loads(response.text)

    if len(failures) > 0:
        print(f"One or more drivers failed to post to the new channel: {dest_channel_id}", file=sys.stderr)
        json.dump(failures, fp=sys.stderr)
        exit(1)


def main():

    # Creating new prod steps
    new_prod_channel_id = create_new_channel()
    clone_drivers_from_channel(PROD_CHANNEL_ID, new_prod_channel_id)

    # Cutting over old prod into support
    checkout_prod()
    create_and_push_git_branch(NEW_BRANCH)
    update_old_channel(NEW_BRANCH)

    print(f"\n\nNew production channel ID: {new_prod_channel_id}\n\n")
    

if __name__ == "__main__":
    main()