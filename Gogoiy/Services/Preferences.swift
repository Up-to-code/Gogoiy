import Foundation

struct Preferences {
    private enum Key {
        static let bestScore = "bestScore"
        static let sound = "soundEnabled"
        static let music = "musicEnabled"
        static let haptics = "hapticsEnabled"
    }

    private let defaults: UserDefaults

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
        defaults.register(defaults: [
            Key.sound: true,
            Key.music: true,
            Key.haptics: true
        ])
    }

    var bestScore: Int {
        get { defaults.integer(forKey: Key.bestScore) }
        nonmutating set { defaults.set(newValue, forKey: Key.bestScore) }
    }

    var soundEnabled: Bool {
        get { defaults.bool(forKey: Key.sound) }
        nonmutating set { defaults.set(newValue, forKey: Key.sound) }
    }

    var musicEnabled: Bool {
        get { defaults.bool(forKey: Key.music) }
        nonmutating set { defaults.set(newValue, forKey: Key.music) }
    }

    var hapticsEnabled: Bool {
        get { defaults.bool(forKey: Key.haptics) }
        nonmutating set { defaults.set(newValue, forKey: Key.haptics) }
    }
}
