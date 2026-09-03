//
//  AppFocusedValues.swift
//  ldap-studio
//

import SwiftUI

/// Everything the top menu bar can trigger, grouped by which window/view
/// actually owns the behavior — each group is published via
/// `.focusedSceneValue` from the view that owns it, so the menu bar always
/// acts on whichever window is actually frontmost, and disables itself
/// automatically when that window (or a required selection within it)
/// isn't there.

struct ConnectionCommands {
    var addConnection: () -> Void
    var importConnection: () -> Void
}

struct SelectedConnectionCommands {
    var open: (() -> Void)?
    var edit: (() -> Void)?
    var export: (() -> Void)?
    var delete: (() -> Void)?
}

struct DirectoryCommands {
    var newEntry: () -> Void
    var importLDIF: () -> Void
    var openSchema: () -> Void
    var advancedSearch: () -> Void
    var deleteSelected: (() -> Void)?
}

struct EntryDetailCommands {
    var addAttribute: () -> Void
    var editAttribute: (() -> Void)?
    var deleteAttribute: (() -> Void)?
    var moveDN: () -> Void
    var copyDN: () -> Void
    var exportLDIF: () -> Void
    var refresh: () -> Void
    var viewValue: (() -> Void)?
    var copyFull: (() -> Void)?
    var copyAttributeName: (() -> Void)?
    var copyValue: (() -> Void)?
    var setPassword: (() -> Void)?
    var setPhoto: (() -> Void)?
}

private struct ConnectionCommandsKey: FocusedValueKey {
    typealias Value = ConnectionCommands
}

private struct SelectedConnectionCommandsKey: FocusedValueKey {
    typealias Value = SelectedConnectionCommands
}

private struct DirectoryCommandsKey: FocusedValueKey {
    typealias Value = DirectoryCommands
}

private struct EntryDetailCommandsKey: FocusedValueKey {
    typealias Value = EntryDetailCommands
}

extension FocusedValues {
    var connectionCommands: ConnectionCommands? {
        get { self[ConnectionCommandsKey.self] }
        set { self[ConnectionCommandsKey.self] = newValue }
    }

    var selectedConnectionCommands: SelectedConnectionCommands? {
        get { self[SelectedConnectionCommandsKey.self] }
        set { self[SelectedConnectionCommandsKey.self] = newValue }
    }

    var directoryCommands: DirectoryCommands? {
        get { self[DirectoryCommandsKey.self] }
        set { self[DirectoryCommandsKey.self] = newValue }
    }

    var entryDetailCommands: EntryDetailCommands? {
        get { self[EntryDetailCommandsKey.self] }
        set { self[EntryDetailCommandsKey.self] = newValue }
    }
}
