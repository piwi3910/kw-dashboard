import pytest
from kw_dashboard.sources.prometheus import parse_vector, parse_matrix, Sample, Series, QUERIES, RANGE_QUERIES

MATRIX = {
    "status": "success",
    "data": {"resultType": "matrix", "result": [
        {"metric": {"instance": "192.168.10.101:9100"},
         "values": [[1000.0, "7.17"], [1060.0, "8.0"]]},
        {"metric": {"instance": "192.168.10.102:9100"},
         "values": [[1000.0, "10.05"], [1060.0, "11.0"]]},
    ]},
}

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


def test_parse_matrix_returns_series_with_points():
    s = parse_matrix(MATRIX)
    assert len(s) == 2
    assert s[0] == Series(labels={"instance": "192.168.10.101:9100"},
                           points=((1000.0, 7.17), (1060.0, 8.0)))


def test_parse_matrix_rejects_error_status():
    with pytest.raises(ValueError):
        parse_matrix({"status": "error", "error": "boom"})


def test_parse_matrix_drops_non_finite_values():
    bad = {"status": "success", "data": {"result": [
        {"metric": {}, "values": [[1.0, "NaN"], [2.0, "3.0"], [3.0, "Inf"]]}]}}
    s = parse_matrix(bad)
    assert s[0].points == ((2.0, 3.0),)


def test_parse_matrix_skips_malformed_entries():
    bad = {"status": "success", "data": {"result": [
        {"metric": {}, "values": "not-a-list"},
        {"no_values_key": True},
        {"metric": {"instance": "ok"}, "values": [[1.0, "5.0"]]},
    ]}}
    s = parse_matrix(bad)
    assert len(s) == 1
    assert s[0].labels == {"instance": "ok"}


def test_range_queries_include_node_and_ns_metrics():
    assert "node_cpu" in RANGE_QUERIES
    assert "node_mem" in RANGE_QUERIES
    assert "ns_mem" in RANGE_QUERIES


def test_uptime_query_added_to_instant_queries():
    assert "node_uptime_days" in QUERIES
    assert "node_boot_time_seconds" in QUERIES["node_uptime_days"]
