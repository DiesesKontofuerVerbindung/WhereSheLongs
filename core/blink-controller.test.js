import { BlinkController, BlinkState } from "./blink-controller.js";
import { BlinkClassifier } from "./blink-classifier.js";
import { mergeBlinkConfig } from "./blink-config.js";

function assert(cond, msg) {
  if (!cond) throw new Error(msg);
}

function testController() {
  const c = new BlinkController();
  c.configure("Room_A", "Room_A_Empty");
  assert(c.state === BlinkState.LOCKED, "start locked");
  assert(c.handleBlink() === false, "blink while locked ignored");
  assert(c.state === BlinkState.LOCKED, "still locked");
  assert(c.unlock() === true, "unlock ok");
  assert(c.isUnlocked(), "unlocked");
  assert(c.handleBlink() === true, "first valid blink consumes");
  assert(c.isConsumed(), "consumed");
  assert(c.handleBlink() === false, "second blink ignored");
  assert(c.state === BlinkState.TRIGGERED, "stays triggered");
  assert(c.unlock() === false, "cannot unlock after trigger");
  assert(c.state === BlinkState.TRIGGERED, "still triggered");
  c.reset();
  assert(c.state === BlinkState.LOCKED, "reset to locked");
  console.log("controller ok");
}

function openSample(now) {
  return { faceDetected: true, leftEar: 0.3, rightEar: 0.3, now };
}
function closedSample(now) {
  return { faceDetected: true, leftEar: 0.12, rightEar: 0.12, now };
}

function testClassifier() {
  const clf = new BlinkClassifier(mergeBlinkConfig());
  let t = 0;
  clf.update(openSample(t));
  t += 40;
  clf.update(openSample(t));
  t += 40;
  clf.update(closedSample(t));
  t += 40;
  clf.update(closedSample(t));
  t += 120;
  const blink = clf.update(openSample(t));
  assert(blink.blink === true, "complete blink counted");
  t += 40;
  clf.update(closedSample(t));
  t += 40;
  clf.update(closedSample(t));
  t += 2000;
  const longClose = clf.update(openSample(t));
  assert(longClose.blink === false, "long close is not a blink");
  t += 300;
  clf.update(closedSample(t));
  t += 40;
  const oneFrame = clf.update(openSample(t));
  assert(oneFrame.blink === false, "single closed frame is not a blink");
  console.log("classifier ok");
}

testController();
testClassifier();
console.log("all tests passed");
