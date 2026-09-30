// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 Vorssaint

import Foundation

/// Once Vorssaint is the default browser, a bare NSWorkspace open of a web URL
/// (or a SwiftUI openURL) anywhere in the app is handed straight back to
/// Vorssaint. This pins every remaining bare open, per file, so a new or
/// moved one fails here and has to be looked at.
enum LinkRouterGuardTests {
    /// Bare `NSWorkspace.shared.open(` statements that do not pass
    /// `withApplicationAt`, all of them files, folders, apps or System
    /// Settings panes, never web links.
    static let allowedBareOpens: [String: Int] = [
        "Core/Permissions.swift": 4,
        "UI/Settings/WindowLayoutSettings.swift": 1,
        "UI/MenuPanel/PanelWindowLayoutView.swift": 1,
        "UI/MenuPanel/MetricDetailView.swift": 1,
        "UI/MenuPanel/DiskSection.swift": 2,
        "UI/Cleaner/CleanerView.swift": 1,
        "UI/Shelf/ShelfTilesView.swift": 1,
        "Services/QuickTools/RecentCaptureService.swift": 1,
        "Services/RadialMenu/RadialMenuService.swift": 1,
        "Services/CommandBar/CommandBarCatalog.swift": 3,
        "Services/LinkRouter/LinkOpener.swift": 1,
    ]

    static func run(_ suite: TestSuite) {
        let root = URL(fileURLWithPath: FileManager.default.currentDirectoryPath)
            .appendingPathComponent("Sources/Vorssaint")
        guard let walker = FileManager.default.enumerator(at: root, includingPropertiesForKeys: nil) else {
            suite.expect(false, "link router guard could not read Sources/Vorssaint from \(root.path)")
            return
        }
        var bare: [String: Int] = [:]
        var openURLUses: [String] = []
        for case let file as URL in walker where file.pathExtension == "swift" {
            guard let text = try? String(contentsOf: file, encoding: .utf8) else { continue }
            let relative = String(file.path.dropFirst(root.path.count + 1))
            let lines = text.components(separatedBy: "\n")
            for (index, line) in lines.enumerated() {
                let code = line.trimmingCharacters(in: .whitespaces)
                if code.hasPrefix("//") || code.hasPrefix("///") { continue }
                if line.contains("NSWorkspace.shared.open(") {
                    let window = lines[index..<min(index + 3, lines.count)].joined(separator: " ")
                    if !window.contains("withApplicationAt") { bare[relative, default: 0] += 1 }
                }
                if line.contains("@Environment(\\.openURL)")
                    || line.range(of: #"\bLink\("#, options: .regularExpression) != nil {
                    openURLUses.append(relative)
                }
            }
        }
        suite.expect(bare == allowedBareOpens,
                     "every bare NSWorkspace open is an allowlisted non-web site. Unexpected difference: "
                        + "\(bare.filter { allowedBareOpens[$0.key] != $0.value }) versus "
                        + "\(allowedBareOpens.filter { bare[$0.key] != $0.value })")
        suite.expect(openURLUses.isEmpty,
                     "no SwiftUI openURL or Link( remains, they resolve to the default browser: \(openURLUses)")
    }
}
