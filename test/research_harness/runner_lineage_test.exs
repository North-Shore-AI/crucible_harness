defmodule CrucibleHarness.RunnerLineageTest do
  use ExUnit.Case, async: true

  alias CrucibleHarness.Runner

  test "emits telemetry metadata with lineage dimensions" do
    handler_id = "lineage-handler-#{System.unique_integer([:positive])}"

    test_pid = self()

    :telemetry.attach(
      handler_id,
      [:research_harness, :task, :complete],
      fn _event, _measurements, metadata, pid ->
        send(pid, {:telemetry_metadata, metadata})
      end,
      test_pid
    )

    on_exit(fn ->
      :telemetry.detach(handler_id)
    end)

    config = %{
      experiment_id: "exp-lineage",
      dataset: :test_dataset,
      dataset_config: %{sample_size: 1},
      conditions: [
        %{name: "baseline", fn: fn _query -> %{accuracy: 1.0} end}
      ],
      metrics: [:accuracy],
      repeat: 1,
      config: %{timeout: 1_000, max_parallel: 1}
    }

    lineage = %{
      trace_id: "trace-1",
      work_id: "work-1",
      plan_id: "plan-1",
      step_id: "step-1"
    }

    assert {:ok, _results} = Runner.run_experiment(config, lineage: lineage)

    assert_receive {:telemetry_metadata, metadata}
    assert metadata.trace_id == "trace-1"
    assert metadata.work_id == "work-1"
    assert metadata.plan_id == "plan-1"
    assert metadata.step_id == "step-1"
  end
end
