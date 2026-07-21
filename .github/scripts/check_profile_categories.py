import csv
import os
import sys
import yaml
from pathlib import Path

cwd = os.getcwd()
missing_category_profiles = []
deleted_profiles = []

with open(str(Path.home()) + '/files.csv', 'r') as csvfile:
    csvreader = csv.reader(csvfile)
    changed_files = next(csvreader)

    for file in changed_files:
        file_basename = os.path.basename(file)
        file_directory = os.path.dirname(file)

        if '/profiles/' in file and file.endswith('.yml'):
            print('\nCHECKING PROFILE:\n%s' % file)

            os.chdir(file_directory)

            if not os.path.exists(file_basename):
                print("Skipping %s - file was deleted" % file_basename)
                deleted_profiles.append(file)
                os.chdir(cwd)
                continue

            with open(file_basename) as fp:
                try:
                    profile = yaml.safe_load(fp)
                except yaml.YAMLError as e:
                    print("Error parsing %s: %s" % (file_basename, e))
                    os.chdir(cwd)
                    continue

            if not profile or 'components' not in profile:
                print("Skipping %s - no components found" % file_basename)
                os.chdir(cwd)
                continue

            # Find the main component and verify it has a categories field
            main_component = next(
                (c for c in profile['components'] if c.get('id') == 'main'),
                None
            )

            if main_component is None:
                print("Warning: %s has no 'main' component" % file_basename)
                os.chdir(cwd)
                continue

            if not main_component.get('categories'):
                print("MISSING CATEGORY: %s" % file)
                missing_category_profiles.append(file)
            else:
                print("OK: %s has categories: %s" % (
                    file_basename,
                    [c['name'] for c in main_component['categories']]
                ))

        os.chdir(cwd)

with open("profile-categories-comment-body.md", "w") as f:
    if missing_category_profiles:
        f.write("Profile category check: :x: **Missing categories detected.**\n\n")
        f.write("The following profiles are missing a `categories` field on the `main` component:\n\n")
        for profile in missing_category_profiles:
            f.write("- `%s`\n" % profile)
        f.write("\nPlease add a `categories` entry to the `main` component. Example:\n")
        f.write("```yaml\ncomponents:\n  - id: main\n    categories:\n      - name: Switch\n    capabilities:\n      ...\n```\n")
    else:
        f.write("Profile category check: :white_check_mark: Passed - all profiles have a category defined.\n")

    if deleted_profiles:
        f.write("\n:warning: **Deleted profile files detected:**\n")
        for deleted in deleted_profiles:
            f.write("- `%s`\n" % deleted)

with open("profile-categories-comment-body.md", "r") as f:
    print("\n" + f.read())

if missing_category_profiles:
    sys.exit(1)
