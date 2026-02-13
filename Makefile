APP_NAME = ChoirController
BUILD_DIR = .build/debug
APP_BUNDLE = $(APP_NAME).app
EXECUTABLE = $(APP_NAME)
PLIST = Sources/$(APP_NAME)/Info.plist

# Xcode build settings
XCODE_PROJECT = Choir Arranger/Choir Arranger.xcodeproj
XCODE_SCHEME = Choir Arranger
XCODE_DERIVED = .xcode-build
XCODE_APP = $(XCODE_DERIVED)/Build/Products/Debug/Choir Arranger.app

.PHONY: run build bundle clean xcode-build xcode-run xcode-clean

# ── Xcode build (full app with icon, signing, etc.) ──────────
xcode-run: xcode-build
	@echo "Launching Choir Arranger..."
	@"$(XCODE_APP)/Contents/MacOS/Choir Arranger"

xcode-build:
	@echo "Building with xcodebuild..."
	@xcodebuild -project "$(XCODE_PROJECT)" -scheme "$(XCODE_SCHEME)" -configuration Debug -derivedDataPath "$(XCODE_DERIVED)" build 2>&1 | tail -3

xcode-clean:
	@rm -rf $(XCODE_DERIVED)

# ── SPM build (quick iteration, no icon) ─────────────────────
run: bundle
	@echo "Launching $(APP_BUNDLE)..."
	@# Launch the binary directly inside the bundle to keep stdout/stderr attached to terminal
	@$(APP_BUNDLE)/Contents/MacOS/$(EXECUTABLE)

build:
	@echo "Building Swift package..."
	@swift build

bundle: build
	@echo "Creating App Bundle..."
	@mkdir -p $(APP_BUNDLE)/Contents/MacOS
	@mkdir -p $(APP_BUNDLE)/Contents/Resources
	@cp $(BUILD_DIR)/$(EXECUTABLE) $(APP_BUNDLE)/Contents/MacOS/
	@cp $(PLIST) $(APP_BUNDLE)/Contents/Info.plist
	@# Create PkgInfo
	@echo "APPL????" > $(APP_BUNDLE)/Contents/PkgInfo
	@# Sign it ad-hoc to make macOS happy with permissions
	@codesign --force --deep --sign - $(APP_BUNDLE)

clean:
	@rm -rf .build $(APP_BUNDLE) $(XCODE_DERIVED)
