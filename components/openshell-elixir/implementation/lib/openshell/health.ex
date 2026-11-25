# Gateway health surface.
#
# `check/2` reports gateway health; returns `{:ok, :healthy}`,
# `{:ok, :degraded}`, or `{:error, reason}`. Every call dispatches to the
# corresponding `Openshell.V1.OpenShell.Stub` method through the default
# transport.
defmodule Openshell.Health do
  @moduledoc false

  def check(client, timeout), do: Openshell.Client.check_health(client, timeout)
end
