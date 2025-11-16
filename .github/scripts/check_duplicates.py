import csv
import os
import yaml
from pathlib import Path

cwd = os.getcwd()
duplicate_pairs = []

def compare_component_capabilities_unordered(comp1, comp2):
    for cap1 in comp1["capabilities"]:
        cap_match_found = False
        for cap2 in comp2["capabilities"]:
            if cap1["id"] == cap2["id"]:
                if cap1 == cap2:
                    cap_match_found = True
                # not a direct match, compare embedded configurations if they exist to see if they are ordered differently
                elif "config" in cap1 and "config" in cap2 and compare_embedded_configs(cap1, cap2):
                        cap_match_found = True

                # comparison is done, so break out of inner loop
                break

        if cap_match_found == False:
            return False

    # no mismatches found
    return True


# check for differences in embedded configs
def compare_embedded_configs(cap1, cap2):
    configs1 = cap1["config"]["values"]
    configs2 = cap2["config"]["values"]
    print("Comparing embedded configs...")
    for config1 in configs1:
        config_match_found = False
        for config2 in configs2:
            if config1["key"] == config2["key"]:
                if config1 == config2:
                    config_match_found = True
                # check for "enabledValues" to see if it is just a difference in ordering of the same values
                elif "enabledValues" in config1 and "enabledValues" in config2:
                    set1 = set(value for value in config1["enabledValues"])
                    set2 = set(value for value in config2["enabledValues"])
                    if set1 == set2:
                        config_match_found = True

                # comparison is done, so break out of inner loop
                break

        if config_match_found == False:
            return False

    # no mismatches found
    return True

def compare_preferences(prof1, prof2):
    if "preferences" in prof1 and "preferences" in prof2:
        return prof1["preferences"] == prof2["preferences"]
    elif "preferences" not in prof1 and "preferences" not in prof2:
        return True
    else:
        return False

def compare_metadata(prof1, prof2):
    if "metadata" in prof1 and "metadata" in prof2:
        return prof1["metadata"] == prof2["metadata"]
    elif "metadata" not in prof1 and "metadata" not in prof2:
        return True
    else:
        return False

def compare_components(prof1, prof2):
    if len(prof1["components"]) == len(prof2["components"]):
        for y, new_component in enumerate(prof1["components"]):
            current_component = prof2["components"][y]

            # compare categores. Use get() in case the category does not exist like in "thing" profiles
            if new_component.get("categories") != current_component.get("categories"):
                return False

            # compare labels
            if new_component.get("label") != current_component.get("label"):
                return False

            # check that there are the same number of capabilities and that the top capability matches
            if  ((len(new_component["capabilities"]) == len(current_component["capabilities"])) and
                (new_component["capabilities"][0]["id"] == current_component["capabilities"][0]["id"])):
                    # check if capabilities are the exact same, or
                    # similar with same top capability but different subsequent ordering
                    if (new_component["capabilities"] == current_component["capabilities"] or
                        compare_component_capabilities_unordered(new_component, current_component)):
                        print("Duplicate capabilties found.")
                    else:
                        return False
            else:
                return False
    else:
        return False

    return True

with open(str(Path.home()) + '/files.csv', 'r') as csvfile:
    csvreader = csv.reader(csvfile)
    changed_files = next(csvreader)

    for file in changed_files:
        file_basename = os.path.basename(file)
        file_directory = os.path.dirname(file)

        if '/profiles/' in file:
            print('\nNEW PROFILE:\n%s is a profile! Comparing to other profiles...' % file)

            os.chdir(file_directory)
            for current_profile in os.listdir("./"):
                new_profile = file_basename

                # compare to YAML files that are not the same file
                # Compare only .yml files and only files that have not already been found to be a duplicate
                if current_profile != new_profile and Path(current_profile).suffix == ".yml" and (current_profile, new_profile) not in duplicate_pairs:
                    print("Comparing %s vs %s" % (new_profile, current_profile))
                    with open(new_profile) as new_data, open(current_profile) as current_data:
                        new_profile_map = yaml.safe_load(new_data)
                        current_profile_map = yaml.safe_load(current_data)

                        ''' Compare profiles. A duplicate is defined as follows:
                            - categories must be the same
                            - capabilities must be the same, with some ordering restrictions
                            - top capability must match, but subsequent ordering does not matter
                            - embedded configs must be the same, but certain values can be ordered differently (i.e. enabledValues)
                            - preferences must be the same
                        '''
                        if(compare_preferences(new_profile_map, current_profile_map) == True and
                           compare_metadata(new_profile_map, current_profile_map) == True and
                           compare_components(new_profile_map, current_profile_map) == True):
                            print("%s and %s are duplicates!\n" % (new_profile, current_profile))
                            duplicate_pairs.append((new_profile, current_profile))

        # return to original directory
        os.chdir(cwd)

with open("profile-comment-body.md", "w") as f:
    if duplicate_pairs:
        f.write("Duplicate profile check: Warning - duplicate profiles detected.\n")
        for duplicate in duplicate_pairs:
            f.write("%s == %s\n" % (duplicate[0], duplicate [1]))
    else:
        f.write("Duplicate profile check: Passed - no duplicate profiles detected.")

with open("profile-comment-body.md", "r") as f:
    print("\n" + f.read())
