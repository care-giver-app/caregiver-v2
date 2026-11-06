import Foundation
import CaregiverAPI

/// The evaluated flags from `GET /flags`, e.g. `{"v1_api":{"enabled":true}}`.
///
/// Anything unexpected reads as off: a missing key, a missing or non-bool
/// `enabled`, or a value that is not an object.
struct FeatureFlags: Equatable, Sendable {
    /// Moves the signed-in flow onto the `/v1` API (on in dev, off in prod until cutover).
    static let v1API = "v1_api"

    private let enabled: Set<String>

    init(enabled: Set<String> = []) {
        self.enabled = enabled
    }

    init(_ flags: Components.Schemas.Flags) {
        var on = Set<String>()
        for (name, raw) in flags.additionalProperties.value {
            guard let object = raw as? [String: (any Sendable)?],
                  let value = object["enabled"] ?? nil,
                  let isOn = value as? Bool, isOn
            else { continue }
            on.insert(name)
        }
        self.enabled = on
    }

    func isEnabled(_ name: String) -> Bool { enabled.contains(name) }
}
