VERSION ?= 0.1.0
APP_NAME = ClaudeNotifier
BUILD_DIR = build
APP_BUNDLE = $(BUILD_DIR)/$(APP_NAME).app
INSTALL_DIR = $(HOME)/.claude/hooks

.PHONY: build install clean release

build:
	@mkdir -p $(APP_BUNDLE)/Contents/MacOS
	@sed 's/__VERSION__/$(VERSION)/g' Resources/Info.plist.template > $(APP_BUNDLE)/Contents/Info.plist
	@swiftc Sources/main.swift \
		-o $(APP_BUNDLE)/Contents/MacOS/$(APP_NAME) \
		-framework Cocoa \
		-framework UserNotifications \
		-O
	@codesign --force --sign - $(APP_BUNDLE)
	@echo "Built $(APP_BUNDLE) (v$(VERSION))"

install: build
	@mkdir -p $(INSTALL_DIR)
	@rm -rf $(INSTALL_DIR)/$(APP_NAME).app
	@cp -R $(APP_BUNDLE) $(INSTALL_DIR)/
	@cp scripts/notification.sh $(INSTALL_DIR)/notification.sh
	@chmod +x $(INSTALL_DIR)/notification.sh
	@echo "Installed to $(INSTALL_DIR)"
	@echo ""
	@echo "Add this to your ~/.claude/settings.json hooks.Notification:"
	@echo '  {"matcher":"","hooks":[{"type":"command","command":"$(INSTALL_DIR)/notification.sh"}]}'

clean:
	@rm -rf $(BUILD_DIR)

release: build
	@cd $(BUILD_DIR) && zip -r $(APP_NAME)-v$(VERSION)-macOS.zip $(APP_NAME).app
	@echo "Created $(BUILD_DIR)/$(APP_NAME)-v$(VERSION)-macOS.zip"
