# OpenShell Elixir Client launcher.
#
# Framework-owned modes (kept thin; they delegate to generated test code and
# never read the generated test manifest):
#
#   main.exs --litai-test   run every generated native behavior case and emit
#                           {"schema":"literate-ai/generated-test-results@1",
#                            "cases":[{"case_id":"...","outcome":"passed"},...]}
#   main.exs --litai-smoke  execute one current non-acceptance generated
#                           example through the real application logic and
#                           emit its ordinary JSON result
#
# This component is a library profile component, so there is no product JSON
# entrypoint; any other invocation is a usage error.

Code.require_file("tests/litai_test.exs", __DIR__)

case System.argv() do
  ["--litai-test"] ->
    results = Openshell.LitaiCases.run_all()
    IO.puts(Openshell.LitaiCases.envelope_json(results))

    if Enum.all?(results, fn {_case_id, outcome} -> outcome == :passed end) do
      System.halt(0)
    else
      System.halt(1)
    end

  ["--litai-smoke"] ->
    encoded = Openshell.LitaiCases.run_case!("generated-example-connect-requires-address")
    IO.puts(JSON.encode!(encoded))

  _ ->
    IO.puts(:stderr, "usage: main.exs --litai-test | --litai-smoke")
    System.halt(2)
end
