TARGET = minui-power-control
TAG ?= $(shell git describe --tags --abbrev=0 2>/dev/null || echo "")

ARCHITECTURES := arm arm64
PLATFORMS := tg5040 tg5050 my355 miyoomini rg35xxplus h700
SET_BRIGHTNESS_PLATFORMS := tg5040 h700

MINUI_PRESENTER_VERSION := 0.13.0
MAKESELF_VERSION := 2.5.0

# minui-presenter asset names stopped matching platform names in 0.13.0: h700
# and tg5050 are published only as NextUI builds. A platform with no entry here
# uses its own name.
MINUI_PRESENTER_ASSET_h700 := h700-nextui
MINUI_PRESENTER_ASSET_tg5050 := tg5050-nextui

clean:
	rm -f bin/*/button-handler
	rm -f bin/*/minui-presenter
	rm -f bin/*/set-brightness
	find bin -type d -empty -delete

build: $(foreach platform,$(PLATFORMS),bin/$(platform)/minui-presenter) $(foreach platform,$(SET_BRIGHTNESS_PLATFORMS),bin/$(platform)/set-brightness) $(foreach arch,$(ARCHITECTURES),bin/$(arch)/button-handler) makeself
	@echo "Building for $(ARCHITECTURES)"
	@echo "Building for $(PLATFORMS)"
	@echo "Build complete"

bin/%/minui-presenter:
	mkdir -p bin/$*
	curl -f -o bin/$*/minui-presenter -sSL https://github.com/josegonzalez/minui-presenter/releases/download/$(MINUI_PRESENTER_VERSION)/minui-presenter-$(or $(MINUI_PRESENTER_ASSET_$*),$*)
	chmod +x bin/$*/minui-presenter

bin/%/button-handler:
	mkdir -p bin/$*
	CGO_ENABLED=0 GOOS=linux GOARCH="$*" go build -o bin/$*/button-handler -ldflags="-s -w" -trimpath ./src/button-handler.go
	chmod +x bin/$*/button-handler

# every platform with set-brightness runs a 64-bit userland
bin/%/set-brightness:
	mkdir -p bin/$*
	CGO_ENABLED=0 GOOS=linux GOARCH="arm64" go build -o bin/$*/set-brightness -ldflags="-s -w -X main.platformName=$*" -trimpath ./src/set-brightness.go
	chmod +x bin/$*/set-brightness

# a test folder exists, so without this make would call the target up to date
.PHONY: test
test:
	go test ./src/button-handler.go ./src/button-handler_test.go
	bats test

makeself:
	curl -f -o makeself.run -sSL https://github.com/megastep/makeself/releases/download/release-$(MAKESELF_VERSION)/makeself-$(MAKESELF_VERSION).run
	sh makeself.run --target makeself
	rm -f makeself.run

release: build
	mkdir -p dist
	chmod +x bin/launch
	chmod +x bin/shutdown
	chmod +x bin/suspend
	sh makeself/makeself.sh --noprogress bin dist/$(TARGET) "$(TARGET) $(TAG)" ./launch
	chmod +x ./dist/$(TARGET)
	@echo "Release created at dist/$(TARGET)"
