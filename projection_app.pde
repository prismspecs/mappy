/**
 * Projection App - Main Module
 * This file coordinates the state and execution of the Controller and Output windows.
 */

import processing.video.*;
import processing.serial.*;
import processing.sound.*;

// Global State
ArrayList<Surface> surfaces;
Surface selectedSurface = null;
LiveAV liveAV;
Playground playground;

// Undo System
ArrayList<JSONArray> undoStack = new ArrayList<JSONArray>();
int maxUndoLevels = 50;

// UI/Interaction State
boolean isMarquee = false;
float marqueeX1, marqueeY1;
boolean isDraggingVertex = false;
boolean isDraggingShape = false;
boolean isDraggingSourceVertex = false;
boolean isDraggingSourceShape = false;
boolean undoPushedThisDrag = false;
boolean showSourceView = false;

// Configuration Constants
int SIDEBAR_WIDTH = 220;
int UI_MARGIN = 20;
int outputDisplay = 2; // Default to display 2 (projector)
int outputMirror = 0; // 0=Normal, 1=Flipped H, 2=Flipped V, 3=Flipped H+V
String[] mirrorLabels = {"Normal", "Mirror H", "Mirror V", "Mirror H+V"};

// Canvas Zoom/Pan (Controller mapping view only)
float canvasZoom = 1.0;
float canvasPanX = 0;
float canvasPanY = 0;
boolean isPanningCanvas = false;
boolean hasAutoFit = false; // Whether we've done the initial fit-to-projector

// Mapping Guide
boolean showMappingGuide = false;
PImage[] guideTextures;
PImage guideGridBg;
int guideIndex = 0;

// Secondary Window
OutputWindow output;

// Diagnostics
int diagMovieEventCount = 0;

void settings() {
  size(1200, 700, P3D);
  pixelDensity(displayDensity());
}

void setup() {
  surface.setTitle("Projection Mapper - Controller");
  
  println("--- System Diagnostics ---");
  println("OS: " + System.getProperty("os.name") + " " + System.getProperty("os.version"));
  println("Java: " + System.getProperty("java.version"));
  println("GStreamer Path Prop: " + System.getProperty("gst.plugin.path"));
  
  String osName = System.getProperty("os.name").toLowerCase();
  if (osName.contains("linux")) {
    // Linux GStreamer conflict resolution
    System.setProperty("gst.plugin.path", "/usr/lib/x86_64-linux-gnu/gstreamer-1.0");
    System.setProperty("gst.registry.fork", "false");
    
    // Aggressively disable plugins that cause SIGSEGV on Linux/NVIDIA/GStreamer 1.24
    String disableRanks = "souphttpsrc:0"
      + ",nvh264dec:0,nvh265dec:0,nvdec:0,nvenc:0,nvh264sldec:0,nvv4l2h264enc:0"
      + ",vaapidecode:0,vaapiencode:0,vaapipostproc:0"
      + ",avdec_h264:0,avdec_h265:0,avdec_mpeg4:0";
    System.setProperty("GST_PLUGIN_FEATURE_RANK", disableRanks);
    println("GST_PLUGIN_FEATURE_RANK set to: " + disableRanks);
  } else {
    println("Non-Linux OS detected, skipping GStreamer overrides.");
  }
  
  println("--------------------------");
  
  surfaces = new ArrayList<Surface>();
  
  // Initialize Live AV Manager
  liveAV = new LiveAV(this);
  
  // Initialize Playground
  playground = new Playground();
  
  // Load previous configuration
  loadConfig();
  if (surfaces.isEmpty()) {
    surfaces.add(new Surface(this));
  }
  
  // Generate guide stripe textures and grid background
  guideTextures = createGuideTextures();
  guideGridBg = createGuideGrid();
  
  // Spawn the secondary output window
  output = new OutputWindow();
  PApplet.runSketch(new String[] {"OutputWindow"}, output);
}

void draw() {
  background(25);
  
  // 0. Auto-fit to projector frame once output window is ready
  if (!hasAutoFit && output != null && output.width > 0 && output.height > 0) {
    fitToProjector();
    hasAutoFit = true;
  }
  
  // 0b. Update Live AV and Playground
  liveAV.update();
  playground.update();
  
  synchronized(surfaces) {
    // 1. Sync video bridge frames (movieEvent fires read(); here we copy pixels to PImage)
    for (Surface s : surfaces) {
      s.updateVideoBridge();
    }
    
    // 2. Draw Controller UI and Mapping Area
    drawMainWorkspace();
  }
  
  // 3. Draw Overlays
  if (isMarquee) {
    drawMarquee();
  }
  
  // 4. Draw Sidebar
  drawSidebar();
}

// Draw the marquee selection box
void drawMarquee() {
  stroke(0, 255, 255, 150);
  fill(0, 255, 255, 30);
  rect(marqueeX1, marqueeY1, mouseX - marqueeX1, mouseY - marqueeY1);
}

void mouseWheel(MouseEvent event) {
  if (mouseX < SIDEBAR_WIDTH) return;
  int mappingAreaX = SIDEBAR_WIDTH;
  if (showSourceView) {
    int viewW = (width - SIDEBAR_WIDTH) / 2;
    if (mouseX < mappingAreaX + viewW) return;
    mappingAreaX += viewW;
  }
  float e = event.getCount();
  float oldZoom = canvasZoom;
  canvasZoom *= (e < 0) ? 1.1 : (1.0 / 1.1);
  canvasZoom = constrain(canvasZoom, 0.1, 10.0);
  float mx = mouseX - mappingAreaX;
  float my = mouseY;
  canvasPanX = mx - (mx - canvasPanX) * (canvasZoom / oldZoom);
  canvasPanY = my - (my - canvasPanY) * (canvasZoom / oldZoom);
}

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

// Called by the video library on a background thread when a new frame is ready.
void movieEvent(Movie m) {
  try {
    m.read();
  } catch (Exception e) {
    // Suppress Texture.copyBufferFromSource NPE race on Mac
    return;
  }
  diagMovieEventCount++;
  if (diagMovieEventCount <= 5) {
    // Check pixels RIGHT here, before any loadPixels() call.
    // If these are non-zero, video.loadPixels() in updateVideoBridge is the bug.
    // If these are zero, the library is using a GL texture path and pixels[] is never populated.
    String p0 = (m.pixels != null && m.pixels.length > 0) ? hex(m.pixels[0]) : "null";
    String pm = (m.pixels != null && m.pixels.length > 1) ? hex(m.pixels[m.pixels.length/2]) : "null";
    println("[DIAG] movieEvent #" + diagMovieEventCount
      + "  w=" + m.width + "  h=" + m.height
      + "  pixel[0]=" + p0 + "  pixel[mid]=" + pm);
  }
}


