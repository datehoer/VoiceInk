import Foundation

enum AudioRetryModeResolution {
    static func modeForRetranscription(
        selectedMode: ModeConfig?,
        currentEffectiveMode: ModeConfig?
    ) -> ModeConfig? {
        selectedMode ?? currentEffectiveMode
    }
}
