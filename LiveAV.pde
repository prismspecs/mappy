/**
 * LiveAV Module
 * Manages Serial input, Sound output, and Generative Visuals.
 */

class LiveAV {
  Serial myPort;
  SawOsc saw;
  PGraphics canvas;
  
  float val = 0.5; // Normalized 0-1 value from Pot or Mouse
  boolean hasSerial = false;
  String portName = "";
  
  int activeCount = 0; // Number of surfaces using this feed

  LiveAV(PApplet parent) {
    // 1. Setup Serial
    try {
      String[] ports = Serial.list();
      if (ports.length > 0) {
        portName = ports[0];
        myPort = new Serial(parent, portName, 9600);
        hasSerial = true;
        println("[LiveAV] Serial connected to: " + portName);
      }
    } catch (Exception e) {
      println("[LiveAV] Serial error: " + e.getMessage());
      hasSerial = false;
    }

    // 2. Setup Sound
    try {
      saw = new SawOsc(parent);
      // Don't play yet
    } catch (Exception e) {
      println("[LiveAV] Sound initialization error: " + e.getMessage());
    }

    // 3. Setup Visual Canvas
    canvas = createGraphics(640, 480, P2D);
  }
  
  void trigger(boolean active) {
    if (active) activeCount++;
    else activeCount = max(0, activeCount - 1);
    
    if (saw != null) {
      if (activeCount > 0) saw.play();
      else saw.stop();
    }
  }

  void update() {
    if (activeCount <= 0) return; // Save CPU/GPU if not in use

    // Read Serial Data
    if (hasSerial && myPort.available() > 0) {
      String inString = myPort.readStringUntil('\n');
      if (inString != null) {
        inString = trim(inString);
        try {
          float raw = float(inString);
          val = map(raw, 0, 1023, 0, 1);
        } catch (Exception e) {}
      }
    } else if (!hasSerial) {
      val = (float)mouseX / width;
    }

    // Update Sound
    if (saw != null) {
      float freq = map(val, 0, 1, 100, 1000);
      saw.freq(freq);
      saw.amp(0.1);
    }

    // Update Visuals
    canvas.beginDraw();
    canvas.background(0);
    canvas.noFill();
    canvas.stroke(255);
    canvas.strokeWeight(2);
    
    int numLines = (int)map(val, 0, 1, 10, 100);
    float spacing = (float)canvas.height / numLines;
    float waveAmp = map(val, 0, 1, 5, 100);
    
    for (int i = 0; i < numLines; i++) {
      float y = i * spacing;
      canvas.beginShape();
      for (float x = 0; x <= canvas.width; x += 10) {
        float angle = map(x, 0, canvas.width, 0, TWO_PI * 2);
        float offset = sin(angle + frameCount * 0.05) * waveAmp;
        canvas.vertex(x, y + offset);
      }
      canvas.endShape();
    }
    
    canvas.fill(0, 255, 0);
    canvas.noStroke();
    canvas.ellipse(20, 20, 10, 10);
    canvas.text("LIVE AV: " + nf(val, 1, 2), 35, 25);
    if (!hasSerial) canvas.text("(MOUSE FALLBACK)", 35, 40);
    canvas.endDraw();
  }
}
