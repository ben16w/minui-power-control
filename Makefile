TARGET = minui-power-control
TAG ?= $(shell git describe --tags --abbrev=0 2>/dev/null || echo "")

ARCHITECTURES := arm arm64
PLATFORMS := tg5040 miyoomini rg35xxplus

MINUI_PRESENTER_VERSION := 0.9.0
MAKESELF_VERSION := 2.5.0

clean:
	rm -f bin/*/button-handler
	rm -f bin/*/minui-presenter
	find bin -type d -empty -delete

build: $(foreach platform,$(PLATFORMS),bin/$(platform)/minui-presenter) $(foreach arch,$(ARCHITECTURES),bin/$(arch)/button-handler) makeself
	@echo "Building for $(ARCHITECTURES)"
	@echo "Building for $(PLATFORMS)"
	@echo "Build complete"

bin/%/minui-presenter:
	mkdir -p bin/$*
	curl -f -o bin/$*/minui-presenter -sSL https://github.com/josegonzalez/minui-presenter/releases/download/$(MINUI_PRESENTER_VERSION)/minui-presenter-$*
	chmod +x bin/$*/minui-presenter

bin/%/button-handler:
	mkdir -p bin/$*
	CGO_ENABLED=0 GOOS=linux GOARCH="$*" go build -o bin/$*/button-handler -ldflags="-s -w" -trimpath ./src/button-handler.go
	chmod +x bin/$*/button-handler

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
