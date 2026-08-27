export const DEFAULT_CLOSED_EYE_CONFIG = {
  holdMs: 1500,
  staleMs: 400,
};

export function mergeClosedEyeConfig(overrides = {}) {
  return { ...DEFAULT_CLOSED_EYE_CONFIG, ...overrides };
}
