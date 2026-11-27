.PHONY: build dev test run release dmg dmg-dev version-major version-minor version-patch version-nightly
build:
	APP_VARIANT=dev zsh scripts/build.sh
test:
	swift test
	python3 -m unittest discover -s tests-release
	python3 -m unittest discover -s tests-startup
release:
	zsh scripts/release.sh
version-major version-minor version-patch:
	@python3 scripts/release_version.py tag $(@:version-%=%)
version-nightly:
	gh workflow run release.yml --ref main -f channel=nightly
dmg:
	DMG_ONLY=1 zsh scripts/release.sh
dev: build
	open "build/Charatify Dev.app"
run: dev
dmg-dev:
	zsh scripts/dmg-dev.sh
