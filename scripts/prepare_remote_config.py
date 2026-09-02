#!/usr/bin/env python3
"""Merge update-policy parameters into an exported Remote Config template.

The active template is the input so unrelated feature flags and conditions are
preserved. This script does not publish anything.
"""

import argparse
import json
from pathlib import Path


ROOT = Path(__file__).resolve().parents[1]
POLICY = ROOT / "release/remote_config_update_policy.template.json"


def main() -> int:
    parser = argparse.ArgumentParser()
    parser.add_argument("active_template", type=Path)
    parser.add_argument("output", type=Path)
    args = parser.parse_args()

    active = json.loads(args.active_template.read_text(encoding="utf-8"))
    values = json.loads(POLICY.read_text(encoding="utf-8"))
    parameters = active.setdefault("parameters", {})
    for key, value in values.items():
        parameters[key] = {
            "defaultValue": {"value": str(value).lower() if isinstance(value, bool) else str(value)},
            "description": "Wefilling release update policy (managed by release workflow)",
            "valueType": "BOOLEAN" if isinstance(value, bool) else (
                "NUMBER" if isinstance(value, int) else "STRING"
            ),
        }
    args.output.parent.mkdir(parents=True, exist_ok=True)
    args.output.write_text(
        json.dumps(active, ensure_ascii=False, indent=2) + "\n",
        encoding="utf-8",
    )
    print(f"Prepared without publishing: {args.output}")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
