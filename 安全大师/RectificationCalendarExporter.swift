//
//  RectificationCalendarExporter.swift
//  安全大师
//

import Foundation
#if canImport(EventKit)
import EventKit
#endif

/// 限期整改时可选写入系统「日历」作为到期提醒（需用户授权）。
enum RectificationCalendarExporter {
    /// - Returns: 是否已成功写入日历事件（用户拒绝授权或失败时为 `false`）。
    static func tryAddDeadlineReminder(
        title: String,
        notes: String,
        deadlineDay: Date,
        location: String?
    ) async -> Bool {
        #if canImport(EventKit)
        let store = EKEventStore()
        let granted = await requestEventAccess(store)
        guard granted else { return false }
        guard let calendar = store.defaultCalendarForNewEvents else { return false }

        let dayStart = Calendar.current.startOfDay(for: deadlineDay)
        let event = EKEvent(eventStore: store)
        event.calendar = calendar
        event.title = title
        event.notes = notes
        event.location = location
        event.isAllDay = true
        event.startDate = dayStart
        event.endDate = Calendar.current.date(byAdding: .day, value: 1, to: dayStart) ?? dayStart

        do {
            try store.save(event, span: .thisEvent, commit: true)
            return true
        } catch {
            return false
        }
        #else
        return false
        #endif
    }

    #if canImport(EventKit)
    private static func requestEventAccess(_ store: EKEventStore) async -> Bool {
        #if os(iOS)
        if #available(iOS 17.0, *) {
            return (try? await store.requestFullAccessToEvents()) ?? false
        }
        return await withCheckedContinuation { cont in
            store.requestAccess(to: .event) { ok, _ in
                cont.resume(returning: ok)
            }
        }
        #elseif os(macOS)
        return await withCheckedContinuation { cont in
            store.requestAccess(to: .event) { ok, _ in
                cont.resume(returning: ok)
            }
        }
        #else
        return false
        #endif
    }
    #endif
}
