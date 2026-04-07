/**
 * IO Module
 * Handles file selection, media loading, JSON configuration, and undo.
 */

// --- Undo System ---

void pushUndo() {
  synchronized(surfaces) {
    JSONArray snapshot = new JSONArray();
    for (int i = 0; i < surfaces.size(); i++) {
      snapshot.setJSONObject(i, surfaces.get(i).toJSON());
    }
    undoStack.add(snapshot);
    if (undoStack.size() > maxUndoLevels) {
      undoStack.remove(0);
    }
  }
}

void performUndo() {
  if (undoStack.isEmpty()) return;
  JSONArray snapshot = undoStack.remove(undoStack.size() - 1);
  synchronized(surfaces) {
    // Unload all current surfaces
    for (Surface s : surfaces) s.unloadMedia();
    surfaces.clear();
    selectedSurface = null;
    // Restore from snapshot
    for (int i = 0; i < snapshot.size(); i++) {
      surfaces.add(new Surface(projection_app.this, snapshot.getJSONObject(i)));
    }
  }
}

// --- Surface Creation ---

void addQuad() {
  pushUndo();
  synchronized(surfaces) {
    Surface s = new Surface(this);
    surfaces.add(s);
    clearAllSelections();
    s.isSelected = true;
    selectedSurface = s;
  }
}

void addCircle() {
  pushUndo();
  synchronized(surfaces) {
    Surface s = new Surface(this);
    s.isCircle = true;
    surfaces.add(s);
    clearAllSelections();
    s.isSelected = true;
    selectedSurface = s;
  }
}

void toggleSourceView() { 
  showSourceView = !showSourceView; 
}

void cycleMirror() {
  outputMirror = (outputMirror + 1) % 4;
}

void toggleMappingGuide() {
  showMappingGuide = !showMappingGuide;
}

void toggleLock() {
  if (selectedSurface != null) {
    selectedSurface.isLocked = !selectedSurface.isLocked;
  }
}

void moveLayerUp() {
  if (selectedSurface == null) return;
  pushUndo();
  synchronized(surfaces) {
    int idx = surfaces.indexOf(selectedSurface);
    if (idx < surfaces.size() - 1) {
      surfaces.remove(idx);
      surfaces.add(idx + 1, selectedSurface);
    }
  }
}

void moveLayerDown() {
  if (selectedSurface == null) return;
  pushUndo();
  synchronized(surfaces) {
    int idx = surfaces.indexOf(selectedSurface);
    if (idx > 0) {
      surfaces.remove(idx);
      surfaces.add(idx - 1, selectedSurface);
    }
  }
}

void resetCanvasView() {
  fitToProjector();
}

void fitToProjector() {
  if (output == null || output.width <= 0 || output.height <= 0) {
    canvasZoom = 1.0;
    canvasPanX = 0;
    canvasPanY = 0;
    return;
  }
  int mappingAreaW = width - SIDEBAR_WIDTH;
  if (showSourceView) mappingAreaW /= 2;
  float margin = 40;
  float availW = mappingAreaW - margin * 2;
  float availH = height - margin * 2;
  float scaleX = availW / output.width;
  float scaleY = availH / output.height;
  canvasZoom = min(scaleX, scaleY);
  canvasPanX = (mappingAreaW - output.width * canvasZoom) / 2;
  canvasPanY = (height - output.height * canvasZoom) / 2;
}

void toggleLiveAction() {
  if (selectedSurface != null) {
    pushUndo();
    synchronized(surfaces) {
      selectedSurface.setLive(!selectedSurface.isLive);
    }
  }
}

void togglePlaygroundAction() {
  if (selectedSurface != null) {
    pushUndo();
    synchronized(surfaces) {
      selectedSurface.setPlayground(!selectedSurface.isPlayground);
    }
  }
}

void loadMediaAction() {
  if (selectedSurface != null) {
    selectInput("Select media:", "fileSelected");
  }
}

void deleteAction() {
  if (selectedSurface != null) {
    pushUndo();
    synchronized(surfaces) {
      selectedSurface.unloadMedia();
      surfaces.remove(selectedSurface);
      selectedSurface = null;
    }
  }
}

void fileSelected(File selection) {
  if (selection != null && selectedSurface != null) {
    pushUndo();
    synchronized(surfaces) {
      selectedSurface.loadMedia(this, selection.getAbsolutePath());
    }
  }
}

void saveConfig() {
  synchronized(surfaces) {
    JSONArray jsonSurfaces = new JSONArray();
    for (int i = 0; i < surfaces.size(); i++) {
      jsonSurfaces.setJSONObject(i, surfaces.get(i).toJSON());
    }
    saveJSONArray(jsonSurfaces, "data/config.json");
  }
  println("Configuration saved to data/config.json");
}

void loadConfig() {
  File f = new File(sketchPath("data/config.json"));
  if (f.exists()) {
    synchronized(surfaces) {
      JSONArray jsonSurfaces = loadJSONArray("data/config.json");
      for (int i = 0; i < jsonSurfaces.size(); i++) {
        surfaces.add(new Surface(this, jsonSurfaces.getJSONObject(i)));
      }
    }
    println("Configuration loaded.");
  }
}
