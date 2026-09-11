#!/bin/bash
#
# test_driver.sh
#
# Run the Lua unit tests for a single SmartThings Edge Driver.
#
# Run this from the driver's `src` directory, e.g.:
#   cd drivers/SmartThings/matter-switch/src
#   $(git rev-parse --show-toplevel)/tools/test_driver.sh [options]
#
# The $(git rev-parse --show-toplevel) form finds the repo root regardless of
# how deep you are, so it works the same from any driver without figuring out
# a relative path back to tools/.
#
# (If you run it from the driver's root directory instead, it will `cd src`
# for you automatically.)
#
# Run with -h for the full list of options.

usage() {
    cat <<'EOF'
Usage: test_driver.sh [-h] [-l] [-v] [-o [file]] [-c|-C] [-f]
                       [-t test_file_number|test_file_path [test_case ...]]
                       [-r] [-g 'search_query' [num_context_lines]]

  -h                                     Show this help message
  -l                                     List available test files
  -v                                     Verbose mode (show test output)
  -o [file]                              Save output to a file (default: test_results.log)
  -c                                     Run luacov for coverage analysis
  -C                                     Run luacov with a fresh report (deletes old coverage files first)
  -t <test file> [test case(s)]          Only run this test file (by number or path), optionally
                                         restricted to specific test case number(s)
  -f                                     Show only failed test cases
  -r                                     Run luacheck instead of the test suite
  -g 'search query' [num_context_lines]  Grep for a string in each test file's raw output
EOF
    exit 0
}

list_test_files() {
    local header="Available Test Files:"
    echo "$header"
    printf '%*s\n' "${#header}" '' | tr ' ' '-'
    local count=1
    for file in test/*.lua; do
        echo "$count: ${file:5}"
        count=$((count+1))
    done
    exit 0
}

# ---------------------------------------------------------------------------
# Defaults
# ---------------------------------------------------------------------------
verbose=false
save_output=false
run_coverage=false
fresh_coverage=false
run_luacheck=false
search_for_string=false
show_failures=false
output_file="test_results.log"
num_context_lines=0
selected_test_file=""
test_cases=()

if [ -d "src" ]; then cd src; fi
test_files=(test/*.lua)
src_files=(*/*.lua *.lua)

red='\033[1;31m'
green='\033[0;32m'
yellow='\033[1;33m'
no_color='\033[0m'

declare -a file_summaries
total_pass_count=0
total_test_count=0
total_error_count=0
total_warning_count=0

# ---------------------------------------------------------------------------
# Option parsing
# ---------------------------------------------------------------------------
while [[ "$1" ]]; do
    case "$1" in
        -h) usage ;;
        -l) list_test_files ;;
        -v) verbose=true; shift ;;
        -o)
            save_output=true
            shift
            if [[ -n "$1" && "$1" != -* ]]; then
                output_file="$1"
                shift
            fi
            ;;
        -c) run_coverage=true; shift ;;
        -C) run_coverage=true; fresh_coverage=true; shift ;;
        -t)
            selected_test_file="$2"
            shift 2
            while [[ -n "$1" && "$1" != -* ]]; do
                test_cases+=("$1")
                shift
            done
            ;;
        -f) show_failures=true; shift ;;
        -r) run_luacheck=true; shift ;;
        -g)
            search_for_string=true
            shift
            string_to_grep="$1"
            shift
            if [[ -n "$1" && "$1" != -* ]]; then
                num_context_lines="$1"
                shift
            fi
            ;;
        *) echo "Unknown option: $1"; usage ;;
    esac
done

if [ "$save_output" = true ]; then
    exec > >(tee "$output_file") 2>&1
fi

# ---------------------------------------------------------------------------
# LUA_PATH setup
#
# Coverage runs need luacov on the LUA_PATH. Ask luarocks where it actually
# installed rocks rather than guessing a fixed directory — that varies by
# platform and by how luarocks itself is configured (system install,
# Homebrew, --local, a custom tree, etc.).
# ---------------------------------------------------------------------------
if [ "$run_coverage" = true ]; then
    if command -v luarocks >/dev/null 2>&1; then
        rocks_lua_path="$(luarocks path --lr-path)"
    fi
    if [[ -n "$LUA_PATH" ]]; then
        export LUA_PATH="$LUA_PATH${rocks_lua_path:+;$rocks_lua_path}"
    else
        export LUA_PATH="./?.lua;./?/init.lua${rocks_lua_path:+;$rocks_lua_path}"
    fi
    echo "LUA_PATH set to: $LUA_PATH"
fi

# ---------------------------------------------------------------------------
# -r: luacheck (mirrors the repo's .github/workflows/.luacheckrc — keep the
# two in sync if that file changes)
# ---------------------------------------------------------------------------
if [ "$run_luacheck" = true ]; then
    echo "Running luacheck..."
    luacheck_tmp=$(mktemp)
    cat > "$luacheck_tmp" <<'EOF'
max_line_length = false
unused_args = false
std = "lua53"
exclude_files = {"**/lustre/**", "**/lunchbox/**"}
codes = true
globals = {"SONOS_SSDP_SEARCH_TERM", "SONOS_API_KEY"}
ignore = {"42*", "43*"}
EOF
    luacheck --config "$luacheck_tmp" "${src_files[@]}"
    rm -f "$luacheck_tmp"
    exit 0
fi

# ---------------------------------------------------------------------------
# -c/-C: luacov coverage report
# ---------------------------------------------------------------------------
if [ "$run_coverage" = true ]; then
    echo "Running tests with luacov..."
    if [ "$fresh_coverage" = true ]; then
        rm -f luacov.stats.out luacov.report.html
    fi

    count=1
    for file in "${test_files[@]}"; do
        if [[ -z "$selected_test_file" || "$selected_test_file" == "$count" || "$selected_test_file" == "$file" ]]; then
            lua -lluacov "$file"
        fi
        count=$((count+1))
    done

    luacov_tmp=$(mktemp)
    cat > "$luacov_tmp" <<'EOF'
exclude = {"%/.+lua_libs+", "test%/.+"}   -- exclude lua libs and test files
reporter = "html"
reportfile = "luacov.report.html"
EOF
    luacov -c="$luacov_tmp"
    rm -f "$luacov_tmp"
    exit 0
fi

# ---------------------------------------------------------------------------
# Default mode: run each test file and build a pass/fail summary
# ---------------------------------------------------------------------------
count=1
for file in "${test_files[@]}"; do
    if [[ -z "$selected_test_file" || "$selected_test_file" == "$count" || "$selected_test_file" == "$file" ]]; then
        echo "Running Test File #$count: ${file:5}..."

        lua "$file" > run_tests_output.log 2>&1

        test_case_num=0
        passed_cases=0
        considered_cases=0
        test_case=""
        devices_api_warning=false

        # -v: echo each test case's raw output as it's found, filtered to the
        # requested test case numbers (all of them, by default) and to
        # failures only when -f is also set.
        if [ "$verbose" = true ]; then
            awk -v cases="${test_cases[*]}" -v show_failures="$show_failures" '
                BEGIN {
                    split(cases, case_arr, " ");
                    for (i in case_arr) wanted_cases[case_arr[i]];
                    case_num = 0;
                }
                /Running test/ {
                    case_num++;
                    buffer = "";
                }
                {
                    buffer = buffer $0 "\n";
                }
                /PASSED|FAILED/ {
                    if (case_num in wanted_cases || length(wanted_cases) == 0) {
                        if (show_failures == "false" || /FAILED/) print buffer;
                    }
                    buffer = "";
                }
            ' run_tests_output.log
        fi

        # Build a one-paragraph summary for this test file: a header line,
        # then one "Test Case #N: [PASS/FAIL] - name" line per case (each
        # tagged with a devices_api warning, if one preceded it).
        summary_index=$count
        summary="\nTest File #$count summary: ${file:5}\n"
        summary+=$(printf '%*s\n' "${#summary}" '' | tr ' ' '-')

        while read -r line; do
            if [[ "$line" == "Running test"* ]]; then
                test_case="${line#Running test }"
            elif [[ "$line" == "devices_api was expecting"* ]]; then
                devices_api_warning=true
                warning_text=$line
                total_warning_count=$((total_warning_count+1))
            elif [[ "$line" == "PASSED" || "$line" == "FAILED" ]]; then
                test_case_num=$((test_case_num+1))
                if [[ ${#test_cases[@]} -eq 0 || " ${test_cases[*]} " =~ " $test_case_num " ]]; then
                    if [[ "$show_failures" = false || "$line" == "FAILED" ]]; then
                        summary+="\n"
                        if [[ ${test_case_num} -eq 1 ]]; then
                            summary+="Test Case "
                        else
                            summary+="\t  "
                        fi
                        if [[ "$line" == "FAILED" ]]; then
                            summary+="#$test_case_num:\t[${red}FAIL${no_color}] - $test_case"
                        else
                            summary+="#$test_case_num:\t[${green}PASS${no_color}] - $test_case"
                        fi
                    fi
                    considered_cases=$((considered_cases+1))
                    if [[ "$line" == "PASSED" ]]; then
                        passed_cases=$((passed_cases+1))
                    fi
                    if [ "$devices_api_warning" = true ]; then
                        summary+="\n\t\t  ** ${yellow}WARNING${no_color}: $warning_text"
                        devices_api_warning=false
                    fi
                fi
            fi
        done < <(grep -E '(Running test|PASSED|FAILED|devices_api was expecting)' run_tests_output.log)

        if [ $considered_cases -gt 0 ]; then
            summary+="\n\n${green}PASS${no_color} count: $passed_cases / $considered_cases\n"
        else
            summary+="\n  ** ${red}ERROR${no_color}: Test failed to run"
            total_error_count=$((total_error_count+1))
            if [ "$verbose" = true ]; then
                cat run_tests_output.log
            fi
        fi

        if [ "$search_for_string" = true ]; then
            summary+="\nSearch results for \"$string_to_grep\":"
            while read -r line; do
                summary+="\n ##  $line"
            done < <(grep -C "$num_context_lines" "$string_to_grep" run_tests_output.log)
            summary+="\n"
        fi

        file_summaries[$summary_index]="$summary"
        total_pass_count=$((total_pass_count + passed_cases))
        total_test_count=$((total_test_count + considered_cases))
    fi
    count=$((count+1))
done

# ---------------------------------------------------------------------------
# Print results
# ---------------------------------------------------------------------------
if [ "$show_failures" = true ]; then
    for summary in "${file_summaries[@]}"; do
        test_file=$(echo "$summary" | grep -o 'Test File.*')
        failed_cases=$(echo -e "$summary" | grep -E "FAIL")
        if [[ -n "$failed_cases" ]]; then
            printf '\n\n%s' "$test_file"
        fi
    done
else
    for key in $(printf "%s\n" "${!file_summaries[@]}" | sort -n); do
        echo -e "${file_summaries[$key]}"
    done
fi

if [[ -z "$selected_test_file" ]]; then
    header="Total ${green}PASS${no_color} count: $total_pass_count / $total_test_count"
    printf '%*s----\n' "${#header}" '' | tr ' ' '-'
    echo -e "$header"
fi

echo

if [ "$total_error_count" -gt 0 ]; then
    echo -e "** ${red}ERROR${no_color} count: $total_error_count"
fi

if [ "$total_warning_count" -gt 0 ]; then
    echo -e "** ${yellow}WARNING${no_color} count: $total_warning_count"
fi

rm -f run_tests_output.log
