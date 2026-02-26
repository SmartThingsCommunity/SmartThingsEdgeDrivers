import os
import sys

TARGETS = [
    "test.register_coroutine_test",
    "test.register_message_test",
]

INSERT_LINES = [
    "{",
    "   min_api_version = 19",
    "}\n"
]


def find_matching_paren(text, start_index):
    """Find matching closing parenthesis handling nested parentheses."""
    depth = 0
    for i in range(start_index, len(text)):
        if text[i] == "(":
            depth += 1
        elif text[i] == ")":
            depth -= 1
            if depth == 0:
                return i
    return -1


def find_next_target(content, start_index):
    """Find the next occurrence of any target."""
    positions = []
    for target in TARGETS:
        pos = content.find(target, start_index)
        if pos != -1:
            positions.append((pos, target))

    if not positions:
        return -1, None

    # Return earliest match
    positions.sort(key=lambda x: x[0])
    return positions[0]


def process_file(filepath):
    with open(filepath, "r", encoding="utf-8") as f:
        content = f.read()

    modified = False
    index = 0

    while True:
        match, target = find_next_target(content, index)
        if match == -1:
            break

        paren_start = content.find("(", match)
        if paren_start == -1:
            break

        paren_end = find_matching_paren(content, paren_start)
        if paren_end == -1:
            break

        call_block = content[paren_start + 1:paren_end]

        # Skip if already contains min_api_version
        if "min_api_version" in call_block:
            index = paren_end
            continue

        lines = call_block.splitlines()

        # Find last non-empty line
        for i in range(len(lines) - 1, -1, -1):
            stripped = lines[i].strip()
            if stripped:
                last_line_index = i
                break
        else:
            index = paren_end
            continue

        last_line = lines[last_line_index]
        stripped = last_line.strip()

        # Only modify if line ends with 'end' or '}'
        if not (stripped.endswith("end") or stripped.endswith("}")):
            index = paren_end
            continue

        indentation = last_line[:len(last_line) - len(last_line.lstrip())]

        # Add comma if needed
        if not stripped.endswith(","):
            lines[last_line_index] = last_line + ","

        # Build inserted block with correct indentation
        indented_insert = [
            indentation + line for line in INSERT_LINES
        ]

        lines = (
            lines[:last_line_index + 1]
            + indented_insert
            + lines[last_line_index + 1:]
        )

        new_call_block = "\n".join(lines)

        content = (
            content[:paren_start + 1]
            + new_call_block
            + content[paren_end:]
        )

        modified = True
        index = paren_start + 1 + len(new_call_block)

    if modified:
        with open(filepath, "w", encoding="utf-8") as f:
            f.write(content)
        print(f"Modified: {filepath}")


def process_directory(root_dir):
    for root, _, files in os.walk(root_dir):
        for file in files:
            if file.endswith(".lua"):
                process_file(os.path.join(root, file))


if __name__ == "__main__":
    if len(sys.argv) != 2:
        print("Usage: python script.py <directory>")
        sys.exit(1)

    process_directory(sys.argv[1])