# Do not mind me. I'm just a nice wrapper around xcodebuild(1).

XCB           = xcodebuild
XCPIPE        =
CONFIGURATION = Debug
SCHEME        = Hermes
HERMES        = ./build/$(CONFIGURATION)/Walnut.app/Contents/MacOS/Walnut
DEBUGGER      = lldb

# For some reason the project's SYMROOT setting is ignored when we specify an
# explicit -project option. The -project option is required when using xctool.
COMMON_OPTS   = -project Hermes.xcodeproj SYMROOT=build

all: hermes

hermes:
	$(XCB) $(COMMON_OPTS) -configuration $(CONFIGURATION) -scheme $(SCHEME) $(XCPIPE)

run: hermes
	$(HERMES)

dbg: hermes
	$(DEBUGGER) $(HERMES)

install:
	$(XCB) $(COMMON_OPTS) -configuration Release -scheme Hermes
	rm -rf /Applications/Walnut.app
	cp -a ./build/Release/Walnut.app /Applications/

# Create an archive to share (for beta testing purposes).
archive: CONFIGURATION = Release
archive: SCHEME = 'Archive Hermes'
archive: hermes

# Used to be called 'archive'. Upload Hermes and update the website.
upload-release: CONFIGURATION = Release
upload-release: SCHEME = 'Upload Hermes Release'
upload-release: hermes

clean:
	$(XCB) $(COMMON_OPTS) -scheme $(SCHEME) clean
	rm -rf build

.PHONY: all hermes run dbg archive clean install archive upload-release
