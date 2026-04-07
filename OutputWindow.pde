/**
 * OutputWindow Module
 * The clean, secondary window designed for the projector.
 * 
 * Performance: Video surfaces load their own Movie instance in this GL
 * context, eliminating the expensive GPU→CPU→GPU pixel bridge. Only
 * Playground still uses a throttled CPU bridge.
 */

public class OutputWindow extends PApplet {
  
  public void settings() {
    fullScreen(P3D, outputDisplay);
    pixelDensity(displayDensity());
  }
  
  public void setup() { 
    background(0);
  }
  
  public void draw() {
    background(0);
    
    // Lazy-init the output-side Syphon/Spout receiver in this GL context
    if (outputTextureReceivingNeeded && !outputTextureReceivingEnabled) {
      initOutputTextureReceiving(this);
    }
    
    // Update output-side Syphon/Spout receiver
    updateOutputTextureReceiving(this);
    
    // Apply output mirror/flip transform
    pushMatrix();
    switch (outputMirror) {
      case 1: // Mirror Horizontal
        translate(width, 0);
        scale(-1, 1);
        break;
      case 2: // Mirror Vertical
        translate(0, height);
        scale(1, -1);
        break;
      case 3: // Mirror H+V
        translate(width, height);
        scale(-1, -1);
        break;
    }
    
    synchronized(surfaces) {
      // Ensure each surface has its own output-side media loaded
      for (int si = 0; si < surfaces.size(); si++) {
        surfaces.get(si).ensureOutputMedia(this);
      }
      
      // Mark bridge frames (Playground) for texture re-upload
      for (int si = 0; si < surfaces.size(); si++) {
        Surface s = surfaces.get(si);
        if (s.isPlayground && s.videoFrame != null) {
          s.videoFrame.setModified(true);
        }
        // Images: mark modified on first use so this context uploads them
        if (!s.isVideo && !s.isPlayground && !s.isSyphonSpout && s.img != null) {
          s.img.setModified(true);
        }
      }
      
      // Force guide textures to re-upload into this GL context
      if (showMappingGuide) {
        for (PImage gt : guideTextures) gt.setModified(true);
        guideGridBg.setModified(true);
        noStroke();
        textureWrap(REPEAT);
        textureMode(IMAGE);
        beginShape(QUADS);
        texture(guideGridBg);
        vertex(0, 0, 0, 0);
        vertex(width, 0, width, 0);
        vertex(width, height, width, height);
        vertex(0, height, 0, height);
        endShape();
      }
      
      for (int si = 0; si < surfaces.size(); si++) {
        guideIndex = si;
        surfaces.get(si).display(this, false, 0, width, false);
      }
    }
    popMatrix();
  }
  
  // Called by the Video library when a frame is ready for Movies owned by this PApplet
  public void movieEvent(Movie m) {
    try { m.read(); } catch (Exception e) {}
  }
}
