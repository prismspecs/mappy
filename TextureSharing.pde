/**
 * TextureSharing Module
 * Platform-safe Syphon (macOS) / Spout (Windows) output via reflection.
 * If the required library is not installed, texture sharing is silently disabled.
 */

static final String TEXTURE_SHARE_NAME = "Mappy";

Object textureSender = null;
java.lang.reflect.Method textureSendMethod = null;
java.lang.reflect.Method textureStopMethod = null;
boolean textureSharingEnabled = false;
String textureSharingBackend = "none";

/**
 * Call once from OutputWindow.setup() to initialize Syphon or Spout.
 * Pass the OutputWindow PApplet so the server binds to the correct GL context.
 */
void initTextureSharing(PApplet outputApplet) {
  String os = System.getProperty("os.name").toLowerCase();

  try {
    if (os.contains("mac")) {
      // Syphon: codeanticode.syphon.SyphonServer(PApplet parent, String name)
      Class<?> cls = Class.forName("codeanticode.syphon.SyphonServer");
      textureSender = cls.getConstructor(PApplet.class, String.class)
                         .newInstance(outputApplet, TEXTURE_SHARE_NAME);
      textureSendMethod = cls.getMethod("sendScreen");
      textureStopMethod = cls.getMethod("stop");
      textureSharingBackend = "Syphon";

    } else if (os.contains("win")) {
      // Spout: spout.Spout(PApplet parent)
      Class<?> cls = Class.forName("spout.Spout");
      textureSender = cls.getConstructor(PApplet.class)
                         .newInstance(outputApplet);
      textureSendMethod = cls.getMethod("sendTexture");
      textureStopMethod = cls.getMethod("dispose");
      textureSharingBackend = "Spout";
    }

    if (textureSender != null) {
      textureSharingEnabled = true;
      println("Texture sharing started via " + textureSharingBackend + " (" + TEXTURE_SHARE_NAME + ")");
    } else {
      println("Texture sharing: no supported backend for this OS (" + os + ")");
    }

  } catch (ClassNotFoundException e) {
    println("Texture sharing: " + (os.contains("mac") ? "Syphon" : "Spout") +
            " library not installed. Install it via Sketch > Import Library > Manage Libraries.");
  } catch (Exception e) {
    println("Texture sharing init failed: " + e.getMessage());
  }
}

/**
 * Call at the end of OutputWindow.draw() to send the current frame.
 */
void sendTextureFrame() {
  if (!textureSharingEnabled) return;
  try {
    textureSendMethod.invoke(textureSender);
  } catch (Exception e) {
    println("Texture sharing send error: " + e.getMessage());
    textureSharingEnabled = false;
  }
}

/**
 * Call on exit to cleanly shut down the server.
 */
void stopTextureSharing() {
  if (textureSender == null) return;
  try {
    if (textureStopMethod != null) {
      textureStopMethod.invoke(textureSender);
    }
    println("Texture sharing stopped.");
  } catch (Exception e) {
    // Ignore errors during shutdown
  }
  textureSender = null;
  textureSharingEnabled = false;
}
