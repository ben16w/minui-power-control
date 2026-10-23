TARGET = minui-power-control
TAG ?= $(shell git describe --tags --abbrev=0 2>/dev/null || echo "")

ARCHITECTURES := arm arm64
PLATFORMS := tg5040 tg5050 my355 miyoomini rg35xxplus h700
SET_BRIGHTNESS_PLATFORMS := tg5040 h700

MAKESELF_VERSION := 2.5.0
EMIT_KEY_VERSION := 0.3.0

# minui-presenter is not bundled: the right build depends on both the platform
# and whether MinUI or NextUI runs it, which only the calling pak knows, so the
# pak puts its own on PATH and messages are only logged without one

clean:
	rm -f bin/*/button-handler
	rm -f bin/*/set-brightness
	rm -f bin/*/emit-key
	find bin -type d -empty -delete

build: $(foreach platform,$(SET_BRIGHTNESS_PLATFORMS),bin/$(platform)/set-brightness) $(foreach arch,$(ARCHITECTURES),bin/$(arch)/button-handler) $(foreach arch,$(ARCHITECTURES),bin/$(arch)/emit-key) makeself
	@echo "Building for $(ARCHITECTURES)"
	@echo "Building for $(PLATFORMS)"
	@echo "Build complete"

bin/%/button-handler:
	mkdir -p bin/$*
	CGO_ENABLED=0 GOOS=linux GOARCH="$*" go build -o bin/$*/button-handler -ldflags="-s -w" -trimpath ./src/button-handler.go
	chmod +x bin/$*/button-handler

# the static builds run on every platform of that architecture
bin/%/emit-key:
	mkdir -p bin/$*
	curl -f -o bin/$*/emit-key -sSL https://github.com/josegonzalez/emit-key/releases/download/$(EMIT_KEY_VERSION)/emit-key-linux-$*
	chmod +x bin/$*/emit-key

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
	chmod +x bin/send-save-keys
	sh makeself/makeself.sh --noprogress bin dist/$(TARGET) "$(TARGET) $(TAG)" ./launch
	chmod +x ./dist/$(TARGET)
	@echo "Release created at dist/$(TARGET)"
