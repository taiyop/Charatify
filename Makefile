.PHONY: build dev test run release dmg-dev
build:
	APP_VARIANT=dev zsh scripts/build.sh
test:
	swift test
	python3 -m unittest discover -s tests-release
release:
	zsh scripts/release.sh
dev: build
	open "build/Charatify Dev.app"
run: dev
dmg-dev:
	zsh scripts/dmg-dev.sh
