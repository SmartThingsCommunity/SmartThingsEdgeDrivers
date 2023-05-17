#!/usr/bin/env python3

import subprocess, junit_xml, os, sys
from pathlib import Path
from multiprocessing import Pool
import regex as re # supports multi-threading

test_case_re = re.compile("Running test \"(.*?)\".+?-{2,}.*?(PASSED|FAILED)", flags=re.DOTALL)
LUACOV_CONFIG = Path(os.path.abspath(__file__)).parent.joinpath("config.luacov")
DRIVER_DIRS = Path(os.path.abspath(__file__)).parents[1].joinpath("drivers")
DRIVERS = [driver for driver in DRIVER_DIRS.glob("*/*") if driver.is_dir()] # this gets all the children of the children of the drivers directory
CHANGED_DRIVERS = [Path(driver).name for driver in sys.argv[1:]]

def per_driver_task(driver_dir):
  os.chdir(driver_dir.joinpath('src'))
  results = map(run_test, driver_dir.glob("src/test/test_*.lua"))
  successes, failures, failure_output, test_suites = 0, 0, "", []
  for result in results:
    test_suites.append(result[0])
    successes += result[1]
    failures += result[2]
    if result[3] != "":
      failure_output += result[3] + '\n'
  with open(driver_dir.parent.parent.parent.joinpath("tools/test_output/").joinpath(driver_dir.name+"_test_output.xml"), 'w+') as outfile:
    junit_xml.to_xml_report_file(outfile, test_suites)
  print("{}: passed {} of {} tests".format(driver_dir.name, successes, successes+failures))
  if failure_output != "":
    failure_output = driver_dir.name + ": \n" + failure_output
  else:
    failure_output = None
  if driver_dir.name in CHANGED_DRIVERS:
    with driver_dir.parent.parent.parent.joinpath("tools/coverage_output").joinpath(driver_dir.name+"_coverage.xml") as outfile:
      subprocess.run("luacov-cobertura -o {} -c {}".format(outfile, LUACOV_CONFIG), shell=True)
  return failure_output

def run_test(test_file):
  if test_file.parent.parent.parent.name in CHANGED_DRIVERS:
    a = subprocess.run("lua -lluacov {}".format(test_file), stdout=subprocess.PIPE, stderr=subprocess.PIPE, shell=True)
  else:
    a = subprocess.run("lua {}".format(test_file), stdout=subprocess.PIPE, stderr=subprocess.PIPE, shell=True)
  error = a.stderr.decode()
  if error and error != "":
    print(error)
  parsed_output = a.stdout.decode()
  test_suite_name = str(test_file)[str(test_file).rindex('/')+1:-4].replace('_',' ')
  test_suite = junit_xml.TestSuite(test_suite_name)
  successes, failures, failure_output, test_cases = 0, 0, "", []
  for match in test_case_re.finditer(parsed_output):
    test_case = junit_xml.TestCase(match[1])
    test_case.stdout = match[0]
    if match[2] == "FAILED":
      failures += 1
      if "traceback" in match[0]:
        failure_output += "\t{} ERROR in {}\n".format(test_suite_name, match[1])
        test_case.add_error_info("ERROR", match[0])
      else:
        failure_output += "\t{} FAILED on {}\n".format(test_suite_name, match[1])
        test_case.add_failure_info("FAILED", match[0])
    else:
      successes += 1
    test_cases.append(test_case)
  test_suite.test_cases = test_cases
  return (test_suite, successes, failures, failure_output)

if __name__ == "__main__":

  try:
    os.mkdir(Path(os.path.abspath(__file__)).parent.joinpath("test_output"))
  except FileExistsError:
    pass

  try:
    os.mkdir(Path(os.path.abspath(__file__)).parent.joinpath("coverage_output"))
  except FileExistsError:
    pass

  failure_output = ""
  with Pool() as pool:
    failure_output = pool.map(per_driver_task, DRIVERS)

  exit_code = 0

  for test_case in failure_output:
    if test_case:
      print(test_case)
      exit_code = 1
  sys.exit(exit_code)
