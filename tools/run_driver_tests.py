#!/usr/bin/env python3

import os, sys
import re
import subprocess
from collections import defaultdict
import argparse
from pathlib import Path
import junit_xml

VERBOSITY_TOTALS_ONLY = 0
VERBOSITY_TEST_STATUS_ONLY = 1
VERBOSITY_FAILURE_TEST_LOGS = 2
VERBOSITY_ALL_TEST_LOGS = 3

DRIVER_DIR = Path(os.path.abspath(__file__)).parents[1].joinpath("drivers")
LUACOV_CONFIG = DRIVER_DIR.parent.joinpath(".circleci", "config.luacov")

def find_affected_tests(working_dir, changed_files):
    affected_tests = []
    if changed_files is not None:
        for file in changed_files:
            if "src" in file:
                path = Path(working_dir).joinpath(file)
                if path.parts[-1] != "src":
                    path = [parent for parent in path.parents if parent.parts[-1] == "src"][0]
                affected_tests.extend(path.rglob("test/test_*.lua"))

    affected_tests = set(affected_tests)
    return affected_tests

def run_tests(verbosity_level, filter, junit, coverage_files):
    owd = os.getcwd()
    coverage_files = find_affected_tests(owd, coverage_files)
    failure_files = defaultdict(list)
    ts = []
    total_tests = 0
    total_passes = 0
    for test_file in DRIVER_DIR.glob("*" + os.path.sep + "*" + os.path.sep + "src" + os.path.sep + "test" + os.path.sep + "test_*.lua"):
        if filter != None and re.search(filter, str(test_file)) is None:
            continue
        os.chdir(test_file.parents[1])
        test_line = "## Running tests from {}".format(test_file)
        print("#" * len(test_line))
        print(test_line)
        if test_file in coverage_files:
            a = subprocess.run("lua -lluacov {}".format(test_file), stdout=subprocess.PIPE, stderr=subprocess.PIPE, shell=True)
        else:
            a = subprocess.run("lua {}".format(test_file), stdout=subprocess.PIPE, stderr=subprocess.PIPE, shell=True)
        lines = a.stdout.decode().split("\n")
        test_count = 0
        passes = 0
        last_line = ""
        in_progress_test_name = ""
        test_cases = []
        test_file_name = os.path.basename(test_file)
        test_suite_name = os.path.splitext(test_file_name)[0].replace('_', ' ')
        test_suite = junit_xml.TestSuite(test_suite_name)
        test_case = None
        test_logs = ""
        test_title = ""
        test_status = ""
        test_done = False
        for line in lines:
            if test_case is not None:
                if test_case.stdout is not None:
                    test_case.stdout += line + '\n'
                else:
                    test_case.stdout = line + '\n'
            if verbosity_level >= 2 and line.strip() != "":
                test_logs += line + "\n"
            m = re.search("Running test \"([^\"]+)\"", line)
            if m is not None:
                test_title = line
                in_progress_test_name = m.group(1)
                test_name_regex = re.compile(in_progress_test_name)
                line_number = None
                with open(test_file, 'r') as search_file:
                    for idx, line in enumerate(search_file, 1):
                        if test_name_regex.search(line) :
                            line_number = idx
                            break
                test_case = junit_xml.TestCase(in_progress_test_name, line=line_number)
                test_count += 1
            elif re.search("PASSED", line) is not None:
                test_done = True
                test_status = line
                passes += 1
                test_cases.append(test_case)
                test_case = None
            elif re.search("FAILED", line) is not None:
                test_done = True
                test_status = line
                failure_string = f"{in_progress_test_name} [line {test_case.line}]"
                failure_files[test_file].append(failure_string)
                if "traceback" in test_case.stdout:
                    test_case.add_error_info(line, test_case.stdout)
                else:
                    test_case.add_failure_info(line, test_case.stdout)
                test_cases.append(test_case)
                test_case = None
            if test_done:
                if verbosity_level == VERBOSITY_TEST_STATUS_ONLY:
                    print(test_title)
                    print(test_status)
                elif verbosity_level == VERBOSITY_FAILURE_TEST_LOGS:
                    if test_status == "FAILED":
                        print(test_logs)
                    else:
                        print(test_title)
                        print(test_status)
                elif verbosity_level == VERBOSITY_ALL_TEST_LOGS:
                    print(test_logs)
                test_title = ""
                test_status = ""
                test_logs = ""
                test_done = False
            if re.match("^\s*$", line) is None:
                last_line = line

        m = re.match("Passed (\d+) of (\d+) tests", last_line)
        if m is None:
            failure_files[test_file].append("\n    ".join(a.stderr.decode().split("\n")))
            test_case = junit_xml.TestCase(test_suite.name)
            test_case.add_error_info("FAILED", a.stderr.decode())
            test_cases.append(test_case)
            test_case = None
        else:
            if verbosity_level == 0:
                print(last_line)
            if int(m.group(1)) != passes or int(m.group(2)) != test_count:
                failure_files[test_file].append("Unexpected difference in test counts")

        print("#" * len(test_line))
        total_tests += test_count
        total_passes += passes
        test_suite.test_cases = test_cases
        ts.append(test_suite)
        if test_file in coverage_files:
            subprocess.run("luacov -c={}".format(LUACOV_CONFIG), shell=True)

    total_test_info = "Total unit tests passes: {}/{}".format(total_passes, total_tests)
    print("#" * len(total_test_info))
    print(total_test_info)
    print("#" * len(total_test_info))

    os.chdir(owd)
    if junit is not None:
        with open(junit, 'w+') as outfile:
            junit_xml.to_xml_report_file(outfile, ts)

    for f in failure_files.keys():
        print("Unit test failures in {}:".format(f))
        for failed_test in failure_files[f]:
            print("    {}".format(failed_test))

    if len(failure_files.keys()) > 0:
        sys.exit(1)

if __name__ == "__main__":
    parser = argparse.ArgumentParser(description="Run all driver tests found in sub directories")
    parser.add_argument("--verbose", "-v", action="store_true", help="print individual test names and pass status")
    parser.add_argument("--extraverbose", "-vv", action="store_true", help="print individual test names and pass status with full logs on failures")
    parser.add_argument("--superextraverbose", "-vvv", action="store_true", help="print all logs from all tests")
    parser.add_argument("--filter", "-f",  type=str, nargs="?", help="only run tests containing the filter value in the path")
    parser.add_argument("--junit", "-j", type=str, nargs="?", help="output test results in JUnit XML to the specified file")
    parser.add_argument("--coverage", "-c", nargs="*", help="run code tests with coverage (luacov must be installed) OPTIONAL: restrict files to run coverage tests for")
    args = parser.parse_args()
    verbosity_level = 0
    if args.verbose:
        verbosity_level = 1
    elif args.extraverbose:
        verbosity_level = 2
    elif args.superextraverbose:
        verbosity_level = 3
    run_tests(verbosity_level, args.filter, args.junit, args.coverage)

