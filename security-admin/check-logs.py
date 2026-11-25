#!/usr/bin/env python3
"""Evidence-based Linux authentication log review; standard library only."""
from __future__ import annotations
import argparse, datetime as dt, gzip, ipaddress, json, re, subprocess, sys, time
from collections import defaultdict
from pathlib import Path

SSH_EVENT = re.compile(
    r"(?P<outcome>Failed|Accepted) (?P<method>password|publickey|keyboard-interactive(?:/pam)?|hostbased|gssapi-with-mic|none)"
    r" for (?:(?:invalid|illegal) user )?(?P<user>[^ ]+) from (?P<ip>[0-9a-fA-F:.]+)(?: port |$)", re.I)
INVALID_USER = re.compile(r"Invalid user (?P<user>[^ ]+) from (?P<ip>[0-9a-fA-F:.]+)", re.I)
PAM_FAILURE = re.compile(r"authentication failure;.*?rhost=(?P<ip>[^ ;]+).*?user=(?P<user>[^ ;]+)", re.I)
ISO_TS = re.compile(r"^(\d{4}-\d\d-\d\d[T ]\d\d:\d\d:\d\d(?:\.\d+)?(?:Z|[+-]\d\d:\d\d)?)")
SYSLOG_TS = re.compile(r"^([A-Z][a-z]{2}\s+\d{1,2}\s+\d\d:\d\d:\d\d)")

def parse_time(line: str, now: dt.datetime):
    m = ISO_TS.match(line)
    if m:
        raw=m.group(1).replace("Z","+00:00")
        try:
            value=dt.datetime.fromisoformat(raw)
            return value.replace(tzinfo=value.tzinfo or dt.timezone.utc).astimezone(dt.timezone.utc)
        except ValueError:
            pass
    m=SYSLOG_TS.match(line)
    if m:
        try:
            local_year=now.astimezone().year
            parsed=time.strptime(f"{local_year} {m.group(1)}", "%Y %b %d %H:%M:%S")
            value=dt.datetime.fromtimestamp(time.mktime(parsed), dt.timezone.utc)
            if value > now + dt.timedelta(days=1):
                parsed=time.strptime(f"{local_year-1} {m.group(1)}", "%Y %b %d %H:%M:%S")
                value=dt.datetime.fromtimestamp(time.mktime(parsed), dt.timezone.utc)
            return value
        except ValueError:
            return None
    return None

def valid_ip(value):
    try:
        ip=ipaddress.ip_address(value.strip("[]"))
        return str(ip)
    except ValueError:
        return None

def parse_event(line, timestamp):
    m=SSH_EVENT.search(line)
    if m:
        ip=valid_ip(m.group("ip"))
        if ip:
            return {"time":timestamp.isoformat(), "ip":ip, "user":m.group("user"), "method":m.group("method").lower(), "outcome":m.group("outcome").lower(), "evidence":line.rstrip()}
    m=INVALID_USER.search(line)
    if m:
        ip=valid_ip(m.group("ip"))
        if ip:
            # OpenSSH may also emit a separate Failed password line for this
            # attempt. Keep this as context, not a second failed attempt.
            return {"time":timestamp.isoformat(), "ip":ip, "user":m.group("user"), "method":"unknown", "outcome":"invalid_user", "evidence":line.rstrip()}
    m=PAM_FAILURE.search(line)
    if m:
        ip=valid_ip(m.group("ip"))
        if ip and ip not in ("", "0.0.0.0", "::"):
            return {"time":timestamp.isoformat(), "ip":ip, "user":m.group("user"), "method":"PAM", "outcome":"failed", "evidence":line.rstrip()}
    return None

def deduplicate_events(events):
    # sshd and PAM can log the same failed attempt within a few seconds.
    # Collapse near-identical records so one attempt is not counted twice.
    deduplicated=[]; last_seen={}; duplicates_suppressed=0
    for event in sorted(events,key=lambda e:e["time"]):
        key=(event["ip"],event["user"],event["outcome"])
        stamp=dt.datetime.fromisoformat(event["time"])
        previous=last_seen.get(key)
        if previous is not None and (stamp-previous).total_seconds() <= 3:
            duplicates_suppressed+=1
            continue
        deduplicated.append(event); last_seen[key]=stamp
    return deduplicated,duplicates_suppressed

def read_sources(now, hours):
    journalctl=__import__("shutil").which("journalctl")
    if journalctl:
        since=(now-dt.timedelta(hours=hours)).strftime("%Y-%m-%d %H:%M:%S UTC")
        try:
            p=subprocess.run([journalctl,"--since",since,"--output=short-iso-precise","--no-pager"],
                             text=True,stdout=subprocess.PIPE,stderr=subprocess.PIPE,timeout=90)
            if p.returncode==0:
                if any(re.search(r"Failed |Accepted |Invalid user |authentication failure", line, re.I) for line in p.stdout.splitlines()):
                    return p.stdout.splitlines(), f"systemd journal ({hours:g}-hour window)", []
                journal_error="journal contains no matching SSH/PAM authentication records"
            else:
                journal_error=p.stderr.strip() or f"journalctl exit status {p.returncode}"
        except (OSError,subprocess.SubprocessError) as exc:
            journal_error=str(exc)
    else:
        journal_error="journalctl is not installed"
    paths=[]
    for pattern in ("/var/log/auth.log*", "/var/log/secure*"):
        paths.extend(Path("/").glob(pattern.lstrip("/")))
    paths=sorted(set(p for p in paths if p.is_file()), key=lambda p:(p.stat().st_mtime,p.name))
    if not paths:
        raise RuntimeError(f"No readable authentication source. Journal fallback: {journal_error}")
    lines=[]; errors=[f"Journal fallback: {journal_error}"]
    for path in paths:
        try:
            opener=gzip.open if path.name.endswith(".gz") else open
            with opener(path,"rt",encoding="utf-8",errors="replace") as stream:
                lines.extend(stream)
        except (OSError,EOFError) as exc:
            errors.append(f"{path}: {exc}")
    return lines, "authentication log files (timestamp-filtered)", errors

def rolling_threshold(values, minutes, threshold):
    values=sorted(values)
    left=0
    window=dt.timedelta(minutes=minutes)
    for right,end in enumerate(values):
        while left<=right and values[left] <= end-window:
            left+=1
        if right-left+1>=threshold:
            return values[left],end,right-left+1
    return None

def detect_alerts(events):
    by_ip=defaultdict(list); by_pair=defaultdict(list)
    for event in events:
        by_ip[event["ip"]].append(event)
        by_pair[(event["ip"],event["user"])].append(event)
    alerts=[]
    for (ip,user),items in by_pair.items():
        failures=[dt.datetime.fromisoformat(e["time"]) for e in items if e["outcome"]=="failed"]
        successes=[dt.datetime.fromisoformat(e["time"]) for e in items if e["outcome"]=="accepted"]
        burst=rolling_threshold(failures,10,8)
        if burst:
            first,last,count=burst
            alerts.append({"type":"account_failure_burst","ip":ip,"user":user,"count":count,"window":"10 minutes",
                           "first_seen":first.isoformat(),"last_seen":last.isoformat(),
                           "detail":"At least 8 failed authentication events for the same account in a rolling 10-minute window."})
        for success in successes:
            prior=[t for t in failures if success-dt.timedelta(minutes=30)<=t<success]
            if len(prior)>=5:
                alerts.append({"type":"failures_then_success","ip":ip,"user":user,"failures":len(prior),"window":"30 minutes",
                               "first_failure":min(prior).isoformat(),"successful_at":success.isoformat(),
                               "detail":"At least 5 failures for the same source IP and username preceded a successful authentication."})
                break
    for ip,items in by_ip.items():
        failures=[dt.datetime.fromisoformat(e["time"]) for e in items if e["outcome"]=="failed"]
        burst=rolling_threshold(failures,10,15)
        if burst:
            first,last,count=burst
            alerts.append({"type":"source_failure_burst","ip":ip,"count":count,"window":"10 minutes",
                           "first_seen":first.isoformat(),"last_seen":last.isoformat(),
                           "detail":"At least 15 failed authentication events from this source across accounts in a rolling 10-minute window."})
        invalid=[dt.datetime.fromisoformat(e["time"]) for e in items if e["outcome"]=="invalid_user"]
        burst=rolling_threshold(invalid,10,8)
        if burst:
            first,last,count=burst
            alerts.append({"type":"invalid_user_enumeration","ip":ip,"count":count,"window":"10 minutes",
                           "first_seen":first.isoformat(),"last_seen":last.isoformat(),
                           "detail":"At least 8 invalid-user probes from this source in a rolling 10-minute window."})
    return alerts

def main():
    parser=argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--hours",type=float,default=48,help="look-back window (default: 48 hours)")
    parser.add_argument("--json",action="store_true",help="emit machine-readable JSON")
    args=parser.parse_args()
    if args.hours<=0 or args.hours>8760:
        parser.error("--hours must be greater than 0 and no more than 8760")
    now=dt.datetime.now(dt.timezone.utc); cutoff=now-dt.timedelta(hours=args.hours)
    try:
        lines,source,errors=read_sources(now,args.hours)
    except RuntimeError as exc:
        print(f"ERROR: {exc}",file=sys.stderr); return 2
    events=[]; unparsed=0; undated=0
    for line in lines:
        if not re.search(r"Failed |Accepted |Invalid user |authentication failure",line,re.I):
            continue
        timestamp=parse_time(line,now)
        if timestamp is None:
            undated+=1; continue
        if timestamp<cutoff or timestamp>now+dt.timedelta(minutes=5):
            continue
        event=parse_event(line,timestamp)
        if event: events.append(event)
        elif re.search(r"Failed |Accepted |Invalid user |authentication failure",line,re.I):
            unparsed+=1
    events,duplicates_suppressed=deduplicate_events(events)
    by_ip=defaultdict(list); by_pair=defaultdict(list)
    for event in events:
        by_ip[event["ip"]].append(event); by_pair[(event["ip"],event["user"])].append(event)
    alerts=detect_alerts(events)
    if args.json:
        print(json.dumps({"host":__import__("socket").gethostname(),"generated_utc":now.isoformat(),
          "window_hours":args.hours,"source":source,"events":events,"alerts":alerts,
          "unparsed_auth_lines":unparsed,"undated_candidate_lines":undated,
          "duplicate_lines_suppressed":duplicates_suppressed,"source_errors":errors},indent=2))
        return 0
    print("="*72); print("AUTHENTICATION ACTIVITY REVIEW")
    print(f"Host: {__import__('socket').gethostname()} | Generated UTC: {now.isoformat()}")
    print(f"Source: {source} | Window: last {args.hours:g} hours")
    print("="*72)
    print(f"Parsed events: {len(events)} | Failed: {sum(e['outcome']=='failed' for e in events)} | Successful: {sum(e['outcome']=='accepted' for e in events)} | Invalid-user probes: {sum(e['outcome']=='invalid_user' for e in events)}")
    print(f"Duplicate log lines suppressed: {duplicates_suppressed} | Unparsed candidates: {unparsed} | Undated candidates: {undated}")
    for error in errors: print(f"WARNING: could not read {error}")
    print("\nSOURCE SUMMARY")
    for ip,items in sorted(by_ip.items()):
        failed=sum(e["outcome"]=="failed" for e in items)
        accepted=sum(e["outcome"]=="accepted" for e in items)
        invalid=sum(e["outcome"]=="invalid_user" for e in items)
        print(f"{ip:>39}  failed={failed:<5} successful={accepted:<5} invalid-user={invalid:<5} users={','.join(sorted({e['user'] for e in items}))}")
    print("\nALERTS")
    if not alerts: print("No configured failure patterns detected. This is not proof that the host is uncompromised.")
    for a in alerts:
        period=f"{a.get('first_seen',a.get('first_failure'))} to {a.get('last_seen',a.get('successful_at'))}"
        print(f"- {a['type']}: {a['ip']} user={a['user']} ({a.get('count',a.get('failures'))} events; {a['window']}; {period}). {a['detail']}")
    print("\nRECENT AUTHENTICATION EVIDENCE (up to 30 events)")
    for e in events[-30:]:
        print(f"{e['time']} {e['outcome'].upper():8} {e['ip']:>39} user={e['user']} method={e['method']}")
    print("\nReview original logs for context. Alerts are pattern matches, not compromise determinations.")
    return 0

if __name__=="__main__":
    try: sys.exit(main())
    except KeyboardInterrupt: sys.exit(130)
