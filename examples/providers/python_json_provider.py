"""Minimal PerfChecker provider with no Python dependencies."""

import json
import os
import platform
import time


case_id = os.environ.get("PERFCHECKER_CASE_ID", "python-json")
output = os.environ["PERFCHECKER_OUTPUT"]
payload = {"bibliography": ["entry"] * 100}

started = time.perf_counter_ns()
encoded = json.dumps(payload, separators=(",", ":")).encode("utf-8")
elapsed = time.perf_counter_ns() - started

result = {
    "schema_version": "perfchecker-provider-result/1",
    "suite": "python-example",
    "case_id": case_id,
    "runtime": {"language": "python", "version": platform.python_version()},
    "environment": {"os": platform.system(), "architecture": platform.machine()},
    "measurement_definitions": [
        {
            "id": "python.wall.time/perf-counter-v1",
            "metric": "python.wall.time",
            "unit": "ns",
            "preference": "lower",
        },
        {
            "id": "network.io.payload/application-json-v1",
            "metric": "network.io.payload",
            "unit": "By",
            "preference": "lower",
        },
    ],
    "observations": [
        {
            "metric": "python.wall.time",
            "value": elapsed,
            "unit": "ns",
            "measurement_definition": "python.wall.time/perf-counter-v1",
            "comparison_key": "json-encode::python.wall.time/perf-counter-v1",
        },
        {
            "metric": "network.io.payload",
            "value": len(encoded),
            "unit": "By",
            "measurement_definition": "network.io.payload/application-json-v1",
            "comparison_key": "json-encode::network.io.payload/application-json-v1",
            "attributes": {
                "capture_layer": "application",
                "direction": "out",
                "protocol": "json",
            },
        },
    ],
}

with open(output, "w", encoding="utf-8") as stream:
    json.dump(result, stream, separators=(",", ":"))
