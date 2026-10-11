import SwiftUI

// Hearken's menus with checkmarks. The system menu always draws its checkmark on the left;
// these draw it on the right in the app's accent color, with each item's icon (in the text
// color) on the left. They open as a small glass popover from their button, like a menu.
//
//   CheckMenu([
//       .button("Reschedule", systemImage: "calendar.badge.clock") { … },
//       .toggle("Daily Reminder", systemImage: "bell", isOn: $reminder),
//       .divider,
//       .button("End Plan", systemImage: "xmark.circle", role: .destructive) { … },
//   ]) {
//       Label("Plan Options", systemImage: "ellipsis")
//   }
//
//   CheckPicker("Layout", selection: $layout, options: [.init(value: .scroll, title: "Scroll")])

/// One row of a CheckMenu.
struct CheckMenuItem {
    enum Kind {
        case button
        case toggle(Binding<Bool>)
        case choice(isSelected: Bool)
        case stepper(CheckMenuStepper)
        case header
        case divider
    }

    var kind: Kind
    var title: String = ""
    var systemImage: String?
    /// The icon's color; the text color when nil (red for destructive items).
    var iconColor: Color?
    var role: ButtonRole?
    var isDisabled = false
    var action: () -> Void = {}

    static func button(
        _ title: String, systemImage: String? = nil, role: ButtonRole? = nil,
        isDisabled: Bool = false, action: @escaping () -> Void
    ) -> CheckMenuItem {
        CheckMenuItem(kind: .button, title: title, systemImage: systemImage, role: role, isDisabled: isDisabled, action: action)
    }

    /// On shows a checkmark; choosing it flips the value.
    static func toggle(_ title: String, systemImage: String? = nil, isOn: Binding<Bool>) -> CheckMenuItem {
        CheckMenuItem(kind: .toggle(isOn), title: title, systemImage: systemImage)
    }

    /// One of a set; the selected one shows a checkmark.
    static func choice(
        _ title: String, systemImage: String? = nil, iconColor: Color? = nil,
        isSelected: Bool, action: @escaping () -> Void
    ) -> CheckMenuItem {
        CheckMenuItem(kind: .choice(isSelected: isSelected), title: title, systemImage: systemImage, iconColor: iconColor, action: action)
    }

    /// Two buttons side by side that leave the menu open, like the text size buttons.
    static func stepper(_ stepper: CheckMenuStepper) -> CheckMenuItem {
        CheckMenuItem(kind: .stepper(stepper))
    }

    /// A small gray title over the rows that follow.
    static func header(_ title: String) -> CheckMenuItem {
        CheckMenuItem(kind: .header, title: title)
    }

    static var divider: CheckMenuItem { CheckMenuItem(kind: .divider) }
}

struct CheckMenuStepper {
    var decreaseTitle: String
    var decreaseImage: String
    var increaseTitle: String
    var increaseImage: String
    var canDecrease: Bool
    var canIncrease: Bool
    var decrease: () -> Void
    var increase: () -> Void
}

/// A button that opens a CheckMenu.
struct CheckMenu<Label: View>: View {
    let items: [CheckMenuItem]
    let label: () -> Label

    @State private var isPresented = false

    init(_ items: [CheckMenuItem], @ViewBuilder label: @escaping () -> Label) {
        self.items = items
        self.label = label
    }

    var body: some View {
        Button {
            isPresented = true
        } label: {
            label()
        }
        .popover(isPresented: $isPresented) {
            CheckMenuList(items: items) { isPresented = false }
        }
    }
}

/// A form row for picking one of a few values, like a menu-style Picker: the title on the
/// left, the current value and ⌃⌄ on the right.
struct CheckPicker<Value: Hashable>: View {
    let title: String
    @Binding var selection: Value
    let options: [CheckPickerOption<Value>]

    @State private var isPresented = false

    init(_ title: String, selection: Binding<Value>, options: [CheckPickerOption<Value>]) {
        self.title = title
        _selection = selection
        self.options = options
    }

    var body: some View {
        let current = options.first { $0.value == selection }
        Button {
            isPresented = true
        } label: {
            HStack(spacing: 8) {
                Text(title)
                    .foregroundStyle(.primary)
                Spacer(minLength: 12)
                Text(current?.title ?? "")
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
                Image(systemName: "chevron.up.chevron.down")
                    .font(.footnote.weight(.semibold))
                    .foregroundStyle(.secondary)
                    .accessibilityHidden(true)
            }
            .contentShape(.rect)
        }
        .buttonStyle(.plain)
        .popover(isPresented: $isPresented, attachmentAnchor: .point(.trailing)) {
            CheckMenuList(items: options.map { option in
                .choice(option.title, systemImage: option.systemImage, isSelected: option.value == selection) {
                    selection = option.value
                }
            }) { isPresented = false }
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(title)
        .accessibilityValue(current?.title ?? "")
        .accessibilityAddTraits(.isButton)
        .accessibilityHint("Shows the choices.")
    }
}

struct CheckPickerOption<Value: Hashable> {
    let value: Value
    let title: String
    var systemImage: String?
}

/// The popover's rows. Scrolls when there are more than fit.
struct CheckMenuList: View {
    let items: [CheckMenuItem]
    let dismiss: () -> Void

    @AppStorage(SettingsKey.accent) private var accent: AccentOption = .blue
    @State private var contentHeight: CGFloat = 0

    private static let maxHeight: CGFloat = 460

    var body: some View {
        let reservesIcon = items.contains { $0.systemImage != nil }

        ScrollView {
            VStack(alignment: .leading, spacing: 0) {
                ForEach(items.indices, id: \.self) { index in
                    row(items[index], reservesIcon: reservesIcon)
                }
            }
            .padding(.vertical, 6)
            .onGeometryChange(for: CGFloat.self) { $0.size.height } action: { contentHeight = $0 }
        }
        .scrollBounceBehavior(.basedOnSize)
        .frame(minWidth: 220)
        .frame(height: min(max(contentHeight, 44), Self.maxHeight))
        .fixedSize(horizontal: true, vertical: false)
        // The checkmark uses the app's accent, even where the menu's button is tinted gray.
        .tint(accent.color)
        .presentationCompactAdaptation(.popover)
    }

    @ViewBuilder
    private func row(_ item: CheckMenuItem, reservesIcon: Bool) -> some View {
        switch item.kind {
        case .divider:
            Divider()
                .padding(.vertical, 6)
        case .header:
            Text(item.title)
                .font(.footnote)
                .foregroundStyle(.secondary)
                .padding(.horizontal, 20)
                .padding(.top, 8)
                .padding(.bottom, 2)
                .accessibilityAddTraits(.isHeader)
        case .stepper(let stepper):
            HStack(spacing: 10) {
                stepButton(stepper.decreaseTitle, stepper.decreaseImage, enabled: stepper.canDecrease, action: stepper.decrease)
                stepButton(stepper.increaseTitle, stepper.increaseImage, enabled: stepper.canIncrease, action: stepper.increase)
            }
            .padding(.horizontal, 14)
            .padding(.vertical, 6)
        case .button:
            rowButton(item, checked: false, reservesIcon: reservesIcon) {
                dismiss()
                // After the popover has closed, so an action that opens a sheet or a
                // confirmation can present it.
                Task {
                    try? await Task.sleep(for: .milliseconds(320))
                    item.action()
                }
            }
        case .toggle(let isOn):
            rowButton(item, checked: isOn.wrappedValue, reservesIcon: reservesIcon) {
                isOn.wrappedValue.toggle()
                dismiss()
            }
        case .choice(let isSelected):
            rowButton(item, checked: isSelected, reservesIcon: reservesIcon) {
                item.action()
                dismiss()
            }
        }
    }

    private func rowButton(_ item: CheckMenuItem, checked: Bool, reservesIcon: Bool, perform: @escaping () -> Void) -> some View {
        let destructive = item.role == .destructive
        return Button(action: perform) {
            HStack(spacing: 14) {
                if let symbol = item.systemImage {
                    Image(systemName: symbol)
                        .font(.body)
                        .foregroundStyle(item.iconColor ?? (destructive ? Color.red : Color.primary))
                        .frame(width: 24)
                        .accessibilityHidden(true)
                } else if reservesIcon {
                    Color.clear.frame(width: 24, height: 1)
                }
                Text(item.title)
                    .foregroundStyle(destructive ? Color.red : Color.primary)
                    .multilineTextAlignment(.leading)
                    .fixedSize(horizontal: false, vertical: true)
                Spacer(minLength: 24)
                Image(systemName: "checkmark")
                    .font(.body.weight(.semibold))
                    .foregroundStyle(.tint)
                    .opacity(checked ? 1 : 0)
                    .accessibilityHidden(true)
            }
            .font(.body)
            .padding(.horizontal, 20)
            .padding(.vertical, 12)
            .contentShape(.rect)
            .opacity(item.isDisabled ? 0.4 : 1)
        }
        .buttonStyle(CheckMenuRowStyle())
        .disabled(item.isDisabled)
        .accessibilityAddTraits(checked ? .isSelected : [])
    }

    private func stepButton(_ title: String, _ image: String, enabled: Bool, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Image(systemName: image)
                .font(.title3)
                .foregroundStyle(Color.primary)
                .frame(maxWidth: .infinity)
                .frame(height: 44)
                .background(Color.primary.opacity(0.08), in: .rect(cornerRadius: 12))
                .opacity(enabled ? 1 : 0.35)
        }
        .buttonStyle(.plain)
        .disabled(!enabled)
        .accessibilityLabel(title)
    }
}

/// A soft highlight while a row is pressed, like a menu.
private struct CheckMenuRowStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .background(configuration.isPressed ? Color.primary.opacity(0.08) : Color.clear)
    }
}
