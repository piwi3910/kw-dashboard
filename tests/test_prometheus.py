import pytest
from kw_dashboard.sources.prometheus import parse_vector, Sample, QUERIES

VECTOR = {
    "status": "success",
    "data": {"resultType": "vector", "result": [
        {"metric": {"instance": "192.168.10.101:9100"}, "value": [1786889057.7, "7.17"]},
        {"metric": {"instance": "192.168.10.102:9100"}, "value": [1786889057.7, "10.05"]},
    ]},
}

def test_parse_vector_returns_samples():
    s = parse_vector(VECTOR)
    assert len(s) == 2
    assert s[0] == Sample(labels={"instance": "192.168.10.101:9100"}, value=7.17)

def test_parse_vector_rejects_error_status():
    with pytest.raises(ValueError):
        parse_vector({"status": "error", "error": "boom"})

def test_parse_vector_handles_empty_result():
    assert parse_vector({"status": "success", "data": {"result": []}}) == []

def test_parse_vector_skips_nan_values():
    bad = {"status": "success", "data": {"result": [
        {"metric": {}, "value": [1.0, "NaN"]}]}}
    assert parse_vector(bad) == []

def test_temperature_query_uses_thermal_zone_not_hwmon():
    # hwmon includes NVMe drive temps and would misreport disk as CPU
    assert "node_thermal_zone_temp" in QUERIES["node_temp"]
    assert "hwmon" not in QUERIES["node_temp"]
    assert "max by" in QUERIES["node_temp"]
