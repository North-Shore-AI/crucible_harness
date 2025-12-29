defmodule CrucibleHarness.Reporter do
  @moduledoc """
  Generates reports in multiple formats (Markdown, LaTeX, HTML, Jupyter).
  """

  alias CrucibleHarness.Reporter.{
    HTMLGenerator,
    JupyterGenerator,
    LaTeXGenerator,
    MarkdownGenerator
  }

  @doc """
  Generates a report in the specified format.

  Supported formats: :markdown, :latex, :html, :jupyter
  """
  def generate(config, analysis, format) do
    case format do
      :markdown -> MarkdownGenerator.generate(config, analysis)
      :latex -> LaTeXGenerator.generate(config, analysis)
      :html -> HTMLGenerator.generate(config, analysis)
      :jupyter -> JupyterGenerator.generate(config, analysis)
      :md -> MarkdownGenerator.generate(config, analysis)
      :tex -> LaTeXGenerator.generate(config, analysis)
      :ipynb -> JupyterGenerator.generate(config, analysis)
      _ -> raise ArgumentError, "Unsupported format: #{format}"
    end
  end

  @doc """
  Generates reports in all supported formats.
  """
  def generate_all(config, analysis) do
    formats = [:markdown, :latex, :html, :jupyter]

    Enum.map(formats, fn format ->
      {format, generate(config, analysis, format)}
    end)
    |> Map.new()
  end
end
