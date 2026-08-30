import AppKit
import ApplicationServices
import Foundation
import OpenIslandCore

/// Reads WorkBuddy's own, freshly fetched balance through macOS Accessibility.
/// This deliberately avoids WorkBuddy's private daemon token and private RPC.
enum WorkBuddyUsageBridge {
    private static let bundleIdentifiers = [
        "com.tencent.workbuddy.mac",
        "com.workbuddy.workbuddy",
    ]
    private static let maxNodes = 700

    @MainActor
    static func runningProcessIdentifier() -> pid_t? {
        bundleIdentifiers.lazy.compactMap { bundleIdentifier in
            NSRunningApplication.runningApplications(withBundleIdentifier: bundleIdentifier)
                .first?
                .processIdentifier
        }
        .first
    }

    @MainActor
    static func isApplicationActive() -> Bool {
        guard let processIdentifier = runningProcessIdentifier() else { return false }
        return NSRunningApplication(processIdentifier: processIdentifier)?.isActive == true
    }

    /// A forced refresh is user initiated, so it is the right moment to show
    /// macOS's one-time Accessibility permission prompt. Passive polling never
    /// prompts or steals focus.
    static func ensureAccessibilityPermission(prompt: Bool) -> Bool {
        guard prompt else { return AXIsProcessTrusted() }
        let options = ["AXTrustedCheckOptionPrompt": true] as CFDictionary
        return AXIsProcessTrustedWithOptions(options)
    }

    /// Passive mode only captures an already visible account menu. Forced mode
    /// opens the account menu, presses WorkBuddy's official refresh control,
    /// reads the resulting balance, then closes the menu if we opened it.
    static func capture(
        processIdentifier: pid_t,
        forceRefresh: Bool
    ) -> WorkBuddyUsageSnapshot? {
        guard ensureAccessibilityPermission(prompt: false) else { return nil }

        let application = AXUIElementCreateApplication(processIdentifier)
        var nodes = accessibilityNodes(from: application)
        var accountTrigger: AXUIElement?
        var openedMenu = false

        if forceRefresh, balance(from: nodes) == nil {
            for candidate in accountTriggerCandidates(in: nodes).prefix(5) {
                guard AXUIElementPerformAction(candidate, kAXPressAction as CFString) == .success else {
                    continue
                }
                Thread.sleep(forTimeInterval: 0.45)
                nodes = accessibilityNodes(from: application)
                if balance(from: nodes) != nil {
                    accountTrigger = candidate
                    openedMenu = true
                    break
                }
                _ = AXUIElementPerformAction(candidate, kAXPressAction as CFString)
                Thread.sleep(forTimeInterval: 0.12)
            }
        }

        if forceRefresh, let refreshButton = refreshButton(in: nodes) {
            _ = AXUIElementPerformAction(refreshButton, kAXPressAction as CFString)
            Thread.sleep(forTimeInterval: 1.6)
            nodes = accessibilityNodes(from: application)
        }

        let points = balance(from: nodes)

        if openedMenu {
            if let menu = nodes.first(where: { $0.role == (kAXMenuRole as String) })?.element {
                let result = AXUIElementPerformAction(menu, kAXCancelAction as CFString)
                if result != .success, let accountTrigger {
                    _ = AXUIElementPerformAction(accountTrigger, kAXPressAction as CFString)
                }
            } else if let accountTrigger {
                _ = AXUIElementPerformAction(accountTrigger, kAXPressAction as CFString)
            }
        }

        guard let points else { return nil }
        return WorkBuddyUsageSnapshot(
            source: forceRefresh ? "workbuddy-live-refresh" : "workbuddy-visible-menu",
            capturedAt: .now,
            pointsRemaining: points
        )
    }

    private struct AccessibilityNode {
        let element: AXUIElement
        let role: String
        let text: String
    }

    private static func accessibilityNodes(from root: AXUIElement) -> [AccessibilityNode] {
        var result: [AccessibilityNode] = []
        var queue: [(AXUIElement, Int)] = [(root, 0)]

        while queue.isEmpty == false, result.count < maxNodes {
            let (element, depth) = queue.removeFirst()
            let role = stringAttribute(kAXRoleAttribute as CFString, of: element) ?? ""
            let text = [
                stringAttribute(kAXTitleAttribute as CFString, of: element),
                stringAttribute(kAXDescriptionAttribute as CFString, of: element),
                stringAttribute(kAXValueAttribute as CFString, of: element),
            ]
            .compactMap { $0 }
            .filter { $0.isEmpty == false }
            .joined(separator: " ")
            result.append(AccessibilityNode(element: element, role: role, text: text))

            guard depth < 14 else { continue }
            if let children = attribute(kAXChildrenAttribute as CFString, of: element) as? [AXUIElement] {
                queue.append(contentsOf: children.map { ($0, depth + 1) })
            }
        }

        return result
    }

    private static func balance(from nodes: [AccessibilityNode]) -> Int? {
        nodes.lazy.compactMap { WorkBuddyUsageParser.pointsBalance(from: $0.text) }.first
    }

    private static func refreshButton(in nodes: [AccessibilityNode]) -> AXUIElement? {
        nodes.first { node in
            node.role == (kAXButtonRole as String)
                && ["刷新", "Refresh"].contains(node.text.trimmingCharacters(in: .whitespacesAndNewlines))
        }?.element
    }

    private static func accountTriggerCandidates(
        in nodes: [AccessibilityNode]
    ) -> [AXUIElement] {
        let exclusions = ["消息中心", "扫码", "选择工作空间", "Message", "QR", "workspace"]
        return nodes.filter { node in
            guard node.role == (kAXPopUpButtonRole as String), node.text.isEmpty == false else {
                return false
            }
            return exclusions.contains { node.text.localizedCaseInsensitiveContains($0) } == false
        }
        .map(\.element)
    }

    private static func stringAttribute(
        _ name: CFString,
        of element: AXUIElement
    ) -> String? {
        attribute(name, of: element) as? String
    }

    private static func attribute(
        _ name: CFString,
        of element: AXUIElement
    ) -> CFTypeRef? {
        var value: CFTypeRef?
        guard AXUIElementCopyAttributeValue(element, name, &value) == .success else {
            return nil
        }
        return value
    }
}
