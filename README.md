Walnut
======

A [Pandora](http://www.pandora.com/) client for macOS, running natively on Apple Silicon and Intel Macs.

Walnut is based on [Hermes](https://github.com/HermesApp/Hermes), which is no longer maintained.
Walnut is not affiliated with Pandora.

### Download Walnut

Signed builds will be published on this repository's [Releases](https://github.com/brandbrook/McHermes/releases) page.

If you would like to compile Walnut, continue reading.

### Develop against Walnut

There are a few ways you can develop against Walnut:

1. `NSDistributedNotificationCenter` - Every time a new song plays, a
   notification is posted with the name `walnut.song` under the object `walnut`
   with `userInfo` as a dictionary representing the song being played. See
   [Song.m](Sources/Pandora/Song.m) for the keys available to you. Playback
   state changes are posted as `walnut.state`.

2. AppleScript - here's an example script:

        tell application "Walnut"
          play          -- resumes playback, does nothing if playing
          pause         -- pauses playback, does nothing if not playing
          playpause     -- toggles playback between pause/play
          next song     -- goes to the next song
          get playback state
          set playback state to playing

          thumbs up     -- likes the current song
          thumbs down   -- dislikes the current song, going to another one
          tired of song -- sets the current song as being "tired of"

          raise volume  -- raises the volume partially
          lower volume  -- lowers the volume partially
          full volume   -- raises volume to max
          mute          -- mutes the volume
          unmute        -- unmutes the volume to the last state from mute

          -- integer 0 to 100 for the volume
          get playback volume
          set playback volume to 92

          -- Working with the current station
          set stationName to the current station's name
          set stationId to station 2's stationId
          set the current station to station 4

          -- Getting information from the current song
          set title to the current song's title
          set artist to the current song's artist
          set album to the current song's album
          ... etc
        end tell

### Want something new/fixed?

1. [Open a ticket](https://github.com/brandbrook/McHermes/issues).

2. Take a stab at it yourself and send a pull request. Here are some common
   things to do at the command line:

        make        # build everything
        make run    # build and run the application (logging to stdout)
        make dbg    # build and run inside LLDB

        # Build with the 'Release' configuration instead of 'Debug'
        make CONFIGURATION=Release [run|dbg]

## License

Code is available under the [MIT License](LICENSE), as was Hermes.
