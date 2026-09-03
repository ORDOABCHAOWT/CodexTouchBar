import AppKit
import CodexTouchBarCore
import Foundation
import TouchBarPrivateBridge

if let variantValue = CommandLine.arguments.firstIndex(of: "--variant").flatMap({ index in
    let next = CommandLine.arguments.index(after: index)
    return next < CommandLine.arguments.endIndex ? Int(CommandLine.arguments[next]) : nil
}) {
    VisualVariant.current = VisualVariant(rawValue: variantValue) ?? .balanced
}

if CommandLine.arguments.contains("--media-capability-check") {
    print(CTBMediaRemoteAvailable() ? "available" : "unavailable")
    exit(CTBMediaRemoteAvailable() ? EXIT_SUCCESS : EXIT_FAILURE)
}

if CommandLine.arguments.contains("--chrome-tab-probe") {
    guard let tabs = ChromeTabController.frontWindowTabs(), !tabs.isEmpty else {
        print("unavailable")
        exit(EXIT_FAILURE)
    }
    print("tabs=\(tabs.count) active=\(tabs.filter(\.isActive).count)")
    exit(tabs.filter(\.isActive).count == 1 ? EXIT_SUCCESS : EXIT_FAILURE)
}

if CommandLine.arguments.contains("--activity-probe") {
    let rows = CTBReadRecentCodexActivity(120)
    let titledRows = rows.filter { row in
        guard let title = row["rawTitle"] as? String else { return false }
        return !title.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }
    for row in titledRows.prefix(3) {
        if let id = row["id"] as? String { print(id) }
    }
    exit(titledRows.isEmpty ? EXIT_FAILURE : EXIT_SUCCESS)
}

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
