#!/usr/bin/env python3
"""Assert on the alerts in one logged hyn_ingest request (read from stdin).

  payload-alerts.py firing <rule> <severity>
  payload-alerts.py resolved <rule> <since> <message-prefix>

`resolved` also checks that every other rule is still reported as firing.
"""
import json
import sys

request = json.loads(sys.stdin.read())
alerts = {a["rule"]: a for a in json.loads(request["body"])["p_payload"]["alerts"]}
mode, rule = sys.argv[1], sys.argv[2]
alert = alerts.get(rule)
assert alert is not None, f"{rule} missing from {sorted(alerts)}"
if mode == "firing":
    assert alert["resolved"] is False and alert["severity"] == sys.argv[3], alert
elif mode == "resolved":
    assert alert["resolved"] is True, alert
    assert alert.get("since") == int(sys.argv[3]), alert
    assert alert["message"].startswith(sys.argv[4]), alert
    others = [a for r, a in alerts.items() if r != rule and a["resolved"] is not False]
    assert not others, others
else:
    raise SystemExit(f"unknown mode {mode}")
