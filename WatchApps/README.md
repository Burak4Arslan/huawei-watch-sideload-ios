# WatchApps/ (the .bin files in here are ignored by git)

`tools/build-watch-app.sh` writes signed watch apps here, named after the app's `app_name` (e.g. `Sample.bin`).
After `./generate.sh`, Xcode bundles every `.bin` from this folder into the iPhone app, and the app shows an
**"Install … on the watch"** button for each of them under "Watch apps".

Do not share signed `.bin` files: they contain your debug profile, including your watch's UDID.
