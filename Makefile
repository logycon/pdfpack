APP_NAME=pdfpack

.PHONY: build run clean

build:
	swift build

run:
	swift run $(APP_NAME)

clean:
	swift package clean
