#!/usr/bin/env python3
"""
Validate fingerprints.yml files changed in a PR.

Required fields per manufacturer section:
  matterManufacturer  → id, deviceLabel, vendorId, productId, deviceProfileName
  zigbeeManufacturer  → id, deviceLabel, manufacturer, model, deviceProfileName
  zwaveManufacturer   → id, deviceLabel, manufacturerId, deviceProfileName
                        + at least one of: productId, productType

Hex fields (vendorId, productId, productType, manufacturerId) must use 0xNNNN notation.
String fields must not be empty or have leading/trailing whitespace.
id values that contain YAML-special characters must be quoted.

Indentation rules (spaces only, no tabs):
  Section key:               col 0   e.g. "matterManufacturer:"
  Entry opening (- id: ...): 2-space e.g. "  - id: ..."
  All other entry fields:    4-space e.g. "    vendorId: 0x115F"

No trailing whitespace on any line.
No duplicate id values within a file.

Generic sections (zigbeeGeneric, zwaveGeneric, matterGeneric, etc.) are skipped.

Usage:
  python3 tools/validate_fingerprints.py                      # auto-detect via git diff
  python3 tools/validate_fingerprints.py path/fingerprints.yml ...
"""

import os
import re
import sys
import subprocess
from pathlib import Path

try:
    import yaml
except ImportError:
    print("Error: pyyaml is required.  pip install pyyaml", file=sys.stderr)
    sys.exit(2)

# ── Section configuration ─────────────────────────────────────────────────────

MANUFACTURER_SECTIONS = {'matterManufacturer', 'zigbeeManufacturer', 'zwaveManufacturer'}

# All fields that must be present in every entry for each section.
# Z-Wave also needs productId OR productType (checked separately).
REQUIRED_FIELDS = {
    'matterManufacturer': ['id', 'deviceLabel', 'vendorId', 'productId', 'deviceProfileName'],
    'zigbeeManufacturer': ['id', 'deviceLabel', 'manufacturer', 'model', 'deviceProfileName'],
    'zwaveManufacturer':  ['id', 'deviceLabel', 'manufacturerId', 'deviceProfileName'],
}

# These fields must be formatted as hex literals (0xNNNN).
HEX_FIELDS = {'vendorId', 'productId', 'productType', 'manufacturerId'}

# YAML characters that force quoting when present in an unquoted scalar.
_YAML_SPECIAL_RE = re.compile(r'[:{}\[\],&#*?|<>=!%@`]')

# Matches a valid hex literal.
_HEX_RE = re.compile(r'^0x[0-9A-Fa-f]+$')

# Matches a field line:  (indent)(key): (value)
_FIELD_RE = re.compile(r'^( *)([\w]+): *(.*?) *$')


# ── Raw-text analysis ─────────────────────────────────────────────────────────

def analyse_lines(lines, filepath):
    """
    Single-pass raw-line analysis. Returns a list of errors and a dict:
      section_entry_lines[section] = list of (lineno, field, raw_value)
    for structured cross-checking later.
    """
    errors = []
    section = None                    # current top-level key
    entry_indent = None               # indent of the "  - id:" line for current entry
    in_manufacturer_section = False

    for lineno, raw in enumerate(lines, 1):
        line = raw.rstrip('\n')

        # ── No tabs ───────────────────────────────────────────────────────────
        if '\t' in line:
            errors.append(f"{filepath}:{lineno}: tab character found (use spaces)")

        # ── Trailing whitespace ───────────────────────────────────────────────
        if line != line.rstrip():
            errors.append(f"{filepath}:{lineno}: trailing whitespace")

        stripped = line.strip()
        if not stripped or stripped.startswith('#'):
            continue

        indent = len(line) - len(line.lstrip())

        # ── Top-level section key detection ───────────────────────────────────
        if indent == 0 and line.endswith(':') and not line.startswith(' '):
            section = line[:-1].strip()
            in_manufacturer_section = section in MANUFACTURER_SECTIONS
            entry_indent = None
            continue

        if not in_manufacturer_section:
            continue

        # ── Entry opening line:  "  - id: ..." ───────────────────────────────
        if stripped.startswith('- '):
            if indent != 2:
                errors.append(
                    f"{filepath}:{lineno}: [{section}] entry list item must be indented "
                    f"2 spaces, found {indent}"
                )
            entry_indent = indent

            # Check that this is the id field
            rest = stripped[2:]  # strip "- "
            m = _FIELD_RE.match('  ' + rest)  # re-prefix spaces for consistent match
            if m:
                field = m.group(2)
                raw_val = m.group(3)
                if field == 'id':
                    _check_id_quoting(raw_val, lineno, section, filepath, errors)
            continue

        # ── Subsequent fields of an entry ─────────────────────────────────────
        if entry_indent is not None:
            expected_indent = entry_indent + 2  # 2 + 2 = 4
            if indent != expected_indent:
                errors.append(
                    f"{filepath}:{lineno}: [{section}] field must be indented "
                    f"{expected_indent} spaces, found {indent}"
                )

            m = _FIELD_RE.match(line)
            if not m:
                continue
            field = m.group(2)
            raw_val = m.group(3).split('#')[0].strip()  # strip inline comment

            # ── Hex field format ──────────────────────────────────────────────
            if field in HEX_FIELDS and raw_val:
                if not _HEX_RE.match(raw_val):
                    errors.append(
                        f"{filepath}:{lineno}: [{section}] field '{field}' "
                        f"value {raw_val!r} must be hex notation (e.g. 0x115F)"
                    )

            # ── String field whitespace ───────────────────────────────────────
            display_val = _strip_quotes(raw_val)
            if field not in HEX_FIELDS and raw_val:
                if display_val != display_val.strip():
                    errors.append(
                        f"{filepath}:{lineno}: [{section}] field '{field}' "
                        f"value has leading/trailing whitespace: {raw_val!r}"
                    )

    return errors


def _strip_yaml_inline_comment(raw_val):
    """
    Strip an inline YAML comment from a raw scalar value.

    Handles:
      "quoted value" # comment  →  "quoted value"
      'quoted value' # comment  →  'quoted value'
      bare value # comment      →  bare value
    """
    if raw_val and raw_val[0] in ('"', "'"):
        q = raw_val[0]
        i = 1
        while i < len(raw_val):
            ch = raw_val[i]
            if q == '"' and ch == '\\':
                i += 2  # skip escaped character
                continue
            if q == "'" and ch == "'" and i + 1 < len(raw_val) and raw_val[i + 1] == "'":
                i += 2  # escaped single-quote inside single-quoted string
                continue
            if ch == q:
                return raw_val[:i + 1]  # return up to and including closing quote
            i += 1
        return raw_val  # unclosed quote — return as-is
    # Unquoted: strip from ' #' (space + hash = inline comment marker)
    idx = raw_val.find(' #')
    if idx != -1:
        return raw_val[:idx].rstrip()
    return raw_val


def _check_id_quoting(raw_val, lineno, section, filepath, errors):
    """Require quoting when the id value contains YAML-special characters."""
    raw_val = _strip_yaml_inline_comment(raw_val)
    is_quoted = (
        len(raw_val) >= 2
        and raw_val[0] in ('"', "'")
        and raw_val[-1] == raw_val[0]
    )
    inner = raw_val[1:-1] if is_quoted else raw_val
    if not is_quoted and _YAML_SPECIAL_RE.search(inner):
        errors.append(
            f"{filepath}:{lineno}: [{section}] id value {raw_val!r} contains "
            f"special characters and must be quoted"
        )


def _strip_quotes(val):
    if len(val) >= 2 and val[0] in ('"', "'") and val[-1] == val[0]:
        return val[1:-1]
    return val


# ── YAML structural checks ────────────────────────────────────────────────────

def check_structure(data, filepath):
    errors = []

    for section, entries in data.items():
        if section not in MANUFACTURER_SECTIONS:
            continue

        if not isinstance(entries, list):
            errors.append(f"{filepath}: [{section}] expected a list of entries, got {type(entries).__name__}")
            continue

        seen_ids = {}
        for entry in entries:
            if not isinstance(entry, dict):
                errors.append(f"{filepath}: [{section}] entry is not a mapping: {entry!r}")
                continue

            entry_id = entry.get('id', '<missing>')

            # ── Duplicate id ──────────────────────────────────────────────────
            if entry_id in seen_ids:
                errors.append(f"{filepath}: [{section}] duplicate id {entry_id!r}")
            seen_ids[entry_id] = True

            # ── Required fields ───────────────────────────────────────────────
            # manufacturer and model may legitimately be "" (device reports no value).
            ALLOW_EMPTY = {'manufacturer', 'model'}
            for field in REQUIRED_FIELDS[section]:
                if field not in entry:
                    errors.append(
                        f"{filepath}: [{section}] id={entry_id!r}: "
                        f"missing required field '{field}'"
                    )
                elif entry[field] is None:
                    errors.append(
                        f"{filepath}: [{section}] id={entry_id!r}: "
                        f"field '{field}' has a null value"
                    )
                elif field not in ALLOW_EMPTY and isinstance(entry[field], str) and entry[field].strip() == '':
                    errors.append(
                        f"{filepath}: [{section}] id={entry_id!r}: "
                        f"field '{field}' is empty"
                    )

            # ── Z-Wave: productId or productType ──────────────────────────────
            if section == 'zwaveManufacturer':
                if 'productId' not in entry and 'productType' not in entry:
                    errors.append(
                        f"{filepath}: [{section}] id={entry_id!r}: "
                        "missing 'productId' or 'productType' (at least one required)"
                    )

    return errors


# ── File validator ────────────────────────────────────────────────────────────

def validate_file(filepath: Path) -> list:
    try:
        raw = filepath.read_text(encoding='utf-8')
    except OSError as exc:
        return [f"{filepath}: cannot read file — {exc}"]

    lines = raw.splitlines(keepends=True)

    # Raw-text pass (indentation, whitespace, hex format, id quoting)
    errors = analyse_lines(lines, str(filepath))

    # YAML structural pass (required fields, duplicates, null/empty values)
    try:
        data = yaml.safe_load(raw)
    except yaml.YAMLError as exc:
        return errors + [f"{filepath}: YAML parse error — {exc}"]

    if not isinstance(data, dict):
        return errors + [f"{filepath}: unexpected top-level YAML structure"]

    errors.extend(check_structure(data, str(filepath)))
    return errors


# ── Git helper ────────────────────────────────────────────────────────────────

def get_changed_files() -> list:
    base = os.environ.get('GITHUB_BASE_REF', 'main')
    for ref in (f'origin/{base}', base, 'HEAD~1'):
        try:
            result = subprocess.run(
                ['git', 'diff', '--name-only', '--diff-filter=AM', f'{ref}...HEAD'],
                capture_output=True, text=True, check=True
            )
            return [
                Path(f) for f in result.stdout.splitlines()
                if f.endswith('fingerprints.yml') and Path(f).exists()
            ]
        except subprocess.CalledProcessError:
            continue
    return []


# ── Main ──────────────────────────────────────────────────────────────────────

def main():
    if len(sys.argv) > 1:
        files = [Path(f) for f in sys.argv[1:]]
    else:
        files = get_changed_files()
        if not files:
            print("No changed fingerprints.yml files detected.")
            sys.exit(0)

    all_errors = []
    for f in files:
        if not f.exists():
            print(f"Warning: {f} does not exist, skipping", file=sys.stderr)
            continue
        print(f"Checking {f} ...")
        errs = validate_file(f)
        all_errors.extend(errs)

    if all_errors:
        print()
        for err in all_errors:
            print(err)
        print(f"\n✗ {len(all_errors)} error(s) found.")
        sys.exit(1)
    else:
        print(f"\n✓ {len(files)} file(s) passed validation.")
        sys.exit(0)


if __name__ == '__main__':
    main()
