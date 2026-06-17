# WhatPort build helpers

BINARY = .build/arm64-apple-macosx/debug/WhatPort
APP = .build/WhatPort.app
BUNDLE_RES = .build/arm64-apple-macosx/debug/WhatPort_WhatPort.bundle

.PHONY: build app run clean test

build:
	swift build

app: build
	@rm -rf $(APP)
	@mkdir -p $(APP)/Contents/MacOS $(APP)/Contents/Resources
	@cp $(BINARY) $(APP)/Contents/MacOS/WhatPort
	@if [ -d "$(BUNDLE_RES)" ]; then cp -R $(BUNDLE_RES) $(APP)/Contents/MacOS/; fi
	@if [ -f "Sources/WhatPort/Resources/AppIcon.png" ]; then \
		cp Sources/WhatPort/Resources/AppIcon.png $(APP)/Contents/Resources/; \
	fi
	@/usr/libexec/PlistBuddy -c "Clear dict" $(APP)/Contents/Info.plist 2>/dev/null; \
	/usr/libexec/PlistBuddy \
		-c "Add :CFBundleName string WhatPort" \
		-c "Add :CFBundleDisplayName string WhatPort" \
		-c "Add :CFBundleIdentifier string app.whatport.whatport" \
		-c "Add :CFBundleVersion string 1" \
		-c "Add :CFBundleShortVersionString string 1.0" \
		-c "Add :CFBundlePackageType string APPL" \
		-c "Add :CFBundleExecutable string WhatPort" \
		-c "Add :LSMinimumSystemVersion string 14.0" \
		-c "Add :LSUIElement bool true" \
		-c "Add :NSPrincipalClass string NSApplication" \
		$(APP)/Contents/Info.plist
	@# Entitlements: network client needed for license key validation
	@/usr/libexec/PlistBuddy -c "Clear dict" $(APP)/Contents/entitlements.plist 2>/dev/null; \
	/usr/libexec/PlistBuddy \
		-c "Add :com.apple.security.network.client bool true" \
		$(APP)/Contents/entitlements.plist
	@echo "Built $(APP)"

run: app
	@pkill -x WhatPort 2>/dev/null || true
	@sleep 0.5
	@open $(APP)
	@echo "WhatPort running"

test:
	swift test

clean:
	swift package clean
	rm -rf $(APP)
