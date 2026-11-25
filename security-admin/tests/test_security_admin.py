#!/usr/bin/env python3
import datetime as dt
import importlib.util
import unittest
from pathlib import Path

spec=importlib.util.spec_from_file_location("check_logs",Path(__file__).parents[1]/"check-logs.py")
mod=importlib.util.module_from_spec(spec); spec.loader.exec_module(mod)

class ParserTests(unittest.TestCase):
    def setUp(self):
        self.now=dt.datetime(2026,11,25,tzinfo=dt.timezone.utc)
    def test_failed_password_ipv4(self):
        e=mod.parse_event("Nov 25 10:00:00 host sshd[1]: Failed password for alice from 203.0.113.8 port 22 ssh2",self.now)
        self.assertEqual((e["ip"],e["user"],e["outcome"]),("203.0.113.8","alice","failed"))
    def test_failed_publickey_ipv6(self):
        e=mod.parse_event("Nov 25 10:00:00 host sshd[1]: Failed publickey for bob from 2001:db8::1 port 22 ssh2",self.now)
        self.assertEqual((e["ip"],e["method"]),("2001:db8::1","publickey"))
    def test_invalid_user(self):
        e=mod.parse_event("Nov 25 10:00:00 host sshd[1]: Invalid user guest from 198.51.100.2",self.now)
        self.assertEqual(e["outcome"],"invalid_user")
    def test_ip_like_username_does_not_override_source(self):
        e=mod.parse_event("Nov 25 10:00:00 host sshd[1]: Failed password for 192.0.2.99 from 203.0.113.7 port 22 ssh2",self.now)
        self.assertEqual(e["ip"],"203.0.113.7")
    def test_pam_rhost(self):
        e=mod.parse_event("Nov 25 10:00:00 host sshd[1]: pam_unix(sshd:auth): authentication failure; logname= uid=0 ruser= rhost=2001:db8::2 user=alice",self.now)
        self.assertEqual(e["ip"],"2001:db8::2")
    def test_syslog_timestamp(self):
        value=mod.parse_time("Nov 25 10:00:00 host sshd: Failed password",self.now)
        self.assertEqual(value.month,11)
    def test_iso_timestamp(self):
        value=mod.parse_time("2026-11-25T10:00:00+00:00 host sshd: Accepted password",self.now)
        self.assertEqual(value.hour,10)
    def test_duplicate_pam_and_sshd_event_suppressed(self):
        base={"ip":"203.0.113.8","user":"alice","outcome":"failed","method":"password"}
        a={**base,"time":"2026-11-25T10:00:00+00:00"}
        b={**base,"time":"2026-11-25T10:00:02+00:00","method":"PAM"}
        result,count=mod.deduplicate_events([a,b])
        self.assertEqual((len(result),count),(1,1))
    def test_separate_attempts_are_retained(self):
        base={"ip":"203.0.113.8","user":"alice","outcome":"failed","method":"password"}
        a={**base,"time":"2026-11-25T10:00:00+00:00"}
        b={**base,"time":"2026-11-25T10:00:05+00:00"}
        result,count=mod.deduplicate_events([a,b])
        self.assertEqual((len(result),count),(2,0))
    def test_rolling_threshold_uses_actual_time_window(self):
        values=[self.now+dt.timedelta(minutes=n) for n in (0,1,2,3,4,5,6,7)]
        self.assertEqual(mod.rolling_threshold(values,10,8)[2],8)
        self.assertIsNone(mod.rolling_threshold(values,5,8))
    def test_invalid_user_enumeration_alert(self):
        events=[{"ip":"203.0.113.9","user":f"guess{i}","outcome":"invalid_user",
                 "time":(self.now+dt.timedelta(seconds=i*20)).isoformat()} for i in range(8)]
        self.assertIn("invalid_user_enumeration",{a["type"] for a in mod.detect_alerts(events)})
    def test_password_spray_across_accounts_alert(self):
        events=[{"ip":"203.0.113.9","user":f"user{i}","outcome":"failed",
                 "time":(self.now+dt.timedelta(seconds=i*20)).isoformat()} for i in range(15)]
        self.assertIn("source_failure_burst",{a["type"] for a in mod.detect_alerts(events)})

if __name__=="__main__": unittest.main()
