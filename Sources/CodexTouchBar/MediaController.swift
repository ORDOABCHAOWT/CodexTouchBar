import Foundation
import TouchBarPrivateBridge

enum MediaCommand: Int {
    case togglePlayPause = 2
    case nextTrack = 4
    case previousTrack = 5
}

enum MediaController {
    static var isAvailable: Bool { CTBMediaRemoteAvailable() }

    @discardableResult
    static func send(_ command: MediaCommand) -> Bool {
        CTBSendMediaCommand(command.rawValue)
    }
}
