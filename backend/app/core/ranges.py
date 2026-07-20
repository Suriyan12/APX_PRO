"""HTTP Range header parsing shared across streaming endpoints."""


def parse_range(header: str, total: int):
    """Parse a single-range 'bytes=start-end' header. Returns (start, end)
    inclusive within [0, total), or None if missing/unsatisfiable."""
    if not header or not header.startswith("bytes=") or total <= 0:
        return None
    spec = header[len("bytes="):].split(",")[0].strip()
    if "-" not in spec:
        return None
    start_s, end_s = spec.split("-", 1)
    try:
        if start_s == "":
            n = int(end_s)  # suffix range: last N bytes
            if n <= 0:
                return None
            start, end = max(0, total - n), total - 1
        else:
            start = int(start_s)
            end = int(end_s) if end_s else total - 1
    except ValueError:
        return None
    if start > end or start >= total:
        return None
    return start, min(end, total - 1)
