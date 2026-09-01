.PHONY: app run install clean debug

app:
	./build.sh

run: app
	open ./DevPorts.app

install: app
	rm -rf /Applications/DevPorts.app
	cp -R ./DevPorts.app /Applications/DevPorts.app
	@echo "Installed to /Applications/DevPorts.app"

debug:
	swift build

clean:
	rm -rf .build DevPorts.app Resources/AppIcon.icns
