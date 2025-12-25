# CrucibleHarness: Inspect-AI Parity Requirements (2025-12-24)

Purpose: document the solver/task-state functionality required to reproduce
inspect-ai behavior used by the Python tinker-cookbook, and map it to current
CrucibleHarness modules.

## Python Sources (line referenced)

Inspect-AI solver stack:
- `tinkex_cookbook/inspect_ai/src/inspect_ai/solver/_task_state.py:137-233`
  TaskState core fields (model, sample_id, epoch, input, messages, target,
  choices, output, limits, metadata, store, scores).
- `tinkex_cookbook/inspect_ai/src/inspect_ai/solver/_solver.py:267-293`
  `generate()` solver and tool-call loop options.
- `tinkex_cookbook/inspect_ai/src/inspect_ai/solver/_chain.py:12-90`
  chain solver behavior (early stop on `state.completed`).
- `tinkex_cookbook/inspect_ai/src/inspect_ai/model/_model.py:215-223`
  `ModelAPI.generate(input, tools, tool_choice, config)` signature.

Cookbook usage:
- `tinkex_cookbook/tinker-cookbook/tinker_cookbook/eval/inspect_utils.py:57-156`
  ModelAPI wrapper used by the cookbook eval runner.
- `tinkex_cookbook/tinker-cookbook/tinker_cookbook/eval/custom_inspect_task.py:58-68`
  example task using `generate()` solver.

## Current CrucibleHarness Coverage (Elixir)

- `../crucible_harness/lib/research_harness/task_state.ex:1-160`
  `CrucibleHarness.TaskState` struct with `sample_id`, `input`, `messages`,
  `output`, `completed`, `metadata`, `store`.
- `../crucible_harness/lib/research_harness/solver.ex:1-109`
  `CrucibleHarness.Solver` behaviour and `solve/2`.
- `../crucible_harness/lib/research_harness/generate.ex:1-172`
  `CrucibleHarness.Generate` behaviour (`generate/2`).
- `../crucible_harness/lib/research_harness/solver/generate.ex:1-182`
  `CrucibleHarness.Solver.Generate` wrapper solver.
- `../crucible_harness/lib/research_harness/solver/chain.ex:1-136`
  `CrucibleHarness.Solver.Chain` sequential composition + early stop.

## Required Functionality for Full Parity

To run inspect-ai style tasks (including inspect_evals tasks referenced in the
cookbook), CrucibleHarness must support:

1. TaskState feature parity
   - Required fields: `model`, `sample_id`, `epoch`, `input`, `messages`,
     `target`, `choices`, `output`, `message_limit`, `token_limit`,
     `completed`, `metadata`, `store`, `scores`.
   - Helpers: `input_text`, `user_prompt`, and helpers for tool calls.
   - Reference: `inspect_ai/solver/_task_state.py:137-233`.

2. Tool-call aware generate flow
   - Inspect-ai passes `tools` and `tool_choice` into `ModelAPI.generate/4`
     and can loop tool calls in the generate solver.
   - Reference: `inspect_ai/model/_model.py:215-223`,
     `inspect_ai/solver/_solver.py:267-293`.

3. Chain semantics
   - Early termination on `state.completed`, and solver sequencing.
   - Reference: `inspect_ai/solver/_chain.py:12-90`.

## Status (v0.3.2)

- TaskState now includes `model`, `epoch`, `target`, `choices`, `scores`, limits,
  tool metadata, and helper functions like `input_text` / `user_prompt`.
- Generate solver supports tool-call loops (`loop`, `single`, `none`) with
  tool execution and message limit checks.
- Generate behaviour accepts tool definitions and tool choice via config.

## Remaining Gaps

- No transcript / solver event logging (inspect-ai does this in the solver loop).

## Integration Contracts (needed outside this lib)

CrucibleHarness is used by:
- `tinkex_cookbook` generation adapter
  (`tinkex_cookbook/lib/tinkex_cookbook/eval/tinkex_generate.ex:61-179`).
- `EvalEx` tasks and scorers (TaskState passed to solvers for scoring flows).

These integrations need a richer TaskState and tool-call aware generate pipeline
to match inspect-ai parity.

## Suggested Tests (parity-focused)

- TaskState initialization mirrors inspect-ai semantics for:
  - `input_text` and user prompt extraction.
  - `choices` shuffle and mapping.
- Solver.Chain halts when `completed` is true (already true, add tests).
- Generate solver supports tool-call loop (new tests once implemented).
