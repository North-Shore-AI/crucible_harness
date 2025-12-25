defmodule CrucibleHarness.Generate do
  @moduledoc """
  Behaviour for LLM generation backends.

  This behaviour defines the interface for calling language model APIs. Different
  implementations can wrap specific clients like Tinkex, OpenAI, Anthropic, etc.

  ## Implementing a Generator

      defmodule MyBackend.Generate do
        @behaviour CrucibleHarness.Generate

        @impl true
        def generate(messages, config) do
          # Call your LLM API
          case MyAPI.chat_completion(messages, config) do
            {:ok, response} ->
              {:ok, %{
                content: response.text,
                finish_reason: response.stop_reason,
                usage: %{
                  prompt_tokens: response.usage.input_tokens,
                  completion_tokens: response.usage.output_tokens,
                  total_tokens: response.usage.total_tokens
                }
              }}

            {:error, reason} ->
              {:error, reason}
          end
        end
      end

  ## Configuration

  The `config` parameter is a map that should include:

    * `:model` - Model identifier (e.g., "gpt-4", "claude-3-opus")
    * `:temperature` - Sampling temperature (0.0 to 1.0+)
    * `:max_tokens` - Maximum tokens to generate
    * `:stop` - List of stop sequences
    * `:tools` - Optional tool definitions for tool calling
    * `:tool_choice` - Optional tool choice directive

  Additional fields can be included for backend-specific options.

  ## Response Format

  The response should be a map with:

    * `:content` - Generated text content
    * `:finish_reason` - Why generation stopped ("stop", "length", "error", etc.)
    * `:usage` - Map with token usage statistics
    * `:tool_calls` - Optional list of tool call maps

  ## Usage with Solvers

      # Create a generate function that uses your backend
      generate_fn = fn state, config ->
        MyBackend.Generate.generate(state.messages, config)
      end

      # Use with a solver
      solver = CrucibleHarness.Solver.Generate.new(%{
        model: "gpt-4",
        temperature: 0.7,
        max_tokens: 1000,
        stop: []
      })

      {:ok, result_state} = solver.solve(state, generate_fn)

  ## Example Implementations

  ### Tinkex Backend

      defmodule TinkexGenerate do
        @behaviour CrucibleHarness.Generate

        @impl true
        def generate(messages, config) do
          case Tinkex.Sampling.create_sample(
            messages: messages,
            model: config.model,
            temperature: config.temperature,
            max_tokens: config.max_tokens
          ) do
            {:ok, sample} ->
              {:ok, %{
                content: sample.content,
                finish_reason: "stop",
                usage: %{
                  prompt_tokens: sample.usage.prompt_tokens,
                  completion_tokens: sample.usage.completion_tokens,
                  total_tokens: sample.usage.total_tokens
                }
              }}

            error -> error
          end
        end
      end

  ### Mock Backend for Testing

      defmodule MockGenerate do
        @behaviour CrucibleHarness.Generate

        @impl true
        def generate(messages, _config) do
          last_msg = List.last(messages)
          {:ok, %{
            content: "Mock response to: \#{last_msg.content}",
            finish_reason: "stop",
            usage: %{
              prompt_tokens: 10,
              completion_tokens: 20,
              total_tokens: 30
            }
          }}
        end
      end
  """

  @type config :: %{
          optional(:model) => String.t(),
          optional(:temperature) => float(),
          optional(:max_tokens) => pos_integer(),
          optional(:stop) => [String.t()],
          optional(:tools) => [CrucibleHarness.Tool.t() | map()],
          optional(:tool_choice) => term(),
          optional(atom()) => any()
        }

  @type response :: %{
          required(:content) => String.t(),
          required(:finish_reason) => String.t(),
          required(:usage) => map(),
          optional(:tool_calls) => [map()],
          optional(atom()) => any()
        }

  @doc """
  Generates text from the language model.

  ## Parameters

    * `messages` - List of message maps with `:role` and `:content` keys
    * `config` - Configuration map with model parameters

  ## Returns

    * `{:ok, response}` - Successfully generated response
    * `{:error, reason}` - Error occurred during generation

  ## Examples

      messages = [
        %{role: "system", content: "You are helpful"},
        %{role: "user", content: "What is 2+2?"}
      ]

      config = %{
        model: "gpt-4",
        temperature: 0.7,
        max_tokens: 100,
        stop: []
      }

      {:ok, response} = MyBackend.generate(messages, config)
      # => %{
      #   content: "2+2 equals 4",
      #   finish_reason: "stop",
      #   usage: %{prompt_tokens: 15, completion_tokens: 8, total_tokens: 23}
      # }
  """
  @callback generate(messages :: [map()], config :: config()) ::
              {:ok, response()} | {:error, term()}
end
