import type { Stage } from './shared-stack';

/**
 * Flag content per stage. `v1_api` routes the iOS app onto the /v1 API (ADR 0013): on in dev so
 * Debug builds exercise it, off in prod until cutover.
 */
export function flagContent(stage: Stage) {
  return {
    flags_demo: { enabled: false },
    v1_api: { enabled: stage === 'dev' },
  };
}
