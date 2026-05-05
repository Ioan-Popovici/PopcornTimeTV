# PopcornTimeTV — developer workflow.
#
# All targets are wrappers around `xcodebuild` and the VLCKit fetch script,
# so every command works without remembering the long invocation.
#
# Run `make help` for a one-line summary of every target.

PROJECT      := PopcornTime.xcodeproj
BUILD_DIR    := build
DERIVED_DIR  := /tmp/PopcornTime-derived
ORIGINAL_REF := 835198f
ORIGINAL_DIR := $(BUILD_DIR)/original
WORKTREE_DIR := /tmp/popcorntime-original

XCODEBUILD_FLAGS := \
  -project $(PROJECT) \
  CODE_SIGN_IDENTITY= \
  CODE_SIGNING_REQUIRED=NO \
  CODE_SIGNING_ALLOWED=NO

XCBEAUTIFY := $(shell command -v xcbeautify 2>/dev/null)
ifeq ($(XCBEAUTIFY),)
PIPE :=
else
PIPE := | xcbeautify
endif

.PHONY: help build build-debug build-ios build-tvos build-release \
        build-original run compare clean clean-all resolve vlc-mac vlc-ios \
        vlc-tv refresh-popcorntorrent lint format ci-local

help: ## Show this help.
	@awk 'BEGIN {FS = ":.*?## "} /^[a-zA-Z0-9_-]+:.*?## / {printf "  \033[36m%-18s\033[0m %s\n", $$1, $$2}' $(MAKEFILE_LIST)

# ---------- Build ----------

build: build-debug ## Alias for `build-debug`.

build-debug: vlc-mac resolve ## Debug build, macOS, into ./build/macOS/.
	@rm -rf $(BUILD_DIR)/macOS
	@xcodebuild $(XCODEBUILD_FLAGS) \
	  -scheme "PopcornTime (macOS)" \
	  -configuration Debug \
	  -destination "platform=macOS" \
	  -derivedDataPath $(DERIVED_DIR) \
	  CONFIGURATION_BUILD_DIR=$(CURDIR)/$(BUILD_DIR)/macOS \
	  build $(PIPE)
	@$(MAKE) --no-print-directory _link-app PLATFORM=macOS
	@echo ""
	@echo "→ $(CURDIR)/$(BUILD_DIR)/macOS/PopcornTime.app"

build-ios: vlc-ios resolve ## Debug build, iOS Simulator, into ./build/iOS/.
	@rm -rf $(BUILD_DIR)/iOS
	@xcodebuild $(XCODEBUILD_FLAGS) \
	  -scheme "PopcornTime (iOS)" \
	  -configuration Debug \
	  -sdk iphonesimulator \
	  -destination "generic/platform=iOS Simulator" \
	  -derivedDataPath $(DERIVED_DIR) \
	  CONFIGURATION_BUILD_DIR=$(CURDIR)/$(BUILD_DIR)/iOS \
	  build $(PIPE)
	@$(MAKE) --no-print-directory _link-app PLATFORM=iOS
	@echo ""
	@echo "→ $(CURDIR)/$(BUILD_DIR)/iOS/PopcornTime.app"

build-tvos: vlc-tv resolve ## Debug build, tvOS Simulator, into ./build/tvOS/ (requires platform installed).
	@rm -rf $(BUILD_DIR)/tvOS
	@xcodebuild $(XCODEBUILD_FLAGS) \
	  -scheme "PopcornTime (tvOS)" \
	  -configuration Debug \
	  -sdk appletvsimulator \
	  -destination "generic/platform=tvOS Simulator" \
	  -derivedDataPath $(DERIVED_DIR) \
	  CONFIGURATION_BUILD_DIR=$(CURDIR)/$(BUILD_DIR)/tvOS \
	  build $(PIPE)
	@$(MAKE) --no-print-directory _link-app PLATFORM=tvOS
	@echo ""
	@echo "→ $(CURDIR)/$(BUILD_DIR)/tvOS/PopcornTime.app"

# Helper: ensure ./build/<platform>/PopcornTime.app exists. Some
# Xcode targets emit "PopcornTime.app" directly (the macOS app target
# overrides PRODUCT_NAME); others emit "PopcornTime (<scheme>).app"
# from the scheme name. Symlink the suffixed name to the canonical one
# so callers get a stable path either way.
.PHONY: _link-app
_link-app:
	@cd "$(BUILD_DIR)/$(PLATFORM)" && \
	  if [ -d "PopcornTime.app" ] && [ ! -L "PopcornTime.app" ]; then \
	    : already canonical; \
	  elif [ -d "PopcornTime ($(PLATFORM)).app" ]; then \
	    rm -f PopcornTime.app && ln -sf "PopcornTime ($(PLATFORM)).app" PopcornTime.app; \
	  else \
	    echo "warning: no PopcornTime.app produced in $(BUILD_DIR)/$(PLATFORM)"; \
	  fi

build-release: vlc-mac resolve ## Release macOS .app into ./build/.
	@-pkill -f "$(BUILD_DIR)/PopcornTime.app/Contents/MacOS/PopcornTime" 2>/dev/null || true
	@rm -rf $(BUILD_DIR)/PopcornTime.app $(BUILD_DIR)/PopcornTime.app.dSYM
	@xcodebuild $(XCODEBUILD_FLAGS) \
	  -scheme "PopcornTime (macOS)" \
	  -configuration Release \
	  -destination "platform=macOS" \
	  -derivedDataPath $(DERIVED_DIR) \
	  CONFIGURATION_BUILD_DIR=$(CURDIR)/$(BUILD_DIR) \
	  build $(PIPE)
	@echo ""
	@echo "→ $(CURDIR)/$(BUILD_DIR)/PopcornTime.app"

build-original: ## Build the unmodified upstream version into ./build/original/ for comparison.
	@git worktree add -f $(WORKTREE_DIR) $(ORIGINAL_REF) >/dev/null 2>&1 || \
	  (echo "worktree exists or git failed; reusing $(WORKTREE_DIR)" && git -C $(WORKTREE_DIR) checkout $(ORIGINAL_REF))
	@bash $(WORKTREE_DIR)/VLCKit/get-vlc-frameworks.sh mac >/dev/null
	@mkdir -p $(ORIGINAL_DIR)
	@rm -rf $(ORIGINAL_DIR)/*
	@xcodebuild \
	  -project $(WORKTREE_DIR)/$(PROJECT) \
	  -scheme "PopcornTime (macOS)" \
	  -configuration Release \
	  -destination "platform=macOS" \
	  -derivedDataPath /tmp/PopcornTime-original-derived \
	  CODE_SIGN_IDENTITY= \
	  CODE_SIGNING_REQUIRED=NO \
	  CODE_SIGNING_ALLOWED=NO \
	  CONFIGURATION_BUILD_DIR=$(CURDIR)/$(ORIGINAL_DIR) \
	  build $(PIPE)
	@git worktree remove --force $(WORKTREE_DIR) >/dev/null 2>&1 || true
	@echo ""
	@echo "→ $(CURDIR)/$(ORIGINAL_DIR)/PopcornTime.app"

# ---------- Run ----------

run: build-release ## Build the macOS app and launch it.
	@open $(BUILD_DIR)/PopcornTime.app
	@echo "Launched $(BUILD_DIR)/PopcornTime.app"

compare: build-release build-original ## Build current + upstream and open both side-by-side.
	@open $(ORIGINAL_DIR)/PopcornTime.app
	@open $(BUILD_DIR)/PopcornTime.app

# ---------- Maintenance ----------

resolve: ## Resolve SwiftPM dependencies (forces a re-fetch on Package.resolved drift).
	@xcodebuild -project $(PROJECT) -resolvePackageDependencies $(PIPE)

vlc-mac: ## Fetch macOS VLCKit binary.
	@bash VLCKit/get-vlc-frameworks.sh mac

vlc-ios: ## Fetch iOS MobileVLCKit binary.
	@bash VLCKit/get-vlc-frameworks.sh ios

vlc-tv: ## Fetch tvOS TVVLCKit binary.
	@bash VLCKit/get-vlc-frameworks.sh tv

refresh-popcorntorrent: ## Re-pull alextud/PopcornTorrent@v2_3 and reapply popcorntorrent.patch (manual maintenance).
	@bash Packages/refresh-popcorntorrent.sh

clean: ## Remove ./build and DerivedData for this project.
	@rm -rf $(BUILD_DIR)/PopcornTime.app $(BUILD_DIR)/PopcornTime.app.dSYM
	@rm -rf $(BUILD_DIR)/macOS $(BUILD_DIR)/iOS $(BUILD_DIR)/tvOS
	@rm -rf $(DERIVED_DIR) /tmp/PopcornTime-original-derived

clean-all: clean ## Also remove the ./build/original copy and the VLCKit binary drop.
	@rm -rf $(ORIGINAL_DIR) VLCKit/MobileVLCKit-binary VLCKit/TVVLCKit-binary "VLCKit/VLCKit - binary package" \
	        VLCKit/Manifest.lock VLCKit/ios-version.lock VLCKit/tv-version.lock VLCKit/mac-version.lock

format: ## Run swiftformat (no-op if not installed).
	@if command -v swiftformat >/dev/null; then swiftformat PopcornTime PopcornKit/Sources --config .swiftformat; \
	else echo "swiftformat not installed (brew install swiftformat)"; fi

lint: ## Strict build: warnings become errors (treats Swift 6 warnings as failures).
	@xcodebuild $(XCODEBUILD_FLAGS) \
	  -scheme "PopcornTime (macOS)" \
	  -configuration Debug \
	  -destination "platform=macOS" \
	  -derivedDataPath $(DERIVED_DIR) \
	  SWIFT_TREAT_WARNINGS_AS_ERRORS=YES \
	  build $(PIPE)

ci-local: ## Run the same build matrix CI does (macOS + iOS + tvOS, Release).
	@$(MAKE) build-release
	@$(MAKE) build-ios
	@$(MAKE) build-tvos
