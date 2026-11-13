.PHONY: build dev test run release dmg dmg-dev
build:
	APP_VARIANT=dev zsh scripts/build.sh
test:
	swift test
	python3 -m unittest discover -s tests-release
	python3 -m unittest discover -s tests-startup
release:
	zsh scripts/release.sh
dmg:
	DMG_ONLY=1 zsh scripts/release.sh
dev: build
	open "build/Charatify Dev.app"
run: dev
dmg-dev:
	zsh scripts/dmg-dev.sh
