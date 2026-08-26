export const DEFAULT_BLINK_CONFIG = {
  closeEar: 0.19,
  openEar: 0.23,
  minBlinkDurationMs: 80,
  maxBlinkDurationMs: 500,
  cooldownMs: 220,
  confidenceThreshold: 0.6,
  minClosedFrames: 2,
};

export function mergeBlinkConfig(overrides = {}) {
  return { ...DEFAULT_BLINK_CONFIG, ...overrides };
}
