/**
 * Interface Module
 * Handles all UI drawing, sidebar layout, and workspace rendering.
 */

void drawMainWorkspace() {
  int mappingAreaX = SIDEBAR_WIDTH;
  int mappingAreaW = width - SIDEBAR_WIDTH;
  
  hint(DISABLE_DEPTH_TEST);
  
  if (showSourceView) {
    int viewW = mappingAreaW / 2;
    
    // Draw Source View (Left) - no zoom/pan
    fill(40);
    noStroke();
    rect(mappingAreaX, 0, viewW, height);
    if (selectedSurface != null) {
      selectedSurface.display(this, true, mappingAreaX, viewW, true);
    }
    
    fill(255, 100);
    textAlign(CENTER, TOP);
    text("SOURCE VIEW (CROPPING)", mappingAreaX + viewW/2, 10);
    
    // Draw Mapping View (Right) - with zoom/pan
    if (showMappingGuide) {
      drawGuideBackground(mappingAreaX + viewW, 0, viewW, height);
    } else {
      fill(20);
      noStroke();
      rect(mappingAreaX + viewW, 0, viewW, height);
    }
    
    renderMappingView(mappingAreaX + viewW, 0, viewW, height);
    
    fill(255, 100);
    textAlign(CENTER, TOP);
    text("MAPPING VIEW (OUTPUT)", mappingAreaX + viewW + viewW/2, 10);
    
    stroke(0);
    line(mappingAreaX + viewW, 0, mappingAreaX + viewW, height);
  } else {
    // Full Mapping View - with zoom/pan
    if (showMappingGuide) {
      drawGuideBackground(mappingAreaX, 0, mappingAreaW, height);
    }
    
    renderMappingView(mappingAreaX, 0, mappingAreaW, height);
    
    fill(255, 100);
    textAlign(CENTER, TOP);
    text("MAPPING VIEW", mappingAreaX + mappingAreaW/2, 10);
  }
}

void renderMappingView(int x, int y, int w, int h) {
  clip(x, y, w, h);
  pushMatrix();
  translate(x + canvasPanX, y + canvasPanY);
  scale(canvasZoom);
  drawProjectorFrame();
  for (int si = 0; si < surfaces.size(); si++) {
    guideIndex = si;
    surfaces.get(si).display(this, true, 0, w, false);
    if (showMappingGuide) drawLayerNumber(surfaces.get(si), si);
    if (surfaces.get(si).isLocked) drawLockIndicator(surfaces.get(si));
  }
  popMatrix();
  noClip();
}

void drawSidebar() {
  fill(45);
  noStroke();
  rect(0, 0, SIDEBAR_WIDTH, height);
  
  fill(255);
  textSize(14);
  textAlign(LEFT, TOP);
  text("CONTROLS", UI_MARGIN, 12);
  
  float btnY = 38;
  float btnW = SIDEBAR_WIDTH - (UI_MARGIN * 2);
  float btnH = 26;
  float spacing = 5;
  
  textSize(11);
  drawButton(UI_MARGIN, btnY, btnW, btnH, "Add Quad (A)", false);
  btnY += btnH + spacing;
  drawButton(UI_MARGIN, btnY, btnW, btnH, "Add Circle (C)", false);
  btnY += btnH + spacing;
  drawButton(UI_MARGIN, btnY, btnW, btnH, "Load Media (L)", false);
  btnY += btnH + spacing;
  drawButton(UI_MARGIN, btnY, btnW, btnH, "Source View (V)", showSourceView);
  btnY += btnH + spacing;
  drawButton(UI_MARGIN, btnY, btnW, btnH, "Playground (P)", selectedSurface != null && selectedSurface.isPlayground);
  btnY += btnH + spacing;
  drawButton(UI_MARGIN, btnY, btnW, btnH, "Syphon/Spout (T)", selectedSurface != null && selectedSurface.isSyphonSpout);
  btnY += btnH + spacing;
  drawButton(UI_MARGIN, btnY, btnW, btnH, "Delete Quad (D)", false);
  btnY += btnH + spacing;
  drawButton(UI_MARGIN, btnY, btnW, btnH, "Save Config (S)", false);
  btnY += btnH + spacing;
  drawButton(UI_MARGIN, btnY, btnW, btnH, "Mirror (M): " + mirrorLabels[outputMirror], false);
  btnY += btnH + spacing;
  drawButton(UI_MARGIN, btnY, btnW, btnH, "Guide (G): " + (showMappingGuide ? "ON" : "OFF"), showMappingGuide);
  btnY += btnH + spacing;
  drawButton(UI_MARGIN, btnY, btnW, btnH, "Lock (X)", selectedSurface != null && selectedSurface.isLocked);
  btnY += btnH + spacing;
  
  // Layer ordering buttons (half-width side by side)
  float halfW = (btnW - spacing) / 2;
  drawButton(UI_MARGIN, btnY, halfW, btnH, "Layer Up ([)", false);
  drawButton(UI_MARGIN + halfW + spacing, btnY, halfW, btnH, "Layer Dn (])", false);
  
  btnY += btnH + 12;
  stroke(100);
  line(UI_MARGIN, btnY, SIDEBAR_WIDTH - UI_MARGIN, btnY);
  
  btnY += 8;
  fill(180);
  textSize(10);
  textAlign(LEFT, TOP);
  text("Display: " + outputDisplay + "  Zoom: " + nf(canvasZoom * 100, 0, 0) + "%", UI_MARGIN, btnY);
  btnY += 16;
  text("Quads: " + surfaces.size(), UI_MARGIN, btnY);
  
  int selectedCount = 0;
  for (Surface s : surfaces) {
    for (boolean b : s.selectedCorners) if (b) selectedCount++;
  }
  if (selectedCount > 0) {
    text("  Sel. Vertices: " + selectedCount, UI_MARGIN + 60, btnY);
  }
  
  if (selectedSurface != null) {
    btnY += 20;
    fill(0, 255, 0);
    textSize(10);
    text("SELECTED:", UI_MARGIN, btnY);
    btnY += 14;
    fill(200);
    String path = selectedSurface.mediaPath;
    if (selectedSurface.isPlayground) path = "Playground";
    else if (selectedSurface.isSyphonSpout) path = "Syphon/Spout Input";
    else if (path.equals("")) path = "No media";
    else {
      File f = new File(path);
      path = f.getName();
    }
    text(path, UI_MARGIN, btnY, btnW, 40);
  }
  
  fill(120);
  textSize(9);
  textAlign(LEFT, BOTTOM);
  String help = "Scroll:Zoom  ALT+Drag:Pan  0:Reset\nSHIFT:Multi-select  [/]:Reorder  Cmd-Z:Undo";
  text(help, UI_MARGIN, height - 8);
}

void drawButton(float x, float y, float w, float h, String label, boolean active) {
  boolean hover = mouseX > x && mouseX < x + w && mouseY > y && mouseY < y + h;
  if (active) {
    fill(hover ? 80 : 45, hover ? 160 : 130, hover ? 80 : 45);
  } else {
    fill(hover ? 75 : 55);
  }
  stroke(active ? color(60, 160, 60) : 90);
  rect(x, y, w, h, 4);
  fill(255);
  textAlign(CENTER, CENTER);
  text(label, x + w/2, y + h/2);
}

void drawGuideBackground(float x, float y, float w, float h) {
  noStroke();
  textureWrap(REPEAT);
  textureMode(IMAGE);
  beginShape(QUADS);
  texture(guideGridBg);
  vertex(x, y, 0, 0);
  vertex(x + w, y, w, 0);
  vertex(x + w, y + h, w, h);
  vertex(x, y + h, 0, h);
  endShape();
}

void drawProjectorFrame() {
  if (output == null || output.width <= 0 || output.height <= 0) return;
  // Dashed-style projector boundary
  stroke(255, 255, 255, 80);
  strokeWeight(1.0 / canvasZoom); // Keep 1px regardless of zoom
  noFill();
  rect(0, 0, output.width, output.height);
  // Corner ticks for visibility
  float tick = 20;
  stroke(255, 255, 255, 150);
  // Top-left
  line(0, 0, tick, 0); line(0, 0, 0, tick);
  // Top-right
  line(output.width, 0, output.width - tick, 0); line(output.width, 0, output.width, tick);
  // Bottom-right
  line(output.width, output.height, output.width - tick, output.height); line(output.width, output.height, output.width, output.height - tick);
  // Bottom-left
  line(0, output.height, tick, output.height); line(0, output.height, 0, output.height - tick);
  // Label
  fill(255, 255, 255, 60);
  noStroke();
  textSize(12 / canvasZoom);
  textAlign(LEFT, TOP);
  text("PROJECTOR  " + output.width + "x" + output.height, 4, 4);
  strokeWeight(1);
}

void drawLayerNumber(Surface s, int idx) {
  // Draw layer index at top-right corner of the surface
  float labelX = s.corners[1].x;  // Top-right corner
  float labelY = s.corners[1].y;
  float sz = 14 / canvasZoom;
  float pad = 3 / canvasZoom;
  String label = str(idx);
  textSize(sz);
  float tw = textWidth(label) + pad * 2;
  float th = sz + pad * 2;
  // Background pill
  fill(0, 200);
  noStroke();
  rect(labelX - tw - 2 / canvasZoom, labelY + 2 / canvasZoom, tw, th, 3 / canvasZoom);
  // Number text
  fill(255);
  textAlign(CENTER, TOP);
  text(label, labelX - tw / 2 - 2 / canvasZoom, labelY + 2 / canvasZoom + pad);
}

void drawLockIndicator(Surface s) {
  // Draw a lock icon at top-left corner of the surface
  float cx = (s.corners[0].x + s.corners[1].x + s.corners[2].x + s.corners[3].x) / 4;
  float cy = (s.corners[0].y + s.corners[1].y + s.corners[2].y + s.corners[3].y) / 4;
  float sz = 12 / canvasZoom;
  float pad = 3 / canvasZoom;
  String icon = "LOCKED";
  textSize(sz);
  float tw = textWidth(icon) + pad * 2;
  float th = sz + pad * 2;
  fill(200, 60, 60, 200);
  noStroke();
  rect(cx - tw / 2, cy - th / 2, tw, th, 3 / canvasZoom);
  fill(255);
  textAlign(CENTER, CENTER);
  text(icon, cx, cy - 1 / canvasZoom);
}

// --- Guide Generation Helpers ---

PImage[] createGuideTextures() {
  int[][] cols = {
    {255, 60, 60},   // 0 red
    {60, 220, 220},  // 1 cyan
    {60, 220, 60},   // 2 green
    {255, 200, 40},  // 3 yellow
    {200, 60, 255},  // 4 purple
    {255, 130, 40},  // 5 orange
    {60, 120, 255},  // 6 blue
    {255, 60, 180},  // 7 pink
    {120, 255, 60},  // 8 lime
    {180, 130, 255}  // 9 lavender
  };
  PImage[] tex = new PImage[cols.length];
  int sz = 128;
  int sw = 8;
  for (int t = 0; t < cols.length; t++) {
    PImage img = createImage(sz, sz, RGB);
    img.loadPixels();
    int r = cols[t][0], g = cols[t][1], b = cols[t][2];
    for (int y = 0; y < sz; y++) {
      for (int x = 0; x < sz; x++) {
        if (((x + y) / sw) % 2 == 0) img.pixels[y * sz + x] = color(r, g, b);
        else img.pixels[y * sz + x] = color(r/4, g/4, b/4);
      }
    }
    img.updatePixels();
    tex[t] = img;
  }
  return tex;
}

PImage createGuideGrid() {
  int sz = 256;
  int gridSpacing = 32;
  PImage img = createImage(sz, sz, RGB);
  img.loadPixels();
  for (int y = 0; y < sz; y++) {
    for (int x = 0; x < sz; x++) {
      if (x % gridSpacing == 0 || y % gridSpacing == 0) {
        img.pixels[y * sz + x] = color(120);
      } else {
        img.pixels[y * sz + x] = color(30);
      }
    }
  }
  img.updatePixels();
  return img;
}
