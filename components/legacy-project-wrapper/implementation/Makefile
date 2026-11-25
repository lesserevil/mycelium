# Delegation Makefile: mix is the build authority; this Makefile is the
# retained driver that litai's lifecycle invokes. The test target relays mix
# output and appends a pytest-style "N passed" summary because the litai
# harness recognizes pytest-style test counts, not ExUnit's summary line.
SHELL := /bin/bash
.SHELLFLAGS := -o pipefail -c
.PHONY: all test clean

all:
	mix compile

test:
	mix test 2>&1 | awk '{ print } / tests?, [0-9]+ failures?/ { n = split($$0, w, " "); for (i = 2; i <= n; i++) { if (w[i] ~ /^tests?,$$/) tests = w[i-1]; if (w[i] ~ /^doctests?,$$/) doct = w[i-1]; if (w[i] ~ /^failures?$$/) fails = w[i-1] } } END { if (tests == "") exit 1; print (doct + 0) + (tests + 0) - (fails + 0) " passed" }'

clean:
	mix clean
