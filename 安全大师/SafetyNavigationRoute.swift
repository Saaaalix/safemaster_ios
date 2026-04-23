//
//  SafetyNavigationRoute.swift
//  安全大师
//
//  全应用共用一个导航路径类型，避免嵌套 NavigationStack 使用不同路径类型时，
//  SwiftUI 在分栏/列状态下触发 AnyNavigationPath.comparisonTypeMismatch 崩溃。

import Foundation

enum SafetyNavigationRoute: Hashable {
    case hazardInspection
    case profile
    case hazardResult(id: UUID, payload: HazardResultPayload)
    case hazardRecords
    case hazardLibrary
}
