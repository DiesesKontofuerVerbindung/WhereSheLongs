export const ClosedEyeState = {
  IDLE: "IDLE",
  ARMED: "ARMED",
  TRIGGERED: "TRIGGERED",
};

/** One-shot: eyes closed >= hold time consumes the trigger. Not a toggle. */
export class ClosedEyeController {
  constructor() {
    this.state = ClosedEyeState.IDLE;
    this.enabled = true;
    this.holdCount = 0;
    this.mapping = { mainScene: "", childScene: "" };
    this.listeners = [];
  }

  configure(mainScene, childScene) {
    this.mapping = { mainScene, childScene };
    if (this.state === ClosedEyeState.IDLE && childScene) this.arm();
  }

  on(fn) {
    this.listeners.push(fn);
  }

  _emit(event) {
    for (const listener of this.listeners) listener(event);
  }

  arm() {
    if (this.state === ClosedEyeState.TRIGGERED) {
      this._emit({ type: "arm_rejected", reason: "already_consumed" });
      return false;
    }
    this.state = ClosedEyeState.ARMED;
    this._emit({ type: "state", state: this.state });
    return true;
  }

  handleClosedHold() {
    this.holdCount += 1;
    if (!this.enabled) {
      this._emit({ type: "ignored", reason: "disabled" });
      return false;
    }
    if (this.state === ClosedEyeState.IDLE) {
      this._emit({ type: "ignored", reason: "idle" });
      return false;
    }
    if (this.state === ClosedEyeState.TRIGGERED) {
      this._emit({ type: "ignored", reason: "already_consumed" });
      return false;
    }
    if (!this.mapping.childScene) {
      this._emit({ type: "ignored", reason: "no_child_scene" });
      return false;
    }
    this.state = ClosedEyeState.TRIGGERED;
    this._emit({
      type: "triggered",
      mainScene: this.mapping.mainScene,
      childScene: this.mapping.childScene,
      state: this.state,
    });
    return true;
  }

  isArmed() {
    return this.state === ClosedEyeState.ARMED;
  }

  isConsumed() {
    return this.state === ClosedEyeState.TRIGGERED;
  }

  reset() {
    this.state = ClosedEyeState.IDLE;
    this.holdCount = 0;
    this._emit({ type: "state", state: this.state });
  }

  enable() {
    this.enabled = true;
  }

  disable() {
    this.enabled = false;
  }
}
