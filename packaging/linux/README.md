# Linux Packaging

This folder has what I need to build a .deb package for Wordwise on Debian and Ubuntu and I added this because the project only had android and ios builds before and I wanted to run wordwise on my linux desktop like a normal app not just with flutter run.

## Files in this folder

- `control` — package info like name version and dependencies
- `wordwise.desktop` — so the app shows up in the app menu
- `build_deb.sh` — the script that builds everything
- `README.md` — this file

## What you need

- Flutter SDK in PATH
- dpkg-deb which comes with dpkg
- ImageMagick the magick command

Install them on Debian and Ubuntu:

    sudo apt install dpkg imagemagick

## How to build

From this folder just run:

    ./build_deb.sh

The script does a few things and first runs flutter build linux release and cleans any old build folder and makes the deb folder structure and copies the built app into usr/lib/wordwise and adds a small launcher script in usr/bin/wordwise and makes icons 256x256 and 512x512 from the ios icon and builds the deb with dpkg-deb and the result goes to build/wordwise_0.1.0_amd64.deb.

## How to install

    sudo dpkg -i build/wordwise_0.1.0_amd64.deb

If something is missing fix it with:

    sudo apt install -f

## How to remove

    sudo dpkg -r wordwise

## What gets installed

- `/usr/bin/wordwise` — small launcher
- `/usr/lib/wordwise/` — the full app
- `/usr/share/applications/wordwise.desktop` — app menu entry
- `/usr/share/icons/hicolor/256x256/apps/wordwise.png` — small icon
- `/usr/share/icons/hicolor/512x512/apps/wordwise.png` — big icon

## Notes

This is a learning setup not a finished thing and I am still testing it and there might be bugs and the app still uses the default flutter icon because I have not made a custom icon for wordwise yet and user progress is saved in the user home folder by path_provider not inside the package.

## Current status

Still working on it and I am testing this on my own system Ubuntu 26.04 amd64 and if you find any problems open an issue and I will take a look.

## Download

If you do not want to build it yourself you can download the .deb file directly from the repo:

https://github.com/rezaziaei28/wordwise/blob/Linux_version_reza_ziaei/packaging/linux/release/wordwise_0.1.0_amd64.deb

Then install it with:

    sudo dpkg -i wordwise_0.1.0_amd64.deb
    sudo apt install -f

