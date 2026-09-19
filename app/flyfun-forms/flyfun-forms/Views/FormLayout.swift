import SwiftUI

// MARK: - Form style

extension View {
    /// The form style every editor in the app uses.
    ///
    /// macOS `Form` defaults to `.formStyle(.columns)`: a label/value grid that
    /// right-aligns labels, renders `Section("Schedule")` as a bare line of text
    /// with no grouping or background, and *centres itself* in the space it is
    /// given. That is why the Mac editors used to float as a narrow column in
    /// the middle of an empty pane with their section titles reading as stray
    /// labels. `.grouped` is the Settings-style treatment: real section headers,
    /// grouped rows, full width, pinned to the top.
    func platformFormStyle() -> some View {
        formStyle(.grouped)
    }
}

// MARK: - Layout width

enum FormLayout {
    /// The widest a label/value form should be allowed to get.
    ///
    /// Wide mode earns its space by showing more at once, never by stretching a
    /// single row across the window — a label pinned to the left edge with its
    /// value 1000pt away is the thing that reads as broken. Roughly the width
    /// of a Settings pane.
    static let columnMaxWidth: CGFloat = 620
}

/// One column of a wide two-pane editor: a grouped form capped at a readable
/// measure and pinned to the top-leading corner of its share of the width.
struct FormColumn<Content: View>: View {
    var maxWidth: CGFloat = FormLayout.columnMaxWidth
    @ViewBuilder var content: Content

    var body: some View {
        Form { content }
            .platformFormStyle()
            .frame(maxWidth: maxWidth, alignment: .topLeading)
            .frame(maxWidth: .infinity, alignment: .topLeading)
    }
}

// MARK: - Detail header

/// A detail pane's identity banner.
///
/// `navigationTitle` is swallowed by `NavigationSplitView` on macOS — the window
/// title bar carries the *content* column's title ("People", "Flights") — so
/// without this the detail pane gives no clue which record is open. It sits
/// outside the form's scroll view so it stays put while the form scrolls.
struct DetailHeader<Content: View>: View {
    @ViewBuilder var content: Content

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            content
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.horizontal, 20)
        .padding(.top, 14)
        .padding(.bottom, 12)
        .background(.bar)
        .overlay(alignment: .bottom) { Divider() }
    }
}

// MARK: - Removable row

/// A list row with an inline remove control.
///
/// Crew and passenger rows used to carry removal on `.swipeActions` alone,
/// which is a no-op on macOS — there was no way at all to take one person off a
/// flight on the Mac short of reopening the whole two-list picker. The button
/// works everywhere; the swipe action stays for the iPhone habit.
struct RemovableRow<Label: View>: View {
    var removeTitle: LocalizedStringKey = "Remove"
    let onRemove: () -> Void
    @ViewBuilder var label: Label

    var body: some View {
        HStack {
            label
            Spacer(minLength: 8)
            Button(role: .destructive, action: onRemove) {
                Image(systemName: "minus.circle.fill")
                    .foregroundStyle(.secondary)
            }
            .buttonStyle(.plain)
            .help(removeTitle)
            .accessibilityLabel(removeTitle)
        }
        .contentShape(Rectangle())
        .contextMenu {
            Button(removeTitle, role: .destructive, action: onRemove)
        }
        .swipeActions {
            Button(removeTitle, role: .destructive, action: onRemove)
        }
    }
}
