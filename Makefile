APP_NAME   := TLDR
BUILD_DIR  := build
PRODUCT    := $(BUILD_DIR)/Build/Products/Release/$(APP_NAME).app
INSTALL    := /Applications/$(APP_NAME).app
LSREGISTER := /System/Library/Frameworks/CoreServices.framework/Frameworks/LaunchServices.framework/Support/lsregister

.PHONY: project build test install default clean

project:
	xcodegen generate

build: project
	xcodebuild -project TLDR.xcodeproj -scheme TLDR -configuration Release \
		-derivedDataPath $(BUILD_DIR) -allowProvisioningUpdates -quiet build

test:
	cd Packages/MarkdownRenderer && swift test

# Copies to /Applications and registers the app + Quick Look extension with the system.
install: build
	rm -rf "$(INSTALL)"
	ditto "$(PRODUCT)" "$(INSTALL)"
	$(LSREGISTER) -f "$(INSTALL)"
	pluginkit -a "$(INSTALL)/Contents/PlugIns/TLDRQuickLook.appex"
	qlmanage -r >/dev/null 2>&1; qlmanage -r cache >/dev/null 2>&1
	@echo "Installed. Quick Look: select a .md file in Finder and press space."

# Makes TL;DR the default app for .md files (macOS may ask for confirmation).
default:
	swift -e 'import AppKit; import UniformTypeIdentifiers; \
		NSWorkspace.shared.setDefaultApplication(at: URL(fileURLWithPath: "$(INSTALL)"), \
		toOpen: UTType("net.daringfireball.markdown")!) { e in print(e.map { "Failed: \($$0)" } ?? "Default app set"); exit(0) }; \
		RunLoop.main.run()'

clean:
	rm -rf $(BUILD_DIR) TLDR.xcodeproj
