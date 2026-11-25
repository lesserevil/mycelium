# Generated native behavior cases for the OpenShell Elixir client.
#
# Executed by `source/main.exs --litai-test` (and reusable by the smoke
# mode). The cases below are the executable twin of the disposable manifest
# at `source/tests/manifest.json`; the manifest itself is lifecycle metadata
# and is never read, embedded, or parsed here.
#
# The suite is hermetic: every RPC goes through `Openshell.FakeGatewayStub`,
# an in-test stub of the generated stub's public function contract, so the
# real gateway is never located, launched, or required.

product_dir = Path.expand("../openshell", __DIR__)

loaded? =
  Enum.all?(
    [Openshell.Client, Openshell.Health, Openshell.Sandboxes, Openshell.Json],
    &Code.ensure_loaded?/1
  )

unless loaded? do
  product_dir
  |> then(&Path.wildcard(Path.join(&1, "*.ex")))
  |> Kernel.ParallelCompiler.compile()
end

defmodule Openshell.FakeGatewayStub do
  @moduledoc false
  @responses_key :__openshell_fake_responses__

  def connect(_address, _opts), do: {:ok, :fake_channel}
  def disconnect(:fake_channel), do: :ok

  def health(_channel, _request, _opts), do: respond(:health)
  def list_sandboxes(_channel, _request, _opts), do: respond(:list_sandboxes)
  def get_sandbox(_channel, _request, _opts), do: respond(:get_sandbox)
  def create_sandbox(_channel, _request, _opts), do: respond(:create_sandbox)
  def delete_sandbox(_channel, _request, _opts), do: respond(:delete_sandbox)

  defp respond(method) do
    case Process.get(@responses_key) do
      responses when is_map(responses) ->
        case Map.fetch(responses, method) do
          {:ok, value} -> if is_tuple(value), do: value, else: {:ok, value}
          :error -> raise ArgumentError, "no fake gateway response configured for #{inspect(method)}"
        end

      _ ->
        raise ArgumentError, "no fake gateway responses configured"
    end
  end
end

defmodule Openshell.LitaiCases do
  @moduledoc false

  @stub_override_key :__openshell_client_stub_override__
  @fake_responses_key :__openshell_fake_responses__

  @doc false
  def cases do
    [
      {"generated-example-connect-requires-address", fn ->
        Openshell.Client.connect([], 5000)
      end, %{"error" => %{"code" => "invalid_argument", "message" => "address is required"}}},
      {"generated-example-connect-plaintext", fn ->
        Process.put(@stub_override_key, Openshell.FakeGatewayStub)
        Process.put(@fake_responses_key, %{})
        Openshell.Client.connect(keyword_opts(%{"address" => "localhost:50051", "tls" => false}), 5000)
      end,
      %{
        "ok" => %{
          "__openshell_client__" => true,
          "address" => "localhost:50051",
          "ca" => nil,
          "cert" => nil,
          "channel" => "fake_channel",
          "key" => nil,
          "stub" => "Elixir.Openshell.FakeGatewayStub",
          "timeout" => 5000,
          "tls" => false,
          "token" => nil
        }
      }},
      {"generated-example-health-healthy", fn ->
        client = connect_client(%{"address" => "gw.example:443"}, 5000)
        fake(:health, %{"status" => "HEALTHY"})
        Openshell.Health.check(client, 5000)
      end, %{"ok" => "healthy"}},
      {"generated-example-sandboxes-get-found", fn ->
        client = connect_client(%{"address" => "gw.example:443"}, 5000)
        fake(:get_sandbox, %{"sandbox" => %{"image" => "alpine:3.19", "name" => "sb-1"}})
        Openshell.Sandboxes.get(client, "default", "sb-1")
      end, %{"ok" => %{"image" => "alpine:3.19", "name" => "sb-1"}}},
      {"generated-example-sandboxes-list-page", fn ->
        client = connect_client(%{"address" => "gw.example:443"}, 5000)
        fake(:list_sandboxes, %{"sandboxes" => [%{"name" => "sb-1"}, %{"name" => "sb-2"}]})
        Openshell.Sandboxes.list(client, "default", 5000)
      end, %{"ok" => [%{"name" => "sb-1"}, %{"name" => "sb-2"}]}},
      {"generated-example-sandboxes-create", fn ->
        client = connect_client(%{"address" => "gw.example:443"}, 5000)
        fake(:create_sandbox, %{"sandbox" => %{"image" => "alpine:3.19", "name" => "sb-new"}})
        spec = %{"image" => "alpine:3.19", "command" => ["sh"], "sizing" => %{"cpu" => 2, "memory_mb" => 512}}
        Openshell.Sandboxes.create(client, "default", spec, 5000)
      end, %{"ok" => %{"image" => "alpine:3.19", "name" => "sb-new"}}},
      {"generated-example-sandboxes-delete", fn ->
        client = connect_client(%{"address" => "gw.example:443"}, 5000)
        fake(:delete_sandbox, %{})
        Openshell.Sandboxes.delete(client, "default", "sb-1")
      end, %{"ok" => "deleted"}},
      {"generated-boundary-health-degraded-enum-prefix", fn ->
        client = connect_client(%{"address" => "gw.example:443"}, 5000)
        fake(:health, %{"status" => "HEALTH_STATUS_DEGRADED"})
        Openshell.Health.check(client, 5000)
      end, %{"ok" => "degraded"}},
      {"generated-boundary-address-missing-port", fn ->
        Openshell.Client.connect([address: "localhost"], 5000)
      end, %{"error" => %{"code" => "invalid_argument", "message" => "address must be host:port"}}},
      {"generated-boundary-sandboxes-get-not-found", fn ->
        client = connect_client(%{"address" => "gw.example:443"}, 5000)
        fake(:get_sandbox, {:error, rpc_error(:not_found, "sandbox not found")})
        Openshell.Sandboxes.get(client, "default", "sb-1")
      end, %{"error" => %{"code" => "not_found", "message" => "sandbox not found"}}},
      {"generated-invariant-connect-default-tls", fn ->
        Process.put(@stub_override_key, Openshell.FakeGatewayStub)
        Process.put(@fake_responses_key, %{})
        Openshell.Client.connect(keyword_opts(%{"address" => "gw.example:443"}), 5000)
      end,
      %{
        "ok" => %{
          "__openshell_client__" => true,
          "address" => "gw.example:443",
          "ca" => nil,
          "cert" => nil,
          "channel" => "fake_channel",
          "key" => nil,
          "stub" => "Elixir.Openshell.FakeGatewayStub",
          "timeout" => 5000,
          "tls" => true,
          "token" => nil
        }
      }},
      {"generated-invariant-close-returns-ok", fn ->
        client = connect_client(%{"address" => "gw.example:443"}, 5000)
        Openshell.Client.close(client)
      end, "ok"}
    ]
  end

  @doc false
  def run_all do
    Enum.map(cases(), fn {case_id, _thunk, _expected} ->
      outcome =
        try do
          run_case!(case_id)
          :passed
        rescue
          _ -> :failed
        catch
          _, _ -> :failed
        end

      {case_id, outcome}
    end)
  end

  @doc false
  def run_case!(case_id) do
    {_id, thunk, expected} = fetch_case!(case_id)
    Process.put(@stub_override_key, Openshell.FakeGatewayStub)
    Process.put(@fake_responses_key, %{})

    encoded = Openshell.Json.encode_result(thunk.())

    unless encoded == expected do
      raise ArgumentError,
            "case #{case_id} expected #{inspect(expected)} but produced #{inspect(encoded)}"
    end

    encoded
  end

  @doc false
  def envelope_json(results) do
    entries =
      results
      |> Enum.map(fn {case_id, outcome} ->
        outcome_name = if outcome == :passed, do: "passed", else: "failed"
        "{\"case_id\":\"" <> case_id <> "\",\"outcome\":\"" <> outcome_name <> "\"}"
      end)
      |> Enum.join(",")

    "{\"schema\":\"literate-ai/generated-test-results@1\",\"cases\":[" <> entries <> "]}"
  end

  defp fetch_case!(case_id) do
    Enum.find(cases(), fn {id, _thunk, _expected} -> id == case_id end) ||
      raise ArgumentError, "unknown generated case #{inspect(case_id)}"
  end

  defp connect_client(opts_map, timeout) do
    Process.put(@stub_override_key, Openshell.FakeGatewayStub)
    Process.put(@fake_responses_key, %{})

    case Openshell.Client.connect(keyword_opts(opts_map), timeout) do
      {:ok, client} -> client
      {:error, _reason} -> raise ArgumentError, "connect failed in test setup"
    end
  end

  defp fake(method, value) do
    responses = Map.put(Process.get(@fake_responses_key) || %{}, method, value)
    Process.put(@fake_responses_key, responses)
  end

  defp keyword_opts(map) when is_map(map) do
    Enum.map(map, fn {key, value} -> {String.to_existing_atom(key), value} end)
  end

  defp rpc_error(code, message) do
    Code.ensure_loaded!(GRPC.RPCError)
    struct(GRPC.RPCError, message: message, code: code, status: code)
  end
end
