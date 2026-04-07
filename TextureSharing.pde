/**
 * TextureSharing Module
 * Platform-safe Syphon (macOS) / Spout (Windows) texture INPUT via reflection.
 * If the required library is not installed, texture receiving is silently disabled.
 *
 * Architecture: ONE SyphonClient lives in the output window (1x density projector)
 * where getGraphics() works correctly. The result is CPU-bridged back to the
 * controller for preview. Syphon's getGraphics() is broken on Retina (2x) —
 * it always fills only 1/4 of the FBO — so we avoid creating clients in the
 * controller context entirely.
 */

// --- Shared classloader for the texture sharing library ---
ClassLoader texShareClassLoader = null;

// --- Single client, lives in output window GL context ---
Object textureReceiver = null;
java.lang.reflect.Method textureNewFrameMethod = null;
java.lang.reflect.Method textureReceiveMethod = null;  // getGraphics(PGraphics)
java.lang.reflect.Method textureReceiverStopMethod = null;
PGraphics syphonSpoutCanvas = null;   // raw Syphon PGraphics in output GL context
PImage syphonSpoutInput = null;       // CPU-bridged PImage for controller display
PImage outputSyphonSpoutInput = null; // alias to syphonSpoutCanvas for output display
boolean textureReceivingEnabled = false;
boolean textureReceivingNeeded = false; // flag for lazy init in output GL context
int texReceiveDebugCount = 0;

/**
 * Locate the Processing libraries folder and load the Syphon or Spout jar.
 * Returns a ClassLoader that can find the library classes, or null.
 */
ClassLoader findLibraryClassLoader(String libraryName) {
  if (texShareClassLoader != null) return texShareClassLoader;
  
  // Processing library locations by OS
  String home = System.getProperty("user.home");
  String os = System.getProperty("os.name").toLowerCase();
  
  String[] searchPaths;
  if (os.contains("mac")) {
    searchPaths = new String[] {
      home + "/Documents/Processing/libraries",
      home + "/Library/Processing/libraries"
    };
  } else if (os.contains("win")) {
    searchPaths = new String[] {
      home + "\\Documents\\Processing\\libraries",
      System.getenv("APPDATA") + "\\Processing\\libraries"
    };
  } else {
    searchPaths = new String[] {
      home + "/sketchbook/libraries",
      home + "/Processing/libraries"
    };
  }
  
  for (String basePath : searchPaths) {
    java.io.File baseDir = new java.io.File(basePath);
    if (!baseDir.exists()) continue;
    
    // Case-insensitive search for the library folder
    java.io.File libDir = null;
    java.io.File[] children = baseDir.listFiles();
    if (children != null) {
      for (java.io.File child : children) {
        if (child.isDirectory() && child.getName().equalsIgnoreCase(libraryName)) {
          libDir = new java.io.File(child, "library");
          break;
        }
      }
    }
    if (libDir == null || !libDir.exists()) continue;
    
    // Collect all jars in the library folder
    java.io.File[] jars = libDir.listFiles(f -> f.getName().endsWith(".jar"));
    if (jars == null || jars.length == 0) continue;
    
    try {
      // Load native libraries (.jnilib on macOS, .dll on Windows, .so on Linux)
      java.io.File[] nativeLibs = libDir.listFiles(f -> {
        String n = f.getName().toLowerCase();
        return n.endsWith(".jnilib") || n.endsWith(".dylib") || n.endsWith(".dll") || n.endsWith(".so");
      });
      if (nativeLibs != null) {
        for (java.io.File nlib : nativeLibs) {
          try {
            System.load(nlib.getAbsolutePath());
            println("[TextureSharing] Loaded native lib: " + nlib.getName());
          } catch (UnsatisfiedLinkError ule) {
            // Already loaded or incompatible — not fatal
            println("[TextureSharing] Native lib note: " + ule.getMessage());
          }
        }
      }
      
      java.net.URL[] urls = new java.net.URL[jars.length];
      for (int i = 0; i < jars.length; i++) {
        urls[i] = jars[i].toURI().toURL();
        println("[TextureSharing] Found jar: " + jars[i].getAbsolutePath());
      }
      texShareClassLoader = new java.net.URLClassLoader(urls, getClass().getClassLoader());
      return texShareClassLoader;
    } catch (Exception e) {
      println("[TextureSharing] Error creating classloader: " + e.getMessage());
    }
  }
  
  println("[TextureSharing] Library '" + libraryName + "' not found in Processing libraries.");
  println("[TextureSharing] Searched: " + java.util.Arrays.toString(searchPaths));
  return null;
}

/**
 * Call on exit to cleanly shut down all receivers.
 */
void stopTextureSharing() {
  if (textureReceiver == null) return;
  try {
    if (textureReceiverStopMethod != null) textureReceiverStopMethod.invoke(textureReceiver);
  } catch (Exception e) {}
  textureReceiver = null;
  textureReceivingEnabled = false;
  syphonSpoutInput = null;
  syphonSpoutCanvas = null;
  outputSyphonSpoutInput = null;
  println("Texture sharing stopped.");
}

// =====================================================
//  Texture Input — single client in output window
// =====================================================

/**
 * Initialize the Syphon/Spout receiver in the output window's GL context.
 * MUST be called from OutputWindow.draw() (its thread owns the GL context).
 * On 1x density projector, getGraphics() works correctly.
 */
void initTextureReceiving(PApplet outputApplet) {
  stopTextureSharing();

  String os = System.getProperty("os.name").toLowerCase();
  try {
    if (os.contains("mac")) {
      ClassLoader cl = findLibraryClassLoader("syphon");
      if (cl == null) { println("[TextureInput] Syphon library not found."); return; }
      Class<?> cls = Class.forName("codeanticode.syphon.SyphonClient", true, cl);
      textureReceiver = cls.getConstructor(PApplet.class).newInstance(outputApplet);
      textureNewFrameMethod = cls.getMethod("newFrame");
      textureReceiveMethod = cls.getMethod("getGraphics", PGraphics.class);
      textureReceiverStopMethod = cls.getMethod("stop");
      textureReceivingEnabled = true;
      textureReceivingNeeded = false;
      println("[TextureInput] Syphon client started (output context, 1x density)");

    } else if (os.contains("win")) {
      ClassLoader cl = findLibraryClassLoader("spout");
      if (cl == null) { println("[TextureInput] Spout library not found."); return; }
      Class<?> cls = Class.forName("spout.Spout", true, cl);
      textureReceiver = cls.getConstructor(PApplet.class).newInstance(outputApplet);
      textureReceiveMethod = cls.getMethod("receiveTexture");
      textureReceiverStopMethod = cls.getMethod("dispose");
      textureReceivingEnabled = true;
      textureReceivingNeeded = false;
      println("[TextureInput] Spout receiver started (output context)");
    } else {
      println("[TextureInput] No supported backend for this OS (" + os + ")");
    }
  } catch (Exception e) {
    println("[TextureInput] Init failed: " + e.getClass().getSimpleName() + ": " + e.getMessage());
    if (e.getCause() != null) println("[TextureInput] Caused by: " + e.getCause());
  }
}

/**
 * Call every frame from OutputWindow.draw() to grab the latest frame.
 * Updates both outputSyphonSpoutInput (PGraphics for output display)
 * and syphonSpoutInput (CPU-bridged PImage for controller preview).
 */
void updateTextureReceiving(PApplet outputApplet) {
  if (!textureReceivingEnabled || textureReceiver == null) return;
  try {
    String os = System.getProperty("os.name").toLowerCase();
    if (os.contains("mac")) {
      boolean hasNew = (Boolean) textureNewFrameMethod.invoke(textureReceiver);
      if (hasNew) {
        syphonSpoutCanvas = (PGraphics) textureReceiveMethod.invoke(textureReceiver, new Object[]{syphonSpoutCanvas});
        if (syphonSpoutCanvas != null) {
          // Output display: use the PGraphics directly (same GL context, 1x density)
          outputSyphonSpoutInput = syphonSpoutCanvas;

          // Controller preview: CPU bridge (loadPixels reads the FBO via glReadPixels)
          syphonSpoutCanvas.loadPixels();
          if (syphonSpoutCanvas.pixels != null && syphonSpoutCanvas.pixels.length > 0) {
            int pw = syphonSpoutCanvas.pixelWidth;
            int ph = syphonSpoutCanvas.pixelHeight;
            if (syphonSpoutInput == null || syphonSpoutInput.width != pw || syphonSpoutInput.height != ph) {
              syphonSpoutInput = createImage(pw, ph, ARGB);
            }
            syphonSpoutInput.loadPixels();
            System.arraycopy(syphonSpoutCanvas.pixels, 0, syphonSpoutInput.pixels, 0, syphonSpoutCanvas.pixels.length);
            syphonSpoutInput.updatePixels();
          }

          texReceiveDebugCount++;
          if (texReceiveDebugCount <= 5) {
            println("[TextureInput] Frame #" + texReceiveDebugCount +
                    " canvas=" + syphonSpoutCanvas.width + "x" + syphonSpoutCanvas.height +
                    " px=" + syphonSpoutCanvas.pixelWidth + "x" + syphonSpoutCanvas.pixelHeight +
                    " img=" + (syphonSpoutInput != null ? syphonSpoutInput.width + "x" + syphonSpoutInput.height : "null"));
          }
        }
      } else if (texReceiveDebugCount == 0 && frameCount % 300 == 0) {
        println("[TextureInput] Waiting for Syphon frames... (is a server running?)");
      }
    } else if (os.contains("win")) {
      textureReceiveMethod.invoke(textureReceiver);
      try {
        java.lang.reflect.Method ri = textureReceiver.getClass().getMethod("receiveImage");
        PImage result = (PImage) ri.invoke(textureReceiver);
        if (result != null && result.width > 0) {
          syphonSpoutInput = result;
          outputSyphonSpoutInput = result;
        }
      } catch (Exception e2) {}
    }
  } catch (Exception e) {
    if (texReceiveDebugCount == 0) {
      println("[TextureInput] Update error: " + e.getClass().getSimpleName() + ": " + e.getMessage());
      if (e.getCause() != null) println("[TextureInput] Caused by: " + e.getCause());
    }
  }
}
