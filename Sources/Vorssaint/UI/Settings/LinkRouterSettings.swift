// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 Vorssaint

import SwiftUI

struct LinkRouterSettings: View {
    @ObservedObject private var l10n = L10n.shared
    private var text: LinkRouterFeatureStrings { FeatureStrings.linkRouter(l10n.language) }

    var body: some View {
        Form {
            Text(text.hubDescription).foregroundStyle(.secondary)
        }
    }
}
