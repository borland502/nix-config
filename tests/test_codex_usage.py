from __future__ import annotations

import gc
import importlib.util
import os
from decimal import Decimal
from pathlib import Path
import stat
import sys
import tempfile
import textwrap
import unittest
import warnings


HELPER_PATH = (
    Path(__file__).parents[1]
    / "ai-tools"
    / "skills"
    / "codex-usage"
    / "scripts"
    / "codex_usage.py"
)
SPEC = importlib.util.spec_from_file_location("codex_usage", HELPER_PATH)
if SPEC is None or SPEC.loader is None:
    raise RuntimeError(f"Could not load Codex usage helper at {HELPER_PATH}")
MODULE = importlib.util.module_from_spec(SPEC)
sys.modules[SPEC.name] = MODULE
SPEC.loader.exec_module(MODULE)


class CodexUsageTests(unittest.TestCase):
    def make_fake_codex(self, mode: str) -> Path:
        temp_dir = tempfile.TemporaryDirectory()
        self.addCleanup(temp_dir.cleanup)
        script_path = Path(temp_dir.name) / "codex"
        self.fake_pid_file = Path(temp_dir.name) / "pid"
        script_path.write_text(
            textwrap.dedent(
                f"""\
                #!{sys.executable}
                import json
                import os
                from pathlib import Path
                import sys
                import time

                mode = {mode!r}
                Path({str(self.fake_pid_file)!r}).write_text(str(os.getpid()))

                if sys.argv[1:] != ["app-server", "--listen", "stdio://"]:
                    raise SystemExit(f"unexpected arguments: {{sys.argv[1:]!r}}")

                initialize = json.loads(sys.stdin.readline())
                if initialize.get("method") != "initialize" or initialize.get("id") != 1:
                    raise SystemExit(f"unexpected initialize request: {{initialize!r}}")
                print(json.dumps({{"id": 1, "result": {{"serverInfo": {{}}}}}}), flush=True)

                initialized = json.loads(sys.stdin.readline())
                if initialized.get("method") != "initialized" or "id" in initialized:
                    raise SystemExit(f"unexpected initialized notification: {{initialized!r}}")

                request = json.loads(sys.stdin.readline())
                if request.get("method") != "account/rateLimits/read" or request.get("id") != 2:
                    raise SystemExit(f"unexpected rate-limit request: {{request!r}}")

                if mode == "timeout":
                    time.sleep(5)
                elif mode == "error":
                    print(json.dumps({{"id": 2, "error": {{"message": "denied"}}}}), flush=True)
                else:
                    print(json.dumps({{
                        "id": 2,
                        "result": {{
                            "rateLimitsByLimitId": {{
                                "codex": {{
                                    "individualLimit": {{
                                        "limit": "36000",
                                        "used": "137.6699390411377",
                                        "remainingPercent": 100,
                                        "resetsAt": 1793491200
                                    }},
                                    "planType": "business"
                                }}
                            }}
                        }}
                    }}), flush=True)
                """
            )
        )
        script_path.chmod(script_path.stat().st_mode | stat.S_IXUSR)
        return script_path

    def test_summarizes_individual_limit(self) -> None:
        response = {
            "rateLimitsByLimitId": {
                "codex": {
                    "individualLimit": {
                        "limit": "36000",
                        "used": "137.6699390411377",
                        "remainingPercent": 100,
                        "resetsAt": 1793491200,
                    },
                    "planType": "business",
                }
            }
        }

        summary = MODULE.summarize_usage(response)

        self.assertEqual(summary.limit, Decimal("36000"))
        self.assertEqual(summary.used, Decimal("137.6699390411377"))
        self.assertEqual(summary.remaining, Decimal("35862.3300609588623"))
        self.assertEqual(
            summary.used_percent.quantize(Decimal("0.01")), Decimal("0.38")
        )

    def test_rejects_missing_individual_limit(self) -> None:
        with self.assertRaisesRegex(MODULE.UsageError, "individualLimit"):
            MODULE.summarize_usage({"rateLimitsByLimitId": {"codex": {}}})

    def test_requests_rate_limits_over_jsonl(self) -> None:
        fake_codex = self.make_fake_codex("success")

        response = MODULE.request_rate_limits(str(fake_codex))

        self.assertEqual(
            response["rateLimitsByLimitId"]["codex"]["individualLimit"]["limit"],
            "36000",
        )

    def test_reports_rpc_error(self) -> None:
        fake_codex = self.make_fake_codex("error")

        with warnings.catch_warnings(record=True) as observed:
            warnings.simplefilter("always", ResourceWarning)
            with self.assertRaisesRegex(MODULE.UsageError, "denied"):
                MODULE.request_rate_limits(str(fake_codex))
            gc.collect()

        resource_warnings = [
            warning
            for warning in observed
            if issubclass(warning.category, ResourceWarning)
        ]
        self.assertEqual(resource_warnings, [])

    def test_times_out_and_stops_child(self) -> None:
        fake_codex = self.make_fake_codex("timeout")

        with self.assertRaisesRegex(MODULE.UsageError, "timed out"):
            MODULE.request_rate_limits(str(fake_codex), timeout=1.0)

        child_pid = int(self.fake_pid_file.read_text())
        with self.assertRaises(ProcessLookupError):
            os.kill(child_pid, 0)


if __name__ == "__main__":
    unittest.main()
