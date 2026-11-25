defmodule MyceliumTest do
  use ExUnit.Case
  doctest Mycelium

  test "greets the world" do
    assert Mycelium.hello() == :world
  end
end
