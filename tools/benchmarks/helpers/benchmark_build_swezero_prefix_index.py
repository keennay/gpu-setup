import argparse
import json
import os
import shutil
import sys
import time
from concurrent.futures import ProcessPoolExecutor, as_completed
from pathlib import Path

import pyarrow as pa
import pyarrow.parquet as pq


DEFAULT_DATASET_REPO_ID = "AlienKevin/SWE-ZERO-12M-trajectories"
DEFAULT_DATASET_CACHE_DIR = "datasets--AlienKevin--SWE-ZERO-12M-trajectories"
DEFAULT_PREFIX_INDEX_CACHE_DIR = f"{DEFAULT_DATASET_CACHE_DIR}-prefix-index"
INPUT_BAND_CHOICES = ("1k", "2k", "4k", "8k", "12k", "16k", "20k")
INPUT_BAND_RANGES = {
    "1k": (1000, 2000),
    "2k": (2000, 3000),
    "4k": (4000, 5000),
    "8k": (8000, 9000),
    "12k": (12000, 13000),
    "16k": (16000, 17000),
    "20k": (20000, 21000),
}
INPUT_BAND_HELP = "Select between " + ", ".join(INPUT_BAND_CHOICES)
FULL_PREFIX_SENTINEL = 65535
VALID_ROLES = {"system", "user", "assistant"}
DEFAULT_CONTENT = "Continue the software-engineering task."
DEFAULT_RENDER_LEN = len(DEFAULT_CONTENT) + 2 * len("user") + 7

INDEX_SCHEMA = pa.schema(
    [
        ("approx_tokens", pa.uint16()),
        ("shard_id", pa.uint16()),
        ("row_in_shard", pa.uint32()),
        ("prefix_end_index", pa.uint16()),
    ]
)


def parse_args():
    parser = argparse.ArgumentParser(
        description="Build a compact SWE-ZERO prefix input-band index for benchmark_swezero.py",
        formatter_class=argparse.ArgumentDefaultsHelpFormatter,
    )
    parser.add_argument(
        "--dataset-path",
        default=None,
        help=(
            "SWE-ZERO dataset root override. Default resolves "
            f"HF_HUB_CACHE/{DEFAULT_DATASET_CACHE_DIR}/snapshots/<current revision>."
        ),
    )
    parser.add_argument(
        "--index-path",
        default=None,
        help=f"Output index path override (default: HF_HUB_CACHE/{DEFAULT_PREFIX_INDEX_CACHE_DIR})",
    )
    parser.add_argument(
        "--bands",
        nargs="+",
        default=list(INPUT_BAND_CHOICES),
        help=f"Input bands to index. {INPUT_BAND_HELP}.",
    )
    parser.add_argument("--workers", type=int, default=min(16, max(1, (os.cpu_count() or 2) // 2)))
    parser.add_argument("--batch-size", type=int, default=2048, help="Parquet read batch size")
    parser.add_argument("--overwrite", action="store_true", help="Replace an existing index path")
    parser.add_argument("--max-shards", type=int, default=None, help="Debug/testing only: index only the first N shards")
    args = parser.parse_args()

    hf_hub_cache, hub_cache_error = resolve_required_hf_hub_cache()
    dataset_path = Path(args.dataset_path).expanduser() if args.dataset_path else None
    if args.index_path is None and hf_hub_cache is not None:
        args.index_path = str(hf_hub_cache / DEFAULT_PREFIX_INDEX_CACHE_DIR)

    errors = []
    if hub_cache_error:
        errors.append(
            "HF_HUB_CACHE is not set. Set HF_HUB_CACHE so the prefix index can be built next to the Hub dataset cache."
        )
    elif dataset_path is None:
        dataset_path, lookup_notes = resolve_cached_swezero_dataset(hf_hub_cache)
        if dataset_path is None:
            errors.append(
                "Unable to find default SWE-ZERO dataset in the Hugging Face Hub cache. "
                f"Expected repo cache for {DEFAULT_DATASET_REPO_ID} under HF_HUB_CACHE. "
                "Download it with: hf download AlienKevin/SWE-ZERO-12M-trajectories --repo-type dataset. "
                + " ".join(lookup_notes)
            )
        else:
            args.dataset_path = str(dataset_path)
    if args.index_path is None and hf_hub_cache is not None:
        errors.append(f"Could not resolve --index-path. Set HF_HUB_CACHE or pass --index-path.")

    if dataset_path is not None and not dataset_path.exists():
        errors.append(f"--dataset-path does not exist: {dataset_path}")
    elif dataset_path is not None and not is_swezero_dataset_root(dataset_path):
        errors.append(f"--dataset-path must contain a data/ directory with Parquet shards: {dataset_path}")
    elif dataset_path is not None:
        args.dataset_path = str(dataset_path)
    if args.workers < 1:
        errors.append("--workers must be >= 1")
    if args.batch_size < 1:
        errors.append("--batch-size must be >= 1")
    if args.max_shards is not None and args.max_shards < 1:
        errors.append("--max-shards must be >= 1")

    normalized_bands = []
    for band in args.bands:
        band = band.strip().lower()
        if band not in INPUT_BAND_RANGES:
            errors.append(f"Invalid band: {band}. {INPUT_BAND_HELP}.")
        elif band not in normalized_bands:
            normalized_bands.append(band)
    args.bands = normalized_bands

    index_path = Path(args.index_path).expanduser() if args.index_path is not None else None
    if index_path is not None and index_path.exists() and not args.overwrite:
        errors.append(f"--index-path already exists: {index_path}. Pass --overwrite to replace it.")
    elif index_path is not None:
        args.index_path = str(index_path.expanduser())

    if errors:
        print("ERROR: Invalid arguments:")
        for error in errors:
            print(f"  - {error}")
        sys.exit(1)

    return args


def resolve_required_hf_hub_cache() -> tuple[Path | None, str]:
    value = os.environ.get("HF_HUB_CACHE")
    if not value:
        return None, "HF_HUB_CACHE is not set"
    return Path(value).expanduser(), ""


def is_swezero_dataset_root(path: Path) -> bool:
    data_dir = path / "data"
    return data_dir.is_dir() and any(data_dir.glob("*.parquet"))


def resolve_cached_swezero_dataset(hf_hub_cache: Path) -> tuple[Path | None, list[str]]:
    repo_cache = hf_hub_cache / DEFAULT_DATASET_CACHE_DIR
    snapshots_dir = repo_cache / "snapshots"
    looked = [
        f"HF_HUB_CACHE resolved to: {hf_hub_cache}",
        f"dataset cache repo: {repo_cache}",
    ]

    if not snapshots_dir.is_dir():
        looked.append(f"snapshots directory not found: {snapshots_dir}")
        return None, looked

    refs_main = repo_cache / "refs" / "main"
    if refs_main.is_file():
        revision = refs_main.read_text().strip()
        if revision:
            snapshot = snapshots_dir / revision
            looked.append(f"refs/main snapshot: {snapshot}")
            if is_swezero_dataset_root(snapshot):
                return snapshot, looked

    snapshots = sorted(
        [path for path in snapshots_dir.iterdir() if path.is_dir()],
        key=lambda path: path.stat().st_mtime,
        reverse=True,
    )
    for snapshot in snapshots:
        looked.append(f"snapshot candidate: {snapshot}")
        if is_swezero_dataset_root(snapshot):
            return snapshot, looked

    looked.append(f"no snapshot containing data/*.parquet found under: {snapshots_dir}")
    return None, looked


def rendered_len_from_parts(total_block_len: int, block_count: int) -> int:
    if block_count <= 0:
        return DEFAULT_RENDER_LEN
    return total_block_len + 2 * (block_count - 1)


def token_estimate(rendered_len: int) -> int:
    return max(1, rendered_len // 4)


def prefix_user_indices(messages: list[dict]) -> list[int]:
    first = []
    saw_assistant_before = False
    for idx, message in enumerate(messages):
        role = message.get("role") if isinstance(message, dict) else None
        if role == "user" and idx >= 3 and saw_assistant_before:
            first.append(idx)
        if role == "assistant":
            saw_assistant_before = True
    if first:
        return first
    return [
        idx
        for idx, message in enumerate(messages)
        if isinstance(message, dict) and message.get("role") == "user" and idx >= 1
    ]


def matching_band(tokens: int, bands: list[str]) -> str | None:
    for band in bands:
        lower, upper = INPUT_BAND_RANGES[band]
        if lower <= tokens < upper:
            return band
    return None


def empty_columns() -> dict[str, list[int]]:
    return {
        "approx_tokens": [],
        "shard_id": [],
        "row_in_shard": [],
        "prefix_end_index": [],
    }


def scan_shard(shard_info: tuple[int, str], bands: list[str], batch_size: int):
    shard_id, shard_str = shard_info
    shard = Path(shard_str)
    by_band = {band: empty_columns() for band in bands}
    rows = 0
    candidates = 0
    parquet_file = pq.ParquetFile(shard)
    row_offset = 0

    for batch in parquet_file.iter_batches(columns=["messages"], batch_size=batch_size):
        messages_col = batch.column(0).to_pylist()
        for local_idx, messages in enumerate(messages_col):
            row_in_shard = row_offset + local_idx
            if not messages:
                messages = []

            cumulative = []
            total_blocks_len = 0
            block_count = 0
            last_normalized_role = None
            for message in messages:
                if not isinstance(message, dict):
                    cumulative.append((total_blocks_len, block_count, last_normalized_role))
                    continue

                role = message.get("role") or "user"
                if role not in VALID_ROLES:
                    role = "user"
                content = message.get("content") or ""
                if content:
                    content = str(content)
                    total_blocks_len += len(content) + 2 * len(role) + 7
                    block_count += 1
                    last_normalized_role = role
                cumulative.append((total_blocks_len, block_count, last_normalized_role))

            user_indices = prefix_user_indices(messages)
            if not user_indices:
                prefix_points = []
                if last_normalized_role == "user":
                    prefix_points.append((FULL_PREFIX_SENTINEL, total_blocks_len, block_count))
            else:
                prefix_points = []
                for end_idx in user_indices:
                    total_len, count, last_role = cumulative[end_idx]
                    if last_role == "user":
                        prefix_points.append((end_idx, total_len, count))

            for prefix_end_index, total_len, count in prefix_points:
                tokens = token_estimate(rendered_len_from_parts(total_len, count))
                band = matching_band(tokens, bands)
                if band is None:
                    continue
                columns = by_band[band]
                columns["approx_tokens"].append(tokens)
                columns["shard_id"].append(shard_id)
                columns["row_in_shard"].append(row_in_shard)
                columns["prefix_end_index"].append(prefix_end_index)
                candidates += 1

            rows += 1
        row_offset += batch.num_rows

    counts = {band: len(columns["approx_tokens"]) for band, columns in by_band.items()}
    return shard_id, rows, candidates, counts, by_band


def write_table(writer: pq.ParquetWriter, columns: dict[str, list[int]]):
    table = pa.Table.from_pydict(columns, schema=INDEX_SCHEMA)
    writer.write_table(table)


def build_index(args):
    dataset_path = Path(args.dataset_path)
    index_path = Path(args.index_path)
    temp_path = index_path.with_name(f"{index_path.name}.tmp-{int(time.time())}")
    shards = sorted((dataset_path / "data").glob("*.parquet"))
    if args.max_shards is not None:
        shards = shards[: args.max_shards]
    shard_infos = [(idx, str(path)) for idx, path in enumerate(shards)]

    if temp_path.exists():
        shutil.rmtree(temp_path)
    temp_path.mkdir(parents=True)

    writers: dict[str, pq.ParquetWriter] = {}
    counts = {band: 0 for band in args.bands}
    rows_total = 0
    candidates_total = 0
    start = time.time()

    try:
        for band in args.bands:
            band_dir = temp_path / f"band={band}"
            band_dir.mkdir(parents=True)
            writers[band] = pq.ParquetWriter(
                band_dir / "part-00000.parquet",
                INDEX_SCHEMA,
                compression="zstd",
                use_dictionary=False,
            )

        print(
            f"Building prefix index at {index_path} from {dataset_path} "
            f"({len(shards)} shards, workers={args.workers}, bands={', '.join(args.bands)})",
            flush=True,
        )

        with ProcessPoolExecutor(max_workers=args.workers) as pool:
            futures = [
                pool.submit(scan_shard, shard_info, args.bands, args.batch_size)
                for shard_info in shard_infos
            ]
            pending = {}
            next_shard_to_write = 0
            for done, future in enumerate(as_completed(futures), start=1):
                shard_id, rows, candidates, shard_counts, by_band = future.result()
                pending[shard_id] = (rows, candidates, shard_counts, by_band)

                while next_shard_to_write in pending:
                    rows, candidates, shard_counts, by_band = pending.pop(next_shard_to_write)
                    rows_total += rows
                    candidates_total += candidates
                    for band, columns in by_band.items():
                        count = shard_counts[band]
                        if count:
                            write_table(writers[band], columns)
                            counts[band] += count
                    next_shard_to_write += 1

                if done % 50 == 0 or done == len(futures):
                    elapsed = time.time() - start
                    rate = rows_total / elapsed if elapsed > 0 else 0
                    print(
                        f"progress shards={done}/{len(futures)} rows={rows_total} "
                        f"candidates={candidates_total} rate={rate:.0f} rows/s elapsed={elapsed:.1f}s",
                        flush=True,
                    )
    finally:
        for writer in writers.values():
            writer.close()

    shard_table = pa.Table.from_pydict(
        {
            "shard_id": list(range(len(shards))),
            "shard_name": [path.name for path in shards],
        },
        schema=pa.schema([("shard_id", pa.uint16()), ("shard_name", pa.string())]),
    )
    pq.write_table(shard_table, temp_path / "shard_map.parquet", compression="zstd")

    metadata = {
        "index_type": "swezero_prefix_input_bands",
        "version": 1,
        "dataset_path": str(dataset_path),
        "data_dir": str(dataset_path / "data"),
        "complete": args.max_shards is None,
        "token_estimate": "max(1, len(rendered_prompt) // 4)",
        "prefix_mode": "eligible user-ending prefixes from benchmark_swezero.py",
        "full_prefix_sentinel": FULL_PREFIX_SENTINEL,
        "bands": {
            band: {
                "lower_inclusive": INPUT_BAND_RANGES[band][0],
                "upper_exclusive": INPUT_BAND_RANGES[band][1],
                "count": counts[band],
            }
            for band in args.bands
        },
        "shards": [path.name for path in shards],
        "rows_scanned": rows_total,
        "candidates_indexed": candidates_total,
        "created_at_unix": time.time(),
    }
    (temp_path / "metadata.json").write_text(json.dumps(metadata, indent=2, sort_keys=True) + "\n")

    if index_path.exists():
        shutil.rmtree(index_path)
    temp_path.rename(index_path)

    elapsed = time.time() - start
    print("\nRESULTS")
    print(f"index_path={index_path}")
    print(f"rows_scanned={rows_total}")
    print(f"candidates_indexed={candidates_total}")
    for band in args.bands:
        lower, upper = INPUT_BAND_RANGES[band]
        print(f"{band} (>={lower} <{upper}): {counts[band]}")
    print(f"elapsed={elapsed:.1f}s")


def main():
    args = parse_args()
    build_index(args)


if __name__ == "__main__":
    main()
