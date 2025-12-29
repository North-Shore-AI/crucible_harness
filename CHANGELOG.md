# Changelog

All notable changes to this project will be documented in this file.

## [0.3.3] - 2025-12-28

### Changed
- **Dependency Update:** Updated `telemetry` from `~> 1.2` to `~> 1.3`
- **Code Quality:** Applied comprehensive Credo fixes including alias sorting, complexity reduction, and style improvements.
- **Cleanup:** Removed commented-out dependency declarations for `crucible_ir` and `crucible_framework`

### No Breaking Changes
All existing code continues to work unchanged.

## [0.3.2] - 2025-12-24

### Added
- **TaskState Parity:** Model/epoch/target/choices/scores/limits/tool metadata + `input_text`/`user_prompt` helpers
- **Tool Calling Flow:** Generate solver supports `loop`, `single`, and `none` tool-call handling
- **Tool Definitions:** `CrucibleHarness.Tool` for normalized tool specs and execution

### Changed
- Generate config docs now include `tools` and `tool_choice`
- README/USAGE updated with tool-call examples and new TaskState fields

### Testing
- Added tests for TaskState helpers, choices, tool-call loop, and message-limit completion

## [0.3.1] - 2025-12-23

### Added
- **inspect-ai Parity Modules:** Added execution orchestration patterns inspired by inspect-ai
  - `CrucibleHarness.Solver` - Behaviour for composable execution steps
  - `CrucibleHarness.Solver.Chain` - Sequential solver composition with early termination
  - `CrucibleHarness.Solver.Generate` - Built-in solver for LLM generation
  - `CrucibleHarness.TaskState` - State object threaded through solver pipelines
  - `CrucibleHarness.Generate` - Behaviour for LLM backend implementations

### Features
- **Solver Composition:** Chain multiple solvers into sequential pipelines
- **Early Termination:** Chains stop on errors or when `state.completed` is set
- **Flexible Solver Types:** Support for both module-based and struct-based solvers
- **State Threading:** TaskState carries messages, metadata, and inter-solver communication via store
- **Backend Abstraction:** Generate behaviour allows swapping LLM backends (Tinkex, OpenAI, etc.)

### Documentation
- Added comprehensive inline documentation with examples for all new modules
- Added design specification in `docs/20251223/INSPECT_AI_PARITY_SPEC.md`

### Testing
- Added 80+ new tests covering all solver functionality
- 100% test pass rate with no compilation warnings

### Technical Details
- New modules follow inspect-ai's Solver/TaskState/Generate architecture
- Compatible with existing CrucibleHarness experiment orchestration
- No breaking changes to existing APIs

## [0.3.0] - 2025-11-26

### Changed
- **Dependency Update:** Now depends on `crucible_ir` v0.1.1 for shared IR structs
- **Framework Integration:** Updated to work with `crucible_framework` v0.5.0
- **Module Namespace:** All IR imports updated from `Crucible.IR.*` to `CrucibleIR.*`

### Migration Guide

If you were using internal IR structs (uncommon in typical usage), update your imports:

```elixir
# Before (if you were using internal IR structs)
alias Crucible.IR.{Experiment, BackendRef, StageDef}

# After
alias CrucibleIR.{Experiment, BackendRef, StageDef}
```

For most users, this change is transparent as the harness API remains unchanged.

### Technical Details
- Added `crucible_ir` as a direct dependency for IR struct definitions
- Updated to `crucible_framework` v0.5.0 which now uses `crucible_ir` internally
- No breaking changes to the public API - all DSL macros work identically

## [0.2.0] - 2025-11-25

### Added
- **Lifecycle Hooks System:** Added comprehensive hook support for experiment lifecycle management
  - `before_experiment/1` - Setup operations before experiment starts
  - `after_experiment/1` - Teardown operations after experiment completes
  - `before_condition/1` - Pre-processing before each condition execution
  - `after_condition/1` - Post-processing after each condition execution
  - `on_error/1` - Custom error handling with :retry, :skip, :abort actions
  - New `CrucibleHarness.Hooks.Executor` module for safe hook execution with error handling

- **Error Recovery Framework (Partial):** Foundation for robust error handling
  - Test suite for retry logic with exponential backoff
  - Test suite for error classification (transient vs permanent)
  - Test suite for dead letter queue (DLQ) for failed tasks
  - Test suite for circuit breaker pattern
  - *Implementation of error recovery modules in progress*

- **Metric Validation System (Partial):** Runtime validation of experiment results
  - Test suite for metric schema validation
  - Test suite for type coercion and range checking
  - Test suite for nested schema validation
  - *Implementation of validation modules in progress*

- **Comprehensive Design Document:** Added `docs/20251125/enhancement_design.md`
  - Detailed analysis of 8 major enhancement areas
  - Implementation roadmap with 4 phases
  - API specifications and examples
  - Testing strategy and performance considerations

### Changed
- Updated `CrucibleHarness.Experiment` module to support hook macros
- Extended experiment configuration to include hooks and metric schemas
- Version bump to 0.2.0 reflecting significant new capabilities

### Documentation
- Added detailed design document in `docs/20251125/`
- Updated README.md with version 0.2.0
- Test files documenting expected behavior for new features

### Testing
- Added 3 new comprehensive test files (90+ tests):
  - `test/research_harness/hooks_test.exs` - Lifecycle hooks testing
  - `test/research_harness/errors_test.exs` - Error recovery testing
  - `test/research_harness/validation_test.exs` - Metric validation testing

### Notes
- **Status:** Core infrastructure for Phase 1 enhancements is in place
- **Next Steps:** Complete implementation of error recovery and metric validation modules
- **Backward Compatibility:** All changes are 100% backward compatible - hooks are optional

## [0.1.1] - 2025-10-29

### Fixed
- Fixed Flow pipeline configuration in Runner for proper parallel execution
- Fixed arithmetic errors in statistical analyzer when variance is zero
- Fixed reporter formatters to handle infinity values gracefully
- Removed unused variable warnings in example files

### Added
- Comprehensive test suite with 13 tests covering all major modules
- Integration tests for full experiment workflow
- Runnable example scripts: `run_simple_comparison.exs` and `run_ensemble_comparison.exs`
- Helper functions for safe number formatting in all report generators

### Improved
- Statistical analyzer now handles edge cases (zero variance, equal means)
- Better error handling throughout the codebase
- Enhanced test coverage for Runner, Collector, Reporter, and utilities

## [0.1.0] - 2025-10-07

### Added
- Initial release
- Automated experiment orchestration for large-scale AI research
- Declarative experiment definition with DSL for complex experimental designs
- Parallel execution leveraging BEAM's concurrency for efficient multi-condition runs
- Fault tolerance with checkpointing and resume capabilities
- Automated statistical analysis with significance testing across all condition pairs
- Multi-format reporting (Markdown, LaTeX, HTML, Jupyter notebooks)
- Cost management with estimation and budget controls
- Reproducibility features with version control and controlled random seeds

### Documentation
- Comprehensive README with examples
- API documentation for experiment definition and execution
- Usage examples for parameter sweeps and A/B testing
- Integration guide for research workflow automation
