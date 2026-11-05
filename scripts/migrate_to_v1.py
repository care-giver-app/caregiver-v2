# /// script
# requires-python = ">=3.11"
# dependencies = ["boto3>=1.34"]
# ///
"""Copy-and-convert the old tables onto the ADR 0012 target model.

Reads caregiver-{source}-{entity} and writes caregiver-{target}-v1-{entity}. The
source tables are only ever scanned, never written. Every new id is a uuid5 of
the old key, so a re-run rewrites the same rows rather than duplicating them.

    uv run scripts/migrate_to_v1.py --source prod --target dev --dry-run
    uv run scripts/migrate_to_v1.py --source prod --target dev
    uv run scripts/migrate_to_v1.py --source prod --target prod --cutover   # cutover day only
"""

from __future__ import annotations

import argparse
import sys
import uuid
from datetime import datetime, timezone
from zoneinfo import ZoneInfo

NAMESPACE = uuid.UUID("6f1c2a52-6d0e-4b8f-9a51-0c1d2e3f4a5b")


def new_id(kind: str, old: str) -> str:
    return str(uuid.uuid5(NAMESPACE, f"{kind}:{old}"))


def option_id(tracker_id: str, field_key: str, label: str) -> str:
    return new_id("option", f"{tracker_id}/{field_key}/{label}")


def parse_time(s: str) -> datetime:
    return datetime.fromisoformat(s.replace("Z", "+00:00"))


# --- conversions (pure; see test_migrate_to_v1.py) ---------------------------


def convert_user(u: dict) -> dict:
    return {
        "user_id": u["user_id"],
        "email": u["email"],
        "name": u.get("name", ""),
        "email_notifications": True,
        "status": "active",
        "created_at": u["created_at"],
    }


def convert_team(g: dict) -> dict:
    return {
        "team_id": new_id("team", g["care_group_id"]),
        "name": g["name"],
        "status": "active",
        "created_by": g["created_by"],
        "created_at": g["created_at"],
    }


def convert_membership(m: dict) -> dict:
    return {
        "user_id": m["user_id"],
        "team_id": new_id("team", m["care_group_id"]),
        "role": m["role"],
        "joined_at": m["created_at"],
        "notify_reminders": True,
        "notify_range_alerts": True,
        "notify_gap_alerts": True,
        "notify_unrecorded_alerts": True,
    }


def convert_invitation(i: dict, now: datetime) -> dict | None:
    """Pending, unexpired invitations only; every invitation now joins as a caregiver."""
    if i.get("status") != "pending" or int(i["expires_at"]) <= now.timestamp():
        return None
    return {
        "code": i["token"],
        "team_id": new_id("team", i["care_group_id"]),
        "email": i["email"],
        "status": "pending",
        "invited_by": i["invited_by"],
        "created_at": i["created_at"],
        "expires_at": int(i["expires_at"]),
    }


def convert_receiver(r: dict, time_zone: str) -> dict:
    out = {
        "receiver_id": new_id("receiver", r["receiver_id"]),
        "team_id": new_id("team", r["care_group_id"]),
        "name": r["name"],
        "time_zone": time_zone,
        "status": "archived" if r.get("archived") else "active",
        "created_by": r["created_by"],
        "created_at": r["created_at"],
    }
    # date_of_birth is dropped: the PRD does not describe it (ADR 0012).
    return out


def convert_field(tracker_id: str, f: dict) -> dict:
    out = {
        "field_id": f["key"],
        "label": f["label"],
        "type": "choice" if f["type"] == "enum" else f["type"],
        "required": bool(f.get("required", False)),
        "status": "active",
    }
    if f.get("unit"):
        out["unit"] = f["unit"]
    if f["type"] == "enum":
        out["multiple"] = False
        out["options"] = [
            {"option_id": option_id(tracker_id, f["key"], o), "label": o, "status": "active"}
            for o in f.get("options", [])
        ]
    thr = f.get("threshold")
    if f["type"] == "number" and thr and ("min" in thr or "max" in thr):
        out["range"] = {k2: thr[k1] for k1, k2 in (("min", "low"), ("max", "high")) if k1 in thr}
    return out


def convert_tracker(t: dict) -> dict:
    out = {
        "tracker_id": new_id("tracker", t["tracker_id"]),
        "receiver_id": new_id("receiver", t["receiver_id"]),
        "team_id": new_id("team", t["care_group_id"]),
        "name": t["name"],
        "fields": [convert_field(t["tracker_id"], f) for f in t.get("fields", [])],
        "status": "paused" if t.get("archived") else "active",
        "created_by": t["created_by"],
        "created_at": t["created_at"],
    }
    for k in ("icon", "color"):
        if t.get(k):
            out[k] = t[k]
    return out


def convert_values(old_tracker: dict, values: dict) -> dict:
    """Re-key nothing (field keys are the field ids); turn choice text into option ids."""
    choice_keys = {f["key"] for f in old_tracker.get("fields", []) if f["type"] == "enum"}
    out = {}
    for k, v in values.items():
        if k in choice_keys:
            out[k] = [option_id(old_tracker["tracker_id"], k, v)]
        else:
            out[k] = v
    return out


def unmatched_choices(old_tracker: dict, values: dict) -> list[str]:
    opts = {f["key"]: set(f.get("options", [])) for f in old_tracker.get("fields", []) if f["type"] == "enum"}
    return [f"{k}={v!r}" for k, v in values.items() if k in opts and v not in opts[k]]


def convert_event(e: dict, old_tracker: dict) -> dict:
    out = {
        "entry_id": new_id("entry", f"event/{e['tracker_id']}/{e['event_id']}"),
        "tracker_id": new_id("tracker", e["tracker_id"]),
        "receiver_id": new_id("receiver", e["receiver_id"]),
        "team_id": new_id("team", e["care_group_id"]),
        "state": "logged",
        "values": convert_values(old_tracker, e.get("values", {})),
        "occurred_at": e["occurred_at"],
        "logged_by": e["logged_by"],
        "logged_at": e["created_at"],
        "created_by": e["logged_by"],
        "created_at": e["created_at"],
        "timeline_at": e["occurred_at"],
    }
    if e.get("note"):
        out["note"] = e["note"]
    return out


def convert_scheduled_item(si: dict, old_tracker: dict, time_zone: str) -> dict:
    at = si["scheduled_for"]
    local = parse_time(at).astimezone(ZoneInfo(time_zone)).strftime("%Y-%m-%dT%H:%M")
    planned = convert_values(old_tracker, si.get("values", {}))
    out = {
        "entry_id": new_id("entry", f"scheduled-item/{si['scheduled_item_id']}"),
        "tracker_id": new_id("tracker", si["tracker_id"]),
        "receiver_id": new_id("receiver", si["receiver_id"]),
        "team_id": new_id("team", si["care_group_id"]),
        "state": "scheduled",
        "occurrence_local": local,
        "occurrence_at": at,
        "planned_values": planned,
        "values": planned,
        "unrecorded_alert": False,
        "created_by": si["created_by"],
        "created_at": si["created_at"],
        "timeline_at": at,
        "open_at": at,
    }
    if si.get("note"):
        out["note"] = si["note"]
    return out


# --- I/O ---------------------------------------------------------------------


def scan(table) -> list[dict]:
    items, kwargs = [], {}
    while True:
        page = table.scan(**kwargs)
        items.extend(page["Items"])
        if "LastEvaluatedKey" not in page:
            return items
        kwargs["ExclusiveStartKey"] = page["LastEvaluatedKey"]


def main() -> int:
    ap = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    ap.add_argument("--source", required=True, choices=["dev", "prod"])
    ap.add_argument("--target", required=True, choices=["dev", "prod"])
    ap.add_argument("--time-zone", default="America/Chicago", help="for every receiver (ADR 0012)")
    ap.add_argument("--region", default="us-east-2")
    ap.add_argument("--dry-run", action="store_true", help="convert and report; write nothing")
    ap.add_argument("--cutover", action="store_true", help="required to write prod")
    args = ap.parse_args()
    if args.target == "prod" and not args.cutover:
        print("refusing to write prod without --cutover", file=sys.stderr)
        return 2
    ZoneInfo(args.time_zone)  # fail fast on a bad zone

    import boto3

    ddb = boto3.resource("dynamodb", region_name=args.region)
    src = lambda e: ddb.Table(f"caregiver-{args.source}-{e}")
    dst = lambda e: ddb.Table(f"caregiver-{args.target}-v1-{e}")
    now = datetime.now(timezone.utc)

    old_trackers = {t["tracker_id"]: t for t in scan(src("tracker"))}
    plan: dict[str, list[dict]] = {
        "user": [convert_user(u) for u in scan(src("user"))],
        "team": [convert_team(g) for g in scan(src("care-group"))],
        "membership": [convert_membership(m) for m in scan(src("membership"))],
        "invitation": [i for i in (convert_invitation(x, now) for x in scan(src("invitation"))) if i],
        "receiver": [convert_receiver(r, args.time_zone) for r in scan(src("receiver"))],
        "tracker": [convert_tracker(t) for t in old_trackers.values()],
        "entry": [],
    }

    problems: list[str] = []
    for e in scan(src("event")):
        t = old_trackers.get(e["tracker_id"])
        if t is None:
            problems.append(f"event {e['event_id']}: tracker {e['tracker_id']} missing")
            continue
        problems += [f"event {e['event_id']}: unmatched choice {u}" for u in unmatched_choices(t, e.get("values", {}))]
        plan["entry"].append(convert_event(e, t))
    for si in scan(src("scheduled-item")):
        t = old_trackers.get(si["tracker_id"])
        if t is None:
            problems.append(f"scheduled item {si['scheduled_item_id']}: tracker {si['tracker_id']} missing")
            continue
        plan["entry"].append(convert_scheduled_item(si, t, args.time_zone))

    for entity, rows in plan.items():
        print(f"{entity:>12}: {len(rows)}")
    if problems:
        print(f"\n{len(problems)} problem(s) — nothing written:", file=sys.stderr)
        for p in problems:
            print(f"  {p}", file=sys.stderr)
        return 1
    if args.dry_run:
        print("\ndry run — nothing written")
        return 0

    for entity, rows in plan.items():
        with dst(entity).batch_writer() as w:
            for row in rows:
                w.put_item(Item=row)
    print(f"\nwrote caregiver-{args.target}-v1-* from caregiver-{args.source}-*")
    return 0


if __name__ == "__main__":
    sys.exit(main())
