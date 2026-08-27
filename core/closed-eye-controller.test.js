import { ClosedEyeController, ClosedEyeState } from "./closed-eye-controller.js";
import { ClosedEyeClassifier } from "./closed-eye-classifier.js";
import { mergeClosedEyeConfig } from "./closed-eye-config.js";

function assert(cond, msg) {
  if (!cond) throw new Error(msg);
}

function testController() {
  const c = new ClosedEyeController();
  assert(c.state === ClosedEyeState.IDLE, "start idle");
  assert(c.handleClosedHold() === false, "hold while idle ignored");
  c.configure("Room_Closed", "Room_After");
  assert(c.isArmed(), "configure arms");
  assert(c.handleClosedHold() === true, "first hold consumes");
  assert(c.isConsumed(), "consumed");
  assert(c.handleClosedHold() === false, "second hold ignored");
  assert(c.arm() === false, "cannot re-arm after trigger");
  c.reset();
  assert(c.state === ClosedEyeState.IDLE, "reset to idle");
  console.log("closed-eye controller ok");
}

function testClassifier() {
  const clf = new ClosedEyeClassifier(mergeClosedEyeConfig({ holdMs: 1500 }));
  let t = 0;
  const closed = (now) => ({
    faceDetected: true,
    leftEye: "closed",
    rightEye: "closed",
    now,
  });
  const open = (now) => ({
    faceDetected: true,
    leftEye: "open",
    rightEye: "open",
    now,
  });

  assert(clf.update(closed(t)).triggered === false, "just closed");
  t += 800;
  assert(clf.update(closed(t)).triggered === false, "0.8s not enough");
  t += 700;
  const hit = clf.update(closed(t));
  assert(hit.triggered === true, "1.5s triggers");
  t += 100;
  assert(clf.update(closed(t)).triggered === false, "same closure does not retrigger");
  t += 40;
  clf.update(open(t));
  t += 1600;
  assert(clf.update(closed(t)).triggered === false, "new closure needs another 1.5s");
  t += 1500;
  assert(clf.update(closed(t)).triggered === true, "second closure can trigger");
  t += 40;
  const blinkish = new ClosedEyeClassifier(mergeClosedEyeConfig({ holdMs: 1500 }));
  blinkish.update(closed(t));
  t += 200;
  assert(blinkish.update(open(t)).triggered === false, "short blink is not a hold");
  console.log("closed-eye classifier ok");
}

testController();
testClassifier();
console.log("closed-eye tests passed");
