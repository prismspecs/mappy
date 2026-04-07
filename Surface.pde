/**
 * Surface Module
 * Handles individual mapping quads, texture interpolation, and cross-window video bridging.
 */

class Surface {
  PVector[] corners;
  PVector[] sourceCorners;
  boolean[] selectedCorners;
  boolean[] selectedSourceCorners;
  boolean isSelected = false;
  
  PImage img;
  Movie video;
  PGraphics bridgeG;  // Offscreen PGraphics for GPU->CPU pixel readback (Playground only)
  PImage videoFrame;  // CPU-side bridge image (Playground only, not needed for video/images)
  String mediaPath = "";
  String pendingMediaPath = "";
  boolean isVideo = false;
  boolean isPlayground = false;
  boolean isSyphonSpout = false;
  boolean isCircle = false;
  boolean isLocked = false;
  
  // Output window's own resources (avoids expensive CPU pixel bridge)
  Movie outputVideo;
  boolean outputNeedsLoad = false;
  
  int gridRes = 20;
  int circleSegments = 36;
  
  Surface(PApplet parent) {
    corners = new PVector[4];
    sourceCorners = new PVector[4];
    selectedCorners = new boolean[4];
    selectedSourceCorners = new boolean[4];
    
    corners[0] = new PVector(150, 100);
    corners[1] = new PVector(350, 100);
    corners[2] = new PVector(350, 300);
    corners[3] = new PVector(150, 300);
    
    sourceCorners[0] = new PVector(0, 0);
    sourceCorners[1] = new PVector(1, 0);
    sourceCorners[2] = new PVector(1, 1);
    sourceCorners[3] = new PVector(0, 1);
  }
  
  Surface(PApplet parent, JSONObject json) {
    this(parent);
    JSONArray jsonCorners = json.getJSONArray("corners");
    for (int i = 0; i < 4; i++) {
      JSONObject cp = jsonCorners.getJSONObject(i);
      corners[i] = new PVector(cp.getFloat("x"), cp.getFloat("y"));
    }
    JSONArray jsonSrc = json.getJSONArray("sourceCorners");
    if (jsonSrc != null) {
      for (int i = 0; i < 4; i++) {
        JSONObject cp = jsonSrc.getJSONObject(i);
        sourceCorners[i] = new PVector(cp.getFloat("x"), cp.getFloat("y"));
      }
    }
    mediaPath = json.getString("mediaPath", "");
    if (!mediaPath.equals("")) loadMedia(parent, mediaPath);
    
    isPlayground = json.getBoolean("isPlayground", false);
    if (isPlayground) setPlayground(true);
    
    isSyphonSpout = json.getBoolean("isSyphonSpout", false);
    if (isSyphonSpout) setSyphonSpout(true);
    
    isCircle = json.getBoolean("isCircle", false);
    isLocked = json.getBoolean("isLocked", false);
  }
  
  void setPlayground(boolean pg) {
    if (pg && !isPlayground) {
      unloadMedia();
      isPlayground = true;
      playground.trigger(true);
    } else if (!pg && isPlayground) {
      isPlayground = false;
      playground.trigger(false);
    }
  }
  
  void setSyphonSpout(boolean ss) {
    if (ss && !isSyphonSpout) {
      unloadMedia();
      isSyphonSpout = true;
    } else if (!ss && isSyphonSpout) {
      isSyphonSpout = false;
    }
  }
  
  void unloadMedia() {
    if (isPlayground) {
      playground.trigger(false);
      isPlayground = false;
    }
    isSyphonSpout = false;
    
    // Set isVideo to false FIRST to stop other threads from accessing 'video'
    isVideo = false;
    
    if (video != null) {
      try {
        video.stop();
        delay(20);
        video.dispose();
      } catch (Exception e) {}
      video = null;
    }
    
    if (outputVideo != null) {
      try {
        outputVideo.stop();
        delay(20);
        outputVideo.dispose();
      } catch (Exception e) {}
      outputVideo = null;
    }
    outputNeedsLoad = false;
    
    if (bridgeG != null) {
      bridgeG.dispose();
      bridgeG = null;
    }
    videoFrame = null;
    img = null;
    mediaPath = "";
  }

  void loadMedia(PApplet parent, String path) {
    this.pendingMediaPath = path;
  }

  private void performLoadMedia(PApplet parent, String path) {
    // Stop and release any previously loaded video before replacing it
    if (video != null) {
      video.stop();
      video.dispose();
      video = null;
    }
    if (bridgeG != null) {
      bridgeG.dispose();
      bridgeG = null;
    }
    videoFrame = null;

    this.mediaPath = path;
    String lowerPath = path.toLowerCase();
    if (lowerPath.endsWith(".mp4") || lowerPath.endsWith(".mov") || lowerPath.endsWith(".avi")) {
      try {
        println("[DEBUG] [Surface] GStreamer Load Start: " + path);
        video = new Movie(parent, path);
        println("[DEBUG] [Surface] GStreamer Load Success: " + path);
        video.loop();
        video.volume(0);  // Mute controller copy — output window plays audio
        isVideo = true;
        img = null;
      } catch (Exception e) {
        println("Error loading video: " + e.getMessage());
      }
    } else {
      img = parent.loadImage(path);
      isVideo = false;
    }
    outputNeedsLoad = true;
  }
  
  /**
   * Load media in the output window's GL context.
   * Called from OutputWindow.draw() so textures are native — no CPU bridge needed.
   */
  void ensureOutputMedia(PApplet outputApp) {
    if (!outputNeedsLoad) return;
    outputNeedsLoad = false;
    
    if (outputVideo != null) {
      try { outputVideo.stop(); outputVideo.dispose(); } catch (Exception e) {}
      outputVideo = null;
    }
    
    if (mediaPath.equals("")) return;
    
    String lowerPath = mediaPath.toLowerCase();
    if (lowerPath.endsWith(".mp4") || lowerPath.endsWith(".mov") || lowerPath.endsWith(".avi")) {
      try {
        outputVideo = new Movie(outputApp, mediaPath);
        outputVideo.loop();
        println("[OutputWindow] Video loaded: " + mediaPath);
      } catch (Exception e) {
        println("[OutputWindow] Error loading video: " + e.getMessage());
      }
    }
    // Images (img) work cross-context via CPU pixels — no output copy needed
  }

  /**
   * Process pending media loads and bridge Playground content.
   * Video and images no longer need the CPU bridge — the output window
   * loads its own Movie/PImage in its own GL context (see ensureOutputMedia).
   * The bridge is only used for Playground (PGraphics sources).
   */
  void updateVideoBridge() {
    // 1. Process thread-safe loading on the main animation thread
    if (!pendingMediaPath.equals("")) {
      performLoadMedia(mappy.this, pendingMediaPath);
      pendingMediaPath = "";
      delay(50);
    }
    
    // 2. Bridge only needed for Playground (PGraphics sources)
    //    Syphon/Spout uses per-context clients — no CPU bridge.
    if (!isPlayground) return;
    
    // 3. Throttle: every other frame to save CPU
    if (frameCount % 2 != 0) return;
    
    PGraphics sourceCanvas = playground.canvas;
    if (sourceCanvas == null) return;
    
    int pw = sourceCanvas.pixelWidth;
    int ph = sourceCanvas.pixelHeight;
    
    // Playground: render through bridgeG then readback
    if (bridgeG == null || bridgeG.width != sourceCanvas.width || bridgeG.height != sourceCanvas.height) {
      if (bridgeG != null) bridgeG.dispose();
      bridgeG = createGraphics(sourceCanvas.width, sourceCanvas.height, P2D);
    }
    bridgeG.beginDraw();
    bridgeG.image(sourceCanvas, 0, 0);
    bridgeG.endDraw();
    bridgeG.loadPixels();
    pw = bridgeG.pixelWidth;
    ph = bridgeG.pixelHeight;
    if (videoFrame == null || videoFrame.width != pw || videoFrame.height != ph) {
      videoFrame = createImage(pw, ph, RGB);
    }
    videoFrame.loadPixels();
    System.arraycopy(bridgeG.pixels, 0, videoFrame.pixels, 0, bridgeG.pixels.length);
    videoFrame.updatePixels();
  }

  void display(PApplet p, boolean isController, int xOffset, int viewWidth, boolean isSourceView) {
    PImage tex;
    if (isController) {
      // Controller uses native GL textures (same GL context) — no bridge overhead
      if (isVideo && video != null) tex = video;
      else if (isPlayground) tex = playground.canvas;
      else if (isSyphonSpout) tex = syphonSpoutInput;
      else tex = img;
    } else {
      // Output window: use its own Movie, or output-side Syphon client, or bridge for Playground
      if (isVideo) tex = outputVideo; // Own Movie in output GL context
      else if (isSyphonSpout) tex = outputSyphonSpoutInput; // Own client in output GL context
      else if (isPlayground) tex = videoFrame; // CPU bridge (throttled)
      else tex = img; // PImages work cross-context (CPU pixel data)
    }
    
    p.pushMatrix();
    p.translate(xOffset, 0);
    
    if (isSourceView) {
      drawSourceView(p, tex, viewWidth);
    } else {
      drawMappingView(p, tex, isController);
    }
    p.popMatrix();
  }

  private void drawSourceView(PApplet p, PImage tex, int viewWidth) {
    if (tex == null) return;
    float aspect = (float)tex.width / tex.height;
    float drawW = viewWidth - 40;
    float drawH = drawW / aspect;
    if (drawH > p.height - 40) {
      drawH = p.height - 40;
      drawW = drawH * aspect;
    }
    float dx = (viewWidth - drawW) / 2;
    float dy = (p.height - drawH) / 2;
    
    p.image(tex, dx, dy, drawW, drawH);
    
    if (isSelected) {
      p.stroke(255, 255, 0, 150);
      p.fill(255, 255, 0, 40);
      p.beginShape();
      for (int i = 0; i < 4; i++) p.vertex(dx + sourceCorners[i].x * drawW, dy + sourceCorners[i].y * drawH);
      p.endShape(CLOSE);
      
      for (int i = 0; i < 4; i++) {
        p.fill(selectedSourceCorners[i] ? p.color(255, 0, 0) : p.color(255, 255, 0));
        p.noStroke();
        p.ellipse(dx + sourceCorners[i].x * drawW, dy + sourceCorners[i].y * drawH, 10, 10);
      }
    }
  }

  private void drawMappingView(PApplet p, PImage tex, boolean isController) {
    PImage activeTex = tex;
    PVector[] activeSrc = sourceCorners;
    
    if (showMappingGuide) {
      activeTex = guideTextures[guideIndex % guideTextures.length];
      activeSrc = new PVector[] {
        new PVector(0, 0), new PVector(1, 0),
        new PVector(1, 1), new PVector(0, 1)
      };
    }
    
    if (isCircle) {
      drawCircleMappingView(p, activeTex, activeSrc, isController);
    } else {
      drawQuadMappingView(p, activeTex, activeSrc, isController);
    }
  }
  
  private void drawQuadMappingView(PApplet p, PImage activeTex, PVector[] activeSrc, boolean isController) {
    if (activeTex != null) {
      p.noStroke();
      p.beginShape(QUADS);
      p.texture(activeTex);
      p.textureMode(NORMAL);
      for (int y = 0; y < gridRes; y++) {
        for (int x = 0; x < gridRes; x++) {
          float u1 = (float)x / gridRes; float v1 = (float)y / gridRes;
          float u2 = (float)(x+1) / gridRes; float v2 = (float)(y+1) / gridRes;
          PVector p1 = getBilinearPoint(u1, v1, corners);
          PVector p2 = getBilinearPoint(u2, v1, corners);
          PVector p3 = getBilinearPoint(u2, v2, corners);
          PVector p4 = getBilinearPoint(u1, v2, corners);
          PVector t1 = getBilinearPoint(u1, v1, activeSrc);
          PVector t2 = getBilinearPoint(u2, v1, activeSrc);
          PVector t3 = getBilinearPoint(u2, v2, activeSrc);
          PVector t4 = getBilinearPoint(u1, v2, activeSrc);

          p.vertex(p1.x, p1.y, t1.x, t1.y);
          p.vertex(p2.x, p2.y, t2.x, t2.y);
          p.vertex(p3.x, p3.y, t3.x, t3.y);
          p.vertex(p4.x, p4.y, t4.x, t4.y);
        }
      }
      p.endShape();
    } else {
      p.stroke(255, 100);
      if (isSelected && isController) p.fill(0, 255, 0, 40);
      else p.noFill();
      p.beginShape();
      for (PVector c : corners) p.vertex(c.x, c.y);
      p.endShape(CLOSE);
    }
    
    if (isController) {
      if (isSelected) {
        p.stroke(0, 255, 0, 150); p.strokeWeight(2); p.noFill();
        p.beginShape();
        for (PVector c : corners) p.vertex(c.x, c.y);
        p.endShape(CLOSE);
        p.strokeWeight(1);
      }
      for (int i = 0; i < 4; i++) {
        p.stroke(255);
        p.fill(selectedCorners[i] ? p.color(255, 255, 0) : p.color(0, 255, 0));
        p.ellipse(corners[i].x, corners[i].y, 12, 12);
      }
    }
  }
  
  private void drawCircleMappingView(PApplet p, PImage activeTex, PVector[] activeSrc, boolean isController) {
    if (activeTex != null) {
      p.noStroke();
      p.textureMode(NORMAL);
      // Polar mesh: rings × segments, mapped through the quad's bilinear transform
      int rings = gridRes;
      for (int r = 0; r < rings; r++) {
        float r1 = (float)r / rings * 0.5;
        float r2 = (float)(r + 1) / rings * 0.5;
        p.beginShape(QUAD_STRIP);
        p.texture(activeTex);
        for (int s = 0; s <= circleSegments; s++) {
          float angle = TWO_PI * s / circleSegments;
          float cosA = cos(angle);
          float sinA = sin(angle);
          // UV coords in the 0-1 quad space
          float u1 = 0.5 + r1 * cosA; float v1 = 0.5 + r1 * sinA;
          float u2 = 0.5 + r2 * cosA; float v2 = 0.5 + r2 * sinA;
          PVector pos1 = getBilinearPoint(u1, v1, corners);
          PVector pos2 = getBilinearPoint(u2, v2, corners);
          PVector tex1 = getBilinearPoint(u1, v1, activeSrc);
          PVector tex2 = getBilinearPoint(u2, v2, activeSrc);

          p.vertex(pos1.x, pos1.y, tex1.x, tex1.y);
          p.vertex(pos2.x, pos2.y, tex2.x, tex2.y);
        }
        p.endShape();
      }
    } else {
      // Draw ellipse outline from corners
      p.stroke(255, 100);
      if (isSelected && isController) p.fill(0, 255, 0, 40);
      else p.noFill();
      p.beginShape();
      for (int s = 0; s <= circleSegments; s++) {
        float angle = TWO_PI * s / circleSegments;
        float u = 0.5 + 0.5 * cos(angle);
        float v = 0.5 + 0.5 * sin(angle);
        PVector pt = getBilinearPoint(u, v, corners);
        p.vertex(pt.x, pt.y);
      }
      p.endShape(CLOSE);
    }
    
    if (isController) {
      if (isSelected) {
        p.stroke(0, 255, 0, 150); p.strokeWeight(2); p.noFill();
        p.beginShape();
        for (int s = 0; s <= circleSegments; s++) {
          float angle = TWO_PI * s / circleSegments;
          float u = 0.5 + 0.5 * cos(angle);
          float v = 0.5 + 0.5 * sin(angle);
          PVector pt = getBilinearPoint(u, v, corners);
          p.vertex(pt.x, pt.y);
        }
        p.endShape(CLOSE);
        p.strokeWeight(1);
      }
      for (int i = 0; i < 4; i++) {
        p.stroke(255);
        p.fill(selectedCorners[i] ? p.color(255, 255, 0) : p.color(0, 255, 0));
        p.ellipse(corners[i].x, corners[i].y, 12, 12);
      }
    }
  }
  
  // Helper: get the texture reference for the controller context
  PImage getControllerTex() {
    if (isVideo && video != null) return video;
    if (isPlayground) return playground.canvas;
    if (isSyphonSpout) return syphonSpoutInput;
    return img;
  }
  
  PVector getBilinearPoint(float u, float v, PVector[] pts) {
    PVector pTop = PVector.lerp(pts[0], pts[1], u);
    PVector pBottom = PVector.lerp(pts[3], pts[2], u);
    return PVector.lerp(pTop, pBottom, v);
  }
  
  void move(float dx, float dy) {
    for (PVector c : corners) c.add(dx, dy);
  }
  
  void moveSource(float du, float dv) {
    for (PVector c : sourceCorners) {
      c.x = constrain(c.x + du, 0, 1);
      c.y = constrain(c.y + dv, 0, 1);
    }
    sourceCorners[1].y = sourceCorners[0].y;
    sourceCorners[3].x = sourceCorners[0].x;
    sourceCorners[2].x = sourceCorners[1].x;
    sourceCorners[2].y = sourceCorners[3].y;
  }
  
  void moveSelectedCorners(float dx, float dy) {
    for (int i = 0; i < 4; i++) if (selectedCorners[i]) corners[i].add(dx, dy);
  }
  
  void moveSelectedSourceCorners(float du, float dv) {
    for (int i = 0; i < 4; i++) {
      if (selectedSourceCorners[i]) {
        sourceCorners[i].x = constrain(sourceCorners[i].x + du, 0, 1);
        sourceCorners[i].y = constrain(sourceCorners[i].y + dv, 0, 1);
        if (i == 0) { sourceCorners[1].y = sourceCorners[0].y; sourceCorners[3].x = sourceCorners[0].x; }
        else if (i == 1) { sourceCorners[0].y = sourceCorners[1].y; sourceCorners[2].x = sourceCorners[1].x; }
        else if (i == 2) { sourceCorners[3].y = sourceCorners[2].y; sourceCorners[1].x = sourceCorners[2].x; }
        else if (i == 3) { sourceCorners[2].y = sourceCorners[3].y; sourceCorners[0].x = sourceCorners[3].x; }
      }
    }
  }

  int getCornerAt(float x, float y, int xOffset) {
    float tx = x - xOffset; float ty = y;
    for (int i = 0; i < 4; i++) if (dist(tx, ty, corners[i].x, corners[i].y) < 15) return i;
    return -1;
  }

  int getEdgeAt(float x, float y, int xOffset) {
    float tx = x - xOffset; float ty = y;
    for (int i = 0; i < 4; i++) {
      PVector p1 = corners[i]; PVector p2 = corners[(i + 1) % 4];
      if (distToSegment(tx, ty, p1.x, p1.y, p2.x, p2.y) < 10) return i;
    }
    return -1;
  }

  float distToSegment(float px, float py, float x1, float y1, float x2, float y2) {
    float l2 = (x1 - x2) * (x1 - x2) + (y1 - y2) * (y1 - y2);
    if (l2 == 0) return dist(px, py, x1, y1);
    float t = ((px - x1) * (x2 - x1) + (py - y1) * (y2 - y1)) / l2;
    t = max(0, min(1, t));
    return dist(px, py, x1 + t * (x2 - x1), y1 + t * (y2 - y1));
  }
  
  int getSourceCornerAt(float x, float y, int xOffset, int viewWidth, PApplet p) {
    PImage tex = getControllerTex();
    if (tex == null) return -1;
    float aspect = (float)tex.width / tex.height;
    float drawW = viewWidth - 40; float drawH = drawW / aspect;
    if (drawH > p.height - 40) { drawH = p.height - 40; drawW = drawH * aspect; }
    float dx = (viewWidth - drawW) / 2 + xOffset;
    float dy = (p.height - drawH) / 2;
    for (int i = 0; i < 4; i++) if (dist(x, y, dx + sourceCorners[i].x * drawW, dy + sourceCorners[i].y * drawH) < 15) return i;
    return -1;
  }
  
  boolean isInside(float x, float y, int xOffset) {
    float tx = x - xOffset; float ty = y;
    if (isCircle) {
      // Approximate ellipse from bounding quad
      float cx = (corners[0].x + corners[1].x + corners[2].x + corners[3].x) / 4;
      float cy = (corners[0].y + corners[1].y + corners[2].y + corners[3].y) / 4;
      float rx = (dist(corners[0].x, corners[0].y, corners[1].x, corners[1].y)
                + dist(corners[3].x, corners[3].y, corners[2].x, corners[2].y)) / 4;
      float ry = (dist(corners[0].x, corners[0].y, corners[3].x, corners[3].y)
                + dist(corners[1].x, corners[1].y, corners[2].x, corners[2].y)) / 4;
      if (rx == 0 || ry == 0) return false;
      float dx = (tx - cx) / rx;
      float dy2 = (ty - cy) / ry;
      return dx * dx + dy2 * dy2 <= 1;
    }
    int i, j; boolean c = false;
    for (i = 0, j = 3; i < 4; j = i++) {
      if (((corners[i].y > ty) != (corners[j].y > ty)) && (tx < (corners[j].x - corners[i].x) * (ty - corners[i].y) / (corners[j].y - corners[i].y) + corners[i].x)) c = !c;
    }
    return c;
  }
  
  boolean isInsideSource(float x, float y, int xOffset, int viewWidth, PApplet p) {
    PImage tex = getControllerTex();
    if (tex == null) return false;
    float aspect = (float)tex.width / tex.height;
    float drawW = viewWidth - 40; float drawH = drawW / aspect;
    if (drawH > p.height - 40) { drawH = p.height - 40; drawW = drawH * aspect; }
    float dx = (viewWidth - drawW) / 2 + xOffset; float dy = (p.height - drawH) / 2;
    float tx = (x - dx) / drawW; float ty = (y - dy) / drawH;
    float minX = min(sourceCorners[0].x, sourceCorners[2].x); float maxX = max(sourceCorners[0].x, sourceCorners[2].x);
    float minY = min(sourceCorners[0].y, sourceCorners[2].y); float maxY = max(sourceCorners[0].y, sourceCorners[2].y);
    return tx > minX && tx < maxX && ty > minY && ty < maxY;
  }
  
  void selectCornersInBox(float x1, float y1, float x2, float y2, int xOffset) {
    float tx1 = min(x1, x2) - xOffset; float ty1 = min(y1, y2);
    float tx2 = max(x1, x2) - xOffset; float ty2 = max(y1, y2);
    for (int i = 0; i < 4; i++) if (corners[i].x > tx1 && corners[i].x < tx2 && corners[i].y > ty1 && corners[i].y < ty2) selectedCorners[i] = true;
  }
  
  void clearSelection() {
    isSelected = false;
    for (int i = 0; i < 4; i++) { selectedCorners[i] = false; selectedSourceCorners[i] = false; }
  }
  
  void clearSourceSelection() { for (int i = 0; i < 4; i++) selectedSourceCorners[i] = false; }

  void printDiag(int idx) {
    println("  --- Surface[" + idx + "] ---");
    println("  mediaPath   : " + mediaPath);
    println("  isVideo     : " + isVideo);
    println("  isPlayground: " + isPlayground);
    println("  isSyphonSpout: " + isSyphonSpout);
    println("  isCircle    : " + isCircle);
    if (isPlayground) {
      println("  pg canvas   : " + playground.canvas.width + " x " + playground.canvas.height);
    } else if (isVideo) {
      if (video == null) {
        println("  video       : NULL");
      } else {
        println("  video dims  : " + video.width + " x " + video.height);
        println("  video time  : " + video.time());
      }
      println("  outputVideo : " + (outputVideo == null ? "NULL" : outputVideo.width + " x " + outputVideo.height));
    } else {
      println("  img         : " + (img == null ? "NULL" : img.width + " x " + img.height));
    }
    if (bridgeG != null) {
      println("  bridgeG     : " + bridgeG.width + "x" + bridgeG.height);
    }
    if (videoFrame != null) {
      println("  videoFrame  : " + videoFrame.width + "x" + videoFrame.height);
    }
  }

  JSONObject toJSON() {
    JSONObject json = new JSONObject();
    JSONArray jsonCorners = new JSONArray();
    for (int i = 0; i < 4; i++) { JSONObject cp = new JSONObject(); cp.setFloat("x", corners[i].x); cp.setFloat("y", corners[i].y); jsonCorners.setJSONObject(i, cp); }
    json.setJSONArray("corners", jsonCorners);
    JSONArray jsonSrc = new JSONArray();
    for (int i = 0; i < 4; i++) { JSONObject cp = new JSONObject(); cp.setFloat("x", sourceCorners[i].x); cp.setFloat("y", sourceCorners[i].y); jsonSrc.setJSONObject(i, cp); }
    json.setJSONArray("sourceCorners", jsonSrc);
    json.setString("mediaPath", mediaPath);
    json.setBoolean("isPlayground", isPlayground);
    json.setBoolean("isSyphonSpout", isSyphonSpout);
    json.setBoolean("isCircle", isCircle);
    json.setBoolean("isLocked", isLocked);
    return json;
  }
}
