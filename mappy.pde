/**
 * Projection App - Main Module
 * This file coordinates the state and execution of the Controller and Output windows.
 */

import processing.video.*;
import processing.serial.*;

// --- Core State ---
ArrayList<Surface> surfaces;
Surface selectedSurface = null;
Playground playground;
OutputWindow output;

// --- Undo/Redo ---
ArrayList<JSONArray> undoStack = new ArrayList<JSONArray>();
int maxUndoLevels = 50;

// --- Interaction State ---
boolean isMarquee = false;
float marqueeX1, marqueeY1;
boolean isDraggingVertex = false;
boolean isDraggingShape = false;
boolean isDraggingSourceVertex = false;
boolean isDraggingSourceShape = false;
boolean isPanningCanvas = false;
boolean showSourceView = false;
boolean undoPushedThisDrag = false;

// --- Viewport State (Controller only) ---
float canvasZoom = 1.0;
float canvasPanX = 0;
float canvasPanY = 0;
boolean hasAutoFit = false;

// --- Display Configuration ---
int SIDEBAR_WIDTH = 220;
int UI_MARGIN = 20;
int outputDisplay = 2; // Default to display 2 (projector)
int outputMirror = 0; // 0=Normal, 1=H, 2=V, 3=H+V
String[] mirrorLabels = {"Normal", "Mirror H", "Mirror V", "Mirror H+V"};

// --- Mapping Guides ---
boolean showMappingGuide = false;
PImage[] guideTextures;
PImage guideGridBg;
int guideIndex = 0;

// --- Debug/Diagnostics ---
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
  
  // Initialize Playground
  playground = new Playground(this);
  
  // Load previous configuration
  loadConfig();
  if (surfaces.isEmpty()) {
    surfaces.add(new Surface(this));
  }
  
  // Start Syphon/Spout receiver if any surface needs it
  for (Surface s : surfaces) {
    if (s.isSyphonSpout) {
      textureReceivingNeeded = true; // lazy-init in output window GL context
      break;
    }
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
  
  // 0b. Update Playground
  playground.update();
  
  synchronized(surfaces) {
    // 1. Sync video/playground/syphon bridge frames
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

void exit() {
  stopTextureSharing();
  super.exit();
}
