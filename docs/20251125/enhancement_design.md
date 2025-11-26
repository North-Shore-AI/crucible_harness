# Crucible Harness Enhancement Design Document

**Date:** 2025-11-25
**Version:** 0.2.0 (Target)
**Author:** Claude Code Analysis
**Status:** Design Proposal

---

## Executive Summary

This document outlines proposed enhancements to the Crucible Harness experiment orchestration framework. After thorough analysis of the codebase, we've identified key areas for improvement that will enhance the framework's robustness, usability, and research capabilities while maintaining backward compatibility.

### Key Enhancement Areas

1. **Experiment Lifecycle Hooks** - Pre/post execution callbacks
2. **Enhanced Progress Monitoring** - Real-time streaming and web dashboard support
3. **Improved Checkpointing** - Incremental saves with metadata
4. **Dataset Integration** - Better sampling strategies and validation
5. **Error Recovery** - Automatic retry with exponential backoff
6. **Metric Validation** - Runtime checking of metric completeness
7. **Parallel Experiment Comparison** - Multi-experiment meta-analysis
8. **Enhanced Statistical Methods** - Bootstrap confidence intervals and non-parametric tests

---

## 1. Current State Analysis

### Strengths
- Clean DSL for experiment definition
- Solid statistical analysis foundation (t-tests, effect sizes)
- Multi-format reporting (Markdown, LaTeX, HTML, Jupyter)
- Rate limiting and progress tracking
- Cost estimation
- Basic checkpointing

### Identified Gaps

#### 1.1 Missing Lifecycle Management
- No hooks for setup/teardown operations
- No pre-condition or post-condition validation
- Cannot inject custom behavior at key execution points

#### 1.2 Limited Progress Observability
- Progress tracking exists but is tied to console output
- No web dashboard or API for external monitoring
- Cannot stream progress to external systems (Weights & Biases, MLflow)

#### 1.3 Checkpoint Limitations
- Checkpoints save all-or-nothing state
- No incremental checkpointing during long runs
- Missing checkpoint metadata (versions, git commit, environment)
- No checkpoint cleanup/rotation policies

#### 1.4 Dataset Handling Gaps
- Mock dataset implementation only
- No stratified sampling or cross-validation splits
- No dataset validation or schema checking
- Cannot handle streaming datasets

#### 1.5 Error Handling Weaknesses
- Single retry attempt per task
- No exponential backoff for transient failures
- No dead letter queue for permanently failed tasks
- Missing error classification (transient vs permanent)

#### 1.6 Metric Validation Absent
- No validation that conditions return expected metrics
- Runtime failures if metrics are missing
- No type checking for metric values
- Cannot enforce metric schemas

#### 1.7 Limited Analysis Capabilities
- Only pairwise t-tests available
- No bootstrap confidence intervals
- No non-parametric alternatives (Mann-Whitney, Kruskal-Wallis)
- Cannot compare multiple experiments (meta-analysis)
- No power analysis for sample size determination

#### 1.8 Configuration Management
- No environment-specific configurations
- Cannot override config at runtime easily
- No configuration validation beyond basic checks

---

## 2. Proposed Enhancements

### Enhancement 1: Experiment Lifecycle Hooks

**Rationale:** Researchers need to perform setup (initialize models, warm up caches) and teardown (cleanup resources, save artifacts) operations around experiments.

**Design:**

```elixir
defmodule MyExperiment do
  use CrucibleHarness.Experiment

  name "Experiment with Hooks"

  # New hook macros
  before_experiment fn config ->
    # Called once before experiment starts
    # Can modify config or set up resources
    {:ok, %{config | metadata: Map.put(config.metadata, :git_sha, get_git_sha())}}
  end

  after_experiment fn config, results ->
    # Called once after experiment completes
    # Can save artifacts, send notifications
    upload_to_s3(results)
    :ok
  end

  before_condition fn condition, query ->
    # Called before each condition execution
    # Can inject logging, monitoring
    Logger.metadata(condition: condition.name)
    :ok
  end

  after_condition fn condition, query, result ->
    # Called after each condition execution
    # Can validate results, log metrics
    emit_telemetry(condition, result)
    :ok
  end

  on_error fn condition, query, error ->
    # Called when a condition fails
    # Can implement custom retry logic or logging
    Logger.error("Condition #{condition.name} failed: #{inspect(error)}")
    :retry  # or :skip, :abort
  end
end
```

**Implementation Plan:**
- Add hook attributes to `Experiment` module
- Modify `Runner` to call hooks at appropriate points
- Add error handling for hook failures (hooks should not crash experiments)
- Document hook signatures and return values

**Testing:**
- Test hooks are called in correct order
- Test hook errors don't crash experiment
- Test hooks can modify configuration
- Test on_error hook retry logic

---

### Enhancement 2: Enhanced Progress Monitoring

**Rationale:** External systems (web dashboards, CI/CD) need structured progress data.

**Design:**

```elixir
# New ProgressMonitor module with pluggable backends

# Configuration
config %{
  progress_monitors: [
    {CrucibleHarness.Monitor.Console, []},
    {CrucibleHarness.Monitor.WebSocket, port: 4000},
    {CrucibleHarness.Monitor.MLflow, uri: "http://localhost:5000"},
    {CrucibleHarness.Monitor.Telemetry, prefix: [:my_exp]}
  ]
}

# Monitor behaviour
defmodule CrucibleHarness.Monitor do
  @callback init(opts :: keyword()) :: {:ok, state :: any()} | {:error, reason :: any()}
  @callback on_start(experiment_id, config, state) :: {:ok, state}
  @callback on_progress(progress_update, state) :: {:ok, state}
  @callback on_complete(results, analysis, state) :: {:ok, state}
  @callback on_error(error, state) :: {:ok, state}
end

# Progress updates include:
%{
  experiment_id: "exp_123",
  completed: 150,
  total: 400,
  progress_pct: 37.5,
  current_condition: "treatment",
  estimated_completion: ~U[2025-11-25 15:30:00Z],
  throughput: 5.2,  # tasks per second
  errors: 2,
  retries: 5,
  current_metrics: %{accuracy: 0.85, latency: 123}
}
```

**Implementation Plan:**
- Create `CrucibleHarness.Monitor` behaviour
- Implement console, WebSocket, and Telemetry backends
- Modify `ProgressTracker` to broadcast to all monitors
- Add configuration for enabling/disabling monitors

**Testing:**
- Test each monitor backend independently
- Test multiple monitors can run simultaneously
- Test monitor failures don't crash experiment
- Test progress data completeness

---

### Enhancement 3: Improved Checkpointing

**Rationale:** Long-running experiments need reliable recovery with full context.

**Design:**

```elixir
# Enhanced checkpoint structure
%{
  # Existing fields
  experiment_id: "exp_123",
  timestamp: ~U[2025-11-25 14:30:00Z],
  completed_results: [...],
  remaining_tasks: [...],
  random_state: {...},

  # New fields
  version: "0.2.0",  # Framework version
  config_snapshot: config,  # Full config at checkpoint time
  environment: %{
    git_sha: "abc123",
    git_dirty: false,
    elixir_version: "1.14.0",
    otp_version: "25.0",
    hostname: "research-node-01",
    pid: 12345
  },
  metrics_summary: %{
    total_queries: 1000,
    successful: 950,
    failed: 45,
    retried: 35,
    elapsed_ms: 45000
  },
  checkpoint_number: 5,  # Incremental checkpoint counter
  checkpoint_strategy: :time,  # or :task_count
  parent_checkpoint: "exp_123_checkpoint_4"  # For rollback
}

# Configuration
config %{
  checkpointing: %{
    enabled: true,
    strategy: :time,  # :time, :task_count, or :both
    interval_ms: 60_000,  # Checkpoint every minute
    interval_tasks: 100,  # Or every 100 tasks
    max_checkpoints: 5,  # Keep last 5 checkpoints
    compression: :gzip,  # Compress checkpoint files
    async: true  # Don't block experiment for checkpoints
  }
}
```

**Implementation Plan:**
- Extend `CheckpointManager` with enhanced metadata
- Add incremental checkpointing logic to `Runner`
- Implement checkpoint rotation (keep last N)
- Add checkpoint validation on restore
- Support async checkpointing (non-blocking)

**Testing:**
- Test checkpoint creation and restoration
- Test checkpoint rotation
- Test async checkpointing doesn't lose data
- Test restoration from old checkpoints

---

### Enhancement 4: Dataset Integration

**Rationale:** Real experiments need robust dataset handling with validation.

**Design:**

```elixir
defmodule CrucibleHarness.Dataset do
  @callback load(config :: map()) :: {:ok, dataset} | {:error, reason}
  @callback sample(dataset, strategy :: atom(), opts :: keyword()) :: {:ok, sample}
  @callback validate(dataset, schema :: map()) :: :ok | {:error, errors}
end

# Example usage
dataset :mmlu_200
dataset_config %{
  loader: CrucibleDatasets.MMLU,  # From crucible_datasets
  sample_size: 200,
  sampling_strategy: :stratified,  # :random, :stratified, :weighted
  stratify_by: :subject,
  random_seed: 42,
  validation: %{
    required_fields: [:question, :choices, :answer],
    field_types: %{
      question: :string,
      choices: {:list, :string},
      answer: :integer
    }
  },
  preprocessing: [
    {Preprocessor.Tokenize, max_length: 512},
    {Preprocessor.Normalize, method: :lowercase}
  ]
}

# Cross-validation support
dataset_config %{
  cv_strategy: :k_fold,
  folds: 5,
  current_fold: 1  # Run experiments per fold
}
```

**Implementation Plan:**
- Create `CrucibleHarness.Dataset` behaviour
- Implement stratified and weighted sampling
- Add dataset validation with schemas
- Integrate with `crucible_datasets` package
- Support cross-validation splits

**Testing:**
- Test different sampling strategies produce expected distributions
- Test dataset validation catches errors
- Test cross-validation split generation
- Test integration with crucible_datasets

---

### Enhancement 5: Error Recovery with Retry Logic

**Rationale:** Transient errors (network, rate limits) shouldn't fail experiments.

**Design:**

```elixir
config %{
  error_handling: %{
    retry_strategy: :exponential_backoff,
    max_retries: 3,
    initial_delay_ms: 1000,
    max_delay_ms: 30_000,
    backoff_factor: 2.0,
    jitter: true,  # Add randomness to prevent thundering herd

    # Error classification
    retryable_errors: [
      :timeout,
      :connection_refused,
      :rate_limited,
      {:http_status, 429},
      {:http_status, 503}
    ],

    permanent_errors: [
      :invalid_query,
      :authentication_failed,
      {:http_status, 401}
    ],

    # Dead letter queue for permanent failures
    dlq_enabled: true,
    dlq_path: "./failed_tasks.jsonl",

    # Failure threshold
    max_failure_rate: 0.1,  # Abort if >10% tasks fail
    failure_window: 100  # Over last 100 tasks
  }
}

# Task result now includes retry info
%{
  experiment_id: "exp_123",
  condition: "treatment",
  query_id: "q_456",
  result: {:ok, %{...}},  # or {:error, reason}
  attempts: 2,
  retry_delays: [1000, 2000],
  final_status: :success,  # :success, :failed_permanent, :failed_retries_exhausted
  elapsed_time: 3500,
  error_history: [
    %{attempt: 1, error: :timeout, timestamp: ~U[...]},
    %{attempt: 2, error: nil, timestamp: ~U[...]}
  ]
}
```

**Implementation Plan:**
- Add retry logic to `Runner.execute_task/1`
- Implement exponential backoff with jitter
- Create error classifier (transient vs permanent)
- Add dead letter queue for permanently failed tasks
- Add circuit breaker to stop experiment if failure rate too high

**Testing:**
- Test retry logic with transient errors
- Test exponential backoff timing
- Test circuit breaker triggers
- Test DLQ captures failed tasks
- Test permanent errors aren't retried

---

### Enhancement 6: Metric Validation

**Rationale:** Catch metric errors early rather than at analysis time.

**Design:**

```elixir
# Declare metric schemas
metrics [:accuracy, :latency, :cost]

metric_schemas %{
  accuracy: %{
    type: :float,
    min: 0.0,
    max: 1.0,
    required: true
  },
  latency: %{
    type: :number,
    min: 0,
    unit: :milliseconds,
    required: true
  },
  cost: %{
    type: :float,
    min: 0.0,
    required: false,
    default: 0.0
  },
  custom_metric: %{
    type: :map,
    schema: %{
      value: {:number, min: 0},
      confidence: {:float, min: 0.0, max: 1.0}
    }
  }
}

# Validation happens automatically after each condition execution
# Invalid results are logged and optionally retried
config %{
  metric_validation: %{
    enabled: true,
    on_invalid: :log_and_continue,  # :log_and_continue, :log_and_retry, :abort
    coerce_types: true  # Try to convert "0.85" -> 0.85
  }
}
```

**Implementation Plan:**
- Add `MetricValidator` module
- Define schema DSL for metrics
- Validate results after each condition execution
- Add coercion for common type errors
- Log validation errors with context

**Testing:**
- Test validation catches type errors
- Test validation catches range errors
- Test validation handles missing required metrics
- Test coercion works correctly
- Test on_invalid strategies

---

### Enhancement 7: Enhanced Statistical Methods

**Rationale:** Researchers need more statistical rigor and flexibility.

**Design:**

```elixir
statistical_analysis %{
  # Existing options
  significance_level: 0.05,
  confidence_interval: 0.95,
  multiple_testing_correction: :bonferroni,

  # New options
  methods: [
    :t_test,  # Existing
    :welch_t_test,  # Existing (unequal variances)
    :mann_whitney,  # New: non-parametric alternative
    :wilcoxon,  # New: paired non-parametric
    :bootstrap  # New: bootstrap confidence intervals
  ],

  bootstrap_config: %{
    n_iterations: 10_000,
    confidence_level: 0.95,
    random_seed: 42,
    method: :percentile  # or :bca (bias-corrected accelerated)
  },

  effect_sizes: [
    :cohens_d,  # Existing
    :glass_delta,  # New: uses control group SD only
    :hedges_g,  # New: corrected for small samples
    :common_language_effect  # New: probability of superiority
  ],

  normality_tests: %{
    enabled: true,
    methods: [:shapiro_wilk, :anderson_darling],
    auto_select_test: true  # Use parametric if normal, non-parametric otherwise
  },

  power_analysis: %{
    enabled: true,
    target_power: 0.8,
    estimate_sample_size: true
  }
}
```

**Implementation Plan:**
- Extend `StatisticalAnalyzer` with new tests
- Implement bootstrap confidence intervals
- Add normality testing
- Implement additional effect size measures
- Add power analysis calculations
- Auto-select parametric vs non-parametric based on normality

**Testing:**
- Test each statistical method with known data
- Test bootstrap produces accurate CIs
- Test normality tests work correctly
- Test auto-selection of appropriate tests
- Test power analysis calculations

---

### Enhancement 8: Parallel Experiment Comparison

**Rationale:** Compare results across multiple experiments (meta-analysis).

**Design:**

```elixir
# New API for comparing experiments
CrucibleHarness.compare([
  "exp_123",  # Experiment IDs or modules
  "exp_456",
  MyExperiment3
], opts)

# Generates comparison report showing:
# - Which conditions appeared in multiple experiments
# - Meta-analysis across experiments (effect size aggregation)
# - Heterogeneity tests (I² statistic)
# - Forest plots of effect sizes
# - Consistency checks

# Output:
%{
  experiments: [
    %{id: "exp_123", name: "Baseline Study", date: ~D[2025-11-20]},
    %{id: "exp_456", name: "Follow-up Study", date: ~D[2025-11-24]}
  ],
  common_conditions: ["baseline", "treatment_a"],
  meta_analysis: %{
    metric: :accuracy,
    pooled_effect_size: 0.45,
    ci_lower: 0.32,
    ci_upper: 0.58,
    heterogeneity_i2: 0.23,  # Low heterogeneity
    tau_squared: 0.01,
    p_value: 0.0001
  },
  forest_plot_data: [...]
}
```

**Implementation Plan:**
- Create `CrucibleHarness.MetaAnalysis` module
- Load and parse multiple experiment results
- Implement fixed and random effects models
- Calculate heterogeneity statistics (I², τ²)
- Generate forest plot data
- Add meta-analysis report generator

**Testing:**
- Test meta-analysis with known effect sizes
- Test heterogeneity calculations
- Test handling of different sample sizes
- Test missing data handling

---

## 3. Implementation Strategy

### Phase 1: Foundation (Week 1)
**Priority: High**
- Enhancement 1: Lifecycle Hooks
- Enhancement 5: Error Recovery
- Enhancement 6: Metric Validation

These provide immediate value and don't depend on other enhancements.

### Phase 2: Observability (Week 2)
**Priority: High**
- Enhancement 2: Progress Monitoring
- Enhancement 3: Improved Checkpointing

These build on Phase 1 and significantly improve reliability.

### Phase 3: Data & Analysis (Week 3)
**Priority: Medium**
- Enhancement 4: Dataset Integration
- Enhancement 7: Enhanced Statistical Methods

These provide deeper research capabilities.

### Phase 4: Advanced Features (Week 4)
**Priority: Low**
- Enhancement 8: Parallel Experiment Comparison

This is a nice-to-have for advanced users.

---

## 4. Backward Compatibility

**Guarantee:** All enhancements will be **100% backward compatible** with existing experiments.

**Strategy:**
- All new features are opt-in (require explicit configuration)
- Default behavior unchanged for existing code
- New macros/functions don't conflict with existing ones
- Deprecation warnings for any breaking changes (none planned)
- Version detection in checkpoints for forward compatibility

**Example:**
```elixir
# Existing experiment - works exactly the same
defmodule MyExperiment do
  use CrucibleHarness.Experiment
  name "Old Experiment"
  conditions [...]
  metrics [...]
end

# New experiment with enhancements - all optional
defmodule MyNewExperiment do
  use CrucibleHarness.Experiment
  name "New Experiment"
  conditions [...]
  metrics [...]

  # Optional: add hooks
  before_experiment fn config -> {:ok, config} end

  # Optional: enhanced config
  config %{
    error_handling: %{max_retries: 3}  # Defaults to 0 if not specified
  }
end
```

---

## 5. Testing Strategy

### Test Coverage Goals
- **Target:** 95%+ line coverage
- **Current:** ~85% (estimated from test file)

### Test Types

#### Unit Tests
- Each new module has comprehensive unit tests
- Test both success and error paths
- Test edge cases (empty data, nil values, etc.)
- Use property-based testing where appropriate (retry logic, statistical methods)

#### Integration Tests
- Test full experiment lifecycle with new features
- Test hook execution order
- Test checkpoint save/restore with new fields
- Test error recovery in realistic scenarios

#### Performance Tests
- Test that overhead of new features is minimal (<5%)
- Test checkpoint write performance with large datasets
- Test progress monitoring doesn't slow execution

#### Regression Tests
- Run existing test suite with new code
- Ensure existing experiments produce same results
- Test backward compatibility of checkpoints

---

## 6. Documentation Updates

### API Documentation
- Document all new macros and functions
- Add examples for each enhancement
- Document configuration options
- Add migration guide for new features

### Guides
- "Getting Started with Lifecycle Hooks"
- "Setting Up Progress Monitoring"
- "Advanced Error Handling Strategies"
- "Statistical Method Selection Guide"
- "Meta-Analysis with Multiple Experiments"

### Examples
- Update existing examples with new features
- Add new examples showcasing each enhancement
- Create "recipes" for common patterns

---

## 7. Performance Considerations

### Memory
- **Checkpointing:** Async writing prevents blocking, compression reduces size
- **Progress Monitoring:** Batch updates to reduce overhead
- **Error Recovery:** Dead letter queue prevents memory accumulation

### CPU
- **Metric Validation:** Validation in parallel with next task execution
- **Statistical Methods:** Bootstrap can be parallelized
- **Hooks:** Hook execution time included in timeout

### I/O
- **Checkpointing:** Write to temp file then atomic rename
- **DLQ:** Append-only writes, async
- **Logs:** Buffer writes, configurable log levels

**Benchmarks:**
- Target: <5% overhead for new features
- Measure with and without enhancements enabled
- Profile hot paths

---

## 8. Security & Safety Considerations

### Checkpoint Safety
- Validate checkpoints before loading (schema, version, checksums)
- Sanitize paths to prevent directory traversal
- Encrypt sensitive data in checkpoints (API keys, credentials)

### Hook Safety
- Hooks run in try/catch to prevent crashes
- Timeout for hooks (configurable)
- Hooks cannot access internal state directly

### Monitor Safety
- Monitor failures don't crash experiment
- Rate limiting for monitor callbacks
- Validate monitor configuration

### Dataset Safety
- Validate dataset schemas before use
- Sanitize user-provided preprocessing code
- Limit dataset size to prevent memory exhaustion

---

## 9. Migration Path

### For Users
1. **Version 0.1.x → 0.2.0:** No code changes required
2. **Opt-in to new features:** Add configuration as desired
3. **Test with dry-run:** Validate before production

### For Contributors
1. **Read this design doc**
2. **Review implementation PRs**
3. **Update related documentation**
4. **Add tests for your changes**

---

## 10. Success Metrics

### Adoption
- % of experiments using new features (track via telemetry)
- GitHub stars, downloads (hex.pm)
- Community feedback (issues, PRs)

### Quality
- Test coverage: 95%+
- Zero critical bugs in first month
- Performance overhead <5%

### Impact
- Reduced experiment failures (error recovery)
- Faster debugging (progress monitoring, hooks)
- More rigorous research (enhanced statistics)

---

## 11. Future Work (Beyond 0.2.0)

### Distributed Execution
- Run experiments across multiple machines
- Distributed checkpointing and result aggregation
- Leader election for coordination

### Real-time Dashboards
- Web UI for monitoring experiments
- Live visualization of results
- Experiment management (pause, resume, abort)

### AutoML Integration
- Hyperparameter optimization
- Automatic condition generation
- Neural architecture search

### Cloud Integration
- S3/GCS for checkpoints and results
- Kubernetes operator for deployment
- Serverless execution (AWS Lambda, GCP Cloud Functions)

---

## 12. Conclusion

These enhancements will significantly improve the Crucible Harness framework while maintaining its core simplicity and elegance. The phased implementation approach allows for iterative development and testing, ensuring high quality at each stage.

### Next Steps
1. ✅ Complete this design document
2. 🔲 Review with stakeholders
3. 🔲 Implement Phase 1 enhancements with TDD
4. 🔲 Release 0.2.0 with comprehensive testing
5. 🔲 Gather feedback and iterate

---

## Appendix A: API Changes Summary

### New Macros
- `before_experiment/1`
- `after_experiment/1`
- `before_condition/1`
- `after_condition/1`
- `on_error/1`
- `metric_schemas/1`

### New Functions
- `CrucibleHarness.compare/2` - Meta-analysis
- `CrucibleHarness.Monitor` - New behaviour
- `CrucibleHarness.Dataset` - New behaviour
- `CrucibleHarness.MetaAnalysis.*` - New module

### Extended Configuration
- `progress_monitors` - List of monitor backends
- `checkpointing` - Enhanced checkpoint options
- `error_handling` - Retry and DLQ configuration
- `metric_validation` - Metric schema validation
- `bootstrap_config` - Bootstrap CI configuration
- `normality_tests` - Statistical test selection

### Backward Compatible
All existing experiments work without modification.

---

## Appendix B: File Structure Changes

```
lib/
  research_harness/
    # Existing (modified)
    experiment.ex              ← Add hook macros
    runner.ex                  ← Add retry logic
    collector/
      statistical_analyzer.ex  ← Add bootstrap, non-parametric tests
    utilities/
      checkpoint_manager.ex    ← Add enhanced metadata

    # New modules
    hooks/
      executor.ex             ← Hook execution engine
      lifecycle.ex            ← Lifecycle management
    monitor/
      behaviour.ex            ← Monitor behaviour
      console.ex              ← Console monitor
      telemetry.ex            ← Telemetry monitor
      websocket.ex            ← WebSocket monitor
    dataset/
      behaviour.ex            ← Dataset behaviour
      sampler.ex              ← Sampling strategies
      validator.ex            ← Schema validation
    errors/
      classifier.ex           ← Error classification
      retry.ex                ← Retry logic
      dlq.ex                  ← Dead letter queue
    validation/
      metric_validator.ex     ← Metric validation
      schema.ex               ← Schema definitions
    meta_analysis/
      analyzer.ex             ← Meta-analysis engine
      forest_plot.ex          ← Forest plot generation
      heterogeneity.ex        ← Heterogeneity stats

test/
  research_harness/
    hooks_test.exs
    monitor_test.exs
    dataset_test.exs
    errors_test.exs
    validation_test.exs
    meta_analysis_test.exs
```

---

**End of Design Document**
