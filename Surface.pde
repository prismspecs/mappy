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
  PImage videoFrame;  // CPU-side bridge image for controller preview
  String mediaPath = "";
  String pendingMediaPath = "";
  boolean isVideo = false;
  boolean isPlayground = false;
  boolean isSyphonSpout = false;
  boolean isCircle = false;
  boolean isLocked = false;
  
  // Single master Movie instance, lives in output window's GL context
  Movie outputVideo;
  PGraphics outputBridgeG; // Downsampled preview generator (output context)
  boolean outputNeedsLoad = false;
  
  int gridRes = 20;
  int circleSegments = 36;
  int maxPreviewDim = 640; // Max dimension for controller preview to save CPU
  
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
    
    // Stop master video
    isVideo = false;
    if (outputVideo != null) {
      try {
        outputVideo.stop();
        delay(20);
        outputVideo.dispose();
      } catch (Exception e) {}
      outputVideo = null;
    }
    if (outputBridgeG != null) {
      outputBridgeG.dispose();
      outputBridgeG = null;
    }
    outputNeedsLoad = false;
    
    videoFrame = null;
    img = null;
    mediaPath = "";
  }

  void loadMedia(PApplet parent, String path) {
    this.pendingMediaPath = path;
  }

  private void performLoadMedia(PApplet parent, String path) {
    this.mediaPath = path;
    String lowerPath = path.toLowerCase();
    if (lowerPath.endsWith(".mp4") || lowerPath.endsWith(".mov") || lowerPath.endsWith(".avi")) {
      isVideo = true;
      img = null;
    } else {
      img = parent.loadImage(path);
      isVideo = false;
    }
    outputNeedsLoad = true;
  }
  
  /**
   * Load and update media in the output window's GL context.
   */
  void ensureOutputMedia(PApplet outputApp) {
    // 1. Handle playback, robust looping, and preview generation for master video
    if (isVideo && outputVideo != null) {
      if (outputVideo.available()) {
        try {
          outputVideo.read();
        } catch (Exception e) {}
      }
      // Robust loop: if we're near the end, jump back to 0
      if (outputVideo.duration() > 0.1 && outputVideo.time() >= outputVideo.duration() - 0.1) {
        outputVideo.jump(0);
        outputVideo.play();
      }
      
      // Generate downsampled preview if needed
      generatePreview(outputApp, outputVideo);
    }

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
        println("[OutputWindow] Master video loaded: " + mediaPath);
      } catch (Exception e) {
        println("[OutputWindow] Error loading video: " + e.getMessage());
      }
    }
  }

  /**
   * Generates a downsampled PGraphics for the controller preview.
   * Runs in the context of the applet that owns the texture (usually output window).
   */
  void generatePreview(PApplet ctx, PImage source) {
    if (source == null || source.width <= 0 || source.height <= 0) return;
    
    // Calculate downsampled dimensions
    int pw = source.width;
    int ph = source.height;
    if (pw > maxPreviewDim || ph > maxPreviewDim) {
      float aspect = (float)pw / ph;
      if (pw > ph) {
        pw = maxPreviewDim;
        ph = (int)(maxPreviewDim / aspect);
      } else {
        ph = maxPreviewDim;
        pw = (int)(maxPreviewDim * aspect);
      }
    }
    
    if (outputBridgeG == null || outputBridgeG.width != pw || outputBridgeG.height != ph) {
      if (outputBridgeG != null) outputBridgeG.dispose();
      outputBridgeG = ctx.createGraphics(pw, ph, P2D);
    }
    
    outputBridgeG.beginDraw();
    outputBridgeG.image(source, 0, 0, pw, ph);
    outputBridgeG.endDraw();
    outputBridgeG.loadPixels(); // Ready for CPU bridge
  }

  /**
   * Bridge content between contexts.
   * - Videos: Bridge from Output Window -> Controller (downsampled preview)
   * - Playground: Bridge from Controller -> Output Window (full pixels)
   * - Syphon: Bridge from Output Window -> Controller (CPU readback)
   */
  void updateVideoBridge() {
    // 1. Process thread-safe loading on the main animation thread
    if (!pendingMediaPath.equals("")) {
      performLoadMedia(mappy.this, pendingMediaPath);
      pendingMediaPath = "";
      delay(50);
    }
    
    // 2. Bridge check
    if (!isVideo && !isPlayground && !isSyphonSpout) return;
    
    // 3. Throttle bridge updates to save CPU (every other frame)
    if (frameCount % 2 != 0) return;
    
    if (isVideo) {
      // BRIDGE: Output -> Controller
      // Copy downsampled pixels from outputBridgeG (populated in output context)
      if (outputBridgeG == null || outputBridgeG.pixels == null || outputBridgeG.pixels.length == 0) return;
      syncVideoFrame(outputBridgeG);
    } 
    else if (isPlayground) {
      // BRIDGE: Controller -> Output
      // The Playground lives in THIS context. We bridge it to videoFrame
      // so the Output window can display it.
      if (playground.canvas == null) return;
      syncVideoFrame(playground.canvas);
    } 
    else if (isSyphonSpout) {
      // Syphon already bridged to syphonSpoutInput by TextureSharing update
      videoFrame = syphonSpoutInput; 
    }
  }

  /**
   * Helper to sync pixels from a source PImage/PGraphics to the videoFrame bridge.
   */
  private void syncVideoFrame(PImage source) {
    if (source.width <= 0 || source.height <= 0) return;
    
    // Use physical pixel dimensions for the bridge to avoid array size mismatch on Retina
    int pw = source.width;
    int ph = source.height;
    if (source instanceof PGraphics) {
      pw = ((PGraphics)source).pixelWidth;
      ph = ((PGraphics)source).pixelHeight;
    }
    
    if (videoFrame == null || videoFrame.width != pw || videoFrame.height != ph) {
      videoFrame = createImage(pw, ph, RGB);
    }
    
    source.loadPixels();
    if (source.pixels != null && source.pixels.length > 0) {
      videoFrame.loadPixels();
      // Ensure we don't overflow if dimensions changed mid-frame
      int len = Math.min(source.pixels.length, videoFrame.pixels.length);
      System.arraycopy(source.pixels, 0, videoFrame.pixels, 0, len);
      videoFrame.updatePixels();
    }
  }

  void display(PApplet p, boolean isController, int xOffset, int viewWidth, boolean isSourceView) {
    PImage tex;
    if (isController) {
      // Controller uses CPU-bridged preview frames for Sync
      if (isVideo || isPlayground || isSyphonSpout) tex = videoFrame;
      else tex = img;
    } else {
      // Output window: use the native Master source (no bridge overhead)
      if (isVideo) tex = outputVideo; 
      else if (isSyphonSpout) tex = outputSyphonSpoutInput; 
      else if (isPlayground) tex = videoFrame; // Playground still bridges to output
      else tex = img; 
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
    if (isVideo || isPlayground || isSyphonSpout) return videoFrame;
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
      if (outputVideo == null) {
        println("  outputVideo : NULL");
      } else {
        println("  video dims  : " + outputVideo.width + " x " + outputVideo.height);
        println("  video time  : " + outputVideo.time());
      }
    } else {
      println("  img         : " + (img == null ? "NULL" : img.width + " x " + img.height));
    }
    if (outputBridgeG != null) {
      println("  outputBridgeG : " + outputBridgeG.width + "x" + outputBridgeG.height);
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
