/** Both eyes closed long enough → one-shot hold event. Independent of blink. */

export class ClosedEyeClassifier {
  constructor(config) {
    this.config = config;
    this.reset();
  }

  reset() {
    this.closedStartedAt = -1;
    this.firedThisClosure = false;
    this.holdMs = 0;
  }

  update(sample) {
    const now = sample.now;
    const bothClosed =
      Boolean(sample.faceDetected) &&
      sample.leftEye === "closed" &&
      sample.rightEye === "closed";

    if (!bothClosed) {
      this.reset();
      return this._result(false, now);
    }

    if (this.closedStartedAt < 0) this.closedStartedAt = now;
    this.holdMs = now - this.closedStartedAt;
    if (!this.firedThisClosure && this.holdMs >= this.config.holdMs) {
      this.firedThisClosure = true;
      return this._result(true, now);
    }
    return this._result(false, now);
  }

  _result(triggered, now) {
    return {
      triggered,
      holdMs: this.holdMs,
      now,
    };
  }
}
