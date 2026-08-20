from kw_dashboard.sources.alerts import parse_alerts, rank_alerts, Alert

PAYLOAD = [
    {
        "labels": {"alertname": "DiskLow", "severity": "warning"},
        "annotations": {"summary": "disk low"},
        "status": {"state": "active"},
        "startsAt": "2026-08-16T10:00:00Z",
    },
    {
        "labels": {"alertname": "NodeDown", "severity": "critical"},
        "annotations": {"summary": "node down"},
        "status": {"state": "active"},
        "startsAt": "2026-08-16T11:00:00Z",
    },
    {
        "labels": {"alertname": "Silenced", "severity": "critical"},
        "annotations": {"summary": "x"},
        "status": {"state": "suppressed"},
        "startsAt": "2026-08-16T09:00:00Z",
    },
]


def test_parse_alerts_skips_suppressed():
    a = parse_alerts(PAYLOAD)
    assert {x.name for x in a} == {"DiskLow", "NodeDown"}


def test_rank_alerts_critical_first():
    assert rank_alerts(parse_alerts(PAYLOAD))[0].name == "NodeDown"


def test_rank_alerts_unknown_severity_sorts_last():
    a = [Alert("X", "bogus", "s", None), Alert("Y", "critical", "s", None)]
    assert [x.name for x in rank_alerts(a)] == ["Y", "X"]


def test_has_critical_detects_preemption_condition():
    from kw_dashboard.sources.alerts import has_critical

    assert has_critical(parse_alerts(PAYLOAD)) is True
    assert has_critical([]) is False
