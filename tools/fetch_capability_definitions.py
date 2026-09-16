#!/usr/bin/env python3
# Copyright 2026 SmartThings
#
# Licensed under the Apache License, Version 2.0 (the "License");
# you may not use this file except in compliance with the License.
# You may obtain a copy of the License at
#
#     http://www.apache.org/licenses/LICENSE-2.0
#
# Unless required by applicable law or agreed to in writing, software
# distributed under the License is distributed on an "AS IS" BASIS,
# WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
# See the License for the specific language governing permissions and
# limitations under the License.

"""fetch_capability_definitions.py

Scans driver profile YAML files to discover all capability IDs and versions in
use, then downloads their fully-inlined JSON definitions from the SmartThings
cloud API and writes each to a separate file in the output directory.

The downloaded JSON files are pre-inlined by the cloud (no $ref strings remain)
and can be used directly by the integration test framework's capability_json_loader
module via the ST_CAPABILITY_JSON_DIR environment variable.

Capability definitions are fetched individually via GET /capabilities/<id>/<version>
by default, which ensures that a failure for one capability does not affect others.
A known allowlist of capabilities (QUERY_ENDPOINT_IDS) that are confirmed to work
with the bulk POST /capabilities/query endpoint are fetched in a single batch
request instead, for efficiency.

Usage
-----
    python3 tools/fetch_capability_definitions.py \\
        --drivers-dir drivers/ \\
        --drivers-dir ~/projects/SmartThingsEdgeDrivers/drivers \\
        --output-dir ~/cap_cache \\
        [--overwrite] \\
        [--failed-output-file failures_comment.md]

Arguments
---------
    --drivers-dir PATH         Root of a driver tree to scan for profiles.
                               May be specified multiple times.
    --output-dir PATH          Directory to write <capabilityId>_<version>.json files.
                               Created if it does not exist.
    --overwrite                When set, re-download and overwrite all capability
                               files even if they already exist in --output-dir.
                               When absent (default), only missing files are fetched;
                               capabilities already on disk are skipped entirely,
                               and no API request is made for them.
    --failed-output-file PATH  When set, write a markdown-formatted report of any
                               capabilities that could not be downloaded to this file.
                               The file is only created when there are failures, making
                               it suitable for use as a PR comment via hashFiles() checks
                               in CI workflows.

Environment
-----------
    CAPABILITY_PAT       Required. SmartThings personal access token used for
                         the Authorization: Bearer header on all API requests.
"""

import argparse
import json
import os
import sys
import time
from pathlib import Path
from typing import Dict, List, Set, Tuple

import requests
import yaml

API_BASE = "https://api.smartthings.com/v1"
QUERY_ENDPOINT = f"{API_BASE}/capabilities/query"

# These two IDs appear in the /capabilities list but are rejected by both the
# /capabilities/query endpoint and the individual GET endpoint.  They are
# lowercase/deprecated duplicates of alarmSensor and samsungTV respectively.
EXCLUDED_IDS = frozenset(["alarmsensor", "samsungTv"])

# These capability IDs are confirmed to work with the bulk POST /capabilities/query
# endpoint and will be fetched in a single batch request for efficiency.  All other
# capability IDs (e.g. namespaced capabilities such as stse.*, sec.*, samsungim.*)
# are fetched individually via GET /capabilities/<id>/<version> by default.  This
# ensures that a new capability added to a profile that is not supported by the
# query endpoint will only cause an isolated failure rather than affecting all
# capabilities in the batch.
QUERY_ENDPOINT_IDS = frozenset([
    "accelerationSensor",
    "activitySensor",
    "airConditionerFanMode",
    "airConditionerMode",
    "airPurifierFanMode",
    "airQualityHealthConcern",
    "airQualitySensor",
    "alarm",
    "atmosphericPressureMeasurement",
    "audioMute",
    "audioNotification",
    "audioRecording",
    "audioTrackData",
    "audioVolume",
    "battery",
    "batteryLevel",
    "bodyWeightMeasurement",
    "bridge",
    "button",
    "cameraPrivacyMode",
    "cameraViewportSettings",
    "carbonDioxideHealthConcern",
    "carbonDioxideMeasurement",
    "carbonMonoxideDetector",
    "carbonMonoxideHealthConcern",
    "carbonMonoxideMeasurement",
    "chargingState",
    "chime",
    "colorControl",
    "colorTemperature",
    "configuration",
    "contactSensor",
    "cookTime",
    "currentMeasurement",
    "dewPoint",
    "doorControl",
    "dustHealthConcern",
    "dustSensor",
    "elevatorCall",
    "energyMeter",
    "evseChargingSession",
    "evseState",
    "fanMode",
    "fanOscillationMode",
    "fanSpeed",
    "fanSpeedPercent",
    "feederOperatingState",
    "feederPortion",
    "filterState",
    "filterStatus",
    "fineDustHealthConcern",
    "fineDustSensor",
    "firmwareUpdate",
    "flowMeasurement",
    "formaldehydeHealthConcern",
    "formaldehydeMeasurement",
    "gasDetector",
    "gasMeter",
    "hardwareFault",
    "hdr",
    "illuminanceMeasurement",
    "imageCapture",
    "imageControl",
    "keypadInput",
    "knob",
    "laundryWasherRinseMode",
    "laundryWasherSpinSpeed",
    "level",
    "localMediaStorage",
    "lock",
    "lockAlarm",
    "lockAliro",
    "lockCodes",
    "lockCredentials",
    "lockSchedules",
    "lockUsers",
    "mechanicalPanTiltZoom",
    "mediaGroup",
    "mediaPlayback",
    "mediaPresets",
    "mediaTrackControl",
    "mode",
    "moldHealthConcern",
    "momentary",
    "motionSensor",
    "movementSensor",
    "multipleZonePresence",
    "nightVision",
    "nitrogenDioxideHealthConcern",
    "nitrogenDioxideMeasurement",
    "operationalState",
    "ozoneHealthConcern",
    "ozoneMeasurement",
    "panicAlarm",
    "pestControl",
    "powerConsumptionReport",
    "powerMeter",
    "powerSource",
    "presenceSensor",
    "pumpControlMode",
    "pumpOperationMode",
    "radonHealthConcern",
    "radonMeasurement",
    "rainSensor",
    "refresh",
    "relativeHumidityMeasurement",
    "remoteControlStatus",
    "robotCleanerOperatingState",
    "safetyValve",
    "serviceArea",
    "signalStrength",
    "smokeDetector",
    "soundSensor",
    "sounds",
    "statelessColorTemperatureStep",
    "statelessCurtainPowerButton",
    "statelessSwitchLevelStep",
    "switch",
    "switchLevel",
    "tamperAlert",
    "temperatureAlarm",
    "temperatureLevel",
    "temperatureMeasurement",
    "temperatureSetpoint",
    "thermostatCoolingSetpoint",
    "thermostatFanMode",
    "thermostatHeatingSetpoint",
    "thermostatMode",
    "thermostatOperatingState",
    "threadBorderRouter",
    "threadNetwork",
    "threeAxis",
    "tone",
    "tvocHealthConcern",
    "tvocMeasurement",
    "ultravioletIndex",
    "valve",
    "veryFineDustHealthConcern",
    "veryFineDustSensor",
    "videoCapture2",
    "videoStreamSettings",
    "voltageMeasurement",
    "waterFlowAlarm",
    "waterMeter",
    "waterSensor",
    "webrtc",
    "wifiInformation",
    "windMode",
    "windowShade",
    "windowShadeLevel",
    "windowShadePreset",
    "windowShadeTiltLevel",
    "zoneManagement",
    "zwMultichannel",
])


def build_headers(pat: str) -> Dict:
    return {
        "Authorization": f"Bearer {pat}",
        "Accept": "application/vnd.smartthings+json;v=1, application/json",
        "Content-Type": "application/json",
    }


def scan_profiles(drivers_dirs: List[Path]) -> Set[Tuple[str, int]]:
    """
    Walk every drivers_dir, find all *.yml files under any profiles/ subdirectory,
    parse them with PyYAML, and extract (capabilityId, version) pairs.

    Returns a deduplicated set of (id, version) tuples.
    """
    found: Set[Tuple[str, int]] = set()
    profile_count = 0
    error_count = 0

    for drivers_dir in drivers_dirs:
        for profile_path in drivers_dir.rglob("profiles/*.yml"):
            profile_count += 1
            try:
                with open(profile_path, encoding="utf-8") as f:
                    profile = yaml.safe_load(f)
                if not profile or not isinstance(profile.get("components"), list):
                    continue
                for component in profile["components"]:
                    for cap in component.get("capabilities") or []:
                        cap_id = cap.get("id")
                        cap_ver = cap.get("version", 1)
                        if cap_id:
                            found.add((cap_id, int(cap_ver)))
            except Exception as exc:
                print(f"  WARNING: failed to parse {profile_path}: {exc}", file=sys.stderr)
                error_count += 1

    print(
        f"Scanned {profile_count} profile(s) across {len(drivers_dirs)} driver tree(s)"
        + (f", {error_count} parse error(s)" if error_count else "")
        + "."
    )
    return found


def output_path(output_dir: Path, cap_id: str, cap_ver: int) -> Path:
    return output_dir / f"{cap_id}_{cap_ver}.json"


def fetch_definitions(
    pairs: List[Tuple[str, int]],
    headers: Dict,
    max_retries: int = 3,
    retry_delay: float = 2.0,
) -> Tuple[Dict[Tuple[str, int], Dict], List[Tuple[str, int, str]]]:
    """
    Fetch capability definitions for the given (id, version) pairs.

    Pairs whose ID is in QUERY_ENDPOINT_IDS are fetched via a single bulk POST
    to /capabilities/query.  All other pairs are fetched individually via
    GET /capabilities/<id>/<version>, so that an unsupported capability causes
    only an isolated failure rather than affecting the entire batch.

    Any capability that is missing from the bulk query response (e.g. due to an
    intermittent API hiccup) is retried individually via GET up to max_retries
    times before being recorded as a failure.

    Returns a tuple of:
      - dict mapping (id, version) -> definition object for successful fetches
      - list of (id, version, reason) tuples for failed fetches
    """
    results: Dict[Tuple[str, int], Dict] = {}
    failures: List[Tuple[str, int, str]] = []
    if not pairs:
        return results, failures

    # Split into bulk-query pairs and individual-GET pairs
    query_pairs = [(cid, ver) for cid, ver in pairs if cid in QUERY_ENDPOINT_IDS]
    get_pairs   = [(cid, ver) for cid, ver in pairs if cid not in QUERY_ENDPOINT_IDS]

    # --- Bulk query for known-good capabilities ---
    if query_pairs:
        query = [{"capabilityId": cid, "version": ver} for cid, ver in query_pairs]
        response = requests.post(QUERY_ENDPOINT, headers=headers, json={"query": query}, timeout=30)

        if response.status_code == 200:
            for item in response.json().get("items", []):
                results[(item["id"], item["version"])] = item
            # Any pair missing from the response gets retried individually - the
            # API occasionally omits items from the bulk response transiently.
            returned = {(item["id"], item["version"]) for item in response.json().get("items", [])}
            missing = [(cid, ver) for cid, ver in query_pairs if (cid, ver) not in returned]
            if missing:
                print(
                    f"  WARNING: {len(missing)} capability/version pair(s) missing from bulk query "
                    "response — retrying individually..."
                )
                for cap_id, cap_ver in missing:
                    _fetch_individual(cap_id, cap_ver, headers, results, failures,
                                      max_retries, retry_delay)
        else:
            print(
                f"  WARNING: bulk query returned HTTP {response.status_code} — "
                "marking all query-endpoint capabilities as failed."
            )
            for cap_id, cap_ver in query_pairs:
                failures.append((cap_id, cap_ver, f"HTTP {response.status_code}"))

    # --- Individual GET for all other capabilities ---
    if get_pairs:
        print(f"  Fetching {len(get_pairs)} capability/version pair(s) via individual GET...")
        for cap_id, cap_ver in get_pairs:
            _fetch_individual(cap_id, cap_ver, headers, results, failures,
                              max_retries, retry_delay)

    return results, failures


def _fetch_individual(
    cap_id: str,
    cap_ver: int,
    headers: Dict,
    results: Dict,
    failures: List,
    max_retries: int = 3,
    retry_delay: float = 2.0,
) -> None:
    """
    Fetch a single capability definition via GET /capabilities/<id>/<version>,
    retrying up to max_retries times on failure with exponential backoff.
    Appends to results on success or failures on final failure.
    """
    last_status = None
    for attempt in range(1, max_retries + 1):
        r = requests.get(
            f"{API_BASE}/capabilities/{cap_id}/{cap_ver}",
            headers=headers,
            timeout=30,
        )
        if r.status_code == 200:
            results[(cap_id, cap_ver)] = r.json()
            return
        last_status = r.status_code
        if attempt < max_retries:
            wait = retry_delay * attempt
            print(
                f"  WARNING: {cap_id} v{cap_ver} — HTTP {last_status} "
                f"(attempt {attempt}/{max_retries}, retrying in {wait:.0f}s...)"
            )
            time.sleep(wait)

    print(f"  WARNING: skipping {cap_id} v{cap_ver} — HTTP {last_status} after {max_retries} attempts.")
    failures.append((cap_id, cap_ver, f"HTTP {last_status}"))


def write_failure_report(
    failures: List[Tuple[str, int, str]],
    output_file: Path,
    truncate_at: int = 10,
) -> None:
    """
    Write a markdown-formatted failure report suitable for use as a PR comment.

    The file is only written when there are failures.  If failures is empty,
    this function does nothing (leaving any previously existing file untouched,
    but no file will be created for a clean run).
    """
    if not failures:
        return

    lines = [
        "## ⚠️ Capability Definition Download Failures",
        "",
        "The following capability definitions could not be downloaded from the SmartThings API:",
        "",
        "| Capability ID | Version | Reason |",
        "|--------------|---------|--------|",
    ]

    shown = failures[:truncate_at]
    for cap_id, cap_ver, reason in shown:
        lines.append(f"| `{cap_id}` | {cap_ver} | {reason} |")

    if len(failures) > truncate_at:
        lines.append("")
        lines.append(f"_...and {len(failures) - truncate_at} more._")

    lines += [
        "",
        "These capabilities may not be available in the test environment. "
        "Tests using these capabilities may fail or fall back to built-in definitions.",
    ]

    output_file.write_text("\n".join(lines) + "\n", encoding="utf-8")


def main(argv=None):
    parser = argparse.ArgumentParser(
        description=__doc__,
        formatter_class=argparse.RawDescriptionHelpFormatter,
    )
    parser.add_argument(
        "--drivers-dir",
        action="append",
        dest="drivers_dirs",
        metavar="PATH",
        required=True,
        help="Root of a driver tree to scan (may be specified multiple times).",
    )
    parser.add_argument(
        "--output-dir",
        metavar="PATH",
        required=True,
        help="Directory to write <capabilityId>_<version>.json files.",
    )
    parser.add_argument(
        "--overwrite",
        action="store_true",
        default=False,
        help=(
            "Re-download and overwrite all capability files even if they already "
            "exist.  Without this flag only missing files are fetched."
        ),
    )
    parser.add_argument(
        "--failed-output-file",
        metavar="PATH",
        default=None,
        help=(
            "When set, write a markdown-formatted report of any capabilities that "
            "could not be downloaded to this file.  The file is only created when "
            "there are failures, making it suitable for use as a PR comment via "
            "hashFiles() checks in CI workflows."
        ),
    )
    args = parser.parse_args(argv)

    pat = os.environ.get("CAPABILITY_PAT", "")
    if not pat:
        print("ERROR: CAPABILITY_PAT environment variable is not set.", file=sys.stderr)
        sys.exit(1)

    headers = build_headers(pat)
    output_dir = Path(args.output_dir).expanduser().resolve()
    output_dir.mkdir(parents=True, exist_ok=True)

    drivers_dirs = [Path(d).expanduser().resolve() for d in args.drivers_dirs]
    for d in drivers_dirs:
        if not d.is_dir():
            print(f"ERROR: --drivers-dir does not exist: {d}", file=sys.stderr)
            sys.exit(1)

    # Step 1: scan profiles
    all_pairs = scan_profiles(drivers_dirs)
    print(f"Found {len(all_pairs)} unique capability/version pair(s).")

    # Step 2: filter known-bad IDs
    excluded = {p for p in all_pairs if p[0] in EXCLUDED_IDS}
    for cap_id, cap_ver in sorted(excluded):
        print(
            f"  WARNING: excluding {cap_id} v{cap_ver} "
            "(rejected by the query endpoint — likely a duplicate/malformed entry)."
        )
    all_pairs -= excluded

    # Step 3: resolve what to fetch
    if args.overwrite:
        to_fetch = sorted(all_pairs)
        already_present = 0
    else:
        to_fetch = sorted(p for p in all_pairs if not output_path(output_dir, p[0], p[1]).exists())
        already_present = len(all_pairs) - len(to_fetch)

    if already_present:
        print(f"{already_present} capability/version pair(s) already on disk — skipping.")

    if not to_fetch:
        print("Nothing to fetch. Output directory is up to date.")
        _print_summary(len(drivers_dirs), len(all_pairs) + len(excluded), len(excluded),
                       already_present, 0, 0, 0, output_dir)
        return

    print(f"Fetching {len(to_fetch)} capability definition(s)...")

    # Step 4: fetch
    definitions, failures = fetch_definitions(to_fetch, headers)

    # Step 5: write
    written = 0
    skipped_api = 0
    for cap_id, cap_ver in to_fetch:
        definition = definitions.get((cap_id, cap_ver))
        if definition is None:
            skipped_api += 1
            continue
        dest = output_path(output_dir, cap_id, cap_ver)
        dest.write_text(json.dumps(definition, indent=2), encoding="utf-8")
        written += 1

    _print_summary(len(drivers_dirs), len(all_pairs) + len(excluded), len(excluded),
                   already_present, len(to_fetch), written, skipped_api, output_dir)

    # Step 6: write failure report if requested
    if args.failed_output_file:
        failed_output_file = Path(args.failed_output_file).expanduser().resolve()
        write_failure_report(failures, failed_output_file)
        if failures:
            print(f"  Failure report written to: {failed_output_file}")


def _print_summary(
    trees: int,
    total_found: int,
    excluded: int,
    already_present: int,
    requested: int,
    written: int,
    skipped_api: int,
    output_dir: Path,
) -> None:
    print()
    print("=== Summary ===")
    print(f"  Driver trees scanned : {trees}")
    print(f"  Unique capabilities  : {total_found}")
    if excluded:
        print(f"  Excluded (bad IDs)   : {excluded}")
    print(f"  Already on disk      : {already_present}")
    print(f"  Requested from API   : {requested}")
    print(f"  Written              : {written}")
    if skipped_api:
        print(f"  Skipped (API error)  : {skipped_api}")
    print(f"  Output directory     : {output_dir}")


if __name__ == "__main__":
    main()
