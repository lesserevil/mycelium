# Canonical JSON-compatible encoding of application results.
#
# The launcher (`--litai-smoke`) and the native behavior tests share this
# encoder so a result term and its manifest expectation are always derived
# the same way. Rules:
#   - `{:ok, term}` becomes an object with a single `"ok"` key.
#   - `{:error, %GRPC.RPCError{}}` becomes `{"error": {"code", "message"}}`
#     where the code is the canonical gRPC status atom as a string.
#   - bare `:ok` becomes the string `"ok"`.
#   - atoms become strings, integers are preserved exactly, floats are
#     rejected (canonical JSON v1 forbids them), lists and maps encode
#     recursively with map keys rendered as strings.
defmodule Openshell.Json do
  @moduledoc false

  @spec encode_result(term) :: term
  def encode_result({:ok, value}), do: %{"ok" => encode_term(value)}
  def encode_result({:error, %GRPC.RPCError{} = error}), do: %{"error" => encode_error(error)}
  def encode_result(:ok), do: "ok"
  def encode_result(term), do: encode_term(term)

  def encode_term(nil), do: nil
  def encode_term(value) when is_boolean(value), do: value
  def encode_term(value) when is_integer(value), do: value
  def encode_term(value) when is_float(value), do: raise(ArgumentError, "floats are not canonical")
  def encode_term(value) when is_atom(value), do: Atom.to_string(value)
  def encode_term(value) when is_binary(value), do: value
  def encode_term(value) when is_list(value), do: Enum.map(value, &encode_term/1)
  def encode_term(value) when is_tuple(value), do: encode_term(Tuple.to_list(value))

  def encode_term(value) when is_map(value) do
    value
    |> Map.delete(:__struct__)
    |> Enum.map(fn {key, term} -> {key_string(key), encode_term(term)} end)
    |> Map.new()
  end

  defp encode_error(error) do
    %{"code" => encode_term(error_code(error)), "message" => encode_term(error_message(error))}
  end

  defp error_code(error) do
    status = Map.get(error, :status)
    code = Map.get(error, :code)

    cond do
      is_atom(status) and not is_nil(status) and not is_boolean(status) -> status
      is_integer(status) -> int_to_status(status)
      is_atom(code) and not is_nil(code) and not is_boolean(code) -> code
      true -> :unknown
    end
  end

  # grpc 0.11 carries integer statuses; GRPC.Status has no reverse map, so
  # derive one from its zero-arity status functions.
  defp int_to_status(code) when is_integer(code) do
    GRPC.Status.module_info(:functions)
    |> Enum.find_value(fn
      {name, 0} -> if apply(GRPC.Status, name, []) == code, do: name
      _ -> nil
    end)
    || :unknown
  end

  defp error_message(error) do
    case Map.get(error, :message) do
      nil -> ""
      message when is_binary(message) -> message
      other -> inspect(other)
    end
  end

  defp key_string(key) when is_atom(key), do: Atom.to_string(key)
  defp key_string(key) when is_binary(key), do: key
end
