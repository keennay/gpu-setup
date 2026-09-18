import importlib.metadata
import json
import os
import re
import socket
import statistics
import threading
import time
import urllib.error
import urllib.parse
import urllib.request
from dataclasses import dataclass, field
from pathlib import Path


HTTP_TIMEOUT_SECONDS = 5


@dataclass(frozen=True)
class PrometheusSample:
    name: str
    labels: tuple[tuple[str, str], ...]
    value: float


@dataclass
class SGLangMetricsSnapshot:
    endpoint: str
    samples: list[PrometheusSample]
    error: str = ""


@dataclass
class HistogramSummary:
    count: float = 0
    total: float = 0
    mean: float = 0
    p95: float | None = None
    p99: float | None = None


@dataclass
class SGLangModelMetadata:
    served_models: list[str]
    sglang_version: str = "N/A"
    max_model_len: int | None = None
    model_path: str = ""
    model_type: str = ""
    architectures: list[str] | None = None
    error: str = ""


@dataclass(frozen=True)
class SGLangStageThroughput:
    prefill_tokens_per_sec: float | None = None
    decode_tokens_per_sec: float | None = None


@dataclass(frozen=True)
class SGLangProcessInfo:
    pid: int | None = None
    command: str = ""
    source_paths: tuple[str, ...] = ()
    status: str = ""


@dataclass(frozen=True)
class BatchThroughputStats:
    count: int = 0
    mean: float | None = None
    median: float | None = None
    p95: float | None = None
    max: float | None = None


@dataclass(frozen=True)
class SGLangBatchThroughputReport:
    process: SGLangProcessInfo = field(default_factory=SGLangProcessInfo)
    prefill_input_tokens_per_sec: BatchThroughputStats = field(default_factory=BatchThroughputStats)
    decode_generation_tokens_per_sec: BatchThroughputStats = field(default_factory=BatchThroughputStats)
    status: str = ""


_METRIC_RE = re.compile(
    r"^([a-zA-Z_:][a-zA-Z0-9_:]*)(?:\{([^}]*)\})?\s+"
    r"([-+]?(?:\d+(?:\.\d*)?|\.\d+)(?:[eE][-+]?\d+)?|[-+]?Inf|NaN)(?:\s|$)"
)
_LABEL_RE = re.compile(r'([a-zA-Z_][a-zA-Z0-9_]*)="((?:\\.|[^"\\])*)"')
_PREFILL_BATCH_RE = re.compile(r"Prefill batch,.*?input throughput \(token/s\):\s*([0-9]+(?:\.[0-9]+)?)")
_DECODE_BATCH_RE = re.compile(r"Decode batch,.*?gen throughput \(token/s\):\s*([0-9]+(?:\.[0-9]+)?)")


def sglang_root_url(base_url: str) -> str:
    parsed = urllib.parse.urlsplit(base_url)
    path = parsed.path.rstrip("/")
    if path.endswith("/v1"):
        path = path[:-3]
    return urllib.parse.urlunsplit((parsed.scheme, parsed.netloc, path.rstrip("/"), "", ""))


def sglang_metrics_endpoint(base_url: str) -> str:
    return f"{sglang_root_url(base_url)}/metrics"


def _base_url_host_port(base_url: str) -> tuple[str, int | None]:
    parsed = urllib.parse.urlsplit(base_url)
    host = parsed.hostname or ""
    port = parsed.port
    if port is None:
        if parsed.scheme == "https":
            port = 443
        elif parsed.scheme == "http":
            port = 80
    return host, port


def _is_local_host(host: str) -> bool:
    normalized = host.strip("[]").lower()
    if normalized in {"", "localhost", "127.0.0.1", "0.0.0.0", "::1"}:
        return True
    try:
        local_names = {socket.gethostname().lower(), socket.getfqdn().lower()}
        return normalized in local_names
    except OSError:
        return False


def _listening_socket_inodes(port: int) -> set[str]:
    inodes: set[str] = set()
    port_hex = f"{port:04X}"
    for proc_file in ("/proc/net/tcp", "/proc/net/tcp6"):
        try:
            lines = Path(proc_file).read_text().splitlines()[1:]
        except OSError:
            continue
        for line in lines:
            fields = line.split()
            if len(fields) < 10:
                continue
            local_address = fields[1]
            state = fields[3]
            inode = fields[9]
            if state != "0A":
                continue
            _, local_port = local_address.rsplit(":", 1)
            if local_port.upper() == port_hex:
                inodes.add(inode)
    return inodes


def _pids_for_socket_inodes(inodes: set[str]) -> set[int]:
    pids: set[int] = set()
    if not inodes:
        return pids

    for proc_dir in Path("/proc").iterdir():
        if not proc_dir.name.isdigit():
            continue
        fd_dir = proc_dir / "fd"
        try:
            fd_paths = list(fd_dir.iterdir())
        except OSError:
            continue
        for fd_path in fd_paths:
            try:
                target = os.readlink(fd_path)
            except OSError:
                continue
            if target.startswith("socket:[") and target.endswith("]"):
                inode = target.removeprefix("socket:[").removesuffix("]")
                if inode in inodes:
                    pids.add(int(proc_dir.name))
                    break
    return pids


def _read_proc_cmdline(pid: int) -> str:
    try:
        raw = Path(f"/proc/{pid}/cmdline").read_bytes()
    except OSError:
        return ""
    parts = [part.decode("utf-8", errors="replace") for part in raw.split(b"\0") if part]
    return " ".join(parts)


def _read_proc_environ(pid: int) -> dict[str, str]:
    try:
        raw = Path(f"/proc/{pid}/environ").read_bytes()
    except OSError:
        return {}
    env = {}
    for item in raw.split(b"\0"):
        if not item or b"=" not in item:
            continue
        key, value = item.split(b"=", 1)
        env[key.decode("utf-8", errors="replace")] = value.decode("utf-8", errors="replace")
    return env


def _is_sglang_server_command(command: str) -> bool:
    lowered = command.lower()
    sglang_markers = (
        "sglang.launch_server",
        "sglang.srt",
        "sglang serve",
        "/sglang serve",
        "sglang-kt",
        "kt-sglang",
        "sglang_kt",
        "kt_sglang",
    )
    return any(marker in lowered for marker in sglang_markers) or (
        "sglang" in lowered and "launch_server" in lowered
    )


def _regular_file_fd_path(pid: int, fd: int) -> str | None:
    try:
        target = os.readlink(f"/proc/{pid}/fd/{fd}")
    except OSError:
        return None
    if target.endswith(" (deleted)"):
        return None
    if not target.startswith("/"):
        return None
    try:
        if Path(target).is_file():
            return target
    except OSError:
        return None
    return None


def _sglang_log_source_paths(pid: int) -> tuple[str, ...]:
    candidates = []
    env = _read_proc_environ(pid)
    launch_log = env.get("SGLANG_LAUNCH_LOG")
    if launch_log and Path(launch_log).is_file():
        candidates.append(launch_log)

    for fd in (1, 2):
        fd_path = _regular_file_fd_path(pid, fd)
        if fd_path:
            candidates.append(fd_path)

    unique = []
    for path in candidates:
        if path not in unique:
            unique.append(path)
    return tuple(unique)


def identify_sglang_process(base_url: str) -> SGLangProcessInfo:
    host, port = _base_url_host_port(base_url)
    if port is None:
        return SGLangProcessInfo(status=f"could not determine port from base URL: {base_url}")
    if not _is_local_host(host):
        return SGLangProcessInfo(status=f"base URL host is not local: {host}")

    inodes = _listening_socket_inodes(port)
    if not inodes:
        return SGLangProcessInfo(status=f"no local listening socket found for port {port}")

    pids = sorted(_pids_for_socket_inodes(inodes))
    if not pids:
        return SGLangProcessInfo(status=f"no process fd matched listening socket on port {port}")

    process_infos = []
    for pid in pids:
        command = _read_proc_cmdline(pid)
        process_infos.append((pid, command, _is_sglang_server_command(command)))

    sglang_infos = [item for item in process_infos if item[2]]
    if sglang_infos:
        pid, command, _ = sglang_infos[0]
        return SGLangProcessInfo(
            pid=pid,
            command=command,
            source_paths=_sglang_log_source_paths(pid),
            status="matched local SGLang listener",
        )

    pid, command, _ = process_infos[0]
    return SGLangProcessInfo(
        pid=pid,
        command=command,
        source_paths=_sglang_log_source_paths(pid),
        status=f"matched local listener on port {port}, but command was not recognized as SGLang",
    )


def _headers(api_key: str | None) -> dict[str, str]:
    headers = {"Accept": "application/json, text/plain;q=0.9, */*;q=0.8"}
    if api_key:
        headers["Authorization"] = f"Bearer {api_key}"
    return headers


def _http_get_text(url: str, api_key: str | None = None) -> tuple[str, str]:
    request = urllib.request.Request(url, headers=_headers(api_key))
    try:
        with urllib.request.urlopen(request, timeout=HTTP_TIMEOUT_SECONDS) as response:
            return response.read().decode("utf-8", errors="replace"), ""
    except (urllib.error.URLError, TimeoutError, OSError) as exc:
        return "", str(exc)


def _http_get_json(url: str, api_key: str | None = None) -> tuple[dict, str]:
    text, error = _http_get_text(url, api_key)
    if error:
        return {}, error
    try:
        return json.loads(text), ""
    except json.JSONDecodeError as exc:
        return {}, f"invalid JSON from {url}: {exc}"


def _decode_label_value(value: str) -> str:
    return value.replace(r"\"", '"').replace(r"\\", "\\").replace(r"\n", "\n")


def _parse_labels(raw_labels: str | None) -> tuple[tuple[str, str], ...]:
    if not raw_labels:
        return ()
    labels = [(match.group(1), _decode_label_value(match.group(2))) for match in _LABEL_RE.finditer(raw_labels)]
    return tuple(sorted(labels))


def parse_prometheus_metrics(text: str) -> list[PrometheusSample]:
    samples: list[PrometheusSample] = []
    for line in text.splitlines():
        line = line.strip()
        if not line or line.startswith("#"):
            continue
        match = _METRIC_RE.match(line)
        if not match:
            continue
        try:
            value = float(match.group(3))
        except ValueError:
            continue
        samples.append(
            PrometheusSample(
                name=match.group(1),
                labels=_parse_labels(match.group(2)),
                value=value,
            )
        )
    return samples


def fetch_sglang_metrics_snapshot(base_url: str, api_key: str | None = None) -> SGLangMetricsSnapshot:
    endpoint = sglang_metrics_endpoint(base_url)
    text, error = _http_get_text(endpoint, api_key)
    if error:
        return SGLangMetricsSnapshot(endpoint=endpoint, samples=[], error=error)
    return SGLangMetricsSnapshot(endpoint=endpoint, samples=parse_prometheus_metrics(text))


def fetch_sglang_version() -> str:
    for package_name in ("sglang-kt", "sglang_kt", "sglang"):
        try:
            return importlib.metadata.version(package_name)
        except importlib.metadata.PackageNotFoundError:
            pass

    try:
        from sglang.version import __version__

        return str(__version__)
    except Exception:
        pass

    try:
        import sglang

        version = getattr(sglang, "__version__", None)
        if version:
            return str(version)
    except Exception:
        pass

    return "N/A"


def fetch_sglang_model_metadata(base_url: str, api_key: str | None = None) -> SGLangModelMetadata:
    models_url = f"{base_url.rstrip('/')}/models"
    model_info_url = f"{sglang_root_url(base_url)}/model_info"

    errors = []
    served_models: list[str] = []
    max_model_len = None
    model_path = ""
    model_type = ""
    architectures = None

    models_json, error = _http_get_json(models_url, api_key)
    if error:
        errors.append(error)
    else:
        for model in models_json.get("data", []):
            model_id = model.get("id")
            if model_id:
                served_models.append(str(model_id))
            if max_model_len is None and model.get("max_model_len") is not None:
                try:
                    max_model_len = int(model["max_model_len"])
                except (TypeError, ValueError):
                    pass

    info_json, error = _http_get_json(model_info_url, api_key)
    if error:
        errors.append(error)
    else:
        model_path = str(info_json.get("model_path") or "")
        model_type = str(info_json.get("model_type") or "")
        raw_architectures = info_json.get("architectures")
        if isinstance(raw_architectures, list):
            architectures = [str(item) for item in raw_architectures]

    return SGLangModelMetadata(
        served_models=served_models,
        sglang_version=fetch_sglang_version(),
        max_model_len=max_model_len,
        model_path=model_path,
        model_type=model_type,
        architectures=architectures,
        error="; ".join(errors),
    )


def _percentile_from_sorted(values: list[float], percentile: float) -> float | None:
    if not values:
        return None
    idx = int(percentile * len(values))
    idx = min(idx, len(values) - 1)
    return values[idx]


def _batch_stats(values: list[float]) -> BatchThroughputStats:
    if not values:
        return BatchThroughputStats()
    sorted_values = sorted(values)
    return BatchThroughputStats(
        count=len(values),
        mean=statistics.mean(values),
        median=statistics.median(values),
        p95=_percentile_from_sorted(sorted_values, 0.95),
        max=max(values),
    )


def parse_sglang_batch_throughput_text(text: str) -> tuple[BatchThroughputStats, BatchThroughputStats]:
    prefill_values = [float(match.group(1)) for match in _PREFILL_BATCH_RE.finditer(text)]
    decode_values = [float(match.group(1)) for match in _DECODE_BATCH_RE.finditer(text)]
    return _batch_stats(prefill_values), _batch_stats(decode_values)


def parse_sglang_batch_throughput_log(log_path: str | Path) -> tuple[BatchThroughputStats, BatchThroughputStats]:
    try:
        text = Path(log_path).read_text(errors="replace")
    except OSError:
        return BatchThroughputStats(), BatchThroughputStats()
    return parse_sglang_batch_throughput_text(text)


class SGLangBatchMetricsCollector:
    def __init__(self, base_url: str):
        self.base_url = base_url
        self.process = SGLangProcessInfo()
        self._stop = threading.Event()
        self._threads: list[threading.Thread] = []
        self._lock = threading.Lock()
        self._chunks: list[str] = []
        self._errors: list[str] = []
        self._status = "not started"

    def start(self) -> None:
        self.process = identify_sglang_process(self.base_url)
        source_paths = [Path(path) for path in self.process.source_paths]
        if not source_paths:
            self._status = "no readable SGLang log source found; batch stats unavailable"
            return

        self._status = "reading existing SGLang log source(s)"
        for source_path in source_paths:
            thread = threading.Thread(target=self._tail_source, args=(source_path,), daemon=True)
            thread.start()
            self._threads.append(thread)

    @property
    def has_log_source(self) -> bool:
        return bool(self.process.source_paths)

    def stop(self) -> SGLangBatchThroughputReport:
        self._stop.set()
        for thread in self._threads:
            thread.join(timeout=2)

        with self._lock:
            text = "".join(self._chunks)
            errors = tuple(self._errors)
        prefill_stats, decode_stats = parse_sglang_batch_throughput_text(text)
        status = self._status
        if errors:
            status = f"{status}; {'; '.join(errors)}"
        return SGLangBatchThroughputReport(
            process=self.process,
            prefill_input_tokens_per_sec=prefill_stats,
            decode_generation_tokens_per_sec=decode_stats,
            status=status,
        )

    def _tail_source(self, source_path: Path) -> None:
        try:
            with source_path.open("r", encoding="utf-8", errors="replace") as source:
                source.seek(0, os.SEEK_END)
                while not self._stop.is_set():
                    chunk = source.read()
                    if chunk:
                        self._append_chunk(chunk)
                    else:
                        time.sleep(0.2)
                chunk = source.read()
                if chunk:
                    self._append_chunk(chunk)
        except OSError as exc:
            with self._lock:
                self._errors.append(f"unable to read SGLang source log {source_path}: {exc}")

    def _append_chunk(self, text: str) -> None:
        with self._lock:
            self._chunks.append(text)


def prompt_continue_without_sglang_logs(process: SGLangProcessInfo) -> bool:
    print()
    print("WARNING: SGLang is not outputting to any readable log source.")
    print("Batch prefill/decode throughput will be reported as N/A.")
    if process.status:
        print(f"Process status: {process.status}")
    if process.pid is not None:
        print(f"Process pid: {process.pid}")

    while True:
        try:
            answer = input("Continue benchmark anyway? [y/N]: ").strip().lower()
        except EOFError:
            print("No response available; aborting benchmark.")
            return False
        if answer in {"y", "yes"}:
            return True
        if answer in {"n", "no"}:
            return False
        print("Unknown input. Please answer 'y' for yes or 'n' for no.")


def sglang_display_model_name(metadata: SGLangModelMetadata, fallback: str) -> str:
    path = metadata.model_path.rstrip("/")
    for part in reversed(path.split("/")):
        if part.startswith("models--"):
            pieces = part.split("--")
            if pieces:
                return pieces[-1]

    if path:
        last_part = path.rsplit("/", 1)[-1]
        if last_part and not re.fullmatch(r"[0-9a-f]{20,}", last_part):
            return last_part

    if metadata.served_models:
        return metadata.served_models[0]
    return fallback


def _labels_dict(sample: PrometheusSample) -> dict[str, str]:
    return dict(sample.labels)


def _sample_matches(
    sample: PrometheusSample,
    model_name: str | None = None,
    required_labels: dict[str, str] | None = None,
) -> bool:
    labels = _labels_dict(sample)
    if model_name is not None and labels.get("model_name") not in (None, model_name):
        return False
    if required_labels:
        for key, expected in required_labels.items():
            if labels.get(key) != expected:
                return False
    return True


def _sample_key(sample: PrometheusSample) -> tuple[str, tuple[tuple[str, str], ...]]:
    return sample.name, sample.labels


def _sample_index(snapshot: SGLangMetricsSnapshot) -> dict[tuple[str, tuple[tuple[str, str], ...]], float]:
    return {_sample_key(sample): sample.value for sample in snapshot.samples}


def _counter_delta(
    start: SGLangMetricsSnapshot,
    end: SGLangMetricsSnapshot,
    name: str,
    model_name: str | None = None,
    required_labels: dict[str, str] | None = None,
) -> float:
    start_index = _sample_index(start)
    total = 0.0
    for sample in end.samples:
        if sample.name != name or not _sample_matches(sample, model_name, required_labels):
            continue
        delta = sample.value - start_index.get(_sample_key(sample), 0.0)
        total += max(0.0, delta)
    return total


def _gauge_value(
    snapshot: SGLangMetricsSnapshot,
    name: str,
    model_name: str | None = None,
    required_labels: dict[str, str] | None = None,
) -> float | None:
    values = [
        sample.value
        for sample in snapshot.samples
        if sample.name == name and _sample_matches(sample, model_name, required_labels)
    ]
    if not values:
        return None
    return max(values)


def _parse_bucket_bound(value: str) -> float:
    if value == "+Inf":
        return float("inf")
    return float(value)


def _histogram_groups(
    start: SGLangMetricsSnapshot,
    end: SGLangMetricsSnapshot,
    base_name: str,
    model_name: str | None = None,
    required_labels: dict[str, str] | None = None,
) -> dict[tuple[tuple[str, str], ...], dict[str, object]]:
    start_index = _sample_index(start)
    groups: dict[tuple[tuple[str, str], ...], dict[str, object]] = {}

    for sample in end.samples:
        if not sample.name.startswith(f"{base_name}_") or not _sample_matches(sample, model_name, required_labels):
            continue
        labels = _labels_dict(sample)
        group_labels = tuple(sorted((key, value) for key, value in labels.items() if key != "le"))
        group = groups.setdefault(group_labels, {"sum": 0.0, "count": 0.0, "buckets": {}})
        delta = sample.value - start_index.get(_sample_key(sample), 0.0)
        delta = max(0.0, delta)

        if sample.name == f"{base_name}_sum":
            group["sum"] = delta
        elif sample.name == f"{base_name}_count":
            group["count"] = delta
        elif sample.name == f"{base_name}_bucket" and "le" in labels:
            buckets = group["buckets"]
            assert isinstance(buckets, dict)
            buckets[_parse_bucket_bound(labels["le"])] = delta

    return groups


def _quantile_from_buckets(buckets: dict[float, float], count: float, quantile: float) -> float | None:
    if count <= 0:
        return None
    target = count * quantile
    for upper_bound, bucket_count in sorted(buckets.items(), key=lambda item: item[0]):
        if bucket_count >= target:
            if upper_bound == float("inf"):
                return None
            return upper_bound
    return None


def _group_to_summary(group: dict[str, object]) -> HistogramSummary:
    count = float(group.get("count") or 0.0)
    total = float(group.get("sum") or 0.0)
    buckets = group.get("buckets") or {}
    assert isinstance(buckets, dict)
    mean = total / count if count > 0 else 0.0
    return HistogramSummary(
        count=count,
        total=total,
        mean=mean,
        p95=_quantile_from_buckets(buckets, count, 0.95),
        p99=_quantile_from_buckets(buckets, count, 0.99),
    )


def _merged_histogram_summary(
    start: SGLangMetricsSnapshot,
    end: SGLangMetricsSnapshot,
    base_name: str,
    model_name: str | None = None,
    required_labels: dict[str, str] | None = None,
) -> HistogramSummary:
    groups = _histogram_groups(start, end, base_name, model_name, required_labels)
    merged = {"sum": 0.0, "count": 0.0, "buckets": {}}
    for group in groups.values():
        merged["sum"] += float(group.get("sum") or 0.0)
        merged["count"] += float(group.get("count") or 0.0)
        buckets = group.get("buckets") or {}
        assert isinstance(buckets, dict)
        merged_buckets = merged["buckets"]
        assert isinstance(merged_buckets, dict)
        for upper_bound, count in buckets.items():
            merged_buckets[upper_bound] = merged_buckets.get(upper_bound, 0.0) + count
    return _group_to_summary(merged)


def _average_histogram_summary_by_label(
    start: SGLangMetricsSnapshot,
    end: SGLangMetricsSnapshot,
    base_name: str,
    average_label: str,
    model_name: str | None = None,
    required_labels: dict[str, str] | None = None,
) -> HistogramSummary:
    groups = _histogram_groups(start, end, base_name, model_name, required_labels)
    summaries = []
    seen = set()
    for labels, group in groups.items():
        label_dict = dict(labels)
        if average_label not in label_dict:
            continue
        label_value = label_dict[average_label]
        if label_value in seen:
            continue
        seen.add(label_value)
        summary = _group_to_summary(group)
        if summary.count > 0:
            summaries.append(summary)

    if not summaries:
        return HistogramSummary()

    p95_values = [summary.p95 for summary in summaries if summary.p95 is not None]
    p99_values = [summary.p99 for summary in summaries if summary.p99 is not None]
    return HistogramSummary(
        count=statistics.mean(summary.count for summary in summaries),
        total=statistics.mean(summary.total for summary in summaries),
        mean=statistics.mean(summary.mean for summary in summaries),
        p95=statistics.mean(p95_values) if p95_values else None,
        p99=statistics.mean(p99_values) if p99_values else None,
    )


def _metric_model_names(snapshot: SGLangMetricsSnapshot) -> list[str]:
    names = sorted(
        {
            labels["model_name"]
            for sample in snapshot.samples
            for labels in [_labels_dict(sample)]
            if labels.get("model_name")
        }
    )
    return names


def _select_metrics_model(
    benchmark_model: str,
    metadata: SGLangModelMetadata,
    start: SGLangMetricsSnapshot,
    end: SGLangMetricsSnapshot,
) -> str | None:
    metric_names = set(_metric_model_names(start)) | set(_metric_model_names(end))
    if benchmark_model in metric_names:
        return benchmark_model
    for model in metadata.served_models:
        if model in metric_names:
            return model
    if len(metric_names) == 1:
        return next(iter(metric_names))
    return benchmark_model or None


def calculate_sglang_stage_throughput(
    benchmark_model: str,
    metadata: SGLangModelMetadata,
    start: SGLangMetricsSnapshot,
    end: SGLangMetricsSnapshot,
) -> SGLangStageThroughput:
    metrics_model = _select_metrics_model(benchmark_model, metadata, start, end)
    prefill = _average_histogram_summary_by_label(
        start,
        end,
        "sglang:per_stage_req_latency_seconds",
        "tp_rank",
        metrics_model,
        {"stage": "prefill_forward"},
    )
    decode_itl = _merged_histogram_summary(start, end, "sglang:inter_token_latency_seconds", metrics_model)

    prompt_tokens = _counter_delta(start, end, "sglang:prompt_tokens_total", metrics_model)
    prefill_tps = prompt_tokens / prefill.total if prefill.total > 0 else None
    decode_tps = decode_itl.count / decode_itl.total if decode_itl.total > 0 else None
    return SGLangStageThroughput(
        prefill_tokens_per_sec=prefill_tps,
        decode_tokens_per_sec=decode_tps,
    )


def _fmt_int(value: float | int | None) -> str:
    if value is None:
        return "N/A"
    return f"{int(round(value)):,}"


def _fmt_float(value: float | None, digits: int = 2) -> str:
    if value is None:
        return "N/A"
    return f"{value:.{digits}f}"


def _fmt_ms(value: float | None) -> str:
    if value is None or value <= 0:
        return "N/A"
    return f"{value * 1000:.0f}ms"


def _fmt_ms_bound(value: float | None) -> str:
    formatted = _fmt_ms(value)
    return formatted if formatted == "N/A" else f"<={formatted}"


def _fmt_seconds(value: float | None) -> str:
    if value is None or value <= 0:
        return "N/A"
    return f"{value:.2f}s"


def _fmt_seconds_bound(value: float | None) -> str:
    formatted = _fmt_seconds(value)
    return formatted if formatted == "N/A" else f"<={formatted}"


def _fmt_tps(value: float | None) -> str:
    if value is None or value <= 0:
        return "N/A"
    return f"{value:.2f}"


def _fmt_percent(value: float | None) -> str:
    if value is None:
        return "N/A"
    return f"{value * 100:.2f}%"


def _histogram_enabled(summary: HistogramSummary) -> str:
    if summary.count <= 0:
        return "not observed"
    return f"enabled ({_fmt_int(summary.count)} samples)"


def _fmt_batch_stat(value: float | None) -> str:
    if value is None:
        return "N/A"
    return f"{value:.2f}"


def print_sglang_batch_throughput_report(report: SGLangBatchThroughputReport | None) -> None:
    print("\n" + "=" * 60)
    print()
    print("SGLang scheduler batch log:")
    if report is None:
        print("  Status:                        unavailable")
        return

    print(f"  Status:                        {report.status}")
    print(f"  Process status:                {report.process.status}")
    print(f"  Process pid:                   {_fmt_int(report.process.pid)}")
    if report.process.command:
        print(f"  Process command:               {report.process.command}")
    if report.process.source_paths:
        print(f"  Source log(s):                 {', '.join(report.process.source_paths)}")
    else:
        print("  Source log(s):                 N/A")

    def print_stats(label: str, stats: BatchThroughputStats) -> None:
        print(f"\n  {label}:")
        print(f"    Samples:                     {_fmt_int(stats.count)}")
        print(f"    Mean tok/s:                  {_fmt_batch_stat(stats.mean)}")
        print(f"    Median tok/s:                {_fmt_batch_stat(stats.median)}")
        print(f"    P95 tok/s:                   {_fmt_batch_stat(stats.p95)}")
        print(f"    Max tok/s:                   {_fmt_batch_stat(stats.max)}")

    print_stats("Prefill batch input throughput", report.prefill_input_tokens_per_sec)
    print_stats("Decode batch generation throughput", report.decode_generation_tokens_per_sec)


def print_sglang_metrics_report(
    base_url: str,
    api_key: str | None,
    benchmark_model: str,
    start: SGLangMetricsSnapshot,
    end: SGLangMetricsSnapshot,
    metadata: SGLangModelMetadata | None = None,
) -> None:
    metadata = metadata or fetch_sglang_model_metadata(base_url, api_key)
    metrics_model = _select_metrics_model(benchmark_model, metadata, start, end)

    print("\n" + "=" * 60)
    print()
    print("SGLang /metrics:")
    print(f"  SGLang Version:              {metadata.sglang_version}")
    print(f"  Metrics endpoint:              {end.endpoint}")

    if start.error or end.error:
        print(f"  Status:                        unavailable ({start.error or end.error})")
        return

    served_models = ", ".join(metadata.served_models) if metadata.served_models else "N/A"
    metric_labels = ", ".join(_metric_model_names(end)) or "N/A"
    architecture = ", ".join(metadata.architectures or []) or "N/A"

    print(f"  Model:                         {sglang_display_model_name(metadata, benchmark_model)}")
    print(f"  Served model id:               {served_models}")
    print(f"  Metrics model label:           {metrics_model or metric_labels}")
    print(f"  Model path:                    {metadata.model_path or 'N/A'}")
    print(f"  Model type:                    {metadata.model_type or 'N/A'}")
    print(f"  Architecture:                  {architecture}")
    print(f"  Max model length:              {_fmt_int(metadata.max_model_len)}")

    ttft = _merged_histogram_summary(start, end, "sglang:time_to_first_token_seconds", metrics_model)
    e2e = _merged_histogram_summary(start, end, "sglang:e2e_request_latency_seconds", metrics_model)
    queue = _average_histogram_summary_by_label(start, end, "sglang:queue_time_seconds", "tp_rank", metrics_model)
    prefill = _average_histogram_summary_by_label(
        start,
        end,
        "sglang:per_stage_req_latency_seconds",
        "tp_rank",
        metrics_model,
        {"stage": "prefill_forward"},
    )
    decode_itl = _merged_histogram_summary(start, end, "sglang:inter_token_latency_seconds", metrics_model)
    prompt_hist = _merged_histogram_summary(start, end, "sglang:prompt_tokens_histogram", metrics_model)
    generation_hist = _merged_histogram_summary(start, end, "sglang:generation_tokens_histogram", metrics_model)

    prompt_tokens = _counter_delta(start, end, "sglang:prompt_tokens_total", metrics_model)
    generation_tokens = _counter_delta(start, end, "sglang:generation_tokens_total", metrics_model)
    prefill_tps = prompt_tokens / prefill.total if prefill.total > 0 else None
    decode_tps = decode_itl.count / decode_itl.total if decode_itl.total > 0 else None

    print(f"  Samples observed:              {_fmt_int(ttft.count or e2e.count)}")

    print("\n  Queue time:")
    print(f"    Mean:                        {_fmt_ms(queue.mean)}")
    print(f"    P95:                         {_fmt_ms_bound(queue.p95)}")
    print(f"    P99:                         {_fmt_ms_bound(queue.p99)}")

    print("\n  TTFT:")
    print(f"    Mean:                        {_fmt_ms(ttft.mean)}")
    print(f"    P95:                         {_fmt_ms_bound(ttft.p95)}")
    print(f"    P99:                         {_fmt_ms_bound(ttft.p99)}")

    print("\n  Prefill:")
    print(f"    Forward mean:                {_fmt_ms(prefill.mean)}")
    print(f"    Forward P95:                 {_fmt_ms_bound(prefill.p95)}")
    print(f"    Prompt tokens:               {_fmt_int(prompt_tokens)}")
    print(f"    Prompt tokens/sec approx:    {_fmt_tps(prefill_tps)}")
    print(f"    Prompt token histogram:      {_histogram_enabled(prompt_hist)}")

    print("\n  Decode:")
    print(f"    Inter-token latency mean:    {_fmt_ms(decode_itl.mean)}")
    print(f"    Inter-token latency P95:     {_fmt_ms_bound(decode_itl.p95)}")
    print(f"    Generation tokens:           {_fmt_int(generation_tokens)}")
    print(f"    Decode tokens/sec approx:    {_fmt_tps(decode_tps)}")
    print(f"    Generation token histogram:  {_histogram_enabled(generation_hist)}")

    print("\n  End-to-end request latency:")
    print(f"    Mean:                        {_fmt_seconds(e2e.mean)}")
    print(f"    P95:                         {_fmt_seconds_bound(e2e.p95)}")
    print(f"    P99:                         {_fmt_seconds_bound(e2e.p99)}")

    print("\n  Scheduler / memory final scrape:")
    print(f"    Running requests:            {_fmt_int(_gauge_value(end, 'sglang:num_running_reqs', metrics_model))}")
    print(f"    Queued requests:             {_fmt_int(_gauge_value(end, 'sglang:num_queue_reqs', metrics_model))}")
    print(f"    Paused requests:             {_fmt_int(_gauge_value(end, 'sglang:num_paused_reqs', metrics_model))}")
    print(f"    Retracted requests:          {_fmt_int(_gauge_value(end, 'sglang:num_retracted_reqs', metrics_model))}")
    print(f"    Token usage:                 {_fmt_percent(_gauge_value(end, 'sglang:token_usage', metrics_model))}")
    print(f"    Used tokens:                 {_fmt_int(_gauge_value(end, 'sglang:num_used_tokens', metrics_model))}")
    print(f"    Max total tokens:            {_fmt_int(_gauge_value(end, 'sglang:max_total_num_tokens', metrics_model))}")
