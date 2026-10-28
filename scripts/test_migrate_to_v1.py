"""Tests for the pure conversions in migrate_to_v1.py. Run: python3 -m unittest scripts/test_migrate_to_v1.py"""

import sys
import unittest
from datetime import datetime, timezone
from pathlib import Path

sys.path.insert(0, str(Path(__file__).parent))
import migrate_to_v1 as m  # noqa: E402

TRACKER = {
    "tracker_id": "t1",
    "receiver_id": "r1",
    "care_group_id": "g1",
    "name": "Mood",
    "kind": "event",
    "icon": "face",
    "fields": [
        {"key": "mood", "label": "Mood", "type": "enum", "required": True, "options": ["great", "ok"]},
        {"key": "weight", "label": "Weight", "type": "number", "unit": "lb", "required": True,
         "threshold": {"min": 100, "max": 200}},
    ],
    "created_by": "u1",
    "created_at": "2026-08-16T00:00:00Z",
    "archived": False,
}


class Conversions(unittest.TestCase):
    def test_ids_are_deterministic(self):
        self.assertEqual(m.new_id("team", "g1"), m.new_id("team", "g1"))
        self.assertNotEqual(m.new_id("team", "g1"), m.new_id("receiver", "g1"))

    def test_tracker_drops_kind_and_converts_fields(self):
        t = m.convert_tracker(TRACKER)
        self.assertNotIn("kind", t)
        self.assertEqual(t["status"], "active")
        mood, weight = t["fields"]
        self.assertEqual(mood["field_id"], "mood")
        self.assertEqual(mood["type"], "choice")
        self.assertFalse(mood["multiple"])
        self.assertEqual([o["label"] for o in mood["options"]], ["great", "ok"])
        self.assertEqual(weight["range"], {"low": 100, "high": 200})
        self.assertNotIn("key", weight)

    def test_event_becomes_logged_entry_with_option_ids(self):
        e = {"tracker_id": "t1", "event_id": "e1", "receiver_id": "r1", "care_group_id": "g1",
             "values": {"mood": "ok", "weight": 150}, "occurred_at": "2026-09-01T13:00:00Z",
             "logged_by": "u2", "created_at": "2026-09-01T13:05:00Z"}
        out = m.convert_event(e, TRACKER)
        self.assertEqual(out["state"], "logged")
        self.assertEqual(out["values"]["mood"], [m.option_id("t1", "mood", "ok")])
        self.assertEqual(out["values"]["weight"], 150)
        self.assertEqual(out["timeline_at"], e["occurred_at"])
        self.assertEqual(out["logged_at"], e["created_at"])
        self.assertNotIn("open_at", out)
        # the option id on the entry is the one on the tracker
        ids = [o["option_id"] for o in m.convert_tracker(TRACKER)["fields"][0]["options"]]
        self.assertIn(out["values"]["mood"][0], ids)

    def test_unmatched_choice_is_reported(self):
        self.assertEqual(m.unmatched_choices(TRACKER, {"mood": "meh"}), ["mood='meh'"])
        self.assertEqual(m.unmatched_choices(TRACKER, {"mood": "ok"}), [])

    def test_scheduled_item_becomes_open_scheduled_entry_in_local_time(self):
        si = {"scheduled_item_id": "s1", "tracker_id": "t1", "receiver_id": "r1", "care_group_id": "g1",
              "values": {}, "scheduled_for": "2026-11-02T15:00:00Z", "created_by": "u1",
              "created_at": "2026-10-01T00:00:00Z"}
        out = m.convert_scheduled_item(si, TRACKER, "America/Chicago")
        self.assertEqual(out["state"], "scheduled")
        self.assertEqual(out["occurrence_local"], "2026-11-02T09:00")  # CST, after DST ends
        self.assertEqual(out["open_at"], out["occurrence_at"])
        self.assertFalse(out["unrecorded_alert"])

    def test_receiver_gets_zone_and_loses_date_of_birth(self):
        r = m.convert_receiver({"receiver_id": "r1", "care_group_id": "g1", "name": "A",
                                "date_of_birth": "1940-01-01", "created_by": "u1",
                                "created_at": "2026-08-16T00:00:00Z"}, "America/Chicago")
        self.assertEqual(r["time_zone"], "America/Chicago")
        self.assertNotIn("date_of_birth", r)

    def test_only_pending_unexpired_invitations_survive_without_role(self):
        now = datetime(2026, 10, 28, tzinfo=timezone.utc)
        base = {"token": "c", "care_group_id": "g1", "email": "a@b.c", "role": "admin",
                "invited_by": "u1", "created_at": "2026-10-20T00:00:00Z"}
        live = m.convert_invitation({**base, "status": "pending", "expires_at": now.timestamp() + 60}, now)
        self.assertEqual(live["code"], "c")
        self.assertNotIn("role", live)
        self.assertIsNone(m.convert_invitation({**base, "status": "accepted", "expires_at": now.timestamp() + 60}, now))
        self.assertIsNone(m.convert_invitation({**base, "status": "pending", "expires_at": now.timestamp() - 1}, now))


if __name__ == "__main__":
    unittest.main()
