from kw_dashboard.logfmt import split_log_line


def test_full_line_ts_info_message():
    ts, level, msg = split_log_line(
        "2026-08-16T15:02:11.884Z INFO worker starting, build 3f91c2a")
    assert ts == "2026-08-16T15:02:11.884Z"
    assert level == "INFO"
    assert msg == "worker starting, build 3f91c2a"


def test_warn_level():
    ts, level, msg = split_log_line(
        "2026-08-16T15:02:19.882Z WARN job 8813 slow: 4.66s")
    assert level == "WARN"
    assert msg == "job 8813 slow: 4.66s"


def test_error_level():
    ts, level, msg = split_log_line(
        "2026-08-16T15:02:33.910Z ERROR job 8815 failed: deadline exceeded")
    assert level == "ERROR"
    assert msg == "job 8815 failed: deadline exceeded"


def test_timestamp_but_no_level_preserves_full_message():
    line = "2026-08-16T15:02:11.884Z worker starting, build 3f91c2a"
    ts, level, msg = split_log_line(line)
    assert ts == "2026-08-16T15:02:11.884Z"
    assert level == ""
    assert msg == "worker starting, build 3f91c2a"


def test_no_timestamp_whole_line_is_message():
    line = "just a plain line with no rfc3339 timestamp at all"
    ts, level, msg = split_log_line(line)
    assert ts == ""
    assert level == ""
    assert msg == line


def test_message_containing_error_word_not_misread_as_level():
    line = "2026-08-16T15:02:11.884Z INFO something ERROR happened later"
    ts, level, msg = split_log_line(line)
    assert level == "INFO"
    assert msg == "something ERROR happened later"

    line2 = "2026-08-16T15:02:11.884Z something failed with ERROR code"
    ts2, level2, msg2 = split_log_line(line2)
    assert level2 == ""
    assert msg2 == "something failed with ERROR code"


def test_empty_string():
    assert split_log_line("") == ("", "", "")
