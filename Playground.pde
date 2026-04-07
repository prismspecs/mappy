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
 * To assign a surface to the playground, select it and press P
 * (or click the "Playground" button in the sidebar).
 */

class Playground {
  PGraphics canvas;
  int activeCount = 0;

  // =============================================
  //  YOUR VARIABLES — add anything you need here
  // =============================================



  Playground() {
    canvas = createGraphics(640, 480, P2D);
    playgroundSetup();
  }

  void trigger(boolean active) {
    if (active) activeCount++;
    else activeCount = max(0, activeCount - 1);
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
    playgroundDraw();
  }
}
