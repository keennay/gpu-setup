---
name: llm-vlm-cookbook-recipe-source
description: "Authoritative source policy for researching, creating, validating, reviewing, or updating LLM/VLM inference recipes, serving commands, engine flags, quantization, parallelism, and speculative decoding for SGLang and vLLM."
alwaysApply: false
---

# LLM and VLM Cookbook Recipe Source

Use this source skill whenever a task involves an LLM or VLM serving recipe, launch command, engine configuration, model compatibility question, or translation between SGLang and vLLM.

## Mandatory first sources

Before consulting model cards, issues, pull requests, third-party examples, or general web results, inspect both official recipe collections:

1. SGLang Cookbook: https://docs.sglang.io/cookbook/autoregressive/
2. vLLM Recipes: https://recipes.vllm.ai/

This lookup is required even when the task initially names only one engine. Find the same model, closest official variant, or relevant model family in both collections. Cite the exact recipe URLs used. If a collection has no matching entry, say so explicitly rather than silently skipping it.

SGLang cookbook pages may encode the selected hardware, variant, quantization, strategy, node count, and modality in URL fragments or query state. Preserve and cite that exact selected URL. When static reading does not expose an interactive cookbook's selected state, use the browser tool to inspect it.

Example of an exact SGLang selection:

https://docs.sglang.io/cookbook/autoregressive/Meta/MuseGlimmer#hw=h200&variant=default&quant=bf16&strategy=dflash&nodes=single&modality=text

## Source order after cookbook lookup

After checking both cookbooks, use this order:

1. Official engine documentation and repository source at the relevant version or commit.
2. Official Hugging Face model card and `config.json`.
3. Upstream engine pull requests and issues, including open, closed, merged, and reverted work.
4. Third-party sources only when authoritative sources do not answer the question.

Prefer primary sources. Do not treat a search-result summary as proof when the underlying recipe, source file, model card, PR, or issue can be read directly.

## Model-specific flag provenance

NEVER add or remove an optional model-specific launch flag without first checking the exact Hugging Face model card's launch instructions. Preserve or add an explicit `--dtype` override, including `--dtype bfloat16`, when that exact model-card command specifies it. Omit or remove the override only when the exact model-card command does not specify it. NEVER blanket-remove dtype flags or copy them from a local template, nearby model, existing recipe, checkpoint `config.json`, or engine auto-resolution.

## Recipe comparison checklist

Verify every applicable field rather than translating flags by name alone:

- Exact publisher/model repository and checkpoint revision.
- Hardware architecture and GPU count.
- Context length and memory-utilization setting.
- Tensor, pipeline, data, expert, and context parallelism.
- Quantization format, checkpoint metadata, and execution backend.
- Attention, linear-attention, Mamba, and MoE backends.
- Reasoning and tool-call parsers.
- Multimodal limits and feature transport.
- Prefix/radix-cache behavior.
- Speculative algorithm, exact draft repository, block size, draft-token count, and draft revision.
- Environment variables and whether they are current, deprecated, optional, or required.

Never assume equivalent-looking SGLang and vLLM speculative counts have identical semantics. For block-diffusion methods, vLLM may describe the number of speculative tokens while SGLang describes the full verification block. Confirm the mapping from the official cookbook, draft model card/config, and engine source.

## Checkpoint context and embedded position scaling

Determine context from the exact checkpoint's official recipe, model card, and stored configuration as one contract. A `rope_scaling` object shipped in `config.json` is checkpoint state, not a recipe-added long-context override.

When authoritative sources advertise the checkpoint's stored `max_position_embeddings` as trained or supported, use that full maximum. NEVER substitute `original_max_position_embeddings` merely because the config names YaRN, supplies a factor, or records an earlier training window; the original value is a scaling reference, not automatically the serving ceiling.

Distinguish embedded checkpoint metadata from a launch-time `--rope-scaling`, environment override, or reconstructed configuration. Preserve embedded scaling unchanged. Add a runtime scaling mechanism only when authoritative sources for the exact checkpoint and engine explicitly require it; never invent one to exceed the checkpoint's supported maximum.

## Version and validation discipline

Cookbooks generally document current upstream behavior. Compare their commands against the project's pinned engine version or commit before applying them. If current cookbook guidance needs a newer commit or PR, name that dependency.

Distinguish clearly between:

- An on-disk recipe file.
- A command copied from an official cookbook.
- A command reconstructed from source fields.
- A command merely proposed.
- A command actually launched and behaviorally validated.

Do not claim a recipe or flag set works until the intended server starts and the relevant API path is exercised. For speculative decoding, confirm from runtime configuration or logs that the requested draft model and effective draft/block size were selected.

## Reporting

For recipe research answers:

- Lead with the decision.
- Link the exact SGLang cookbook selection and exact vLLM recipe page when available.
- State which source fields support the decision.
- State any cookbook/version mismatch.
- State missing official coverage explicitly.
- Keep inferred behavior labeled as inference until runtime validation proves it.
