/** OPEN -> CLOSED -> OPEN classifier. Independent of game / scene logic. */

export class BlinkClassifier {
  constructor(config) {
    this.config = config;
    this.reset();
  }

  reset() {
    this.phase = "need_open";
    this.closedStartedAt = 0;
    this.closedFrames = 0;
    this.openFrames = 0;
    this.lastBlinkAt = 0;
    this.leftEye = "unknown";
    this.rightEye = "unknown";
  }

  _eyeState(ear) {
    if (ear < this.config.closeEar) return "closed";
    if (ear > this.config.openEar) return "open";
    return "uncertain";
  }

  update(sample) {
    const now = sample.now;
    if (!sample.faceDetected) {
      this.reset();
      return this._result(false, now, 0);
    }

    const leftEar = sample.leftEar;
    const rightEar = sample.rightEar;
    this.leftEye = this._eyeState(leftEar);
    this.rightEye = this._eyeState(rightEar);

    const closedScore =
      (this.leftEye === "closed" ? 0.5 : 0) + (this.rightEye === "closed" ? 0.5 : 0);
    const openScore =
      (this.leftEye === "open" ? 0.5 : 0) + (this.rightEye === "open" ? 0.5 : 0);
    const confidence = Math.max(closedScore, openScore);

    if (closedScore >= this.config.confidenceThreshold && this.leftEye !== "uncertain" && this.rightEye !== "uncertain") {
      this.closedFrames += 1;
      this.openFrames = 0;
      if (this.closedFrames >= this.config.minClosedFrames) {
        if (this.phase === "open") {
          this.phase = "closed";
          this.closedStartedAt = now;
        } else if (this.phase === "need_open") {
          this.phase = "closed_before_open";
        }
      }
      return this._result(false, now, confidence);
    }

    if (openScore >= this.config.confidenceThreshold) {
      this.openFrames += 1;
      this.closedFrames = 0;
      if (this.openFrames < 1) return this._result(false, now, confidence);

      if (this.phase === "closed") {
        const duration = now - this.closedStartedAt;
        this.phase = "open";
        const inWindow =
          duration >= this.config.minBlinkDurationMs &&
          duration <= this.config.maxBlinkDurationMs;
        const cooled = now - this.lastBlinkAt >= this.config.cooldownMs;
        if (inWindow && cooled) {
          this.lastBlinkAt = now;
          return this._result(true, now, confidence, duration);
        }
        return this._result(false, now, confidence, duration);
      }

      if (this.phase === "closed_before_open" || this.phase === "need_open") {
        this.phase = "open";
      }
      return this._result(false, now, confidence);
    }

    return this._result(false, now, confidence);
  }

  _result(blink, now, confidence, durationMs = 0) {
    return {
      blink,
      leftEye: this.leftEye,
      rightEye: this.rightEye,
      phase: this.phase,
      confidence,
      durationMs,
      now,
    };
  }
}
