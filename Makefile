# SidePiece — Screen-docked Telegram widget for macOS
.PHONY: all build install test dmg pkg clean

all: build

build:
	@bash build.sh

pkg: build
	@echo "Building native macOS installer package..."
	@mkdir -p build/pkg-root/Applications build/pkg-scripts dist
	@rm -rf build/pkg-root/Applications/SidePiece.app
	@cp -R build/SidePiece.app build/pkg-root/Applications/
	@echo "#!/bin/bash" > build/pkg-scripts/postinstall
	@echo "xattr -cr /Applications/SidePiece.app 2>/dev/null || true" >> build/pkg-scripts/postinstall
	@echo "xattr -dr com.apple.quarantine /Applications/SidePiece.app 2>/dev/null || true" >> build/pkg-scripts/postinstall
	@echo "exit 0" >> build/pkg-scripts/postinstall
	@chmod +x build/pkg-scripts/postinstall
	@pkgbuild --root build/pkg-root --scripts build/pkg-scripts --identifier com.sidepiece.app --version 1.0.0 dist/SidePiece.pkg
	@echo "Package built at dist/SidePiece.pkg"

install: build
	@echo "Installing SidePiece.app to /Applications..."
	@rm -rf /Applications/SidePiece.app
	@cp -R build/SidePiece.app /Applications/SidePiece.app
	@xattr -dr com.apple.quarantine /Applications/SidePiece.app 2>/dev/null || true
	@xattr -dr "com.apple.fileprovider.fpfs#P" /Applications/SidePiece.app 2>/dev/null || true
	@echo "SidePiece.app installed to /Applications successfully."

test:
	@echo "Running test suite..."
	@xcrun swift Tests/backtest.swift

dmg:
	@bash build.sh --dmg

clean:
	@rm -rf build/ dist/ /tmp/tg_*.log /tmp/tg_selftest.*
	@echo "Cleaned build artifacts."
