/**
 * Playground Module
 * Your creative sandbox for projection-mapped sketches!
 *
 * Edit playgroundSetup() and playgroundDraw() below to create your own
 * visuals. They work just like Processing's setup() and draw(), but
 * render to a canvas that gets projection-mapped onto your surfaces.
 *
 * The canvas is a PGraphics — use it the same way you'd use the main
 * Processing canvas. Refer to it as `canvas` inside the draw function.
 *
 * SERIAL: If you want to use serial input (e.g. Arduino), it's ready to go.
 * Set useSerial = true and adjust the baud rate / parsing in serialSetup().
 * Read values from serialValues[] in your playgroundDraw().
 *
 * To assign a surface to the playground, select it and press P
 * (or click the "Playground" button in the sidebar).
 */

class Playground {
  PGraphics canvas;
  int activeCount = 0;
  PApplet parent;

  // =============================================
  //  SERIAL — set useSerial = true to enable
  // =============================================
  boolean useSerial = false;
  int baudRate = 9600;
  Serial serialPort;
  boolean serialConnected = false;
  float[] serialValues = new float[8];  // Up to 8 values from Arduino (comma-separated)

  // =============================================
  //  YOUR VARIABLES — add anything you need here
  // =============================================



  Playground(PApplet parent) {
    this.parent = parent;
    canvas = createGraphics(640, 480, P2D);
    serialSetup();
    playgroundSetup();
  }

  void trigger(boolean active) {
    if (active) activeCount++;
    else activeCount = max(0, activeCount - 1);
  }

  // =============================================
  //  SERIAL SETUP — configure your serial port
  // =============================================

  void serialSetup() {
    if (!useSerial) return;
    try {
      String[] ports = Serial.list();
      println("[Playground] Available serial ports:");
      for (int i = 0; i < ports.length; i++) println("  [" + i + "] " + ports[i]);
      if (ports.length > 0) {
        // Change the index if your device isn't on ports[0]
        serialPort = new Serial(parent, ports[0], baudRate);
        serialPort.bufferUntil('\n');
        serialConnected = true;
        println("[Playground] Serial connected: " + ports[0] + " @ " + baudRate);
      } else {
        println("[Playground] No serial ports found.");
      }
    } catch (Exception e) {
      println("[Playground] Serial error: " + e.getMessage());
      serialConnected = false;
    }
  }

  /**
   * Reads serial data. Default expects comma-separated values, e.g. "512,1023,0\n"
   * Override this parsing to match your Arduino sketch.
   */
  void serialUpdate() {
    if (!useSerial || !serialConnected || serialPort == null) return;
    while (serialPort.available() > 0) {
      String line = serialPort.readStringUntil('\n');
      if (line != null) {
        line = line.trim();
        try {
          String[] parts = line.split(",");
          for (int i = 0; i < min(parts.length, serialValues.length); i++) {
            serialValues[i] = Float.parseFloat(parts[i].trim());
          }
        } catch (Exception e) {
          // Ignore malformed lines
        }
      }
    }
  }

  // =============================================
  //  YOUR SETUP — runs once at startup
  // =============================================

  void playgroundSetup() {
    canvas.beginDraw();
    canvas.background(0);
    canvas.endDraw();
  }

  // =============================================
  //  YOUR DRAW — runs every frame
  //  Edit this to make your own sketch!
  //
  //  Default: randomly placed colorful squares
  //
  //  Serial values (if enabled) are in serialValues[]
  //  e.g. serialValues[0] for the first sensor value
  // =============================================

  void playgroundDraw() {
    canvas.beginDraw();

    // Random colorful squares that accumulate on screen
    canvas.noStroke();
    canvas.fill(random(255), random(255), random(255), 200);
    float sz = random(10, 60);
    canvas.rect(random(canvas.width), random(canvas.height), sz, sz);

    canvas.endDraw();
  }

  // Ignore this bit. It simply skips rendering the playground if it is not active
  void update() {
    if (activeCount <= 0) return;
    serialUpdate();
    playgroundDraw();
  }
}
