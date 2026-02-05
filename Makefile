APP_NAME = ChoirController
BUILD_DIR = .build/debug
APP_BUNDLE = $(APP_NAME).app
EXECUTABLE = $(APP_NAME)
PLIST = Sources/$(APP_NAME)/Info.plist

.PHONY: run build bundle clean

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
	@rm -rf .build $(APP_BUNDLE)
