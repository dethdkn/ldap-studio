//
//  AttributeValueDetailSheet.swift
//  ldap-studio
//

import SwiftUI

/// Opened by double-clicking a value in the attribute table — some values
/// (long text, photos) don't fit in a table row, so this shows the full
/// thing in a resizable, scrollable, selectable panel.
struct AttributeValueDetailSheet: View {
    let attribute: Attribute

    @Environment(\.dismiss) private var dismiss

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack {
                Text(attribute.name)
                    .font(.headline)
                Spacer()
                Button("Close") {
                    dismiss()
                }
                .keyboardShortcut(.cancelAction)
            }
            .padding()

            Divider()

            if let image = attribute.decodedImage {
                ScrollView([.horizontal, .vertical]) {
                    Image(nsImage: image)
                        .resizable()
                        .scaledToFit()
                        .padding()
                }
            } else {
                ScrollView(.vertical) {
                    Text(attribute.value)
                        .font(attribute.isBinary ? .system(.body, design: .monospaced) : .body)
                        .textSelection(.enabled)
                        .fixedSize(horizontal: false, vertical: true)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding()
                }
            }
        }
        .frame(minWidth: 420, idealWidth: 560, minHeight: 320, idealHeight: 440)
    }
}

#Preview {
    AttributeValueDetailSheet(attribute: Attribute(name: "description", value: String(repeating: "This is a very long value. ", count: 40)))
}
