# Mappy Changelog (LLM Context)

## Syphon/Spout Input (Apr 2026)
- Mappy is INPUT only (receives textures from other apps). No Syphon/Spout output/server.
- Two SyphonClients: one per GL context (controller + output window). Each must be created in its own context's thread.
- Reflection + URLClassLoader to load Syphon jars at runtime (no `import` = cross-platform compile).
- Native JNI libs loaded via `System.load()` (not `System.loadLibrary()`).
- **Retina Quad Fix (FAILURES)**:
    1.  **Direct pixelDensity(1) override**: Failed (Black Screen). Interferes with PGraphics FBO initialization on macOS.
    2.  **Matrix Scaling (scale(d))**: Failed (Black Screen). Syphon's TEXTURE_RECTANGLE fails to blit to PGraphics in P3D when transformations are active.
    3.  **Logical Dimension Division (srcW/d)**: Failed (Black Screen). Coordinate mismatch between 2x-logical source and 1x-logical destination.
    4.  **UV Coordinate Scaling (Surface.pde)**: Failed (Black Screen). Even with stable blit, sampling the Syphon texture at 0.5 range failed to resolve.
    5.  **CPU readback (loadPixels + arraycopy to PImage)**: Failed (lower-left quarter only). Even a plain PImage created from glReadPixels shows same offset — the Syphon PGraphics FBO itself only has content in lower-left quarter on Retina.
- **Root Cause Found**: Syphon's `getGraphics()` was NEVER fixed for pixelDensity. `createGraphics(texW, texH)` makes a 2x FBO on Retina, but `drawTexture()` only writes to logical area (1/4 of FBO). PR #39 only fixed `getImage()` array size, NOT the underlying FBO rendering.
    6.  **getImage() via reflection**: Failed (still quarter). PR #39 only fixes the PImage size. Internally it still uses a tempDest PGraphics which has the same 2x FBO / 1/4 fill problem. The pixel readback reads the broken FBO.
    7.  **Shared method handles between dual clients**: Also broke output. Controller's getImage method handle overwrote the output's getGraphics handle via shared variable.
- **Final Fix**: Single SyphonClient in output window (1x density projector, getGraphics works). CPU-bridge the pixels to a plain PImage for controller preview. Same pattern as Playground but in reverse direction.
- **Current State**: The Syphon client in the controller window is currently broken (black screen) on Retina displays. Projector output (density 1) remains functional.
- **Technical Note**: The root cause is an architectural conflict between the Syphon library (which inherits HighDPI density) and Processing's P3D renderer's handling of GL_TEXTURE_RECTANGLE during PGraphics-to-PGraphics blits.
- **NEVER call `setModified(true)` on PGraphics blit buffers**. It re-uploads from the empty CPU `pixels[]` array, overwriting the correct FBO texture with garbage. Blit buffers rendered via `beginDraw()/image()/endDraw()` are already native GPU textures in their GL context.
- LiveAV module was fully removed; Playground replaced it.
- Serial scaffolding added to Playground (optional, comma-separated Arduino values).
