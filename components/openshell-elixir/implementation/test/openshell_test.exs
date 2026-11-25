# Native ExUnit behavior cases for the OpenShell Elixir client.
#
# One test per generated manifest case, invoking the same application logic
# with the same arguments and asserting the same complete expected result.
# The suite is hermetic: every RPC goes through `Openshell.FakeGatewayStub`,
# an in-test stub of the generated stub's public function contract; the real
# gateway is never located, launched, or required, and the generated test
# manifest is never read.

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
    responses = Process.get(@responses_key)

    case responses do
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

defmodule Openshell.ClientTest do
  use ExUnit.Case, async: false

  alias Openshell.{Client, Health, Json, Sandboxes}

  @stub_override_key :__openshell_client_stub_override__
  @fake_responses_key :__openshell_fake_responses__

  test "generated-example-connect-requires-address" do
    result = Client.connect([], 5000)

    assert Json.encode_result(result) ==
             %{"error" => %{"code" => "invalid_argument", "message" => "address is required"}}
  end

  test "generated-example-connect-plaintext" do
    client = connect_client(%{"address" => "localhost:50051", "tls" => false})

    assert Json.encode_result({:ok, client}) ==
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
             }
  end

  test "generated-example-health-healthy" do
    client = connect_client(%{"address" => "gw.example:443"})
    fake(:health, %{"status" => "HEALTHY"})

    assert Json.encode_result(Health.check(client, 5000)) == %{"ok" => "healthy"}
  end

  test "generated-example-sandboxes-get-found" do
    client = connect_client(%{"address" => "gw.example:443"})
    fake(:get_sandbox, %{"sandbox" => %{"image" => "alpine:3.19", "name" => "sb-1"}})

    assert Json.encode_result(Sandboxes.get(client, "default", "sb-1")) ==
             %{"ok" => %{"image" => "alpine:3.19", "name" => "sb-1"}}
  end

  test "generated-example-sandboxes-list-page" do
    client = connect_client(%{"address" => "gw.example:443"})
    fake(:list_sandboxes, %{"sandboxes" => [%{"name" => "sb-1"}, %{"name" => "sb-2"}]})

    assert Json.encode_result(Sandboxes.list(client, "default", 5000)) ==
             %{"ok" => [%{"name" => "sb-1"}, %{"name" => "sb-2"}]}
  end

  test "generated-example-sandboxes-create" do
    client = connect_client(%{"address" => "gw.example:443"})
    fake(:create_sandbox, %{"sandbox" => %{"image" => "alpine:3.19", "name" => "sb-new"}})
    spec = %{"image" => "alpine:3.19", "command" => ["sh"], "sizing" => %{"cpu" => 2, "memory_mb" => 512}}

    assert Json.encode_result(Sandboxes.create(client, "default", spec, 5000)) ==
             %{"ok" => %{"image" => "alpine:3.19", "name" => "sb-new"}}
  end

  test "generated-example-sandboxes-delete" do
    client = connect_client(%{"address" => "gw.example:443"})
    fake(:delete_sandbox, %{})

    assert Json.encode_result(Sandboxes.delete(client, "default", "sb-1")) == %{"ok" => "deleted"}
  end

  test "generated-boundary-health-degraded-enum-prefix" do
    client = connect_client(%{"address" => "gw.example:443"})
    fake(:health, %{"status" => "HEALTH_STATUS_DEGRADED"})

    assert Json.encode_result(Health.check(client, 5000)) == %{"ok" => "degraded"}
  end

  test "generated-boundary-address-missing-port" do
    result = Client.connect([address: "localhost"], 5000)

    assert Json.encode_result(result) ==
             %{"error" => %{"code" => "invalid_argument", "message" => "address must be host:port"}}
  end

  test "generated-boundary-sandboxes-get-not-found" do
    client = connect_client(%{"address" => "gw.example:443"})
    fake(:get_sandbox, {:error, rpc_error(:not_found, "sandbox not found")})

    assert Json.encode_result(Sandboxes.get(client, "default", "sb-1")) ==
             %{"error" => %{"code" => "not_found", "message" => "sandbox not found"}}
  end

  test "generated-invariant-connect-default-tls" do
    client = connect_client(%{"address" => "gw.example:443"})

    assert Json.encode_result({:ok, client}) ==
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
             }
  end

  test "generated-invariant-close-returns-ok" do
    client = connect_client(%{"address" => "gw.example:443"})

    assert Json.encode_result(Client.close(client)) == "ok"
  end

  defp connect_client(opts_map) do
    Process.put(@stub_override_key, Openshell.FakeGatewayStub)
    Process.put(@fake_responses_key, %{})

    case Client.connect(keyword_opts(opts_map), 5000) do
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
