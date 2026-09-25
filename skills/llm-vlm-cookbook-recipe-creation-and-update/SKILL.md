---
name: llm-vlm-cookbook-recipe-creation-and-update
description: "Creates or updates and behaviorally validates portable SGLang and vLLM LLM/VLM recipes at each model's maximum officially supported checkpoint context before promotion."
---

# SGLang & vLLM Recipe Creation and Update

Use this skill when creating, updating, porting, repairing, or validating an SGLang or vLLM recipe for an LLM or VLM in `recipes/<repo>` (where `<repo>` is the lowercase publisher/organization directory, e.g. `recipes/deepseek-ai/`, `recipes/qwen/`, `recipes/redhatai/`).

The `llm-vlm-cookbook-recipe-source` skill defines cookbook lookup, model-card/config inspection, engine source verification, version comparison, and reporting. This skill adds repository-specific implementation and runtime constraints. For repository field configuration, apply the explicit defaults and validated-configuration rules below rather than conflicting generic field guidance; continue authoritative source verification for new or changed model/engine settings.

Read that source skill before either operation. Use it to fill model-wide fields and verify architecture-specific choices, subject to the explicit existing-recipe context-reuse and sweep-only shortcuts below.

## Recipe directory naming

Every new publisher directory directly under `recipes/` MUST be lowercase. Derive `<repo>` by lowercasing the publisher parsed from the validated recipe's filename (for example, `${publisher,,}` in Bash), not from `MODEL_REPO`, which may name a different organization. Thus `vllm_Qwen_Qwen3.8-27B-FP8.sh` belongs in `recipes/qwen/`, and a `MiniMaxAI` launcher belongs in `recipes/minimaxai/`.

Reuse the existing lowercase directory when present; NEVER create a mixed-case duplicate. Create a new directory only at promotion, after the required validation succeeds. Lowercase only this one directory component, not the entire path: preserve recipe filenames, benchmark filenames, nested directory names, and exact Hugging Face model/draft repository IDs.

## Architecture configuration contract

The sole structural template for both SGLang and vLLM is [`template.sh`](template.sh), bundled beside this `SKILL.md`. Resolve it relative to the actual loaded skill file/resource location supplied by the coding CLI harness, not the caller's working directory or an assumed installation path. Skill installation locations are harness-dependent; never hard-code a workspace path, home-directory path, or repository-relative skill directory. Locate the target cookbook repository independently of the skill installation. New recipes MUST start from the adjacent template, not an existing launcher in `recipes/`. Existing recipes are expected to follow that template; their current values are update inputs, not an alternative structural template.

MUST read the current adjacent `template.sh` at the start of **every** creation or update and read it again before final structural validation/promotion. Derive the field set, field count/order, spacing, comments, architecture suffixes, block layout, and helper/call structure from that live file each time. It is the structural source of truth if it changes in the future; this skill's field descriptions and GPU examples are not a frozen copy of its schema. Never substitute a remembered layout, cached template, or existing recipe. If it changes during the task, reconcile the `/tmp` candidate and repeat affected validation before promotion; do not publish a stale layout or silently widen a sweep-only update.

The recipe configuration unit is one GPU architecture block, not a global context, tensor-parallel, or memory-utilization setting. Read the supported blocks and their order from the current `template.sh`. Use the vendor-neutral placeholder `<ARCH>` for the exact suffix defined by the live template and recognized by the helper, such as `SM90` for NVIDIA. It is not a literal recipe variable or a requirement that every vendor use SM notation. The field families below describe the settings handled by this workflow; they do not replace the live template's field set or order:

```text
BACKEND_ATTENTION_<ARCH>
BACKEND_FP8_GEMM_<ARCH>
BACKEND_FP4_GEMM_<ARCH>
BACKEND_MOE_RUNNER_<ARCH>
CONTEXT_LEN_VALUE_<ARCH>
GPU_MEM_UTIL_VALUE_<ARCH>
TENSOR_PARALLEL_SIZE_<ARCH>
```

Edit only the selected architecture block. For a new recipe, every architecture value defined by the current `template.sh` MUST initially be empty in `/tmp`, preserving its empty assignment style (`NAME=""` or `NAME=`). Do not seed them from an existing launcher or use `"0"` as a substitute for blank. Then configure only the selected block's applicable backends, maximum context, and tensor-parallel size. Leave its memory-utilization field blank until the measured sweep supplies candidates and the final value. Leave all other blocks blank. For an update, preserve every non-target architecture block byte-for-byte; do not reset or populate them.

Preserve the current `template.sh` exactly in structure: its environment fields, field order, spacing, blank lines, architecture blocks, and shared-helper call; no extra comments or script lines. Backend fields contain complete quoted flag/value strings, while context, memory utilization, and tensor-parallel fields contain scalar values in the template's style. Put CLI backend selectors represented by the template in their matching architecture fields, not `EXTRA_ARGS`. Validated environment-based GEMM selectors belong in `INFERENCE_ENV` and take precedence over competing CLI selectors for the same GEMM path.

The template is not entirely blank: it also contains fixed launcher plumbing. Preserve the template's `RECIPE_DIR` assignment verbatim in both temporary and promoted recipes; do not clear it or replace it with a literal directory. The helper `source` line MUST match the template in repository recipes. Its path may be adjusted only in the `/tmp` candidate so temporary validation can reach the existing repository helper; restore the exact template source line before promotion. The blank-initialization rule applies to architecture values, not these constants, and never authorizes changing the bundled template itself.

### Target architecture selection

1. An explicit GPU architecture or GPU model in the request selects the target. Resolve its vendor and actual architecture to the exact suffix supported by the template/helper. On NVIDIA, a bare `SM90` and “for H200s” both select `SM90`. If a supplied GPU name and architecture disagree, resolve the discrepancy rather than silently selecting one.
2. Without an explicit target, inspect the first GPU used by the shared helper, not the most capable GPU or a majority vote. Use the vendor's supported inventory tool and the helper's device-selection behavior. On NVIDIA, read `nvidia-smi --query-gpu=index,name,uuid,compute_cap --format=csv,noheader` and honor `CUDA_VISIBLE_DEVICES`: the current helper uses its first entry when set, otherwise the first enumerated GPU. For another vendor, inspect its supported helper/runtime selection mechanism rather than assuming CUDA tooling applies. The first-selected-GPU rule also applies to heterogeneous systems.
3. For NVIDIA only, normalize CUDA compute capability to the exact field suffix: `9.0` → `SM90`, `10.0` → `SM100`, `10.3` → `SM103`, `12.0` → `SM120`, `12.1` → `SM121`. Do not collapse all Blackwell GPUs into one block. For other vendors, use their documented architecture identifier and the template/helper's suffix mapping; do not convert it into an invented SM value.
4. Select available GPUs matching the target vendor and architecture for runtime validation. Use the helper/runtime-supported device selection externally to the candidate (`CUDA_VISIBLE_DEVICES` on NVIDIA), with actual device IDs/UUIDs, so the first selected GPU resolves the intended block. Restrict the GPU ladder to those eligible physical GPUs; do not mix vendors or architectures to reach a count or override the helper's detected architecture. Record exact GPU models and VRAM as well as the architecture suffix: a result on one GPU model does not prove it fits every model sharing that suffix.

NVIDIA quick reference:

| GPU model | Architecture suffix |
| --- | --- |
| H100 / H200 / GH100 / GH200 | `SM90` |
| B100 / B200 / GB200 | `SM100` |
| B300 / GB300 | `SM103` |
| GeForce RTX 5090 / 5080 / 5070 Ti / 5070 / 5060 Ti / 5060 / 5050 | `SM120` |
| RTX PRO 6000 / 5000 / 4500 / 4000 / 2000 Blackwell | `SM120` |
| GB10 / DGX Spark | `SM121` |

This NVIDIA table is not exhaustive. For older/newer NVIDIA GPUs, use NVIDIA's [current](https://developer.nvidia.com/cuda/gpus) or [legacy](https://developer.nvidia.com/cuda/gpus/legacy) tables and the actual hardware query. For a non-NVIDIA GPU, use that vendor's authoritative architecture documentation and supported hardware query. Do not guess from a product-family name. Use a suffix only if the current `template.sh`, unchanged helper, and selected engine support it; otherwise report missing architecture support, not a successful recipe. Vendor-neutral notation does not add runtime support by itself. Do not invent a block, map to a nearby architecture, or modify the template/helper within this skill. If the requested hardware is unavailable, keep any candidate unpromoted and report runtime validation blocked; another architecture cannot validate it.

### Backend selection and flag mapping

Verify accepted flags and backend values against the exact installed engine release/commit and its selection logic, then confirm the effective choices in launch logs. This table distinguishes the value stored in each recipe field from the engine option emitted at launch:

| Architecture field | Recipe field contains | SGLang flag | vLLM flag |
| --- | --- | --- | --- |
| `BACKEND_ATTENTION_<ARCH>` | Full flag/value string, or empty when appropriate | `--attention-backend` | `--attention-backend` |
| `BACKEND_FP8_GEMM_<ARCH>` | Full flag/value string, or empty when appropriate | `--fp8-gemm-backend` | `--linear-backend` |
| `BACKEND_FP4_GEMM_<ARCH>` | Full flag/value string, or empty when appropriate | `--fp4-gemm-backend` | `--linear-backend` |
| `BACKEND_MOE_RUNNER_<ARCH>` | Full flag/value string, or empty when appropriate | `--moe-runner-backend` | `--moe-backend` |
| `CONTEXT_LEN_VALUE_<ARCH>` | Context token count only | `--context-length` | `--max-model-len` |
| `GPU_MEM_UTIL_VALUE_<ARCH>` | Memory-utilization fraction only | `--mem-fraction-static` | `--gpu-memory-utilization` |
| `TENSOR_PARALLEL_SIZE_<ARCH>` | Tensor-parallel GPU count only | `--tp` | `--tensor-parallel-size` |

The three scalar fields MUST contain only their values, never a CLI flag plus a value. The unchanged inference helper adds the appropriate context, memory-utilization, and tensor-parallel flags for the selected engine. Preserve the template's quoting style; quoting a numeric value does not make it a flag string. Do not duplicate these helper-generated options in `EXTRA_ARGS`.

The vLLM memory option described informally as `--gpu-mem-util` is emitted by the current helper as `--gpu-memory-utilization`; use the canonical flag, not an assumed abbreviation. Flags and accepted values vary by engine version; a table entry is not proof that an older engine supports it.

For each applicable architecture-specific backend field not superseded by a validated environment-based GEMM selector, try to make the engine's auto-selected backend explicit for the exact model, precision, GPU architecture, and engine version. Inspect source selection logic first; where needed, observe auto-selection during a sweep launch with the relevant field empty, then set the source-verified flag/value and rerun. Do not select from the architecture name alone, copy another block's backend, or invent a value. Preserve an exact model-card/cookbook-mandated backend instead of overriding it with an automatic default.

An unused precision backend or a dense model's MoE field may remain `""`. An engine default may also remain blank when no supported explicit equivalent exists; record why and the observed effective backend in the report, not in extra recipe comments. Blank does not automatically mean unconfigured. The current helper selects the nonempty FP8 GEMM field first and uses the FP4 GEMM field only as a fallback; it does not emit both. Identical validated `--linear-backend` values in both fields are harmless and do not require recipe rewrites or new environments. If the fields differ, the FP8 field wins regardless of checkpoint precision. When changing a selected block's backend, account for that precedence and verify the emitted selector; do not migrate unrelated recipes or architecture blocks.

When a validated environment variable in `INFERENCE_ENV` selects a GEMM backend, retain it as the sole selector for that GEMM path. Leave the corresponding CLI-backed architecture fields empty; do not duplicate or supplement that selection through CLI flags in any field, including `EXTRA_ARGS`. Resolve a conflict in the selected block by removing its competing CLI selector, not by overriding the validated environment selection or retuning unrelated architecture blocks. Independent attention and MoE backend choices remain configurable. Validated specialized backend options without a dedicated template field may remain in `EXTRA_ARGS`, but must not compete with the environment-selected GEMM path.

Freeze validated backend choices before the final utilization search. If a backend, engine, or dependency changes after measurements, repeat the sweep under the new configuration; measurements from another configuration cannot establish the final maximum.

## Skill operations and mode selection

### 1. Create a new recipe

Accept a target `<publisher>/<model>`, optionally followed by a GPU name or architecture, for example “Create a new cookbook recipe for nvidia/GLM-5.3-NVFP4”, “for H200s”, or “SM90”.

Use the full temporary-first workflow below. Copy the current bundled `template.sh` to the correctly named script under `/tmp`, retaining every architecture block it defines as blank and preserving its fixed launcher plumbing. Fill the other configurable recipe fields using `llm-vlm-cookbook-recipe-source`; do not treat template constants as model settings. Populate only the resolved architecture's applicable backend fields, `CONTEXT_LEN_VALUE_<ARCH>`, and `TENSOR_PARALLEL_SIZE_<ARCH>`. Obtain `GPU_MEM_UTIL_VALUE_<ARCH>` through the required sweep, not a copied or guessed default. Promote only after full behavioral validation on matching hardware.

#### Model-wide field completion

New-recipe creation must address the model-wide fields as well as the target architecture block, but this is **not a universal nonempty-field checklist**. Read every configurable assignment from the live template and choose its value for the exact model, engine, and recipe variant. Preserve empty values for optional or inapplicable settings; do not invent flags, parsers, or plugin paths to fill the template. Apply the explicit defaults and model-card exceptions below. For other model-specific choices, use the applicable validated recipe as the configuration reference and authoritative model/engine research for new or changed settings; do not impose one model's values on another. The live template remains the structural authority.

Use these fixed serving defaults for new SGLang and vLLM recipes:

```bash
HOST="0.0.0.0"
DEFAULT_PORT=8000
API_KEY="--api-key YOUR_API_KEY"
```

For SGLang, also set `METRICS_FLAG="--enable-metrics"`. vLLM does not require that flag; leave `METRICS_FLAG=""` unless an explicit, engine-supported configuration calls for a value. The remaining field groups describe configuration decisions, not additional universal nonempty requirements or a replacement for the live template:

| Fields | Configuration guidance |
| --- | --- |
| `PYTHON_ENV`, `INFERENCE_PROVIDER` | Select the reproducible environment and the correct helper-recognized provider (`SGLang` or `vLLM`). |
| `INFERENCE_ENV` | Use `""` or the validated `env NAME=value ...` prefix for model/engine compatibility, integration, backend, startup, or performance settings. Environment-based GEMM selectors are permitted and take precedence over competing CLI backend selectors for the same GEMM path. |
| `MODEL_REPO`, `MODEL_NAME`, `SERVED_MODEL_NAME` | Set the exact checkpoint repository and the appropriate model/parser alias and API-served name using validated repository conventions. |
| `TRUST_REMOTE_CODE` | Follow the validated model/engine configuration; use `"--trust-remote-code"` when applicable, otherwise `""`. Do not make it universally required. |
| `REASONING_PARSER` | Prioritize finding a compatible reasoning parser and configure it when available and applicable. Native/automatic handling or an empty field may be valid. Do not invent a parser or fail the recipe solely because none is available. |
| `ENABLE_AUTO_TOOL_CHOICE`, `TOOL_CALL_PARSER` | Prefer supported tool-call configuration for the exact model and engine. SGLang leaves the auto-tool-choice field empty; vLLM tool-parser configurations use `"--enable-auto-tool-choice"`. These fields contain flag strings, not numeric switches. |
| `HOST`, `DEFAULT_PORT`, `API_KEY` | Use the fixed cross-engine serving defaults above. |
| `METRICS_FLAG` | SGLang: `"--enable-metrics"`. vLLM: empty by default; this is not a cross-engine requirement. |
| `ENABLE_CACHE_FLAG`, `NO_PREFIX_CACHE` | Always populate `NO_PREFIX_CACHE` in new recipes: SGLang uses `"--disable-radix-cache"`; vLLM uses `"--no-enable-prefix-caching"`. Set `ENABLE_CACHE_FLAG=0` unless the exact model card explicitly requires disabling the cache for that configuration; only that exception uses `1`. This setting is independent of `ENABLE_SPECULATIVE`. Route the disabling flag through these fields, not `EXTRA_ARGS`. |
| `ENABLE_SPECULATIVE`, `SPECULATIVE` | When the exact model card provides an applicable primary speculative configuration, create regular and speculative scripts unless the user explicitly limits the requested variants. Store the same complete configuration in both files; set `ENABLE_SPECULATIVE=0` in the regular file and `1` in the speculative file. A populated string alone does not activate speculation. Without an applicable configuration, use `0` and `""`. This switch does not control cache behavior. |
| `ENABLE_REASONING_PARSER`, `REASONING_PARSER_PLUGIN` | Normally use `0` and `""`. Use `1` and a validated official plugin path only when that plugin is needed. Native reasoning parsers do not require this switch; it controls the helper's plugin-file check, not native reasoning parsing. The helper emits any nonempty plugin path, so leave it empty when unused. |
| `QUANTIZATION`, `EXTRA_ARGS` | Preserve validated explicit quantization choices and other model/engine settings, including tuning. For new recipes, include explicit `--dtype` only when the exact model card's launch command supplies it; do not inherit it solely from an existing recipe. Leave optional fields empty when appropriate. Do not duplicate cache-disabling flags or backend selectors that belong in their dedicated fields, and do not add CLI selectors competing with an environment-selected GEMM backend. |

Populate the numeric switches `ENABLE_CACHE_FLAG`, `ENABLE_SPECULATIVE`, and `ENABLE_REASONING_PARSER` with explicit `0` or `1`, not empty assignments. `ENABLE_AUTO_TOOL_CHOICE` remains a flag string or `""`. Keep the template's fixed `RECIPE_DIR` expression and the temporary-source/promotion rules unchanged. Inspect the final emitted command to confirm intended fields are active: stored configuration, numeric switches, and engine-native behavior have distinct roles.

### 2. Update an existing recipe

Accept a recipe filename plus an optional GPU name or architecture, for example “Update the vllm_Qwen_Qwen3.8-27B-FP8.sh cookbook recipe for H200s” or “for SM90”. Resolve the target as above. The normal update scope is the entire target architecture block defined by the live template, not the other architecture blocks or unrelated model-wide settings.

Read the supplied script, check that its structure follows the current bundled `template.sh`, and record `PYTHON_ENV`, all target fields, helper path, launch arguments, and the original target memory-utilization value for the final report. Reuse context from another architecture in the same file according to the context policy below. Preserve existing values outside the update scope; do not replace a populated update candidate with the blank template.

Choose the update path:

- **Configured target block, no broader change requested:** redo the target `GPU_MEM_UTIL_VALUE_<ARCH>` sweep. The block is configured when its context and tensor-parallel values are positive, its utilization is usable/nonzero, and its applicable backend choices are established. Intentionally blank automatic or inapplicable backend fields count as configured; blank scalar fields or a zero utilization sentinel do not.
- **Unconfigured/partial target block, or an explicit architecture/backend refresh:** copy the existing script to `/tmp` with the **same basename before editing**, configure the target field group, and use full behavioral validation. Do not first launch a different populated block or force an empty target block to launch. Record why the initial in-place baseline is not applicable.
- **Failed configured baseline, or an explicit broader port/repair/model-card refresh:** use the recovery/full workflow below. Any necessary model-wide repair must be source-verified, staged only in `/tmp`, and reported; it is not permission to retune unrelated architecture blocks.

In every update path, the original repository recipe remains untouched until validation succeeds. The validated `/tmp` copy then replaces that same recipe, with its standard helper source path restored. Do not create a second recipe or a mixed-case publisher directory.

### Configured-target sweep-only workflow

This path takes precedence over conflicting full-creation requirements. Preserve the model repository, target maximum context, engine environment, parsers, backends, cache behavior, precision, CUDA settings, and unrelated flags unless the user explicitly requests otherwise.

1. Run the supplied repository script **first, in place, before making a `/tmp` copy**, on the selected target GPUs with its existing target tensor-parallel size, memory utilization, context, port, and other launch settings.
   - Always perform this initial run for a configured target, even when the environment already exists.
   - Allow the unchanged helper to auto-create a missing configured environment and install the engine through the existing package catalog.
   - Wait for final API readiness, confirm the target architecture and configured model/settings in logs, send one coherent non-gibberish baseline prompt, verify a relevant non-empty response, and stop cleanly.
   - This establishes an operational baseline, not the final sweep or behavioral result.
2. Copy the exact script that was run to `/tmp` with the **same basename before editing**, whether the baseline passed or failed. Make only the mechanical source-path adjustment needed to invoke `tools/recipes/inference_recipe.sh`; do not copy or symlink the helper.
3. If the baseline failed, follow the recovery workflow below before sweeping. Otherwise do not redo cookbook, model-card, `config.json`, parser, backend, context, or engine-version research.
4. Run the full one → two → four → eight eligible-GPU ladder and two-decimal sweep. On the normal sweep-only path, the only recipe fields that may change are the target `TENSOR_PARALLEL_SIZE_<ARCH>` and `GPU_MEM_UTIL_VALUE_<ARCH>`. Keep the target `CONTEXT_LEN_VALUE_<ARCH>` and all four backend fields unchanged.
5. Preserve unrelated existing model/draft revision selectors in sweep-only mode; never add a new selector. A non-VRAM error during an otherwise working sweep is not permission to redesign the recipe. Report it unless the user requests repair or the explicit SM120/SM121 backend-recovery rule applies.
6. At the smallest passing GPU count and maximum passing two-decimal utilization, rerun the `/tmp` copy, wait for final API readiness, verify the 16,384 MiB reserve on every selected GPU, and check a coherent baseline response. Do not rerun reasoning, tool-call, modality, speculative, model-card, or parser-specific suites for an unchanged sweep-only setup unless requested.
7. Only after that run passes, replace the original with the validated copy, restoring the standard helper source line. Preserve all unrelated content; if both target values are unchanged, do not rewrite the original needlessly.
8. Run the final repository recipe once to API readiness on the same target GPUs, recheck the reserve and baseline response, then run Bash syntax and ShellCheck. Retain a pre-update copy until this succeeds; restore it if final-path validation fails.
9. Do not add a new recipe, environment, installer, or catalog entry for a normal sweep-only update. If no available target GPU count can satisfy maximum context plus reserve, leave the original byte-for-byte unchanged and mark the sweep failed.

### Architecture setup and failed-baseline recovery

For a partial/unconfigured block, perform the authoritative research needed for its target fields, except for reusable same-file context, then run the temporary-first workflow and full behavioral suite. Preserve model-wide settings unless an explicit broader request or a source-verified compatibility requirement necessitates a change. Do not copy backend, utilization, or tensor-parallel values from another architecture as evidence.

If a configured initial run failed, keep the exact failed recipe as the `/tmp` starting point and perform full authoritative research before repairing it, retaining the context-reuse shortcut where valid. Keep its structure aligned with the bundled `template.sh`, create or repair only a temporary candidate environment through the reproducible installer contract, run static checks, and resolve failures through source-verified engine/configuration/dependency choices allowed by the engine-source policy below. Establish final API readiness at maximum context and a coherent baseline response before beginning the selection sweep. Freeze those validated repairs, then repeat the GPU ladder and full behavioral validation; the earlier baseline does not validate changed backends or engine dependencies.

Keep all repairs and provisional environment wiring out of the original recipe and repository catalogs until promotion. Remove them on failure. Full-mode revision, parser, modality, engine-source, and promotion rules apply to this recovery path. Report every change outside the target block. The b12x recovery below applies to both creation and update, including an otherwise sweep-only update that encounters a qualifying backend failure.

## Non-negotiable outcome

A successful task produces or updates a repository-format recipe that:

1. serves the exact requested SGLang / vLLM cookbook recipe, or the Hugging Face model repository if the former don't exist;
2. configures the model's maximum officially supported checkpoint context without inventing a recipe-level RoPE-scaling override;
3. starts on real available GPUs without reducing protected runtime limits;
4. selects the smallest available GPU count that can satisfy maximum context and the mandatory free-memory reserve;
5. records the selected architecture's configuration as defined by the current template, including the maximum passing two-decimal `GPU_MEM_UTIL_VALUE_<ARCH>`;
6. exercises the model's actual API behavior, including its modality and model-card-advertised parsers/features, as required by the selected mode;
7. follows the selected operation's workflow, including the initial in-place run for configured-target updates and temporary-only setup/recovery for missing or failed target configurations;
8. is copied into its respective repository directory `recipes/<repo>` or updated there in place only after the required behavioral validation succeeds; and
9. has a reproducible package installer and consistently ordered environment entries.

If those conditions cannot be met with the available GPUs and a reproducible SGLang/vLLM source allowed by the engine-source policy below, the result is a **failure**, not a narrowed recipe.

## Context-length policy

### Required value

For a new recipe, or when existing-recipe context cannot be reused as described below, MUST determine the maximum officially supported context from the exact checkpoint's authoritative sources:

1. exact official SGLang/vLLM cookbook selection;
2. exact Hugging Face model card;
3. exact checkpoint `config.json` and related configuration;
4. official engine source/docs for the chosen version.

Set the target architecture's `CONTEXT_LEN_VALUE_<ARCH>` to the highest context length officially supported by that exact checkpoint without adding a recipe-level or runtime RoPE-scaling override. The repository helper maps it to:

- vLLM: `--max-model-len`
- SGLang: `--context-length`

Treat position scaling already shipped in the exact checkpoint's `config.json` as checkpoint state, not as an optional recipe-added YaRN configuration. When authoritative sources advertise the stored `max_position_embeddings` as a trained or supported context, use that full value even if the same config also contains `rope_scaling`, `rope_type: yarn`, a scaling `factor`, or `original_max_position_embeddings`.

`original_max_position_embeddings` records a pre-extension or scaling reference; it is not by itself the checkpoint's serving ceiling. NEVER clamp an officially advertised maximum down to that original value solely because the checkpoint embeds YaRN or another RoPE-scaling method.

If the model card advertises a supported maximum larger than the stored config and the engine requires a documented opt-in environment variable to honor it, include that environment variable in `INFERENCE_ENV`. Every such variable MUST be source-verified for the exact model and engine version; never guess one.

### Existing-recipe context reuse

When configuring a target architecture in an existing recipe, first inspect populated `CONTEXT_LEN_VALUE_<ARCH>` fields across all architecture blocks in that same file. If another block supplies an unambiguous positive context for the unchanged checkpoint and context-related model settings, reuse it exactly for the target `CONTEXT_LEN_VALUE_<ARCH>` and record the donor field. Do not repeat a `llm-vlm-cookbook-recipe-source` context lookup solely because the hardware architecture changes. This reuses the recipe's established maximum, not its other architecture-specific settings.

If multiple populated blocks agree, reuse that value. If they disagree, a value is invalid, the checkpoint/context-related settings change, or the user requests a context audit, resolve the maximum through the authoritative lookup rather than choosing the lowest, highest, or first value arbitrarily. With no reusable value, perform the lookup. A normal configured-target sweep preserves its established target context; conflicting context evidence requires resolution before treating it as sweep-only. Never change non-target blocks as part of the target update.

This shortcut avoids only redundant context research. It does not waive backend/version/source verification when setting up or repairing a target block, maximum-context runtime validation, or the prohibition on lowering context to fit.

### Forbidden recipe-added context mechanisms

NEVER add, reconstruct, or override YaRN/RoPE settings merely to exceed the exact checkpoint's officially supported maximum. Distinguish such a recipe-level override from scaling metadata already embedded in the checkpoint. Preserve embedded metadata and let the engine consume it normally.

NEVER lower context length to make the model fit GPU memory. Scale GPU count instead. If the model still cannot start at maximum context, mark the attempt as failed.

## Optional n-gram policy

Source-verified RAM/disk offload variants are allowed without a separate explicit user opt-in. This includes Engram/PLE offload, CPU or pinned-RAM lookup, and memory-mapped, NVMe, or SSD-backed lookup. Use the applicable validated recipe or authoritative model/engine configuration; do not invent offload flags or unrelated prompt n-gram speculative configurations.

Checkpoint-native Engram/PLE tables are model state. Preserve the selected recipe variant's source-verified GPU, host-RAM, or disk placement rather than automatically forcing all native tables onto GPUs or disabling an established offload mode.

A candidate may pass with the RAM/disk offload specified by its validated configuration. Confirm its intended state placement in final launch logs and runtime inspection, while retaining maximum context, the per-GPU reserve, and protected runtime settings. Keep that placement fixed during the GPU-count/utilization sweep; do not silently turn a GPU-resident recipe into an offload variant to make a failing sweep pass.

For an n-gram configuration, source-verify its algorithm, state placement, and engine-specific flags; do not infer them from a nearby model or another engine.

### N-gram artifact naming

Every recipe that explicitly enables an optional n-gram mode MUST append its storage mode after all other recipe qualifiers:

```text
<recipe-base>_ngram_ram.sh
<recipe-base>_ngram_disk.sh
```

Use `_ngram_ram` for CPU or pinned-host-RAM-resident tables. Use `_ngram_disk` for memory-mapped, NVMe, SSD, or otherwise disk-backed tables. Keep speculative-method qualifiers before the n-gram suffix; for example:

```text
<model>_speculative_dspark_ngram_ram.sh
```

The matching benchmark basename MUST preserve the same n-gram suffix immediately before the mandatory hardware suffix, so the filename still ends in `_<gpu-type>x<gpu-qty>.json`:

```text
<recipe-base>_ngram_ram_<gpu-type>x<gpu-qty>.json
<recipe-base>_ngram_disk_<gpu-type>x<gpu-qty>.json
```

Do not publish an optional n-gram recipe or benchmark under the unsuffixed base name.

### Model-specific flag provenance

Before adding, removing, or changing a model-specific flag, check the exact Hugging Face model card's launch instructions and the selected engine's support. For **new recipes**, omit explicit `--dtype` unless the exact model-card launch command supplies it; when supplied, use that documented value. A validated existing recipe, checkpoint metadata, or engine auto-resolution is not permission to add `--dtype` to a new recipe.

For **existing recipes**, preserve validated dtype, quantization, and performance settings unless the user requests their change. Do not retroactively remove dtype flags during an unrelated update or sweep; model-card silence alone does not authorize that cleanup. Preserve applicable validated settings other than the new-recipe dtype exception, and do not invent overrides or blindly copy values from an unrelated model or an unconfigured template. The explicit cache defaults and model-card exception rule below still apply.

### Speculative configuration integrity

Treat the primary speculative configuration stored in `SPECULATIVE` as immutable during validation. NEVER add, remove, rewrite, simplify, or toggle any speculative field to make startup pass, including the method, draft model, draft-token count, draft sampling method, rejection sampling method, block size, or adaptive-verification setting. The regular script retains that configuration but does not emit it because `ENABLE_SPECULATIVE=0`. This intentional regular configuration is not permission to disable a failed speculative candidate or substitute the regular script's validation. Repair or upgrade the engine while preserving the complete model-card configuration; if no allowed engine source supports it, mark that speculative recipe failed.

Use the model's documented primary configuration. Do not manufacture MTP, DSpark, and DFlash variants merely because those methods exist. Separately documented draft-model configurations remain distinct alternatives; do not assume a model can only ever have one configuration. N-gram and offload configurations follow the policy above.

Use the relevant validated repository naming convention, with `_speculative_<method>` where a method qualifier is needed, before any required n-gram suffix. Determine activation from the configured switch and emitted command, not the filename alone. Validate every requested script independently at the same checkpoint's maximum context; do not transfer GPU-count, memory-utilization, or API results between scripts. A normal single-recipe sweep update remains scoped to the supplied script and does not create another variant unless requested.

## Protected runtime settings

### Prefix/radix cache

For new recipes, always populate the existing `NO_PREFIX_CACHE` field with the selected engine's flag:

| Engine | `NO_PREFIX_CACHE` |
| --- | --- |
| vLLM | `"--no-enable-prefix-caching"` |
| SGLang | `"--disable-radix-cache"` |

Set `ENABLE_CACHE_FLAG=0` unless the exact model card explicitly requires cache disabling for the configuration being created. The shared helper appends `NO_PREFIX_CACHE` only when `ENABLE_CACHE_FLAG=1`; this enables emission of a **cache-disabling argument**, not the engine's cache. `ENABLE_SPECULATIVE` is a separate switch and does not change this default or determine whether the cache flag is needed.

Record the exact model-card requirement before setting `ENABLE_CACHE_FLAG=1`. Keep the disabling argument in `NO_PREFIX_CACHE`, not `EXTRA_ARGS`, and inspect the full emitted command for duplicates or conflicting cache options. Do not leave `NO_PREFIX_CACHE` empty to mask the switch's effect. Never change cache behavior during the memory sweep to make a recipe fit. Existing sweep-only updates preserve their supplied cache settings unless the user requests a change.

### Request and batch limits

NEVER add or reduce request/batch limits merely to fit memory or get startup to pass. Omit undocumented limits, including engine-equivalent forms such as:

```text
--max-running-requests
--max-num-seqs
--max-batch-size
--max-num-batched-tokens
```

A model-card command MAY supply one of these; preserve it only when it is explicit for the exact recipe.

### CUDA graphs

NEVER disable CUDA graphs. Forbidden examples include:

```text
--disable-cuda-graph
--disable-cuda-graphs
--enforce-eager
--cuda-graph-backend-decode disabled
--cuda-graph-backend-prefill disabled
```

Do not lower concurrency, context, or batch limits as a substitute for CUDA-graph support.

### CUDA graph batch-size flags

NEVER invent, remove, or change `--max-num-seqs` or any CUDA graph batch-size/capture flag unless the exact model card explicitly specifies it. Protected CUDA graph examples include:

```text
--cuda-graph-max-bs
--cuda-graph-max-bs-decode
--cuda-graph-max-bs-prefill
--max-cudagraph-capture-size
```

When the exact model card specifies a CUDA batch-size flag for the applicable hardware architecture, preserve that exact value. A copied template's value does not count as model-card evidence.

## Model-repository revision policy

In full recipe creation or broad update mode, every generated recipe MUST follow the model and draft repositories' default revisions. NEVER add, preserve, or copy a model-repository revision selector into a temporary or promoted new recipe.

Forbidden examples include:

```text
--revision
--code-revision
--tokenizer-revision
--model-revision
--draft-model-revision
--speculative-draft-model-revision
--lora-revision
```

This prohibition also covers:

- any other CLI flag whose purpose is selecting a branch, tag, commit, snapshot, or revision;
- revision keys embedded in `--speculative-config` JSON or another config object;
- repository IDs suffixed with `@<branch>`, `@<tag>`, or `@<commit>`;
- local Hugging Face `snapshots/<sha>` paths used in place of `MODEL_REPO`;
- environment variables or helper fields that pin model, tokenizer, code, adapter, target, or draft repository revisions.

In full recipe creation or broad update mode, strip all such revision selectors from the temporary candidate even if the template contains them. The higher-precedence existing-recipe sweep-only mode preserves unrelated existing flags but still never adds a new revision selector. If an exact model-card command itself includes a model revision during full mode, do not copy it: test the repository default. If the default cannot work without a model-revision pin, mark the recipe attempt as failed rather than adding the pin.

This rule applies to model artifacts referenced by the recipe. It does **not** prohibit pinning the SGLang or vLLM engine source in the candidate environment installer. Engine release, commit, or PR pins belong only in `installers/06_install_packages.sh` and MUST NOT be emitted as model revision flags in the serve command.

## Engine-source policy

Use a reproducible engine source appropriate to the exact recipe:

- official release/tag;
- upstream `main`;
- specific upstream commit;
- a specific pull request at the exact tested source commit; or
- a model-publisher/provider-maintained SGLang or vLLM fork at a recorded repository URL and exact tested commit.

Provider-maintained forks are valid engine sources; do not replace a validated fork with upstream solely to satisfy a source-location convention. Recorded compatibility patchsets used by validated recipe installers are also allowed when the upstream/fork base, complete patch, resulting source identity, installation commands, and any separately selected binary source are captured reproducibly.

NEVER use an unexplained fork, unrecorded local patch, or hidden site-packages edit. Allowing recorded integrations does not authorize inventing an ad hoc engine modification to make a candidate pass.

For a new PR-specific environment, use repository naming conventions, for example:

```text
env_<publisher>-sglang-pr-<number>
env_<publisher>-vllm-pr-<number>
```

Record an unambiguous PR identity and the exact tested source commit in the installer function and final report. A PR URL or its canonical repository plus PR number is sufficient; a literal URL is not mandatory when those identifiers are already recorded. Record the actual tested source identity, including a documented merge/test-merge commit when applicable, rather than requiring it to be the PR head. Preserve established environment names and mappings; do not recreate environments or rewrite recipes solely to expand a PR URL.

### SM120 / SM121 vLLM b12x recovery

For **both creation and update**, if vLLM cannot launch on `SM120` or `SM121` because of backend/kernel incompatibility, MUST try the Local Inference Lab team's **b12x** kernels in one or more applicable backend fields in the target architecture block using a vLLM version that supports them. Classify the failure first: b12x is a backend recovery path, not a substitute for the GPU ladder or an excuse to ignore insufficient VRAM.

1. Follow the source skill's lookup order, then inspect the chosen vLLM source's exact version/commit, backend registry, CLI, and integration code together with the [b12x project](https://github.com/local-inference-lab/b12x). The upstream [attention-backend documentation](https://github.com/vllm-project/vllm/blob/main/docs/design/attention_backends.md) documents optional b12x attention integration; current `main` documentation is not proof of support in the installed version or provider fork.
2. Verify each flag/value independently. For a compatible version, try `--attention-backend b12x` in `BACKEND_ATTENTION_SM120` or `BACKEND_ATTENTION_SM121`. Try `--linear-backend b12x` in the applicable FP8/FP4 GEMM field and/or `--moe-backend b12x` in the MoE field **only if that exact engine source supports that selector for the checkpoint and hardware**. Never assume all four backend fields accept `b12x`, copy an attention identifier into another flag, or enable inapplicable precision/MoE fields.
3. Install any required unmodified b12x package and a compatible vLLM source allowed by the engine-source policy in the temporary candidate environment using exact recorded installation commands. Local Inference Lab's published b12x dependency is explicitly allowed for this requested fallback. Existing reproducible provider forks and recorded integrations remain allowed; do not invent an unrecorded fork, local patch, copied integration, unofficial parser, or hidden site-packages edit to add b12x support. Promote tested dependencies only through the reproducible installer.
4. Keep maximum context, requested precision, speculative configuration, cache/CUDA-graph protections, the selected variant's weight/native-table placement, and the per-GPU reserve unchanged. Do not import loader, offload, n-gram, or batch-limit settings from a b12x example. Change only the applicable target backend fields and source-required environment/dependency settings; leave other architecture blocks untouched.
5. Record the original backend failure, exact engine and b12x versions/commits, selectors attempted, and outcomes. Confirm b12x is actually selected in runtime logs. A backend or dependency change exits sweep-only validation: rerun the target GPU-count/utilization sweep and the full behavioral suite before promotion.

If no allowed engine source supports an applicable b12x integration, or the fallback still fails, report the tested sources and exact blocker and leave the original recipe/catalogs unchanged. Do not claim b12x success from package installation or CLI acceptance alone.

## Python-environment integrity

### Allowed

- Create a new candidate environment under `/tmp` for this task.
- Install packages into that temporary environment with exact, recorded package-manager commands derived from repository installer conventions.
- Install or reinstall an engine source allowed by the engine-source policy, including a pinned provider fork or recorded integration, in the temporary candidate environment while evaluating compatibility.
- Let the package manager populate the environment normally.
- Use installer-managed engine checkouts and editable installs, including under `$HOME/env_*/sglang` or `$HOME/env_*/vllm`, when the source identity and installation commands are recorded. These are not prohibited merely because they are editable.
- Run recorded upstream/provider dependency-build or installation scripts and generate normal activation/CUDA metadata as part of the reproducible environment setup.
- Use unmodified plugins from official engine or model-publisher sources, recording the exact source and installation. Configure them through existing recipe fields without adding script lines or changing the shared template.
- Store required official plugin artifacts under `recipes/<repo>/plugin/`, where `<repo>` is the lowercase publisher/organization directory, not the inference provider. Stage the same layout under `/tmp` during validation and promote the plugin artifacts only with a validated recipe. Reference or install them through existing recipe fields and the reproducible environment installer; do not add script lines or change the shared template.

### Forbidden

NEVER make unrecorded or ad hoc source/config/helper changes inside a Python environment, including:

```text
$HOME/env_*/lib/python*/site-packages
$HOME/env_*/sglang
$HOME/env_*/vllm
```

NEVER introduce ad hoc import monkey-patches, hidden site-packages edits, or unrecorded copied model code. Reproduce allowed source changes through the captured installation procedure rather than hand-editing an established environment.

NEVER create or modify a repository serving helper, unofficial reasoning parser plugin, unofficial tool parser plugin, or ad hoc compatibility shim to make the model work. Reuse `tools/recipes/inference_recipe.sh` unchanged. Official plugins, provider forks, recorded engine integration patchsets, and supported b12x dependencies remain allowed under their source and validation requirements; fail only when no allowed configuration supports the required model behavior.

### Additional Python packages

During `/tmp` validation, install source-required additional packages with exact, recorded package-manager commands or the recorded upstream/provider dependency-build and installation scripts allowed above. Do not edit `installers/05_setup_env.sh`, `installers/06_install_packages.sh`, or `launch_env.sh` yet.

Only after the temporary environment and `/tmp` recipe reach API readiness and pass behavioral validation, promote the exact tested installation by adding its environment mapping and installer definition to those repository scripts. Then recreate or reinstall the promoted environment from that definition and revalidate it. A failed candidate MUST leave all three repository environment scripts unchanged.

## Temporary-first workflow

In the remaining sections, **full recipe creation or broad update mode** also covers unconfigured target-block setup, architecture/backend refresh, failed-baseline recovery, and b12x recovery. The configured-target sweep-only path retains its narrower validation and change scope.

### 1. Research (full recipe creation or broad update mode)

MUST perform the cookbook/model-card/source lookup before constructing commands, subject only to the same-file context-reuse shortcut. Determine:

- exact model repository and variant;
- maximum officially supported checkpoint context and whether any position scaling is checkpoint-embedded or recipe-added;
- model precision and loader requirements;
- reasoning/tool parsers;
- multimodal limits and API format;
- engine minimum version and exact source repository/revision, including any required provider fork, PR, or recorded integration patchset;
- model-card-mandated environment variables and backend flags.
- target GPU vendor/model, architecture identifier, eligible GPU IDs/count, and the helper's selected architecture suffix;
- applicable backend flags and the engine's source-verified automatic selections for that checkpoint and architecture.

If either official recipe collection has no matching entry, state that explicitly and continue in the source order defined by the `llm-vlm-cookbook-recipe-source` skill.

### 2. Load the bundled template

On every invocation, read `template.sh` beside the actual loaded `SKILL.md`, using the harness-provided skill location to resolve that sibling resource. Do not assume the skill is installed inside the target repository. If the adjacent resource cannot be located or read, report the missing template prerequisite; do not fall back to an existing launcher, a fixed filesystem path, or an embedded/cached template.

For creation, copy this exact template to `/tmp` under the final recipe basename, then fill only its configurable assignments; do not clear or regenerate its constants, or search `recipes/` for a replacement template. For updates, copy the supplied script as required by the selected update path and use `template.sh` only as the structural contract. Existing launchers are assumed to conform; if structural drift is found, report it rather than adopting it as a second template or silently widening a sweep-only update.

Use applicable validated same-model/same-engine recipes as the authority for repository field usage and model-specific configuration, including intentional empty values, environment settings, parser handling, and naming conventions. If generic guidance conflicts with an applicable validated configuration, correct the guidance rather than normalizing the recipe to it. Follow the explicit serving defaults, independent cache rule, and other requested policies in this skill; do not generalize values from unrelated recipes. Existing recipes are not structural templates: the live `template.sh` defines structure, and the source skill supplies authoritative model/engine verification for new or changed configurations.

Preserve the template's field count/order, spacing, blank lines, comments, architecture blocks, and shared-helper launch contract. Retain its existing `RECIPE_DIR` assignment verbatim. Only the helper source path has a temporary validation exception, described below; both plumbing lines must match the current template when promoted. Do not run the unconfigured template as a launcher, add initialization lines, or replace the helper call with a one-off serve command.

### Parser configuration contract

In full recipe creation or broad update mode, prioritize researching compatible reasoning and tool-call handling for the exact checkpoint and chosen engine. Parser discovery is important, but a nonempty reasoning-parser field is not a prerequisite for a valid recipe:

- If a compatible reasoning parser is available and applicable, configure its verified flag. Native/automatic reasoning handling and intentionally empty `REASONING_PARSER` values are also valid; do not invent a parser or fail the recipe solely because none is available.
- If structured tool calling is supported and needs an explicit parser, set `TOOL_CALL_PARSER` to the verified flag. Preserve validated native/automatic handling where an explicit parser is unnecessary.
- For vLLM tool-parser configurations, set `ENABLE_AUTO_TOOL_CHOICE="--enable-auto-tool-choice"`. Leave that field empty for SGLang; it is a flag string, not a numeric switch.
- Exercise both reasoning and tool behavior when available. An unavailable reasoning parser does not excuse skipping supported tool behavior or make a valid native reasoning configuration incomplete.
- Leave unsupported or inapplicable parser fields empty rather than copying an unrelated model's parser. Record unavailable reasoning-parser support as a limitation, not a standalone failure.
- `REASONING_PARSER_PLUGIN` normally remains `""`, with `ENABLE_REASONING_PARSER=0`. Use a validated official plugin path and switch `1` only when needed. The switch requests the helper's plugin-file check; it does not gate native reasoning parsing, and any nonempty plugin path is emitted independently of it.

Verify parser choices against the applicable validated recipe, exact engine release/main/commit/PR, or official plugin and model guidance. Do not create an unofficial parser plugin or helper. A missing reasoning parser alone is not a failure condition. Required structured tool behavior must still work through native handling or a compatible parser; verify the actual API response rather than treating field nonemptiness as proof.

### 3. Create the temporary environment (full recipe creation or broad update mode)

Create a new candidate environment under `/tmp`; do not experiment inside an established environment used by other recipes. Record every exact installation command and engine source identity used, including any allowed provider fork or recorded integration.

Keep the shared helper's `$HOME/$PYTHON_ENV` lookup unchanged, and keep `PYTHON_ENV` as a logical `env_*` name rather than an absolute path. For isolated candidate setup and launch, use a process-local `HOME` under the task's `/tmp` staging directory and pre-create the candidate at that `$HOME/$PYTHON_ENV`. Apply the override only to those validation processes, never globally. Preserve required model-cache and credential locations through explicit supported settings, and verify the selected Python and engine executables are under the staging directory. Merely activating a different environment is not sufficient. Promotion and final repository validation use the original `$HOME` and its normal managed environment.

Use `installers/06_install_packages.sh` only as the installation-pattern reference during candidate validation. NEVER edit `installers/05_setup_env.sh`, `installers/06_install_packages.sh`, or `launch_env.sh` before the temporary environment and `/tmp` recipe pass API-readiness and behavioral validation.

### 4. Create the temporary recipe

Write the candidate recipe under `/tmp` before writing anything under `recipes/`. New recipes start with every architecture field in the current template blank; existing recipes start as exact copies with only the selected block in scope. The configured-target initial in-place baseline is the sole pre-copy launch exception.

The temporary filename MUST already match repository format:

```text
/tmp/vllm_<publisher>_<model>[-variant].sh
/tmp/sglang_<publisher>_<model>[-variant].sh
```

Use the exact Hugging Face publisher/model identity and repository suffix conventions. Make it executable.

The temporary script MUST invoke the existing helper at:

```text
tools/recipes/inference_recipe.sh
```

Do not create a helper copy, helper symlink, unofficial plugin, unrecorded patch, or ad hoc shim under `/tmp`. Allowed engine checkouts and recorded integration work stay inside the temporary environment under the installation contract above. Keep the template's `RECIPE_DIR` assignment unchanged. For temporary validation, adjust only the helper source path to the existing helper's absolute path, resolved from the actual target cookbook repository, not the skill installation. This exception applies only to the `/tmp` copy: restore the exact relative source line from the current template before promotion and rerun the final repository script.

### Engine-stable launch logs

The skill executor, not a recipe or shared helper, MUST own the stable `/tmp` log mirror for every supervised server launch. Select `/tmp/vllm.log` for vLLM or `/tmp/sglang.log` for SGLang, then run the exact candidate or final recipe through a temporary shell wrapper equivalent to:

```bash
TEMP_LOG=/tmp/vllm.log  # Use /tmp/sglang.log for SGLang.
set -o pipefail
: > "$TEMP_LOG"
<exact recipe command> 2>&1 | tee -a "$TEMP_LOG"
```

The recipe's unchanged shared helper continues to write the normal timestamped file under `recipes/logs/`; the outer `tee` writes the same live output to the selected stable `/tmp` path. Preserve the recipe's exit status with `pipefail`, and supervise the complete wrapper process group. Truncate only the selected engine's stable log immediately before each launch. NEVER add either stable `/tmp` path, a second log destination, or this wrapper behavior to `inference_recipe.sh`, an individual recipe, or an environment launcher.
Continuous log streaming by operators or external observers (such as `tail -F /tmp/vllm.log` or `tail -F /tmp/sglang.log`) MUST be protected across server restarts, sweeps, and cleanups. Operators should use `tail -F` (capital `-F`, `--follow=name --retry`) so log streams survive file truncations and recreations without interruption. During process management and server teardown, NEVER use broad command-substring pattern matches such as `pkill -f vllm` or `pkill -f sglang`, which terminate external watcher processes like `tail -F /tmp/vllm.log`. Always terminate the server cleanly via its specific launcher PID or process group (`kill -INT -- "-$SERVER_PID"`), or if forced process termination is required, use an exact binary regex (for example `pkill -9 -f 'vllm (serve|entrypoints)|VLLM::EngineCore'` or `pkill -9 -f 'sglang.launch_server'`) that specifically excludes monitoring tools and log watchers.

### 5. Static check before launch

Run Bash syntax and ShellCheck using the repository convention. Fix real findings before runtime. Do not suppress findings with broad directives.

Read the current adjacent `template.sh` again and compare the candidate's structure against it: variable names/count/order, blank lines, comments, architecture blocks, and helper/call lines must match, allowing only configurable assignment values and the temporary helper source path to differ. Check `RECIPE_DIR` verbatim even in `/tmp`; the final repository helper source line must also match the template verbatim. Derive this comparison from the live file, not hard-coded field/block counts or the examples in this skill. For updates, also verify that non-target blocks and unrelated values remain unchanged. Repeat this check before promotion; do not promote a nonconforming or stale-template script.

### 6. GPU-count and memory-utilization sweep

For creation and unconfigured target setup, the memory-utilization sweep **replaces** any guessed or template-derived fixed-value initial validation. The configured-target initial baseline and failed-baseline recovery are explicit exceptions described above, not evidence for the final GPU count. NEVER predict that a model needs multiple GPUs from parameter count, checkpoint size, or prior experience. Always begin the selection sweep at maximum context on one eligible target GPU.

Use this exact GPU-count ladder, counting only available physical GPUs matching the target architecture:

1. one eligible GPU;
2. two GPUs, only if at least two eligible physical GPUs exist;
3. four GPUs, only if at least four eligible physical GPUs exist;
4. eight GPUs, only if at least eight eligible physical GPUs exist.

For each GPU count, set only `TENSOR_PARALLEL_SIZE_<ARCH>` in the target block and sweep `GPU_MEM_UTIL_VALUE_<ARCH>` to find the **maximum passing value to two decimal places**. The final recipe value must have exactly two decimal places, in the form:

```text
0.xx
```

The selected value MUST leave at least **16 GiB = 16,384 MiB** free on **every selected GPU** after the engine has fully loaded the model, completed internal warmup/graph capture, exposed the API, and reached its true ready state. Aggregate free memory is not sufficient; the least-free selected GPU controls the result.

For each GPU count:

1. Confirm all selected target GPUs are clean and record their IDs, vendor/model, architecture identifiers, and total/free device memory in MiB. On NVIDIA, use `nvidia-smi` (`compute_cap`, `memory.total`, `memory.free`); for another supported vendor, use its authoritative equivalent and normalize units to MiB. Do not substitute host RAM, aggregate memory, or estimates for per-device readings. Select the exact devices externally; verify the helper resolves the intended architecture block.
2. Keep `CONTEXT_LEN_VALUE_<ARCH>` at the maximum officially supported checkpoint context and keep validated backends and every protected request, batch, cache, precision, CUDA-graph, and checkpoint-embedded RoPE setting unchanged. Do not edit non-target blocks or model-wide fields during the sweep.
3. Compute a theoretical two-decimal upper cap from each selected GPU's total memory:

   ```text
   floor_to_2_decimals((total_mib - 16384) / total_mib)
   ```

   Use the smallest cap across selected GPUs and never test above `0.99`.
4. Write each utilization candidate only into the temporary recipe's `GPU_MEM_UTIL_VALUE_<ARCH>` for the target block. Leave `TENSOR_PARALLEL_SIZE_<ARCH>` at this ladder count. Launch from a clean process/GPU state.
5. A candidate passes the memory sweep only if the server reaches its final ready state and the supported vendor telemetry reports at least 16,384 MiB free on every selected GPU after memory settles.
6. A startup crash, OOM, inability to allocate KV cache for maximum context, or reserve below 16,384 MiB is a failed candidate. Classify non-VRAM software/configuration errors separately. In full mode, fix them through an allowed engine source and retry the same GPU count; in sweep-only mode, obey its narrower repair rules. On SM120/SM121 vLLM backend failures, follow the b12x recovery policy. Restart measurements if the engine, backend, or dependencies change.
7. Establish a passing/failing bracket and use bounded search in `0.01` increments, keeping every candidate at exactly two decimal places. Runtime behavior is authoritative; do not assume engine memory utilization is perfectly linear.
8. Prove maximality: after finding a passing two-decimal value, test the next value `+0.01` when it does not exceed the theoretical cap. If the next value also passes, continue the search. If the theoretical cap itself passes, it is the maximum without an additional failing probe.
9. Restart once more at the selected value, wait for final API readiness, resample every selected GPU, and retain the measured free MiB as evidence.
10. Stop cleanly and confirm GPU memory is released before any next candidate or GPU-count attempt.

If no utilization value can both start the maximum-context model and preserve 16,384 MiB free per selected GPU, that GPU count fails for insufficient VRAM. Continue to the next available eligible ladder count. If the next count does not physically exist on the target architecture, stop; do not substitute another topology or use GPUs from another architecture. Stop increasing the count as soon as the smallest count passes.

NEVER respond to sweep failure by:

- lowering maximum context;
- reducing maximum requests or batch size;
- reducing CUDA graph batch sizes;
- disabling CUDA graphs;
- changing the selected recipe variant's established cache behavior as a memory workaround;
- changing precision away from the requested checkpoint;
- accepting less than 16,384 MiB free on any selected GPU.

If no available ladder count through eight GPUs passes, record every attempted count, utilization bound, and failure, then mark the recipe failed.

## Behavioral validation contract

For full recipe creation or broad update mode, a process launch is not success. Creation and unconfigured target setup begin runtime validation through the GPU-count/utilization sweep; do not run a separate recipe first with a guessed or template-derived `GPU_MEM_UTIL_VALUE_<ARCH>`. Only configured-target updates first run the supplied script in place with its current target settings. If that baseline fails, reconstruct that exact failed script under `/tmp` and complete the working-setup recovery before starting the sweep. Backend or engine changes, including b12x recovery, require the full suite rather than the sweep-only baseline check.

Only after the sweep selects the smallest passing GPU count and final two-decimal utilization value, run the complete behavioral suite at those exact final settings:

1. Confirm logs show the exact model, selected GPU IDs and architecture suffix, target `CONTEXT_LEN_VALUE_<ARCH>`, `TENSOR_PARALLEL_SIZE_<ARCH>`, final `GPU_MEM_UTIL_VALUE_<ARCH>`, dtype/quantization, effective choices for the four target-architecture backend fields, parsers, and requested engine source. Distinguish unused backend fields from active automatic defaults.
2. Wait until the server has completed model loading, warmup/graph capture, and reached its true API-ready state.
3. Send a coherent baseline prompt with an objectively checkable answer. Use ordinary meaningful language, not random tokens, repeated characters, a one-token smoke prompt, or gibberish.
4. Verify the baseline response is non-empty, coherent, relevant to the prompt, and semantically correct. Reject repetitive degeneration, raw control/chat-template tokens, unexpected raw markup that configured/native parsing should handle, malformed Unicode/replacement characters, or unrelated text.
5. If reasoning/thinking is available:
   - use validated native/automatic reasoning handling or a compatible configured parser when available; an unavailable reasoning parser alone does not fail the recipe;
   - send a meaningful multi-step prompt with a known final answer, such as a short arithmetic or logic problem;
   - enable the checkpoint's documented thinking mode when it is request-controlled;
   - verify final content contains the correct answer; when native structured reasoning or a configured parser is available, also verify reasoning is separated into the engine's structured reasoning field;
   - when structured reasoning handling is available, inline raw `<think>` markup instead of the expected parsed output is a failure; otherwise record the parser limitation without claiming structured-parser validation.
6. If tool calling is available:
   - use validated native tool handling or the compatible tool-call parser and required automatic-tool-choice flag;
   - send a coherent request that clearly requires a supplied function, together with a real JSON-schema tool definition;
   - verify the response contains a structured tool call, the expected function name, and parseable JSON arguments grounded in the prompt;
   - raw `<tool_call>` text, an unstructured prose imitation, malformed arguments, or answering without the required tool is a failure.
7. When both reasoning and tool calling are available, validate both paths. When native reasoning separation or a compatible reasoning parser is available, the tool-call test should also confirm that reasoning is parsed rather than leaked as raw markup.
8. If the model is a VLM or multimodal model, send an actual supported image/video/audio input and verify a grounded, non-gibberish response. Text-only validation is insufficient.
9. Verify `ENABLE_SPECULATIVE` independently: with `0`, confirm the stored speculative configuration is absent from the emitted command and runtime configuration; with `1`, confirm the requested method, draft path where applicable, and complete effective settings are active, then exercise generation. Separately, verify cache behavior against `ENABLE_CACHE_FLAG`, the populated `NO_PREFIX_CACHE`, and any exact model-card cache-disabling requirement; inspect the complete emitted command for duplicate or conflicting cache options.
10. Verify the same launch output is present in both the helper's timestamped `recipes/logs/` file and the engine-specific stable mirror (`/tmp/vllm.log` or `/tmp/sglang.log`).
11. Stop with Ctrl+C and confirm clean process/GPU teardown.

Do not claim a model/engine combination works unless this complete suite passes on the selected GPU count, final two-decimal utilization value, and maximum officially supported checkpoint context.

## Failure contract

Mark the effort failed when any of these remain true after exhausting applicable sources allowed by the engine-source policy and the available GPU ladder:

- insufficient per-GPU VRAM to run maximum context while preserving at least 16,384 MiB free on every selected GPU;
- no allowed engine source or supported integration can serve the required configuration. A reproducible provider fork, recorded integration patchset, official plugin, or supported b12x dependency is not itself a failure. Required integrations must not add recipe script lines or alter the shared template;
- required modality, reasoning, or tool behavior fails its applicable API checks; an unavailable or inapplicable reasoning parser alone is not a failure;
- startup requires a forbidden context/batch/CUDA workaround;
- a required dependency cannot be captured reproducibly in the environment installer.

On failure:

- do not copy the recipe into `recipes/<repo>`;
- leave an existing recipe byte-for-byte unchanged, restoring its pre-update copy if final-path validation failed; keep other architecture blocks intact;
- do not leave permanent environment catalog entries;
- remove provisional installer/catalog wiring;
- remove temporary scripts/environments created for the attempt unless the user asks to retain them;
- report every GPU count tried and the exact blocker.

## Promotion after success

Use this promotion process only after a full recipe creation or broad update candidate passes the complete behavioral contract. A normal configured-target sweep uses its narrower replacement/revalidation process and does not add catalog entries.

Before copying, set the target `TENSOR_PARALLEL_SIZE_<ARCH>` to the smallest ladder count that passed and `GPU_MEM_UTIL_VALUE_<ARCH>` to the proven maximum two-decimal value. Keep its maximum `CONTEXT_LEN_VALUE_<ARCH>` and four validated backend fields fixed. Rerun the temporary recipe with the exact final block and full behavioral contract. Confirm new recipes still have blank non-target blocks and updates have unchanged non-target blocks.

1. copy the validated script into its respective repository directory `recipes/<repo>` (where `<repo>` is the lowercased publisher parsed from the script name); reuse or create only that lowercase directory, preserve the script's basename and unchanged template `RECIPE_DIR` assignment, and restore the exact helper source line from the current template. For an update, replace the supplied recipe at its existing path only now; retain its pre-update copy through final-path validation;
2. ensure executable mode;
3. retain the exact validated engine source, any recorded integration patchset and build/install commands, and the package list in `installers/06_install_packages.sh`;
4. if a new or changed environment is required, add or update the validated environment consistently in:
   - `installers/05_setup_env.sh`
   - `installers/06_install_packages.sh`
   - `launch_env.sh`
5. insert the environment alphabetically by the existing publisher/environment ordering;
6. renumber every numeric resolver/menu entry consistently;
7. update menu ranges and validation messages;
8. keep `custom_uv` and `custom_pip` as the final two entries at the bottom;
9. verify the three catalogs, `ENV_TYPES`, descriptions, dispatch, and installer function all agree;
10. run the copied repository script again from its final path on the same selected target GPUs, repeating the mode-required behavioral checks and per-GPU reserve check; do not claim validation for other architecture blocks;
11. run final `bash -n` and ShellCheck for every changed shell file.

Do not promote a partially validated script or leave a temporary-only dependency undocumented.

## Final report

Report, with evidence:

- exact model repository and checkpoint variant;
- maximum officially supported checkpoint context and authoritative source, or the same-file donor `CONTEXT_LEN_VALUE_<ARCH>` reused without a redundant context lookup;
- engine repository, release/commit, any provider fork or PR identity, and the exact tested source identity plus provenance of any recorded integration patchset;
- extra packages added to the installer;
- requested/detected target GPU vendor/model and architecture suffix, physical device selection, and eligible GPU counts attempted in order;
- the utilization sweep candidates and two-decimal search bounds;
- before/after values for all target architecture fields from the current template, including final `GPU_MEM_UTIL_VALUE_<ARCH>` and `TENSOR_PARALLEL_SIZE_<ARCH>`, and confirmation that non-target blocks were preserved or left blank for a new recipe;
- backend auto-selection evidence, explicit flag mappings, environment-based GEMM selections and their precedence, and reasons for any intentionally blank backend fields;
- for existing-recipe updates, the initial in-place run result or why it was not applicable to an unconfigured block, whether temporary setup/recovery was entered, any source-verified changes outside the target block, and any environment auto-creation/install;
- for SM120/SM121 vLLM backend failures, b12x selectors attempted, supporting engine/b12x versions and sources, runtime selection evidence, and the fallback outcome or exact unsupported-integration blocker;
- total and free MiB for every selected GPU at final API readiness;
- evidence that the next `+0.01` candidate failed, or that the theoretical reserve cap passed;
- successful API/modalities/features exercised;
- for each requested regular or speculative script, its filename, stored speculative configuration, `ENABLE_SPECULATIVE` value, independent sweep and behavioral results, and any failure; report cache configuration and its model-card exception separately;
- peak or relevant memory observations when available;
- final recipe and environment names;
- catalog ordering/validation results;
- exact static and runtime validation commands;
- explicit failure status when promotion did not occur.
