SHELL := /usr/bin/env bash
.DEFAULT_GOAL := help

ISO ?=

.PHONY: help doctor fetch dev release verify inspect test clean-work clean-cache

help:
	@tools/napos-build help

doctor:
	@tools/napos-build doctor

fetch:
	@tools/napos-build fetch

dev:
	@tools/napos-build build dev

release:
	@tools/napos-build build release

verify:
	@tools/napos-build verify "$(ISO)"

inspect:
	@tools/napos-build inspect "$(ISO)"

test:
	@tools/tests/selftest.sh

clean-work:
	@tools/napos-build clean-work

clean-cache:
	@tools/napos-build clean-cache
