import os
import sys
import re

ignored_folders = ["test"]

driver = os.getcwd() + "/drivers/SmartThings/zigbee-thermostat/"
subdriver_folders = list(filter(lambda x: "." not in x and x not in ignored_folders, os.listdir(driver + "src/")))

for subdriver in subdriver_folders:
    path = driver + "src/" + subdriver
    init_file = path 

    new_init_buffer = []
    new_init = path + "/init.lua.new" 

    capture_key = None
    captures = {}

    end_counter = 0
    filename = path + "/init.lua"
    print(filename)
    with open(filename, 'r') as fd:
        for line in fd:

            # unnamed can_handle function
            if match := re.match(r"(\s*)can_handle\s*=\s*(function.*)",line):
                capture_key = "can_handle.lua"
                replacement = f"{match.group(1)}can_handle = require(\"{subdriver}.can_handle\")\n"

                print(match.groups())
                print(replacement)
                new_init_buffer.append(replacement)

            # named function somewhere else
            elif match := re.match(r"(\s*)can_handle\s*=\s*(.*)",line):
                replacement = f"{match.group(1)}can_handle = require(\"{subdriver}.can_handle\")\n"
                print(match.groups())
                print(replacement)
                new_init_buffer.append(replacement)
                print("Reread")





            elif capture_key:
                # Create or append the line to the captured segment
                try:
                    captures[capture_key].append(line)
                except KeyError:
                    captures[capture_key] = [line]
                print(f"{capture_key}{end_counter}:{line}",end="")
                    
                if match := re.match(r"(?!\s*(?:else|elseif))(?=.*\b(?:then|if|for|function)\b).+$",line):
                    end_counter += 1
                elif match := re.match(r"\s*end\s*",line):
                    end_counter = max(end_counter-1,0)
                
                if end_counter == 0:
                    capture_key = None
            # elif match := re.match(r"\s*local\s+(?:function|(?:(.+\S)\s*=))\s*(?:function)?\s*\(.*\)",line):
            #     end_counter += 1
            #     capture_key = match.group(1)
            #     captures[capture_key] = [line]
            #     print(f"{capture_key}:{line}",end="")
            # else:
            #     new_init_buffer.append(line)
    
    with open(filename, 'r') as fd:
        for line in fd:
            
    for key in captures.keys():
        print(f"Key:{key}")
        # for l in captures[key]:
        #     print(l,end="")
    break
    # print("="*20)
    
    # with open(new_init,'w') as fd:
    #     fd.writelines(new_init_buffer)