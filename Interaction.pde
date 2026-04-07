/**
 * Interaction Module
 * Handles all mouse and keyboard events.
 */

// Convert screen coordinates to canvas space
float toCanvasX(float sx, int mappingAreaX) {
  return (sx - mappingAreaX - canvasPanX) / canvasZoom;
}
float toCanvasY(float sy) {
  return (sy - canvasPanY) / canvasZoom;
}

void mousePressed() {
  if (mouseX < SIDEBAR_WIDTH) {
    handleSidebarClick();
    return;
  }
  
  int mappingAreaX = SIDEBAR_WIDTH;
  int mappingAreaW = width - SIDEBAR_WIDTH;
  
  if (showSourceView) {
    int viewW = mappingAreaW / 2;
    if (mouseX > mappingAreaX && mouseX < mappingAreaX + viewW) {
      if (selectedSurface != null) {
        int idx = selectedSurface.getSourceCornerAt(mouseX, mouseY, mappingAreaX, viewW, this);
        if (idx != -1) {
          selectedSurface.clearSourceSelection();
          selectedSurface.selectedSourceCorners[idx] = true;
          isDraggingSourceVertex = true;
          return;
        } else if (selectedSurface.isInsideSource(mouseX, mouseY, mappingAreaX, viewW, this)) {
          isDraggingSourceShape = true;
          return;
        }
      }
    }
    mappingAreaX += viewW;
    mappingAreaW = viewW;
  }
  
  // Canvas panning (ALT+click or middle mouse)
  if ((keyPressed && keyCode == ALT) || mouseButton == CENTER) {
    isPanningCanvas = true;
    return;
  }
  
  // Convert mouse coords to canvas space for hit testing
  float cmx = toCanvasX(mouseX, mappingAreaX);
  float cmy = toCanvasY(mouseY);
  
  boolean hitVertex = false;
  boolean hitEdge = false;
  
  // 1. Check Vertex Hits (Priority)
  for (Surface s : surfaces) {
    if (s.isLocked) continue;
    int idx = s.getCornerAt(cmx, cmy, 0);
    if (idx != -1) {
      hitVertex = true;
      if (keyPressed && keyCode == SHIFT) {
        s.selectedCorners[idx] = !s.selectedCorners[idx]; // Toggle
        if (s.selectedCorners[idx]) s.isSelected = true;
      } else if (!s.selectedCorners[idx]) {
        clearAllSelections();
        s.selectedCorners[idx] = true;
        s.isSelected = true;
        selectedSurface = s;
      }
      isDraggingVertex = true;
      break;
    }
  }
  
  // 2. Check Edge Hits
  if (!hitVertex) {
    for (Surface s : surfaces) {
      if (s.isLocked) continue;
      int edgeIdx = s.getEdgeAt(cmx, cmy, 0);
      if (edgeIdx != -1) {
        hitEdge = true;
        if (!(keyPressed && keyCode == SHIFT)) clearAllSelections();
        s.selectedCorners[edgeIdx] = true;
        s.selectedCorners[(edgeIdx + 1) % 4] = true;
        s.isSelected = true;
        selectedSurface = s;
        isDraggingVertex = true;
        break;
      }
    }
  }
  
  // 3. Check Shape Hits
  if (!hitVertex && !hitEdge) {
    for (Surface s : surfaces) {
      if (s.isInside(cmx, cmy, 0)) {
        if (!(keyPressed && keyCode == SHIFT) && !s.isSelected) clearAllSelections();
        s.isSelected = true;
        selectedSurface = s;
        if (!s.isLocked) isDraggingShape = true;
        return;
      }
    }
  }
  
  // 4. Marquee Selection
  if (!hitVertex && !hitEdge && !isDraggingShape) {
    if (!(keyPressed && keyCode == SHIFT)) clearAllSelections();
    isMarquee = true;
    marqueeX1 = mouseX;
    marqueeY1 = mouseY;
  }
}

void mouseDragged() {
  float dx = mouseX - pmouseX;
  float dy = mouseY - pmouseY;
  
  if (isPanningCanvas) {
    canvasPanX += dx;
    canvasPanY += dy;
    return;
  }
  
  if (isDraggingSourceVertex || isDraggingSourceShape) {
    if (!undoPushedThisDrag) { pushUndo(); undoPushedThisDrag = true; }
    int viewW = (width - SIDEBAR_WIDTH) / 2;
    PImage tex = selectedSurface.getControllerTex();
    if (tex != null) {
      float aspect = (float)tex.width / tex.height;
      float drawW = viewW - 40;
      float drawH = drawW / aspect;
      if (drawH > height - 40) {
        drawH = height - 40;
        drawW = drawH * aspect;
      }
      if (isDraggingSourceVertex) selectedSurface.moveSelectedSourceCorners(dx / drawW, dy / drawH);
      else selectedSurface.moveSource(dx / drawW, dy / drawH);
    }
  } else if (isDraggingVertex) {
    if (!undoPushedThisDrag) { pushUndo(); undoPushedThisDrag = true; }
    for (Surface s : surfaces) {
      s.moveSelectedCorners(dx / canvasZoom, dy / canvasZoom);
    }
  } else if (isDraggingShape) {
    if (!undoPushedThisDrag) { pushUndo(); undoPushedThisDrag = true; }
    if (selectedSurface != null) selectedSurface.move(dx / canvasZoom, dy / canvasZoom);
  }
}

void mouseReleased() {
  if (isMarquee) {
    int mappingAreaX = SIDEBAR_WIDTH;
    if (showSourceView) mappingAreaX += (width - SIDEBAR_WIDTH) / 2;
    float mx1 = toCanvasX(marqueeX1, mappingAreaX);
    float my1 = toCanvasY(marqueeY1);
    float mx2 = toCanvasX(mouseX, mappingAreaX);
    float my2 = toCanvasY(mouseY);
    for (Surface s : surfaces) {
      s.selectCornersInBox(mx1, my1, mx2, my2, 0);
      if (anyCornerSelected(s)) s.isSelected = true;
    }
  }
  isMarquee = false;
  isDraggingVertex = false;
  isDraggingShape = false;
  isDraggingSourceVertex = false;
  isDraggingSourceShape = false;
  isPanningCanvas = false;
  undoPushedThisDrag = false;
}

void keyPressed() {
  // Undo: Ctrl-Z (Windows/Linux) or Cmd-Z (Mac)
  if ((key == 26 || key == 'z') && (keyCode == 90) && 
      ((keyEvent.isControlDown() && !keyEvent.isShiftDown()) || 
       (keyEvent.isMetaDown() && !keyEvent.isShiftDown()))) {
    performUndo();
    return;
  }
  
  if (key == 'a') addQuad();
  else if (key == 'c') addCircle();
  else if (key == 'l') loadMediaAction();
  else if (key == 'v') toggleSourceView();
  else if (key == 'p') togglePlaygroundAction();
  else if (key == 't') toggleSyphonSpoutAction();
  else if (key == 's') saveConfig();
  else if (key == 'm') cycleMirror();
  else if (key == 'g') toggleMappingGuide();
  else if (key == 'x') toggleLock();
  else if (key == '[') moveLayerDown();
  else if (key == ']') moveLayerUp();
  else if (key == '0') resetCanvasView();
  else if (key == 'd' || keyCode == BACKSPACE || keyCode == DELETE) deleteAction();
  else if (key == 'i' || key == 'I') {
    println("\n====== DIAGNOSTIC DUMP (frame " + frameCount + ") ======");
    println("movieEvent fires so far: " + diagMovieEventCount);
    for (int i = 0; i < surfaces.size(); i++) {
      surfaces.get(i).printDiag(i);
    }
    println("========================================\n");
  }
}

boolean anyCornerSelected(Surface s) {
  for (boolean b : s.selectedCorners) if (b) return true;
  return false;
}

void clearAllSelections() {
  selectedSurface = null;
  for (Surface s : surfaces) s.clearSelection();
}

void handleSidebarClick() {
  float btnW = SIDEBAR_WIDTH - (UI_MARGIN * 2);
  float btnH = 26;
  float spacing = 5;
  float startY = 38;
  
  if (mouseX > UI_MARGIN && mouseX < UI_MARGIN + btnW) {
    if (mouseY > startY && mouseY < startY + btnH) addQuad();
    else if (mouseY > startY + (btnH + spacing) && mouseY < startY + (btnH + spacing) + btnH) addCircle();
    else if (mouseY > startY + (btnH + spacing) * 2 && mouseY < startY + (btnH + spacing) * 2 + btnH) loadMediaAction();
    else if (mouseY > startY + (btnH + spacing) * 3 && mouseY < startY + (btnH + spacing) * 3 + btnH) toggleSourceView();
    else if (mouseY > startY + (btnH + spacing) * 4 && mouseY < startY + (btnH + spacing) * 4 + btnH) togglePlaygroundAction();
    else if (mouseY > startY + (btnH + spacing) * 5 && mouseY < startY + (btnH + spacing) * 5 + btnH) toggleSyphonSpoutAction();
    else if (mouseY > startY + (btnH + spacing) * 6 && mouseY < startY + (btnH + spacing) * 6 + btnH) deleteAction();
    else if (mouseY > startY + (btnH + spacing) * 7 && mouseY < startY + (btnH + spacing) * 7 + btnH) saveConfig();
    else if (mouseY > startY + (btnH + spacing) * 8 && mouseY < startY + (btnH + spacing) * 8 + btnH) cycleMirror();
    else if (mouseY > startY + (btnH + spacing) * 9 && mouseY < startY + (btnH + spacing) * 9 + btnH) toggleMappingGuide();
    else if (mouseY > startY + (btnH + spacing) * 10 && mouseY < startY + (btnH + spacing) * 10 + btnH) toggleLock();
    else if (mouseY > startY + (btnH + spacing) * 11 && mouseY < startY + (btnH + spacing) * 11 + btnH) {
      // Layer ordering buttons: left half = Up, right half = Down
      float halfW = (btnW - 5) / 2;
      if (mouseX < UI_MARGIN + halfW) moveLayerUp();
      else moveLayerDown();
    }
  }
}
