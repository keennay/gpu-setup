---
name: llm-vlm-cookbook-recipe-creation-and-update
description: "Creates or updates and behaviorally validates portable SGLang and vLLM LLM/VLM recipes at each model's maximum non-YaRN context before promotion."
alwaysApply: false
---

# SGLang & vLLM Recipe Creation and Update

Use this skill when creating, updating, porting, repairing, or validating an SGLang or vLLM recipe for an LLM or VLM in `/workspace/scripts/recipes`.

## Mandatory prerequisite

Before research, environment creation, command construction, or file changes, **MUST** read and follow:

```text
~/.omp/agent/skills/llm-vlm-cookbook-recipe-source/SKILL.md
```

The prerequisite **LLM and VLM Cookbook Recipe Source** skill controls source authority, cookbook lookup, model-card/config inspection, engine source verification, version comparison, and reporting. This skill adds repository-specific implementation and runtime constraints; it does not replace that source policy.

## Mode selection and precedence

### Existing recipe GPU-sweep update mode

When the user supplies an existing recipe script and does not explicitly request broader recipe changes, treat the task as a **GPU memory sweep update**, not a new-recipe audit. This mode has higher precedence than conflicting full-creation requirements below.

The supplied script is the initial configuration contract. Its model repository, maximum context, engine environment, parsers, backends, cache behavior, precision, CUDA settings, and all other flags remain unchanged during the normal update path unless the user explicitly names another requested change.

Workflow:

1. Read the supplied script and record its existing `PYTHON_ENV`, `DEFAULT_TENSOR_PARALLEL_SIZE`, `GPU_MEM_UTIL_VALUE`, helper path, and launch arguments. Preserve the original `GPU_MEM_UTIL_VALUE` as the before value for the final report.
2. Run the supplied repository script **first, in place, before making a `/tmp` copy**, using its existing/default tensor-parallel size, memory utilization, context, port, and all other launch settings.
   - Always perform this initial run, even when the configured environment already exists.
   - Allow the shared helper to auto-create the configured environment when it is missing and install the engine through the existing package catalog. This initial environment creation/install is explicitly permitted for update validation.
   - Wait for final API readiness, confirm the logs show the configured model and launch settings, send one coherent non-gibberish baseline prompt, verify a relevant non-empty response, and stop the server cleanly.
   - This run establishes whether the supplied configuration is operational; it does not replace the required final GPU sweep or final behavioral validation.
3. If the initial in-place run reaches API readiness and passes the baseline check, copy the unchanged script to `/tmp` using the **same basename**. Keep the original repository file untouched during the sweep. Make only the mechanical temporary source-path adjustment needed to invoke `/workspace/scripts/recipes/helpers/inference_recipe.sh`; do not create a helper copy or symlink.
4. If the initial in-place run fails before establishing a working baseline:
   - Keep the original repository file untouched.
   - Copy the exact script that failed to `/tmp` using the **same basename before editing it**, then make only the mechanical helper source-path adjustment.
   - Follow the full temporary-first creation workflow on that copied script to establish a working setup before beginning the GPU sweep: perform the required authoritative source lookup, use the failed script as the same-engine template, create or repair only the candidate environment through the reproducible installer contract, run static checks, resolve source-verified upstream engine/configuration/dependency failures, launch at the maximum configured context, and verify final API readiness plus a coherent baseline response.
   - Do not begin the GPU sweep until this copied `/tmp` candidate is a working setup. Keep all candidate repairs and provisional installer/catalog changes out of the original recipe, and remove them if the attempt fails.
5. After either branch establishes a working baseline, run the full one → two → four → eight GPU ladder and six-decimal memory-utilization sweep defined below. During the normal sweep-only path, the only recipe fields that may change are:

  ```text
  DEFAULT_TENSOR_PARALLEL_SIZE
  GPU_MEM_UTIL_VALUE
  ```

  If the fallback creation workflow required source-verified configuration changes, freeze those validated candidate changes before the sweep and report them explicitly.
6. Existing model/draft revision selectors and other legacy flags are outside normal sweep scope: do not add new revision selectors, but do not remove or change an existing unrelated selector unless the user explicitly requests revision cleanup. The fallback creation workflow must still obey the full model-repository revision policy.
7. A non-VRAM software/configuration failure in the normal sweep-only path is not permission to repair or redesign the recipe. The initial-run failure branch is the explicit exception: repair only through the allowed upstream engine, reproducible installer, and source-verified configuration process described in step 4.
8. Do not redo cookbook, model-card, `config.json`, parser, backend, context, or engine-version research after a successful initial in-place run. If that run fails and step 4 is entered, perform the full authoritative research required by the temporary-first creation workflow before changing candidate configuration.
9. Preserve the existing `CONTEXT_LEN_VALUE` exactly on the normal sweep-only path. In the fallback creation workflow, use the full context-length policy and keep the candidate at the highest officially supported non-YaRN context before sweeping.
10. After selecting the smallest passing GPU count and maximum six-decimal utilization value, rerun the `/tmp` copy at those exact values, wait for final API readiness, verify the 16,384 MiB per-selected-GPU reserve, and send one coherent non-gibberish baseline prompt. Do not rerun reasoning, tool-call, modality, speculative, model-card, or parser-specific suites unless the user requests them.
11. Only after that final temporary run passes, update the supplied original file **in place**. On the normal sweep-only path, change only `DEFAULT_TENSOR_PARALLEL_SIZE` and `GPU_MEM_UTIL_VALUE`; on the fallback creation path, also apply only the source-verified candidate changes required to establish the working setup. If a value is unchanged, do not rewrite it needlessly.
12. Run the updated original once to final API readiness, recheck the reserve and coherent baseline response, then run Bash syntax and ShellCheck.
13. For a normal sweep-only update, do not add a new recipe, environment, installer, or entries in `05_setup_env.sh`, `06_install_packages.sh`, or `launch_env.sh`. If the initial-run failure branch requires full creation-workflow candidate wiring, treat it as provisional, remove it on failure, and promote it only under the full promotion rules after success.
14. If no available GPU count can satisfy maximum context plus the reserve, leave the original file byte-for-byte unchanged and mark the sweep failed.

### Full recipe creation or broad update mode

Use the remaining full workflow when no existing recipe is supplied, when creating a new recipe, or when the user explicitly requests a broader port/repair/model-card refresh.

## Non-negotiable outcome

A successful task produces or updates a repository-format recipe that:

1. serves the exact requested SGLang / vLLM cookbook recipe, or the Hugging Face model repository if the former don't exist;
2. configures the model's maximum officially supported **non-YaRN** context length;
3. starts on real available GPUs without reducing protected runtime limits;
4. selects the smallest available GPU count that can satisfy maximum context and the mandatory free-memory reserve;
5. records the maximum passing six-decimal `GPU_MEM_UTIL_VALUE`;
6. exercises the model's actual API behavior, including its modality and model-card-advertised parsers/features;
7. For a normal existing-recipe update, first validate the supplied repository script in place; if that run fails, reconstruct and validate its exact failed copy under `/tmp` with a temporary candidate environment before promotion.
8. is copied into `/workspace/scripts/recipes` only after behavioral validation succeeds; and
9. has a reproducible package installer and consistently ordered environment entries.

If those conditions cannot be met with the available GPUs and an upstream SGLang/vLLM version, the result is a **failure**, not a narrowed recipe.

## Context-length policy

### Required value

MUST determine the maximum officially supported context from the exact checkpoint's authoritative sources:

1. exact official SGLang/vLLM cookbook selection;
2. exact Hugging Face model card;
3. exact checkpoint `config.json` and related configuration;
4. official engine source/docs for the chosen version.

Set the recipe's `CONTEXT_LEN_VALUE` to the highest context length officially supported by that checkpoint without YaRN. The repository helper maps it to:

- vLLM: `--max-model-len`
- SGLang: `--context-length`

If the model card advertises a supported maximum larger than the stored config and the engine requires a documented opt-in environment variable to honor it, include that environment variable in `INFERENCE_ENV`. Every such variable MUST be source-verified for the exact model and engine version; never guess one.

### Forbidden context mechanisms

NEVER use YaRN, YaRN rope scaling, or a reconstructed YaRN configuration to reach the requested context. If the advertised maximum is available only through YaRN, use the highest officially supported non-YaRN value and state the limitation.

NEVER lower context length to make the model fit GPU memory. Scale GPU count instead. If the model still cannot start at maximum context, mark the attempt as failed.

## Protected runtime settings

### Prefix/radix cache

Omit both of these by default:

```text
--disable-radix-cache
--no-enable-prefix-caching
```

They MAY be included only when the exact model card or exact official cookbook command explicitly requires them. A nearby model, third-party command, old local recipe, or memory workaround is insufficient evidence.

For the mandatory recipe field, set `NO_PREFIX_CACHE=""` unless an authoritative source explicitly requires otherwise.

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

Do not invent, remove, or change CUDA graph batch-size/capture flags unless the exact model card explicitly specifies them. Protected examples include:

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

This rule applies to model artifacts referenced by the recipe. It does **not** prohibit pinning the SGLang or vLLM engine source in the candidate environment installer. Engine release, commit, or PR pins belong only in `/workspace/scripts/06_install_packages.sh` and MUST NOT be emitted as model revision flags in the serve command.

## Engine-source policy

Use only a reproducible upstream engine source:

- official release/tag;
- upstream `main`;
- specific upstream commit; or
- a specific pull request and exact tested head commit.

NEVER use an unexplained local patch, copied source diff, ad hoc fork worktree, or hidden site-packages edit.

If a pull request is required, name the environment using repository conventions, for example:

```text
env_<publisher>-sglang-pr-<number>
env_<publisher>-vllm-pr-<number>
```

Record both the PR URL and exact tested head commit in the installer function and final report.

## Python-environment integrity

### Allowed

- Create a new temporary candidate environment for this task.
- Install packages only through the candidate environment's installer definition.
- Reinstall a different official release, commit, main, or PR into the candidate environment while evaluating engine compatibility.
- Let the package manager populate the environment normally.

### Forbidden

NEVER directly edit, overwrite, copy, or create source/config/helper files inside the Python environment, including:

```text
$HOME/env_*/lib/python*/site-packages
$HOME/env_*/sglang
$HOME/env_*/vllm
```

NEVER monkey-patch imports, mutate installed Python modules, use `sed`/`perl` on site-packages, copy model code into the environment, or keep an editable local engine checkout there.

NEVER create or modify a repository helper, patch file, reasoning parser plugin, tool parser plugin, or compatibility shim to make the model work. Reuse `/workspace/scripts/recipes/helpers/inference_recipe.sh` unchanged. If native support is unavailable in an official release/main/commit/PR, fail the attempt.

### Additional Python packages

If the authoritative model card or a demonstrated import/runtime error proves an additional Python package is required, add that package to the temporary environment's installer function in:

```text
/workspace/scripts/06_install_packages.sh
```

Do not install one-off packages ad hoc and forget to record them. The installer function is the source of truth. Provisional candidate installer/catalog wiring MUST be removed on failure and promoted only after success.

## Temporary-first workflow

### 1. Research (full recipe creation or broad update mode)

MUST perform the prerequisite cookbook/model-card/source lookup before constructing commands. Determine:

- exact model repository and variant;
- maximum non-YaRN context;
- model precision and loader requirements;
- reasoning/tool parsers;
- multimodal limits and API format;
- engine minimum version, main commit, or required PR;
- model-card-mandated environment variables and backend flags.

If either official recipe collection has no matching entry, state that explicitly and continue in the source order defined by the prerequisite skill.

### 2. Select a repository template

The test script MUST be based on an existing same-engine script from:

```text
/workspace/scripts/recipes
```

Prefer the same publisher/model family, then the closest architecture. Preserve the repository's exact field order and shared-helper launch contract. Do not replace it with a one-off direct serve command.

### Parser configuration contract

In full recipe creation or broad update mode, the recipe MUST configure every natively available model capability advertised by the exact model card/checkpoint:

- If reasoning/thinking is supported and the chosen engine source provides a compatible native parser, set `REASONING_PARSER` to the source-verified parser flag.
- If structured tool calling is supported and the chosen engine source provides a compatible native parser, set `TOOL_CALL_PARSER` to the source-verified parser flag.
- For vLLM tool calling, also set `ENABLE_AUTO_TOOL_CHOICE=\"--enable-auto-tool-choice\"` when required by the authoritative command.
- If both reasoning and tool calling are available, the script MUST enable and later validate both. Enabling only one is incomplete.
- If a capability is not advertised for the exact checkpoint, leave its parser field empty rather than copying a parser from the template.

Parser availability must come from the exact engine release/main/commit/PR and authoritative model guidance. Do not create a parser plugin or helper. If the model requires reasoning or structured tools but no allowed engine source provides the required native parser, mark that engine/model recipe failed.

### 3. Create the temporary environment (full recipe creation or broad update mode)

Create a new candidate environment; do not experiment inside an established environment used by other recipes. The candidate name must follow repository naming conventions and be valid for the setup/install scripts.

Use `/workspace/scripts/06_install_packages.sh` as the package contract. If testing multiple engine sources, update only the candidate installer. Never modify an unrelated shared environment.

### 4. Create the temporary recipe

Write the candidate recipe under `/tmp` before writing anything under `recipes/`.

The temporary filename MUST already match repository format:

```text
/tmp/vllm_<publisher>_<model>[-variant].sh
/tmp/sglang_<publisher>_<model>[-variant].sh
```

Use the exact Hugging Face publisher/model identity and repository suffix conventions. Make it executable.

The temporary script MUST invoke the existing helper at:

```text
/workspace/scripts/recipes/helpers/inference_recipe.sh
```

Do not create a helper copy, helper symlink, plugin, patch, or shim under `/tmp`. A temporary script may use an absolute source path during validation; restore the standard repository-relative source line when promoted and rerun the final script.

### 5. Static check before launch

Run Bash syntax and ShellCheck using the repository convention. Fix real findings before runtime. Do not suppress findings with broad directives.

### 6. GPU-count and memory-utilization sweep

The memory-utilization sweep **replaces** any fixed-value initial validation. NEVER predict that a model needs multiple GPUs from parameter count, checkpoint size, or prior experience. Always begin the real maximum-context launch process on one GPU.

Use this exact GPU-count ladder:

1. one GPU;
2. two GPUs, only if at least two physical GPUs exist;
3. four GPUs, only if at least four physical GPUs exist;
4. eight GPUs, only if at least eight physical GPUs exist.

For each GPU count, sweep `GPU_MEM_UTIL_VALUE` and find the **maximum passing value to six decimal places**. The final recipe value must have the form:

```text
0.******
```

The selected value MUST leave at least **16 GiB = 16,384 MiB** free on **every selected GPU** after the engine has fully loaded the model, completed internal warmup/graph capture, exposed the API, and reached its true ready state. Aggregate free memory is not sufficient; the least-free selected GPU controls the result.

For each GPU count:

1. Confirm all selected GPUs are clean and record `memory.total` and `memory.free` with `nvidia-smi`.
2. Keep the model at maximum non-YaRN context and keep every protected request, batch, cache, precision, and CUDA-graph setting unchanged.
3. Compute a theoretical six-decimal upper cap from each selected GPU's total memory:

   ```text
   floor_to_6_decimals((total_mib - 16384) / total_mib)
   ```

   Use the smallest cap across selected GPUs and never test above `0.999999`.
4. Write each candidate only into the temporary recipe's `GPU_MEM_UTIL_VALUE`. Launch from a clean process/GPU state.
5. A candidate passes the memory sweep only if the server reaches its final ready state and `nvidia-smi` reports at least 16,384 MiB free on every selected GPU after memory settles.
6. A startup crash, OOM, inability to allocate KV cache for maximum context, or reserve below 16,384 MiB is a failed candidate. Classify non-VRAM software/configuration errors separately; fix those through an allowed upstream engine source and retry the same GPU count.
7. Establish a passing/failing bracket and use bounded search to `0.000001` resolution. Runtime behavior is authoritative; do not assume engine memory utilization is perfectly linear.
8. Prove maximality: after finding a passing six-decimal value, test the next value `+0.000001` when it does not exceed the theoretical cap. If the next value also passes, continue the search. If the theoretical cap itself passes, it is the maximum without an additional failing probe.
9. Restart once more at the selected value, wait for final API readiness, resample every selected GPU, and retain the measured free MiB as evidence.
10. Stop cleanly and confirm GPU memory is released before any next candidate or GPU-count attempt.

If no utilization value can both start the maximum-context model and preserve 16,384 MiB free per selected GPU, that GPU count fails for insufficient VRAM. Continue to the next available ladder count. If the next ladder count does not physically exist, stop; do not substitute another topology.

NEVER respond to sweep failure by:

- lowering maximum context;
- reducing maximum requests or batch size;
- reducing CUDA graph batch sizes;
- disabling CUDA graphs;
- disabling cache behavior without model-card authority;
- changing precision away from the requested checkpoint;
- accepting less than 16,384 MiB free on any selected GPU.

If no available ladder count through eight GPUs passes, record every attempted count, utilization bound, and failure, then mark the recipe failed.

## Behavioral validation contract

For full recipe creation or broad update mode, a process launch is not success. The GPU-count/utilization sweep is the initial runtime validation. Do not run a separate recipe first with a guessed or template-derived `GPU_MEM_UTIL_VALUE`. Existing-recipe update mode first runs the supplied script in place with its current configuration; if that baseline fails, it then reconstructs that exact failed script under `/tmp` and completes the temporary-first working-setup validation before starting the sweep.

Only after the sweep selects the smallest passing GPU count and final six-decimal utilization value, run the complete behavioral suite at those exact final settings:

1. Confirm logs show the exact model, maximum context length, tensor-parallel size, final `GPU_MEM_UTIL_VALUE`, dtype/quantization, parser/backend choices, and requested engine source.
2. Wait until the server has completed model loading, warmup/graph capture, and reached its true API-ready state.
3. Send a coherent baseline prompt with an objectively checkable answer. Use ordinary meaningful language, not random tokens, repeated characters, a one-token smoke prompt, or gibberish.
4. Verify the baseline response is non-empty, coherent, relevant to the prompt, and semantically correct. Reject repetitive degeneration, raw control/chat-template tokens, raw parser markup, malformed Unicode/replacement characters, or unrelated text.
5. If reasoning/thinking is available:
   - the launch script MUST contain the validated reasoning parser;
   - send a meaningful multi-step prompt with a known final answer, such as a short arithmetic or logic problem;
   - enable the checkpoint's documented thinking mode when it is request-controlled;
   - verify reasoning is separated into the engine's structured reasoning field and final content contains the correct answer;
   - inline raw `<think>` markup without parser separation is a failure.
6. If tool calling is available:
   - the launch script MUST contain the validated tool-call parser and any required automatic-tool-choice flag;
   - send a coherent request that clearly requires a supplied function, together with a real JSON-schema tool definition;
   - verify the response contains a structured tool call, the expected function name, and parseable JSON arguments grounded in the prompt;
   - raw `<tool_call>` text, an unstructured prose imitation, malformed arguments, or answering without the required tool is a failure.
7. When both reasoning and tool calling are available, validate both paths. The tool-call test should also confirm that any reasoning trace is parsed rather than leaked as raw markup.
8. If the model is a VLM or multimodal model, send an actual supported image/video/audio input and verify a grounded, non-gibberish response. Text-only validation is insufficient.
9. If the recipe is speculative, confirm from runtime configuration/logs that the requested speculative method and draft path are active, then exercise generation.
10. Verify log creation through the shared helper.
11. Stop with Ctrl+C and confirm clean process/GPU teardown.

Do not claim a model/engine combination works unless this complete suite passes on the selected GPU count, final six-decimal utilization value, and maximum non-YaRN context.

## Failure contract

Mark the effort failed when any of these remain true after exhausting authoritative engine release/main/commit/PR candidates and the available GPU ladder:

- insufficient per-GPU VRAM to run maximum context while preserving at least 16,384 MiB free on every selected GPU;
- no upstream engine source supports the model without a patch/plugin/helper;
- required modality, reasoning, or tool behavior does not work;
- startup requires a forbidden context/batch/CUDA workaround;
- a required dependency cannot be captured reproducibly in the environment installer.

On failure:

- do not copy the recipe into `/workspace/scripts/recipes`;
- do not leave permanent environment catalog entries;
- remove provisional installer/catalog wiring;
- remove temporary scripts/environments created for the attempt unless the user asks to retain them;
- report every GPU count tried and the exact blocker.

## Promotion after success

Only after a full recipe creation or broad update candidate passes the complete behavioral contract:

Before copying, set `DEFAULT_TENSOR_PARALLEL_SIZE` to the smallest ladder count that passed and set `GPU_MEM_UTIL_VALUE` to the proven maximum six-decimal value. Rerun the temporary recipe once with both final values and the full behavioral contract.

1. copy the validated script into `/workspace/scripts/recipes` with only the source-path adjustment required for the standard relative helper line;
2. ensure executable mode;
3. retain the exact validated engine source and package list in `06_install_packages.sh`;
4. add the validated environment to:
   - `/workspace/scripts/05_setup_env.sh`
   - `/workspace/scripts/06_install_packages.sh`
   - `/workspace/scripts/launch_env.sh`
5. insert the environment alphabetically by the existing publisher/environment ordering;
6. renumber every numeric resolver/menu entry consistently;
7. update menu ranges and validation messages;
8. keep `custom_uv` and `custom_pip` as the final two entries at the bottom;
9. verify the three catalogs, `ENV_TYPES`, descriptions, dispatch, and installer function all agree;
10. run the copied repository script again from its final path;
11. run final `bash -n` and ShellCheck for every changed shell file.

Do not promote a partially validated script or leave a temporary-only dependency undocumented.

## Final report

Report, with evidence:

- exact model repository and checkpoint variant;
- maximum configured non-YaRN context and source;
- engine release/main/commit/PR and exact commit;
- extra packages added to the installer;
- hardware and GPU counts attempted in order;
- the utilization sweep candidates and six-decimal search bounds;
- the final `GPU_MEM_UTIL_VALUE`;
- for existing-recipe update mode, the result of the mandatory initial in-place run, whether the fallback `/tmp` working-setup path was entered, and any environment auto-creation/install performed;
- total and free MiB for every selected GPU at final API readiness;
- evidence that the next `+0.000001` candidate failed, or that the theoretical reserve cap passed;
- successful API/modalities/features exercised;
- peak or relevant memory observations when available;
- final recipe and environment names;
- catalog ordering/validation results;
- exact static and runtime validation commands;
- explicit failure status when promotion did not occur.
