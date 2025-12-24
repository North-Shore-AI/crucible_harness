defmodule CrucibleHarness.GenerateTest do
  use ExUnit.Case, async: true

  alias CrucibleHarness.Generate

  # Mock implementation of Generate behaviour
  defmodule MockGenerate do
    @behaviour Generate

    @impl true
    def generate(messages, config) do
      # Simple mock that echoes the last user message
      last_user_msg = Enum.find(Enum.reverse(messages), &(&1.role == "user"))

      response = %{
        content: "Mock response to: #{last_user_msg.content}",
        finish_reason: "stop",
        usage: %{
          prompt_tokens: 10,
          completion_tokens: 15,
          total_tokens: 25
        }
      }

      # Store config for testing
      send(self(), {:generate_called, config})

      {:ok, response}
    end
  end

  defmodule ErrorGenerate do
    @behaviour Generate

    @impl true
    def generate(_messages, _config) do
      {:error, :api_error}
    end
  end

  defmodule TimeoutGenerate do
    @behaviour Generate

    @impl true
    def generate(_messages, _config) do
      {:error, :timeout}
    end
  end

  describe "Generate behaviour" do
    test "MockGenerate implements generate callback" do
      messages = [
        %{role: "system", content: "You are helpful"},
        %{role: "user", content: "Hello"}
      ]

      config = %{
        model: "test-model",
        temperature: 0.7,
        max_tokens: 100,
        stop: []
      }

      {:ok, response} = MockGenerate.generate(messages, config)

      assert response.content == "Mock response to: Hello"
      assert response.finish_reason == "stop"
      assert response.usage.total_tokens == 25
    end

    test "generate receives config parameters" do
      messages = [%{role: "user", content: "test"}]

      config = %{
        model: "gpt-4",
        temperature: 0.9,
        max_tokens: 500,
        stop: ["END"]
      }

      {:ok, _response} = MockGenerate.generate(messages, config)

      assert_received {:generate_called, ^config}
    end

    test "ErrorGenerate returns error tuple" do
      messages = [%{role: "user", content: "test"}]
      config = %{model: "test", temperature: 0.7, max_tokens: 100, stop: []}

      assert {:error, :api_error} = ErrorGenerate.generate(messages, config)
    end

    test "TimeoutGenerate returns timeout error" do
      messages = [%{role: "user", content: "test"}]
      config = %{model: "test", temperature: 0.7, max_tokens: 100, stop: []}

      assert {:error, :timeout} = TimeoutGenerate.generate(messages, config)
    end
  end

  describe "config structure" do
    test "config includes all required fields" do
      config = %{
        model: "gpt-4o",
        temperature: 0.7,
        max_tokens: 1000,
        stop: ["\n\n"]
      }

      messages = [%{role: "user", content: "test"}]

      {:ok, _response} = MockGenerate.generate(messages, config)

      assert_received {:generate_called, received_config}
      assert received_config.model == "gpt-4o"
      assert received_config.temperature == 0.7
      assert received_config.max_tokens == 1000
      assert received_config.stop == ["\n\n"]
    end

    test "config can have additional fields" do
      config = %{
        model: "test",
        temperature: 0.7,
        max_tokens: 100,
        stop: [],
        top_p: 0.9,
        presence_penalty: 0.1,
        custom_field: "value"
      }

      messages = [%{role: "user", content: "test"}]

      {:ok, _response} = MockGenerate.generate(messages, config)

      assert_received {:generate_called, received_config}
      assert received_config.top_p == 0.9
      assert received_config.custom_field == "value"
    end
  end

  describe "response structure" do
    test "response includes content, finish_reason, and usage" do
      messages = [%{role: "user", content: "test"}]
      config = %{model: "test", temperature: 0.7, max_tokens: 100, stop: []}

      {:ok, response} = MockGenerate.generate(messages, config)

      assert is_binary(response.content)
      assert is_binary(response.finish_reason)
      assert is_map(response.usage)
    end

    test "usage includes token counts" do
      messages = [%{role: "user", content: "test"}]
      config = %{model: "test", temperature: 0.7, max_tokens: 100, stop: []}

      {:ok, response} = MockGenerate.generate(messages, config)

      assert response.usage.prompt_tokens == 10
      assert response.usage.completion_tokens == 15
      assert response.usage.total_tokens == 25
    end
  end

  describe "message handling" do
    test "handles single message" do
      messages = [%{role: "user", content: "Hello"}]
      config = %{model: "test", temperature: 0.7, max_tokens: 100, stop: []}

      {:ok, response} = MockGenerate.generate(messages, config)

      assert response.content =~ "Hello"
    end

    test "handles multiple messages" do
      messages = [
        %{role: "system", content: "Be helpful"},
        %{role: "user", content: "First question"},
        %{role: "assistant", content: "First answer"},
        %{role: "user", content: "Second question"}
      ]

      config = %{model: "test", temperature: 0.7, max_tokens: 100, stop: []}

      {:ok, response} = MockGenerate.generate(messages, config)

      assert response.content =~ "Second question"
    end

    test "handles empty message list" do
      # While not typical, implementation should handle gracefully
      defmodule EmptyGenerate do
        @behaviour Generate

        @impl true
        def generate([], _config) do
          {:ok, %{content: "empty", finish_reason: "stop", usage: %{}}}
        end

        def generate(messages, _config) do
          {:ok, %{content: "not empty: #{length(messages)}", finish_reason: "stop", usage: %{}}}
        end
      end

      config = %{model: "test", temperature: 0.7, max_tokens: 100, stop: []}

      {:ok, response} = EmptyGenerate.generate([], config)
      assert response.content == "empty"

      {:ok, response} = EmptyGenerate.generate([%{role: "user", content: "hi"}], config)
      assert response.content == "not empty: 1"
    end
  end

  describe "integration with real backend patterns" do
    test "simulates Tinkex-style backend" do
      defmodule TinkexStyleGenerate do
        @behaviour Generate

        @impl true
        def generate(messages, config) do
          # Simulate API call
          request = %{
            messages: messages,
            model: config.model,
            temperature: config.temperature,
            max_tokens: config.max_tokens
          }

          # Simulate response
          {:ok,
           %{
             content: "Simulated Tinkex response",
             finish_reason: "stop",
             usage: %{
               prompt_tokens: estimate_tokens(messages),
               completion_tokens: 20,
               total_tokens: estimate_tokens(messages) + 20
             },
             model: request.model
           }}
        end

        defp estimate_tokens(messages) do
          messages
          |> Enum.map(& &1.content)
          |> Enum.join(" ")
          |> String.length()
          |> div(4)
        end
      end

      messages = [
        %{role: "system", content: "You are a coding assistant"},
        %{role: "user", content: "Write a hello world program"}
      ]

      config = %{
        model: "tinker/llama-3.1-8b",
        temperature: 0.7,
        max_tokens: 500,
        stop: []
      }

      {:ok, response} = TinkexStyleGenerate.generate(messages, config)

      assert response.content == "Simulated Tinkex response"
      assert response.model == "tinker/llama-3.1-8b"
    end

    test "simulates OpenAI-style backend" do
      defmodule OpenAIStyleGenerate do
        @behaviour Generate

        @impl true
        def generate(_messages, config) do
          # Simulate OpenAI API response
          {:ok,
           %{
             content: "OpenAI response",
             finish_reason: determine_finish_reason(config),
             usage: %{
               prompt_tokens: 50,
               completion_tokens: 100,
               total_tokens: 150
             },
             system_fingerprint: "fp_12345"
           }}
        end

        defp determine_finish_reason(config) do
          if config.max_tokens <= 50, do: "length", else: "stop"
        end
      end

      messages = [%{role: "user", content: "Hello"}]
      config = %{model: "gpt-4", temperature: 0.7, max_tokens: 100, stop: []}

      {:ok, response} = OpenAIStyleGenerate.generate(messages, config)

      assert response.content == "OpenAI response"
      assert response.finish_reason == "stop"
      assert Map.has_key?(response, :system_fingerprint)
    end
  end
end
