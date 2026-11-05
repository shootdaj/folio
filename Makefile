APP := build/FuckFinder.app

.PHONY: app run test

app:
	swift build -c release
	mkdir -p $(APP)/Contents/MacOS $(APP)/Contents/Resources
	cp "$$(swift build -c release --show-bin-path)/FuckFinder" $(APP)/Contents/MacOS/FuckFinder
	cp Resources/Info.plist $(APP)/Contents/Info.plist
	codesign --force --deep -s - $(APP)

run: app
	open $(APP)

test:
	swift test
