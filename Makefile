APP := build/Folio.app
# The version comes from git tags vX.Y.Z only (tools/ci/version.sh runs git describe --tags --always --dirty):
# 1.2.3 on the tag, 1.2.3-4-gabc1234 four commits after it, 0.0.0-abc1234 with no tag, -dirty when tracked
# files differ. Info.plist gets the X.Y.Z part as CFBundleShortVersionString, the commit count as
# CFBundleVersion, and the whole version and the short commit for `Folio --version`.
VERSION := $(shell tools/ci/version.sh)
SHORT_VERSION := $(shell tools/ci/version.sh --short)
BUILD_NUMBER := $(shell tools/ci/version.sh --build)
GIT_SHA := $(shell tools/ci/version.sh --sha)
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
	/usr/libexec/PlistBuddy -c "Set :CFBundleShortVersionString $(SHORT_VERSION)" -c "Set :CFBundleVersion $(BUILD_NUMBER)" \
		-c "Set :FolioVersion $(VERSION)" -c "Set :FolioGitCommit $(GIT_SHA)" $(APP)/Contents/Info.plist
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
