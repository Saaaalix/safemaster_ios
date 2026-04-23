//
//  NavigationTitleMode+iOS.swift
//  安全大师
//

import SwiftUI

extension View {
    @ViewBuilder
    func inlineNavigationTitleMode() -> some View {
#if os(iOS)
        navigationBarTitleDisplayMode(.inline)
#else
        self
#endif
    }
}
