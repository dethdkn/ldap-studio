//
//  DoubleClickObserver.swift
//  ldap-studio
//

import AppKit
import SwiftUI

/// An invisible view that observes double-clicks within its bounds without
/// ever claiming/consuming the click — unlike a SwiftUI `Gesture`, which
/// competes with a List's native click-to-select handling on macOS, this
/// taps the raw event stream and always lets the event continue on its way.
struct DoubleClickObserver: NSViewRepresentable {
    let onDoubleClick: () -> Void

    func makeNSView(context: Context) -> ObserverView {
        let view = ObserverView()
        view.onDoubleClick = onDoubleClick
        return view
    }

    func updateNSView(_ nsView: ObserverView, context: Context) {
        nsView.onDoubleClick = onDoubleClick
    }

    final class ObserverView: NSView {
        var onDoubleClick: (() -> Void)?
        private var monitor: Any?

        override func viewDidMoveToWindow() {
            super.viewDidMoveToWindow()
            if let monitor {
                NSEvent.removeMonitor(monitor)
                self.monitor = nil
            }
            guard window != nil else { return }
            monitor = NSEvent.addLocalMonitorForEvents(matching: .leftMouseDown) { [weak self] event in
                guard let self, event.clickCount == 2 else { return event }
                let locationInView = self.convert(event.locationInWindow, from: nil)
                if self.bounds.contains(locationInView) {
                    self.onDoubleClick?()
                }
                return event
            }
        }

        deinit {
            if let monitor {
                NSEvent.removeMonitor(monitor)
            }
        }
    }
}
