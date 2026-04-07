/**
 * TextureSharing Module
 * Platform-safe Syphon (macOS) / Spout (Windows) texture INPUT via reflection.
 * If the required library is not installed, texture receiving is silently disabled.
 *
 * Processing only adds library jars to the classpath when it sees an `import`.
 * Since we intentionally avoid imports (so this compiles on all platforms),
 * we locate the jars at runtime from Processing's libraries folder and load
 * them via URLClassLoader.
 */

// --- Shared classloader for the texture sharing library ---
ClassLoader texShareClassLoader = null;

// --- Input (Client) – Controller side ---
Object textureReceiver = null;
java.lang.reflect.Method textureReceiveMethod = null;
java.lang.reflect.Method textureNewFrameMethod = null;
java.lang.reflect.Method textureReceiverStopMethod = null;
PGraphics syphonSpoutCanvas = null;  // raw Syphon PGraphics (GL_TEXTURE_RECTANGLE)
PGraphics syphonBlitBuffer = null;   // density-compensated blit buffer for controller
PImage syphonSpoutInput = null;
boolean textureReceivingEnabled = false;

// --- Input (Client) – Output window side ---
Object outputTextureReceiver = null;
PGraphics outputSyphonSpoutCanvas = null;  // raw Syphon PGraphics
PGraphics outputSyphonBlitBuffer = null;   // regular PGraphics for use as texture
PImage outputSyphonSpoutInput = null;
boolean outputTextureReceivingEnabled = false;
boolean outputTextureReceivingNeeded = false; // flag for lazy init in output GL context

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
  if (textureReceiver == null && outputTextureReceiver == null) return;
  stopTextureReceiving();
  stopOutputTextureReceiving();
  println("Texture sharing stopped.");
}

// =====================================================
//  Texture Input (Syphon Client / Spout Receiver)
// =====================================================

/**
 * Initialize a Syphon Client or Spout Receiver to receive frames from
 * another application. Call from the main sketch (controller) context.
 */
void initTextureReceiving(PApplet parent) {
  // Stop any existing receiver
  stopTextureReceiving();

  String os = System.getProperty("os.name").toLowerCase();
  try {
    if (os.contains("mac")) {
      ClassLoader cl = findLibraryClassLoader("syphon");
      if (cl == null) { println("[TextureInput] Syphon library not found."); return; }
      Class<?> cls = Class.forName("codeanticode.syphon.SyphonClient", true, cl);
      textureReceiver = cls.getConstructor(PApplet.class).newInstance(parent);
      textureNewFrameMethod = cls.getMethod("newFrame");
      textureReceiveMethod = cls.getMethod("getGraphics", PGraphics.class);
      textureReceiverStopMethod = cls.getMethod("stop");
      textureReceivingEnabled = true;
      println("[TextureInput] Syphon client started");

    } else if (os.contains("win")) {
      ClassLoader cl = findLibraryClassLoader("spout");
      if (cl == null) { println("[TextureInput] Spout library not found."); return; }
      Class<?> cls = Class.forName("spout.Spout", true, cl);
      textureReceiver = cls.getConstructor(PApplet.class).newInstance(parent);
      textureReceiveMethod = cls.getMethod("receiveTexture");
      textureReceiverStopMethod = cls.getMethod("dispose");
      textureReceivingEnabled = true;
      println("[TextureInput] Spout receiver started");
    } else {
      println("[TextureInput] No supported backend for this OS (" + os + ")");
    }
  } catch (Exception e) {
    println("[TextureInput] Init failed: " + e.getClass().getSimpleName() + ": " + e.getMessage());
    if (e.getCause() != null) println("[TextureInput] Caused by: " + e.getCause());
  }
}

/**
 * Call every frame to grab the latest input texture.
 * Returns the current frame as a PImage, or null if unavailable.
 */
int texReceiveDebugCount = 0;

PImage updateTextureReceiving(PApplet parent) {
  if (!textureReceivingEnabled || textureReceiver == null) return syphonSpoutInput;
  try {
    String os = System.getProperty("os.name").toLowerCase();
    if (os.contains("mac")) {
      boolean hasNew = (Boolean) textureNewFrameMethod.invoke(textureReceiver);
      if (hasNew) {
        syphonSpoutCanvas = (PGraphics) textureReceiveMethod.invoke(textureReceiver, new Object[]{syphonSpoutCanvas});
        if (syphonSpoutCanvas != null) {
          // Blit Syphon PGraphics (GL_TEXTURE_RECTANGLE) into a standard PGraphics (GL_TEXTURE_2D)
          // using image() which handles RECT textures correctly.
          // Do NOT call setModified() on the result — the FBO texture is already correct.
          int srcW = syphonSpoutCanvas.width;
          int srcH = syphonSpoutCanvas.height;
          if (syphonBlitBuffer == null || syphonBlitBuffer.width != srcW || syphonBlitBuffer.height != srcH) {
            if (syphonBlitBuffer != null) syphonBlitBuffer.dispose();
            syphonBlitBuffer = createGraphics(srcW, srcH, P3D);
          }
          syphonBlitBuffer.beginDraw();
          syphonBlitBuffer.background(0);
          syphonBlitBuffer.image(syphonSpoutCanvas, 0, 0);
          syphonBlitBuffer.endDraw();
          syphonSpoutInput = syphonBlitBuffer;
          texReceiveDebugCount++;
          if (texReceiveDebugCount <= 5) {
            println("[TextureInput] Got frame #" + texReceiveDebugCount +
                    " syphon=" + srcW + "x" + srcH +
                    " blit=" + syphonBlitBuffer.width + "x" + syphonBlitBuffer.height +
                    " blitPx=" + syphonBlitBuffer.pixelWidth + "x" + syphonBlitBuffer.pixelHeight);
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
        if (result != null && result.width > 0) syphonSpoutInput = result;
      } catch (Exception e2) {}
    }
  } catch (Exception e) {
    if (texReceiveDebugCount == 0) {
      println("[TextureInput] Update error: " + e.getClass().getSimpleName() + ": " + e.getMessage());
      if (e.getCause() != null) println("[TextureInput] Caused by: " + e.getCause());
    }
  }
  return syphonSpoutInput;
}

void stopTextureReceiving() {
  if (textureReceiver == null) return;
  try {
    if (textureReceiverStopMethod != null) textureReceiverStopMethod.invoke(textureReceiver);
  } catch (Exception e) {}
  textureReceiver = null;
  textureReceivingEnabled = false;
  syphonSpoutInput = null;
  syphonSpoutCanvas = null;
  if (syphonBlitBuffer != null) { syphonBlitBuffer.dispose(); syphonBlitBuffer = null; }
  println("[TextureInput] Receiver stopped.");
}

// =====================================================
//  Output-side Texture Input (second client per GL context)
// =====================================================

/**
 * Initialize a second Syphon Client / Spout Receiver for the output window.
 * MUST be called from the output window's thread so the client binds to
 * the output GL context.
 */
void initOutputTextureReceiving(PApplet outputApplet) {
  stopOutputTextureReceiving();

  String os = System.getProperty("os.name").toLowerCase();
  try {
    if (os.contains("mac")) {
      ClassLoader cl = findLibraryClassLoader("syphon");
      if (cl == null) { println("[TextureInput-Output] Syphon library not found."); return; }
      Class<?> cls = Class.forName("codeanticode.syphon.SyphonClient", true, cl);
      outputTextureReceiver = cls.getConstructor(PApplet.class).newInstance(outputApplet);
      // Reuse method handles from the controller client (same class)
      if (textureNewFrameMethod == null) textureNewFrameMethod = cls.getMethod("newFrame");
      if (textureReceiveMethod == null)  textureReceiveMethod  = cls.getMethod("getGraphics", PGraphics.class);
      if (textureReceiverStopMethod == null) textureReceiverStopMethod = cls.getMethod("stop");
      outputTextureReceivingEnabled = true;
      outputTextureReceivingNeeded = false;
      println("[TextureInput-Output] Syphon client started (output context)");

    } else if (os.contains("win")) {
      ClassLoader cl = findLibraryClassLoader("spout");
      if (cl == null) { println("[TextureInput-Output] Spout library not found."); return; }
      Class<?> cls = Class.forName("spout.Spout", true, cl);
      outputTextureReceiver = cls.getConstructor(PApplet.class).newInstance(outputApplet);
      if (textureReceiveMethod == null) textureReceiveMethod = cls.getMethod("receiveTexture");
      if (textureReceiverStopMethod == null) textureReceiverStopMethod = cls.getMethod("dispose");
      outputTextureReceivingEnabled = true;
      outputTextureReceivingNeeded = false;
      println("[TextureInput-Output] Spout receiver started (output context)");
    }
  } catch (Exception e) {
    println("[TextureInput-Output] Init failed: " + e.getClass().getSimpleName() + ": " + e.getMessage());
    if (e.getCause() != null) println("[TextureInput-Output] Caused by: " + e.getCause());
  }
}

/**
 * Call every frame from OutputWindow.draw() to grab the latest input texture.
 */
PImage updateOutputTextureReceiving(PApplet outputApplet) {
  if (!outputTextureReceivingEnabled || outputTextureReceiver == null) return outputSyphonSpoutInput;
  try {
    String os = System.getProperty("os.name").toLowerCase();
    if (os.contains("mac")) {
      boolean hasNew = (Boolean) textureNewFrameMethod.invoke(outputTextureReceiver);
      if (hasNew) {
        outputSyphonSpoutCanvas = (PGraphics) textureReceiveMethod.invoke(outputTextureReceiver, new Object[]{outputSyphonSpoutCanvas});
        if (outputSyphonSpoutCanvas != null) {
          // Blit onto a regular GL_TEXTURE_2D PGraphics for the output context
          if (outputSyphonBlitBuffer == null || outputSyphonBlitBuffer.width != outputSyphonSpoutCanvas.width || outputSyphonBlitBuffer.height != outputSyphonSpoutCanvas.height) {
            if (outputSyphonBlitBuffer != null) outputSyphonBlitBuffer.dispose();
            outputSyphonBlitBuffer = outputApplet.createGraphics(outputSyphonSpoutCanvas.width, outputSyphonSpoutCanvas.height, P3D);
          }
          outputSyphonBlitBuffer.beginDraw();
          outputSyphonBlitBuffer.background(0);
          outputSyphonBlitBuffer.image(outputSyphonSpoutCanvas, 0, 0);
          outputSyphonBlitBuffer.endDraw();
          outputSyphonSpoutInput = outputSyphonBlitBuffer;
        }
      }
    } else if (os.contains("win")) {
      textureReceiveMethod.invoke(outputTextureReceiver);
      try {
        java.lang.reflect.Method ri = outputTextureReceiver.getClass().getMethod("receiveImage");
        PImage result = (PImage) ri.invoke(outputTextureReceiver);
        if (result != null && result.width > 0) outputSyphonSpoutInput = result;
      } catch (Exception e2) {}
    }
  } catch (Exception e) {
    println("[TextureInput-Output] Update error: " + e.getClass().getSimpleName() + ": " + e.getMessage());
  }
  return outputSyphonSpoutInput;
}

void stopOutputTextureReceiving() {
  if (outputTextureReceiver == null) return;
  try {
    if (textureReceiverStopMethod != null) textureReceiverStopMethod.invoke(outputTextureReceiver);
  } catch (Exception e) {}
  outputTextureReceiver = null;
  outputTextureReceivingEnabled = false;
  outputSyphonSpoutInput = null;
  outputSyphonSpoutCanvas = null;
  if (outputSyphonBlitBuffer != null) { outputSyphonBlitBuffer.dispose(); outputSyphonBlitBuffer = null; }
  println("[TextureInput-Output] Receiver stopped.");
}
