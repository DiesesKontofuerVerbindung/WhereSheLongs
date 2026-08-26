import { BlinkClassifier } from "../core/blink-classifier.js";
import { mergeBlinkConfig } from "../core/blink-config.js";

const LEFT_EYE = [33, 160, 158, 133, 153, 144];
const RIGHT_EYE = [362, 385, 387, 263, 373, 380];

function dist(a, b) {
  return Math.hypot(a.x - b.x, a.y - b.y);
}

function ear(lm, idx) {
  const p1 = lm[idx[0]];
  const p2 = lm[idx[1]];
  const p3 = lm[idx[2]];
  const p4 = lm[idx[3]];
  const p5 = lm[idx[4]];
  const p6 = lm[idx[5]];
  const h = dist(p1, p4);
  if (h < 1e-6) return 1;
  return (dist(p2, p6) + dist(p3, p5)) / (2 * h);
}

export class WebcamBlinkDetector {
  constructor(options = {}) {
    this.config = mergeBlinkConfig(options.config);
    this.classifier = new BlinkClassifier(this.config);
    this.onFrame = options.onFrame || (() => {});
    this.onBlink = options.onBlink || (() => {});
    this.video = options.video;
    this.canvas = options.canvas;
    this.ctx = this.canvas ? this.canvas.getContext("2d") : null;
    this.landmarker = null;
    this.stream = null;
    this.running = false;
    this.rafId = 0;
    this.cameraConnected = false;
    this.faceDetected = false;
  }

  async _loadModel() {
    if (this.landmarker) return;
    const { FaceLandmarker, FilesetResolver } = await import(
      "https://cdn.jsdelivr.net/npm/@mediapipe/tasks-vision@0.10.17/+esm"
    );
    const fileset = await FilesetResolver.forVisionTasks(
      "https://cdn.jsdelivr.net/npm/@mediapipe/tasks-vision@0.10.17/wasm"
    );
    const modelUrl =
      "https://storage.googleapis.com/mediapipe-models/face_landmarker/face_landmarker/float16/latest/face_landmarker.task";
    const options = (delegate) => ({
      baseOptions: { modelAssetPath: modelUrl, delegate },
      runningMode: "VIDEO",
      numFaces: 1,
    });
    try {
      this.landmarker = await FaceLandmarker.createFromOptions(fileset, options("GPU"));
    } catch (e) {
      this.landmarker = await FaceLandmarker.createFromOptions(fileset, options("CPU"));
    }
  }

  async start() {
    await this._loadModel();
    this.stream = await navigator.mediaDevices.getUserMedia({
      video: { facingMode: "user", width: { ideal: 640 }, height: { ideal: 480 } },
      audio: false,
    });
    this.video.srcObject = this.stream;
    await this.video.play();
    this.cameraConnected = true;
    this.classifier.reset();
    this.running = true;
    this._loop();
  }

  stop() {
    this.running = false;
    cancelAnimationFrame(this.rafId);
    if (this.stream) {
      for (const track of this.stream.getTracks()) track.stop();
      this.stream = null;
    }
    this.cameraConnected = false;
    this.faceDetected = false;
    if (this.video) this.video.srcObject = null;
  }

  _draw(landmarks) {
    if (!this.ctx) return;
    const w = this.canvas.width;
    const h = this.canvas.height;
    this.ctx.save();
    this.ctx.translate(w, 0);
    this.ctx.scale(-1, 1);
    this.ctx.drawImage(this.video, 0, 0, w, h);
    if (landmarks) {
      this.ctx.fillStyle = "#00e676";
      for (const i of LEFT_EYE.concat(RIGHT_EYE)) {
        const p = landmarks[i];
        this.ctx.beginPath();
        this.ctx.arc(p.x * w, p.y * h, 2.5, 0, Math.PI * 2);
        this.ctx.fill();
      }
    }
    this.ctx.restore();
  }

  _loop() {
    if (!this.running) return;
    if (this.video.readyState >= 2) {
      if (this.canvas.width !== this.video.videoWidth || this.canvas.height !== this.video.videoHeight) {
        this.canvas.width = this.video.videoWidth || 640;
        this.canvas.height = this.video.videoHeight || 480;
      }
      const result = this.landmarker.detectForVideo(this.video, performance.now());
      const face = result.faceLandmarks && result.faceLandmarks[0];
      this.faceDetected = Boolean(face);
      const classified = this.classifier.update({
        faceDetected: this.faceDetected,
        leftEar: face ? ear(face, LEFT_EYE) : 1,
        rightEar: face ? ear(face, RIGHT_EYE) : 1,
        now: performance.now(),
      });
      this._draw(face || null);
      this.onFrame({
        cameraConnected: this.cameraConnected,
        faceDetected: this.faceDetected,
        leftEye: classified.leftEye,
        rightEye: classified.rightEye,
        confidence: classified.confidence,
      });
      if (classified.blink) this.onBlink(classified);
    }
    this.rafId = requestAnimationFrame(() => this._loop());
  }
}
