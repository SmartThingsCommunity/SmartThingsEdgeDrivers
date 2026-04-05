import argparse
import re
import os
import subprocess

if os.environ.get("LUA_PATH") == None:
	print("LUA_PATH environment variable must be set")
	exit(1)
script = 'local v=require(\"version\"); print(v.api)'
LIBS_VERSION = int(os.popen(f"lua -e '{script}'").read().strip())
print(f"Found lua-libs version: {LIBS_VERSION}")

TEST_CODE_REGEX = r"(test\.register_(?:coroutine|message)_test\(\s*\"([^\"]+)\"[\s\S]*?min_api_version\s*=\s*)(\d+)([\s\S]*?\))"
TEST_RESULT_REGEX = r"Running test \"(.+?(?=\"))\" \(\d+ of \d+\)\n(PASSED|FAILED)"
TEST_FILE_REGEX = r"Running tests from (\S+.lua)"

def capture_test_output(test_filter = None) -> str:
	command = f"python3 tools/run_driver_tests.py -v".split(" ")
	if test_filter != None:
		command = f"python3 tools/run_driver_tests.py --filter {test_filter} -v".split(" ")

	print(f"Running command: {command}")
	proc = subprocess.run(command, stdout=subprocess.PIPE, stderr=subprocess.PIPE)
	print(f"Done")
	return proc.stdout.decode('utf-8')

def get_results_from_output(output:str) -> dict:
	passing = {}
	failing = {}
	while (m := re.search(TEST_FILE_REGEX,output)):
		# print(m.group(1))
		output = output[m.end():]

		passed = []
		failed = []
		while True:
			eot_index = len(output)
			if eot := (re.search(r"#{10,}", output) or re.search(TEST_FILE_REGEX, output)):
				eot_index = eot.start()

			if t := re.search(TEST_RESULT_REGEX,output[:eot_index]):
				if t.group(2) == 'PASSED':
					passed.append(t.group(1))
				else:
					failed.append(t.group(1))
				output = output[t.end():]
			else:
				output = output[eot_index:]
				break
		if len(passed) > 0:
			passing[m.group(1)] = passed
		if len(failed) > 0:
			failing[m.group(1)] = failed
	return (passing,failing)

def show_failing_tests(failing):
	for filename in failing:
		tests = failing[filename]
		print(f"Failing tests for: {filename}")
		for tn in tests:
			print(f"	{tn}")

def update_passing_tests(passing):
	for filename in passing:
		# print(f"Parsing file: {filename}")
		fn = filename
		passing_tests = list(passing[filename])

		def replace_function(match):
			if match.group(2) in passing_tests and int(match.group(3)) > LIBS_VERSION:
				return f"{match.group(1)}{LIBS_VERSION}{match.group(4)}"
			else:
				return match.group(0)


		with open(filename,'r') as fd:
			file_contents = fd.read()

		updated_test_file = re.sub(TEST_CODE_REGEX,replace_function,file_contents)

		with open(filename + ".new", 'w') as fd:
			fd.write(updated_test_file)

		os.replace(filename + ".new", filename)
		print(f"Updated: {filename}")

if __name__ == "__main__":

	parser = argparse.ArgumentParser(description="""Runs driver tests against lua libs, parses the output of the tests results,
								  and updates the min_api_version of the tests that successfully passed if the test version is
								  less than the test's min_api_version.NOTE: this CAN NOT be done if test filtering is active.
								  If enabled, disable this by temporarily removing the code or commenting it out.""")
	parser.add_argument("--filter", "-f", help="Filter of tests to run and update min_api_version for. Argument is passed into the tools/run_driver_tests.py --filter <arg>",default=None)
	args = parser.parse_args()
	
	test_output = capture_test_output(args.filter)
	passing, failing = get_results_from_output(test_output)
	update_passing_tests(passing)
	show_failing_tests(failing)

