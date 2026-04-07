# Live AV & Arduino Integration Guide

This guide explains how to use the Live AV feature to modulate visuals and sound using an Arduino and a potentiometer.

## Hardware Setup

1. **Components**:
   - Arduino (Uno, Nano, etc.)
   - 10k Potentiometer
   - Jumper wires

2. **Wiring**:
   - Connect the center pin of the potentiometer to **Analog Pin A0** on the Arduino.
   - Connect the other two pins to **5V** and **GND**.

## Software Setup

1. **Arduino Sketch**:
   - Open the sketch located at `session09/arduino_pot_serial/arduino_pot_serial.ino`.
   - Upload it to your Arduino.
   - Note the Serial port (e.g., `/dev/ttyUSB0` or `COM3`).

2. **Processing Libraries**:
   - Ensure the **Serial** and **Sound** libraries are installed in Processing (Tools > Add Tool > Libraries).

## Using Live AV in the App

1. **Launch**: Start the `projection_app`. The console will log if an Arduino is detected.
2. **Select a Quad**: Click on a surface or add a new one ('A').
3. **Toggle Live Mode**:
   - Click the **Live AV (K)** button in the sidebar.
   - OR press the **'K'** key on your keyboard.
4. **Modulate**: Turn the potentiometer to change the frequency of the sawtooth wave and modulate the generative "wave" visual on the selected quad.

## Mouse Fallback
If no Arduino is detected at startup, the app will automatically fall back to **Mouse X** position to control the Live AV parameters.

## Troubleshooting
- **Serial Error**: If the app fails to connect, ensure the Serial Monitor in the Arduino IDE is closed.
- **No Sound**: Verify that your speakers are on and the Processing Sound library is properly initialized.
- **Lag**: For 4K video mapping, the app uses downsampling to maintain performance. Live AV is optimized for 60fps.
