.PHONY: build test run
build:
	zsh scripts/build.sh
test:
	swift test
run: build
	open "build/Charatify.app"
