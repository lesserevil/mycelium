# OpenShell gateway client (`openshell.v1` over gRPC).
#
# Public surface (interface `interfaces/openshell-elixir.md`):
#   - `connect/2` — `connect(opts, timeout)` opens a channel to a gateway.
#   - `close/1` — closes a client's channel; returns `:ok`.
#
# Errors are always `{:error, %GRPC.RPCError{}}`; credentials never appear in
# exception messages, log output, or error payloads. The default transport
# dispatches every call to the corresponding `Openshell.V1.OpenShell.Stub`
# method through the pinned protobuf modules; no call ever returns a stubbed
# or simulated result.
defmodule Openshell.Client do
  @default_stub Openshell.V1.OpenShell.Stub
  @stub_override_key :__openshell_client_stub_override__

  @request_modules %{
    health: Openshell.V1.HealthRequest,
    list_sandboxes: Openshell.V1.ListSandboxesRequest,
    get_sandbox: Openshell.V1.GetSandboxRequest,
    create_sandbox: Openshell.V1.CreateSandboxRequest,
    delete_sandbox: Openshell.V1.DeleteSandboxRequest
  }

  @rpc_methods %{
    health: :health,
    list_sandboxes: :list_sandboxes,
    get_sandbox: :get_sandbox,
    create_sandbox: :create_sandbox,
    delete_sandbox: :delete_sandbox
  }

  @doc """
  Opens a channel to a gateway. `opts` accepts `:address` (required,
  `"host:port"`), `:tls` (`true` by default; `false` for local plaintext),
  `:ca` (CA certificate file or PEM contents), `:cert` and `:key` (client
  certificate and private key, file path or PEM contents, for mTLS gateways),
  and `:token` (bearer credential, optional for local gateways). Returns
  `{:ok, client}` or `{:error, reason}`.
  """
  def connect(opts, timeout) when is_list(opts) do
    case validate_opts(opts) do
      {:ok, normalized} -> dial(normalized, timeout)
      {:error, {code, message}} -> {:error, error(code, message)}
    end
  end

  @doc "Closes a client's channel; returns `:ok`."
  def close(%{__openshell_client__: true} = client) do
    channel = Map.fetch!(client, :channel)
    stub = Map.fetch!(client, :stub)

    cond do
      is_atom(stub) and Code.ensure_loaded?(stub) and function_exported?(stub, :disconnect, 1) ->
        apply(stub, :disconnect, [channel])

      Code.ensure_loaded?(GRPC.Stub) and function_exported?(GRPC.Stub, :disconnect, 1) ->
        apply(GRPC.Stub, :disconnect, [channel])

      true ->
        :ok
    end

    :ok
  end

  @doc false
  def check_health(%{__openshell_client__: true} = client, timeout) do
    request = build_request(:health, %{})

    case rpc(client, :health, request, timeout) do
      {:ok, response} -> health_result(response)
      error -> error
    end
  end

  @doc false
  def list_sandboxes(%{__openshell_client__: true} = client, workspace, timeout) do
    with {:ok, workspace} <- validate_name(workspace, "workspace") do
      request = build_request(:list_sandboxes, %{workspace_scope: workspace_selector(workspace)})

      case rpc(client, :list_sandboxes, request, timeout) do
        {:ok, response} -> {:ok, page_of(response)}
        error -> error
      end
    end
  end

  @doc false
  def get_sandbox(%{__openshell_client__: true} = client, workspace, name) do
    with {:ok, workspace} <- validate_name(workspace, "workspace"),
         {:ok, name} <- validate_name(name, "name") do
      request =
        build_request(:get_sandbox, %{
          workspace_scope: workspace_selector(workspace),
          name: name
        })

      case rpc(client, :get_sandbox, request, client_timeout(client)) do
        {:ok, response} -> {:ok, record_of(response)}
        error -> error
      end
    end
  end

  @doc false
  def create_sandbox(%{__openshell_client__: true} = client, workspace, spec, timeout) do
    with {:ok, workspace} <- validate_name(workspace, "workspace"),
         {:ok, spec} <- validate_spec(spec) do
      request =
        build_request(:create_sandbox, %{
          workspace_scope: workspace_selector(workspace),
          spec: sandbox_spec(spec),
          name: spec_value(spec, :name) || ""
        })

      case rpc(client, :create_sandbox, request, timeout) do
        {:ok, response} -> {:ok, record_of(response)}
        error -> error
      end
    end
  end

  @doc false
  def delete_sandbox(%{__openshell_client__: true} = client, workspace, name) do
    with {:ok, workspace} <- validate_name(workspace, "workspace"),
         {:ok, name} <- validate_name(name, "name") do
      request =
        build_request(:delete_sandbox, %{
          workspace_scope: workspace_selector(workspace),
          name: name
        })

      case rpc(client, :delete_sandbox, request, client_timeout(client)) do
        {:ok, _response} -> {:ok, :deleted}
        error -> error
      end
    end
  end

  ## Option validation

  defp validate_opts(opts) do
    with {:ok, address} <- validate_address(Keyword.get(opts, :address)),
         {:ok, tls} <- validate_tls(Keyword.get(opts, :tls)),
         {:ok, ca} <- validate_string_opt(Keyword.get(opts, :ca), "ca"),
         {:ok, cert} <- validate_string_opt(Keyword.get(opts, :cert), "cert"),
         {:ok, key} <- validate_string_opt(Keyword.get(opts, :key), "key"),
         {:ok, token} <- validate_string_opt(Keyword.get(opts, :token), "token") do
      {:ok, %{address: address, tls: tls, ca: ca, cert: cert, key: key, token: token}}
    end
  end

  defp validate_address(nil), do: {:error, {:invalid_argument, "address is required"}}

  defp validate_address(address) when is_binary(address) do
    case String.split(address, ":", parts: 2) do
      [host, port] when byte_size(host) > 0 and byte_size(port) > 0 -> {:ok, address}
      _ -> {:error, {:invalid_argument, "address must be host:port"}}
    end
  end

  defp validate_address(_), do: {:error, {:invalid_argument, "address must be a string"}}

  defp validate_tls(nil), do: {:ok, true}
  defp validate_tls(tls) when is_boolean(tls), do: {:ok, tls}
  defp validate_tls(_), do: {:error, {:invalid_argument, "tls must be a boolean"}}

  defp validate_string_opt(nil, _name), do: {:ok, nil}
  defp validate_string_opt(value, name) when is_binary(value), do: {:ok, value}
  defp validate_string_opt(_, name), do: {:error, {:invalid_argument, name <> " must be a string"}}

  defp validate_name(value, _kind) when is_binary(value) and byte_size(value) > 0, do: {:ok, value}
  defp validate_name(_, kind), do: {:error, error(:invalid_argument, kind <> " must be a nonempty string")}

  defp validate_spec(spec) when is_map(spec), do: {:ok, spec}
  defp validate_spec(_), do: {:error, error(:invalid_argument, "spec must be a map")}

  ## Dialing

  defp dial(normalized, timeout) do
    stub = stub()
    transport_opts = transport_opts(normalized)

    result =
      try do
        # A stub may own connect/2 (test fakes do); the real generated stub
        # does not, so fall back to the generic GRPC.Stub connection API.
        if function_exported?(stub, :connect, 2) do
          apply(stub, :connect, [normalized.address, transport_opts])
        else
          apply(GRPC.Stub, :connect, [normalized.address, transport_opts])
        end
      rescue
        e -> {:error, e}
      catch
        :exit, reason -> {:error, {:exit, reason}}
      end

    case result do
      {:ok, channel} -> {:ok, client(normalized, channel, stub, timeout)}
      {:error, %GRPC.RPCError{} = e} -> {:error, e}
      {:error, reason} -> {:error, error(:unavailable, "connect failed: " <> inspect(reason))}
      other -> {:error, error(:unavailable, "connect failed: " <> inspect(other))}
    end
  end

  defp stub do
    case Process.get(@stub_override_key) do
      nil -> @default_stub
      stub when is_atom(stub) -> stub
      _ -> @default_stub
    end
  end

  defp transport_opts(%{tls: tls, ca: ca, cert: cert, key: key}) do
    if tls and Code.ensure_loaded?(GRPC.Credential) do
      [cred: apply(GRPC.Credential, :new, [[ssl: ssl_opts(ca, cert, key)]])]
    else
      []
    end
  end

  defp ssl_opts(nil, nil, nil), do: []

  defp ssl_opts(ca, cert, key) do
    ssl_value(ca, :cacertfile, &cacerts_from_pem/1) ++
      ssl_value(cert, :certfile, &cert_from_pem/1) ++
      ssl_value(key, :keyfile, &key_from_pem/1)
  end

  defp ssl_value(nil, _file_opt, _pem_fun), do: []

  defp ssl_value(value, file_opt, pem_fun) do
    if File.regular?(value) do
      [{file_opt, String.to_charlist(value)}]
    else
      pem_fun.(value)
    end
  end

  defp cacerts_from_pem(pem) do
    certs =
      pem
      |> :public_key.pem_decode()
      |> Enum.map(fn {_type, der, _cipher} -> :public_key.pkix_decode_cert(der, :plain) end)

    [{:cacerts, certs}]
  end

  defp cert_from_pem(pem) do
    case :public_key.pem_decode(pem) do
      [{_type, der, _cipher} | _] -> [{:cert, der}]
      _ -> []
    end
  end

  defp key_from_pem(pem) do
    case :public_key.pem_decode(pem) do
      [{type, der, _cipher} | _] -> [{:key, {type, der}}]
      _ -> []
    end
  end

  defp client(normalized, channel, stub, timeout) do
    Map.merge(normalized, %{
      __openshell_client__: true,
      channel: channel,
      stub: stub,
      timeout: timeout
    })
  end

  ## RPC dispatch

  defp rpc(%{channel: channel, stub: stub} = client, kind, request, timeout) do
    args = [channel, request, call_opts(client, timeout)]

    result =
      try do
        apply(stub, rpc_method(kind), args)
      rescue
        e -> {:error, e}
      catch
        :exit, reason -> {:error, {:exit, reason}}
        :error, reason -> {:error, {:exit, reason}}
      end

    case result do
      {:ok, response} -> {:ok, response}
      {:error, %GRPC.RPCError{} = e} -> {:error, e}
      {:error, reason} -> {:error, error(:unavailable, "rpc failed: " <> inspect(reason))}
      other -> {:error, error(:unavailable, "rpc failed: " <> inspect(other))}
    end
  end

  defp call_opts(client, timeout) do
    opts = [timeout: timeout]

    case Map.get(client, :token) do
      nil -> opts
      token -> Keyword.put(opts, :metadata, %{"authorization" => "Bearer " <> token})
    end
  end

  defp client_timeout(client), do: Map.get(client, :timeout)

  defp rpc_method(kind), do: Map.fetch!(@rpc_methods, kind)

  defp build_request(kind, attrs) do
    # protobuf-elixir 0.17+ no longer generates new/1; struct!/2 fails loudly
    # on unknown keys instead of silently degrading to an unencodable map.
    struct!(Map.fetch!(@request_modules, kind), attrs)
  end

  ## Response mapping

  defp health_result(response) do
    case health_outcome(status_of(response)) do
      outcome when outcome in [:healthy, :degraded] -> {:ok, outcome}
      _ -> {:error, error(:internal, "unexpected health response")}
    end
  end

  defp health_outcome(raw) do
    case normalize_status(raw) do
      "healthy" -> :healthy
      "degraded" -> :degraded
      _ -> :unknown
    end
  end

  defp status_of(response) do
    Enum.find_value([:status, :state, :health_status, "status", "state", "health_status"], fn key ->
      case response do
        %{^key => value} when value != nil -> value
        _ -> nil
      end
    end)
  end

  defp normalize_status(value) when is_atom(value) and not is_boolean(value) and not is_nil(value),
    do: value |> Atom.to_string() |> normalize_status()

  defp normalize_status(value) when is_binary(value) do
    value
    |> String.downcase()
    |> strip_health_prefix()
  end

  defp normalize_status(_), do: :unknown

  defp strip_health_prefix("health_status_" <> rest), do: strip_health_prefix(rest)
  defp strip_health_prefix("service_status_" <> rest), do: strip_health_prefix(rest)
  defp strip_health_prefix("health_" <> rest), do: strip_health_prefix(rest)
  defp strip_health_prefix(other), do: other

  defp page_of(%{sandboxes: value}) when is_list(value), do: value
  defp page_of(%{"sandboxes" => value}) when is_list(value), do: value
  defp page_of(response) when is_list(response), do: response
  defp page_of(response), do: response

  defp record_of(%{sandbox: value}) when value != nil, do: value
  defp record_of(%{"sandbox" => value}) when value != nil, do: value
  defp record_of(response), do: response

  defp sandbox_spec(spec) do
    %Openshell.V1.SandboxSpec{
      template: %Openshell.V1.SandboxTemplate{
        image: spec_value(spec, :image),
        resources: resources_struct(spec_value(spec, :sizing))
      },
      command: command_list(spec_value(spec, :command))
    }
  end

  defp workspace_selector(workspace),
    do: %Openshell.Datamodel.V1.WorkspaceSelector{selection: {:workspace, workspace}}

  # `command` is a repeated string on the wire; accept one binary or a list.
  defp command_list(command) when is_binary(command), do: [command]
  defp command_list(command) when is_list(command), do: command
  defp command_list(_), do: []

  # `SandboxTemplate.resources` is a google.protobuf.Struct; sizing maps are
  # converted with scalar values only.
  defp resources_struct(nil), do: nil

  defp resources_struct(sizing) when is_map(sizing) do
    %Google.Protobuf.Struct{
      fields: Map.new(sizing, fn {key, value} -> {key_string(key), struct_value(value)} end)
    }
  end

  defp struct_value(value) when is_binary(value),
    do: %Google.Protobuf.Value{kind: {:string_value, value}}

  defp struct_value(value) when is_integer(value),
    do: %Google.Protobuf.Value{kind: {:number_value, value * 1.0}}

  defp struct_value(value) when is_float(value),
    do: %Google.Protobuf.Value{kind: {:number_value, value}}

  defp struct_value(value) when is_boolean(value),
    do: %Google.Protobuf.Value{kind: {:bool_value, value}}

  defp struct_value(_), do: %Google.Protobuf.Value{kind: {:null_value, :NULL_VALUE}}

  defp key_string(key) when is_atom(key), do: Atom.to_string(key)
  defp key_string(key) when is_binary(key), do: key

  defp spec_value(spec, key) do
    case spec do
      %{^key => value} -> value
      _ -> Map.get(spec, Atom.to_string(key))
    end
  end

  ## Errors

  defp error(code, message) do
    # grpc 0.11 carries the canonical status as an integer (GRPC.Status);
    # callers match with the integer or GRPC.Status.is_rpc_error/2 guards.
    Code.ensure_loaded!(GRPC.Status)
    struct(GRPC.RPCError, message: message, status: apply(GRPC.Status, code, []))
  end
end
