.PHONY: app dmg run install clean debug

app:
	./build.sh

dmg: app
	./Scripts/make-dmg.sh

run: app
	open ./DevPorts.app

install: app
	rm -rf /Applications/DevPorts.app
	cp -R ./DevPorts.app /Applications/DevPorts.app
	@echo "Installed to /Applications/DevPorts.app"

debug:
	swift build

clean:
	rm -rf .build DevPorts.app dist Resources/AppIcon.icns
