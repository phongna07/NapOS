SHELL := /usr/bin/env bash
.DEFAULT_GOAL := help

ISO ?=

.PHONY: help doctor fetch dev release verify inspect test clean-work clean-cache

help:
	@tools/vnmint-build help

doctor:
	@tools/vnmint-build doctor

fetch:
	@tools/vnmint-build fetch

dev:
	@tools/vnmint-build build dev

release:
	@tools/vnmint-build build release

verify:
	@tools/vnmint-build verify "$(ISO)"

inspect:
	@tools/vnmint-build inspect "$(ISO)"

test:
	@tools/tests/selftest.sh

clean-work:
	@tools/vnmint-build clean-work

clean-cache:
	@tools/vnmint-build clean-cache
