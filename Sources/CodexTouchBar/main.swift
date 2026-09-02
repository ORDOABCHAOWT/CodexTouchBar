import AppKit
import CodexTouchBarCore
import Foundation

if CommandLine.arguments.contains("--hook") {
    let data = FileHandle.standardInput.readDataToEndOfFile()
    if let packet = try? HookPacketParser.parse(data: data) {
        HookSocketClient.send(packet)
    }
    exit(EXIT_SUCCESS)
}

if CommandLine.arguments.contains("--install-hook") {
    do {
        let executable = Bundle.main.executablePath ?? URL(fileURLWithPath: CommandLine.arguments[0]).standardized.path
        try HookConfiguration.install(executablePath: executable)
        print("CodexTouchBar status connection installed")
        exit(EXIT_SUCCESS)
    } catch {
        fputs("CodexTouchBar hook install failed: \(error.localizedDescription)\n", stderr)
        exit(EXIT_FAILURE)
    }
}

if CommandLine.arguments.contains("--uninstall-hook") {
    do {
        try HookConfiguration.uninstall()
        print("CodexTouchBar status connection removed")
        exit(EXIT_SUCCESS)
    } catch {
        fputs("CodexTouchBar hook removal failed: \(error.localizedDescription)\n", stderr)
        exit(EXIT_FAILURE)
    }
}

MainActor.assumeIsolated {
    let application = NSApplication.shared
    let delegate = AppDelegate()
    application.delegate = delegate
    application.setActivationPolicy(.accessory)
    application.run()
}
