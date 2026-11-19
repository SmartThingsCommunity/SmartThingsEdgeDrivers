import requests, subprocess, os, sys, json, time

ENVIRONMENT = os.environ.get('ENVIRONMENT')
DRY_RUN = bool(os.environ.get('DRY_RUN'))
TOKEN = os.environ.get('TOKEN')
ENVIRONMENT_URL = os.environ.get('ENVIRONMENT_URL')
PROD_CHANNEL_ID = os.environ.get('PROD_CHANNEL_ID')
CHANNEL_TAG = os.environ.get("CHANNEL_TAG")

print(f"Environment: {ENVIRONMENT}")
print(f"Dry Run: {DRY_RUN}")
print(f"Token Present: {TOKEN != None}")
print(f"Environment URL: {ENVIRONMENT_URL}")
print(f"Production Channel ID: {PROD_CHANNEL_ID}")
print(f"New Channel Tag: {CHANNEL_TAG}")

GIT_URL = "https://github.com/SmartThingsCommunity/SmartThingsEdgeDrivers"

DRIVERID = "driverId"
VERSION = "version"

def clone_new_channel(source_channel_id):
    response = requests.request(
        "POST",
        url=f"{ENVIRONMENT_URL}/channels/clone/{source_channel_id}",
        headers={
            "Accept": "application/vnd.smartthings+json;v=20200810",
            "Authorization": "Bearer "+TOKEN,
            "Content-Type": "application/json",
            "X-ST-LOG-LEVEL": "DEBUG"
        }
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

def update_old_channel(channel_tag):
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
            "name": f"SmartThings Drivers - {channel_tag}",
            "description": f"SmartThings Driver - {channel_tag}",
            "termsOfServiceUrl": f"{GIT_URL}"
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


def main():

    new_prod_channel_id = clone_new_channel(PROD_CHANNEL_ID)
    update_old_channel(CHANNEL_TAG)

    print(f"\n\nNew production channel ID: {new_prod_channel_id}\n\n")
    

if __name__ == "__main__":
    main()