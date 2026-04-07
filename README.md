# Basic Projection Mapping App

A simple Processing-based tool for projection mapping quads with corner pinning.

## Features
- **Dual Window Setup**: 
  - **Controller Window**: UI for dragging corners and managing surfaces.
  - **Output Window**: Clean output for the projector (defaulted to full screen on the first monitor, can be adjusted for a second).
- **Corner Pinning**: Drag the green handles in the Controller window to map your quads.
- **Media Support**: Load images (`.jpg`, `.png`) or videos (`.mp4`, `.mov`) onto any quad.
- **Live AV (Arduino)**: Connect an Arduino with a potentiometer to drive live sound and modulated generative visuals. [**See the Live AV Guide**](LIVE_AV_GUIDE.md).
- **Persistence**: Save your mapping configuration to `data/config.json`.
- **Multiple Surfaces**: Add as many quads as you need.

## Requirements
- **Processing 3 or 4**
- **Video Library**: Install the "Video" library by the Processing Foundation via the Contribution Manager (Tools > Add Tool > Libraries).

## Downloads (Pre-built)
If you don't want to run from source, you can download the latest exported binaries:
- [**Download for macOS (Apple Silicon)**](https://github.com/prismspecs/mappy/releases/latest/download/mappy-macos-aarch64.zip)
- [**Download for macOS (Intel)**](https://github.com/prismspecs/mappy/releases/latest/download/mappy-macos-x86_64.zip)
- [**Download for Linux (amd64)**](https://github.com/prismspecs/mappy/releases/latest/download/mappy-linux-amd64.zip)
- [**Download for Windows (amd64)**](https://github.com/prismspecs/mappy/releases/latest/download/mappy-windows-amd64.zip)

> These links always point to the most recent [GitHub Release](https://github.com/prismspecs/mappy/releases). When publishing a new release, upload assets with the filenames above.

## Controls
- **Mouse Drag**: Move corners of a quad.
- **'a'**: Add a new quad.
- **'s'**: Save current configuration to `data/config.json`.
- **'l'**: Load media (image or video) for the currently selected corner's quad.
- **'Esc'**: Close the app.

## How to use on a Projector
1. Connect your projector as a second display.
2. In `projection_app.pde`, find the `OutputWindow` class.
3. In `settings()`, change `fullScreen(P3D, 1);` to `fullScreen(P3D, 2);` (or whichever index corresponds to your projector).
4. Run the sketch. The output should appear on your projector.
