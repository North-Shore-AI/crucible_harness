defmodule CrucibleHarness.MixProject do
  use Mix.Project

  @version "0.3.3"
  @source_url "https://github.com/North-Shore-AI/crucible_harness"

  def project do
    [
      app: :crucible_harness,
      version: @version,
      elixir: "~> 1.14",
      start_permanent: Mix.env() == :prod,
      deps: deps(),
      description: description(),
      package: package(),
      docs: docs(),
      source_url: @source_url,
      homepage_url: @source_url,
      name: "CrucibleHarness"
    ]
  end

  def application do
    [
      extra_applications: [:logger]
    ]
  end

  defp deps do
    [
      # Core Dependencies
      {:gen_stage, "~> 1.2"},
      {:flow, "~> 1.2"},
      {:jason, "~> 1.4"},
      {:nimble_csv, "~> 1.2"},
      {:statistex, "~> 1.0"},
      {:telemetry, "~> 1.3"},

      # Development and Testing
      {:ex_doc, "~> 0.31", only: :dev, runtime: false},
      {:dialyxir, "~> 1.4", only: [:dev], runtime: false},
      {:credo, "~> 1.7", only: [:dev, :test], runtime: false}
    ]
  end

  defp description do
    "Experimental research framework for running AI benchmarks at scale. Provides orchestration, streaming processing with Flow/GenStage, and statistical analysis."
  end

  defp package do
    [
      name: "crucible_harness",
      description: description(),
      files: ~w(lib mix.exs README.md CHANGELOG.md LICENSE),
      licenses: ["MIT"],
      links: %{
        "GitHub" => @source_url,
        "Online documentation" => "https://hexdocs.pm/crucible_harness"
      },
      maintainers: ["nshkrdotcom"]
    ]
  end

  defp docs do
    [
      main: "readme",
      name: "CrucibleHarness",
      source_ref: "v#{@version}",
      source_url: @source_url,
      homepage_url: @source_url,
      extras: ["README.md", "CHANGELOG.md"],
      assets: %{"assets" => "assets"},
      logo: "assets/crucible_harness.svg",
      before_closing_head_tag: &mermaid_config/1
    ]
  end

  defp mermaid_config(:html) do
    """
    <script defer src="https://cdn.jsdelivr.net/npm/mermaid@10.2.3/dist/mermaid.min.js"></script>
    <script>
      let initialized = false;

      window.addEventListener("exdoc:loaded", () => {
        if (!initialized) {
          mermaid.initialize({
            startOnLoad: false,
            theme: document.body.className.includes("dark") ? "dark" : "default"
          });
          initialized = true;
        }

        let id = 0;
        for (const codeEl of document.querySelectorAll("pre code.mermaid")) {
          const preEl = codeEl.parentElement;
          const graphDefinition = codeEl.textContent;
          const graphEl = document.createElement("div");
          const graphId = "mermaid-graph-" + id++;
          mermaid.render(graphId, graphDefinition).then(({svg, bindFunctions}) => {
            graphEl.innerHTML = svg;
            bindFunctions?.(graphEl);
            preEl.insertAdjacentElement("afterend", graphEl);
            preEl.remove();
          });
        }
      });
    </script>
    """
  end

  defp mermaid_config(_), do: ""
end
