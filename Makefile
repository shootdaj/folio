APP := build/Folio.app
VERSION := 0.9.0
# The commit the build came from (-dirty when files differ from it), for `Folio --version`.
GIT_SHA := $(shell git rev-parse --short HEAD 2>/dev/null || echo unknown)$(shell git diff --quiet HEAD -- 2>/dev/null || echo -dirty)
BUILD_NUMBER := $(shell git rev-list --count HEAD 2>/dev/null || echo 1)
# `make install-cli` puts ff in $(PREFIX)/bin: /usr/local/bin (sudo may be needed), or PREFIX=$$HOME for ~/bin.
PREFIX ?= /usr/local
LSREGISTER := /System/Library/Frameworks/CoreServices.framework/Frameworks/LaunchServices.framework/Support/lsregister

.PHONY: app run test install install-cli uninstall

# Builds the bundle; runs nothing but folio-icon, which draws the Dock icon's PNGs into build/.
app:
	swift build -c release
	mkdir -p $(APP)/Contents/MacOS $(APP)/Contents/Resources
	cp "$$(swift build -c release --show-bin-path)/Folio" $(APP)/Contents/MacOS/Folio
	cp Resources/Info.plist $(APP)/Contents/Info.plist
	/usr/libexec/PlistBuddy -c "Set :CFBundleShortVersionString $(VERSION)" -c "Set :CFBundleVersion $(BUILD_NUMBER)" \
		-c "Set :FolioGitCommit $(GIT_SHA)" $(APP)/Contents/Info.plist
	mkdir -p $(APP)/Contents/Resources/Fonts
	cp -R Resources/Fonts/ $(APP)/Contents/Resources/Fonts/
	"$$(swift build -c release --show-bin-path)/folio-icon" build/Folio.iconset
	iconutil -c icns build/Folio.iconset -o $(APP)/Contents/Resources/Folio.icns
	codesign --force --deep -s - $(APP)
	@echo "built $(APP): Folio $(VERSION) ($(GIT_SHA))"

run: app
	open $(APP)

test:
	swift test

# Copies the bundle to /Applications (an older copy goes to the Trash first) and registers it with
# Launch Services, so `ff`, `open -b com.anshul.folio` and the folio: URL find it.
install: app
	@if pgrep -x Folio >/dev/null; then echo "Quit Folio first (Cmd+Q), then run make install again."; exit 1; fi
	@if [ -d /Applications/Folio.app ]; then mv /Applications/Folio.app "$$HOME/.Trash/Folio-$$(date +%Y%m%d-%H%M%S).app"; fi
	ditto $(APP) /Applications/Folio.app
	$(LSREGISTER) -f /Applications/Folio.app
	@echo "installed /Applications/Folio.app"

install-cli:
	swift build -c release --product ff
	mkdir -p $(PREFIX)/bin
	install -m 755 "$$(swift build -c release --show-bin-path)/ff" $(PREFIX)/bin/ff
	@echo "installed $(PREFIX)/bin/ff"

# Moves the app and ff to the Trash. Turn off "Open folders in Folio instead of Finder" first (Folder
# Options > General), so macOS hands folders back to Finder.
uninstall:
	@if pgrep -x Folio >/dev/null; then echo "Quit Folio first (Cmd+Q)."; exit 1; fi
	@if [ -d /Applications/Folio.app ]; then $(LSREGISTER) -u /Applications/Folio.app; mv /Applications/Folio.app "$$HOME/.Trash/Folio-$$(date +%Y%m%d-%H%M%S).app"; fi
	@for f in /usr/local/bin/ff "$$HOME/bin/ff"; do if [ -f "$$f" ]; then mv "$$f" "$$HOME/.Trash/ff-$$(date +%Y%m%d-%H%M%S)"; echo "moved $$f to the Trash"; fi; done
	@echo "Folio removed (its settings stay in ~/Library/Preferences/com.anshul.folio.plist and ~/Library/Application Support/Folio)"
