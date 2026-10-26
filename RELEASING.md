# Releasing Walnut

A release is a notarized `Walnut-x.y.zip` on the GitHub Releases page, plus an entry in
[`appcast.xml`](appcast.xml) so existing copies of Walnut offer the update through Sparkle.

## One-time setup

On the Mac that makes releases:

1. **Developer ID certificate.** In Xcode → Settings → Accounts, sign in with the Apple
   developer account (team `RPZ6JR7U39`) and make sure a *Developer ID Application*
   certificate is installed.
2. **Notarization login.** Create an app-specific password at account.apple.com →
   Sign-In and Security → App-Specific Passwords, then save it in the keychain:

       xcrun notarytool store-credentials walnut-notary --apple-id YOUR_APPLE_ID --team-id RPZ6JR7U39

   (Use another profile name by setting `NOTARY_PROFILE` when running `make release`.)
3. **Sparkle key.** The EdDSA private key for updates lives in the login keychain
   (Sparkle's `generate_keys` put it there). Its public half is `SUPublicEDKey` in
   `Resources/Hermes-Info.plist`. Never commit the private key; if it is lost, existing
   copies of Walnut can no longer verify updates. Back it up with
   `build/sparkle-tools/bin/generate_keys -x walnut-sparkle-key.txt` and keep that file
   somewhere safe, outside the repository.
4. **Pushing.** This repository uses its own SSH key (`core.sshCommand` in `.git/config`),
   so no global GitHub login is needed.

## Making a release

1. **Set the version** in `Resources/Hermes-Info.plist`:
   - `CFBundleShortVersionString` — what people see, e.g. `1.1`.
   - `CFBundleVersion` — a whole number that must go up with every release (Sparkle compares
     it). Walnut 1.0 is `100`; use `110` for 1.1, `111` for 1.1.1, and so on. Keep
     `CURRENT_PROJECT_VERSION` in the Xcode project the same.
2. **Update [`CHANGELOG.md`](CHANGELOG.md)** with a section for the new version.
3. **Build:**

       make release

   This archives the app, exports it with Developer ID, sends it to Apple for notarization
   and waits, staples the approval, zips it as `build/Walnut-x.y.zip`, signs the zip for
   Sparkle, and adds the new version to the top of `appcast.xml`. Nothing is uploaded.
4. **Try the build:** `build/export/Walnut.app` is the exact app in the zip.
5. **Publish on GitHub** (github.com/brandbrook/WalnutPlayer → Releases → *Draft a new release*):
   - Tag: `vx.y` (e.g. `v1.1`), target `master`, created on publish.
   - Title: `Walnut x.y`; notes: the changelog section.
   - Attach `build/Walnut-x.y.zip`, with exactly that file name; the appcast points at it.
   - Publish.
6. **Commit and push the appcast** (with the version and changelog changes):

       git commit -am "Walnut x.y"
       git push

   Do this *after* the release is published, so Sparkle never offers a download that
   doesn't exist yet. Within a few minutes, *Check for Updates…* in older copies finds it.

## Website

The site is in [`docs/`](docs/) and served by GitHub Pages at
https://brandbrook.github.io/WalnutPlayer/. Its download button opens the latest release,
so it needs no change per release.

### Re-recording the website video

The hero video is a transparent recording of the Walnut window. With Walnut open and playing:

    swiftc -O Scripts/record-window.swift -o build/record-window
    ./build/record-window 8 build/walnut-window.mov
    ffmpeg -i build/walnut-window.mov -r 30 -c:v libvpx-vp9 -pix_fmt yuva420p -crf 36 -b:v 0 -row-mt 1 -an docs/radio.webm
    ffmpeg -i build/walnut-window.mov -r 30 -c:v hevc_videotoolbox -alpha_quality 0.8 -q:v 55 -tag:v hvc1 -an docs/radio.mov
    ffmpeg -i build/walnut-window.mov -frames:v 1 -pix_fmt rgba docs/radio.png

The recorder needs Screen Recording permission (System Settings → Privacy & Security).
`radio.mov` (HEVC with alpha) plays in Safari, `radio.webm` (VP9 with alpha) in Chrome and
Firefox, and `radio.png` is the still shown before the video loads and with reduced motion.
