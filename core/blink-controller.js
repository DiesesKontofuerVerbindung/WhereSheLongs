export const BlinkState = {
  LOCKED: "LOCKED",
  UNLOCKED: "UNLOCKED",
  TRIGGERED: "TRIGGERED",
};

/** One-shot lock. Blink is a consumable trigger, not a toggle. */
export class BlinkController {
  constructor() {
    this.state = BlinkState.LOCKED;
    this.enabled = true;
    this.blinkCount = 0;
    this.mapping = { mainScene: "", childScene: "" };
    this.listeners = [];
  }

  configure(mainScene, childScene) {
    this.mapping = { mainScene, childScene };
  }

  on(fn) {
    this.listeners.push(fn);
  }

  _emit(event) {
    for (const fn of this.listeners) fn(event);
  }

  unlock() {
    if (this.state === BlinkState.TRIGGERED) {
      this._emit({ type: "unlock_rejected", reason: "already_consumed" });
      return false;
    }
    this.state = BlinkState.UNLOCKED;
    this._emit({ type: "state", state: this.state });
    return true;
  }

  handleBlink() {
    this.blinkCount += 1;
    if (!this.enabled) {
      this._emit({ type: "ignored", reason: "disabled", blinkCount: this.blinkCount });
      return false;
    }
    if (this.state === BlinkState.LOCKED) {
      this._emit({ type: "ignored", reason: "locked", blinkCount: this.blinkCount });
      return false;
    }
    if (this.state === BlinkState.TRIGGERED) {
      this._emit({ type: "ignored", reason: "already_consumed", blinkCount: this.blinkCount });
      return false;
    }
    this.state = BlinkState.TRIGGERED;
    this._emit({
      type: "triggered",
      mainScene: this.mapping.mainScene,
      childScene: this.mapping.childScene,
      blinkCount: this.blinkCount,
      state: this.state,
    });
    return true;
  }

  isUnlocked() {
    return this.state === BlinkState.UNLOCKED;
  }

  isConsumed() {
    return this.state === BlinkState.TRIGGERED;
  }

  getBlinkCount() {
    return this.blinkCount;
  }

  reset() {
    this.state = BlinkState.LOCKED;
    this.blinkCount = 0;
    this._emit({ type: "state", state: this.state });
  }

  enable() {
    this.enabled = true;
  }

  disable() {
    this.enabled = false;
  }
}
