# Delegation Makefile: mix is the build authority; this Makefile is the
# retained driver that litai's lifecycle invokes.
.PHONY: all test clean

all:
	mix compile

test:
	mix test

clean:
	mix clean
