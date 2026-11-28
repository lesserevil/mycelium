defmodule Mycelium.Service.Endpoint.Auth do
  @moduledoc false
  @behaviour Plug

  import Plug.Conn

  @impl true
  def init(opts), do: opts

  @impl true
  def call(conn, _opts) do
    case Application.get_env(:mycelium_service, :bearer_token) do
      nil ->
        conn

      token ->
        case get_req_header(conn, "authorization") do
          ["Bearer " <> ^token] ->
            conn

          _ ->
            conn
            |> put_resp_content_type("application/json")
            |> send_resp(401, ~s({"error":{"code":"unauthorized","message":"bearer token required"}}))
            |> halt()
        end
    end
  end

  # Runs before the JSON parser so auth can reject without reading the body.
  # Invoked via the :body_reader option, not a behaviour.
  def read_body(conn, opts) do
    if conn.halted do
      {:ok, "", conn}
    else
      Plug.Conn.read_body(conn, opts)
    end
  end
end

defmodule Mycelium.Service.Endpoint do
  @moduledoc """
  The Plug router for the supervisor protocol:
  `POST /mycelium/v1/checkin` and `POST /mycelium/v1/poll`.

  The OTP host application runs this under Bandit. Bearer-token auth is
  optional: configure `config :mycelium_service, bearer_token: "..."` to
  require `Authorization: Bearer <token>` on every request.
  """

  use Plug.Router

  plug(:match)
  plug(Mycelium.Service.Endpoint.Auth)
  plug(Plug.Parsers,
    parsers: [:json],
    pass: ["application/json"],
    json_decoder: Jason,
    body_reader: {Mycelium.Service.Endpoint.Auth, :read_body, []}
  )
  plug(:dispatch)

  post "/mycelium/v1/checkin" do
    case Mycelium.Service.check_in(conn.body_params, []) do
      {:ok, _connection} ->
        conn |> put_resp_content_type("application/json") |> send_resp(200, ~s({"ok":true}))

      {:error, {status, code, message}} ->
        error(conn, status, code, message)
    end
  end

  post "/mycelium/v1/poll" do
    case Mycelium.Service.poll(conn.body_params["sandbox"], []) do
      {:ok, assignments} ->
        conn
        |> put_resp_content_type("application/json")
        |> send_resp(200, Jason.encode!(%{"assignments" => assignments}))

      {:error, {status, code, message}} ->
        error(conn, status, code, message)
    end
  end

  match _ do
    if conn.halted do
      conn
    else
      error(conn, 404, "not_found", "unknown route")
    end
  end

  defp error(conn, status, code, message) do
    body = Jason.encode!(%{"error" => %{"code" => code, "message" => message}})

    conn
    |> put_resp_content_type("application/json")
    |> send_resp(status, body)
  end
end
