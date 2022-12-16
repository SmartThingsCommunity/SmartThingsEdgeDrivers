import csv
import os
import yaml
from pathlib import Path

cwd = os.getcwd()
duplicate_pairs = []

def compare_component_capabilities_no_order(comp1, comp2):
    for cap1 in comp1["capabilities"]:
        for cap2 in comp2["capabilities"]:
            if cap1["id"] == cap2["id"]:
                if cap1 == cap2:
                    # capabilities are an exact match (including embedded configs if present), continue to next comparison
                    break
                # not a direct match, compare embedded configurations if they exist to see if they are ordered differently
                elif "config" in cap1 and "config" in cap2:
                    if compare_embedded_configs(cap1, cap2):
                        # embedded configs match but have a different order
                        break
                    else:
                        # embedded configs do not match
                        return False
                else:
                    return False

    # no mismatches found
    return True


# check for differences in embedded configs
def compare_embedded_configs(cap1, cap2):
    configs1 = cap1["config"]["values"]
    configs2 = cap2["config"]["values"]
    print("Comparing embedded configs...")
    for config1 in configs1:
        for config2 in configs2:
            if config1["key"] == config2["key"]:
                if config1 == config2:
                    break
                # check for "enabledValues" to see if it is just a difference in ordering of the same values
                elif "enabledValues" in config1 and "enabledValues" in config2:
                    set1 = set( value for value in config1["enabledValues"])
                    set2 = set( value for value in config2["enabledValues"])
                    if set1 == set2:
                        # match found, continue to next config comparison
                        break
                    else:
                        return False
                # configs are not equivalent
                else:
                    return False

    # no mismatches found
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
                    is_duplicate = True
                    print("Comparing %s vs %s" % (new_profile, current_profile))
                    with open(new_profile) as new_data, open(current_profile) as current_data:
                        new_profile_map = yaml.safe_load(new_data)
                        current_profile_map = yaml.safe_load(current_data)

                        ''' Compare components. A duplicate is defined as follows:
                            - categories must be the same
                            - capabilities must be the same, with some ordering restrictions
                            - top capability must match, but subsequent ordering does not matter
                            - embedded configs must be the same, but certain values can be ordered differently (i.e. enabledValues)
                        '''
                        if len(new_profile_map["components"]) == len(current_profile_map["components"]):
                            for y, new_component in enumerate(new_profile_map["components"]):
                                current_component = current_profile_map["components"][y]

                                # compare categores
                                if new_component["categories"] != current_component["categories"]:
                                    is_duplicate = False
                                    break

                                # check that there are the same number of capabilities and that the top capability matches
                                if  ((len(new_component["capabilities"]) == len(current_component["capabilities"])) and
                                    (new_component["capabilities"][0]["id"] == current_component["capabilities"][0]["id"])):
                                        # check if capabilities are the exact same, or
                                        # similar with same top capability but different subsequent ordering
                                        if (new_component["capabilities"] == current_component["capabilities"] or
                                            compare_component_capabilities_no_order(new_component, current_component)):
                                            print("Duplicate capabilties found.")
                                        else:
                                            print("Capabilities do not match.")
                                            is_duplicate = False
                                            break
                                else:
                                    is_duplicate = False
                                    break
                        else:
                            is_duplicate = False

                        if is_duplicate:
                            print("%s and %s are duplicates!\n" % (new_profile, current_profile))
                            duplicate_pairs.append((new_profile, current_profile))

        # return to original directory
        os.chdir(cwd)

with open("profile-comment-body.md", "w") as f:
    if duplicate_pairs:
        f.write("Duplicate profile(s) detected:\n")
        for duplicate in duplicate_pairs:
            f.write("%s == %s\n" % (duplicate[0], duplicate [1]))
    else:
        f.write("No duplicate profiles detected.")
