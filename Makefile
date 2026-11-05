APP := build/Folio.app

.PHONY: app run test

app:
	swift build -c release
	mkdir -p $(APP)/Contents/MacOS $(APP)/Contents/Resources
	cp "$$(swift build -c release --show-bin-path)/Folio" $(APP)/Contents/MacOS/Folio
	cp Resources/Info.plist $(APP)/Contents/Info.plist
	mkdir -p $(APP)/Contents/Resources/Fonts
	cp -R Resources/Fonts/ $(APP)/Contents/Resources/Fonts/
	codesign --force --deep -s - $(APP)

run: app
	open $(APP)

test:
	swift test
