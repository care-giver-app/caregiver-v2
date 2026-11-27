import type { Stage } from './shared-stack';

/**
 * Flag content per stage. `v1_api` routes the iOS app onto the /v1 API (ADR 0013). On in every
 * stage since the cutover migrated prod onto the v1 tables.
 */
export function flagContent(_stage: Stage) {
  return {
    flags_demo: { enabled: false },
    v1_api: { enabled: true },
  };
}
