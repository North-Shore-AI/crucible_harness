# Changelog

All notable changes to this project will be documented in this file.

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
