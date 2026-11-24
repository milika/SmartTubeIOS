import SwiftUI

// MARK: - SettingsPicker
//
// A Settings row that picks one of `options`.
//
// tvOS 27 pushes an empty list for a `Picker` in a `Form` (the default navigation-link
// style, and `.pickerStyle(.navigationLink)` too), even for a two-option picker in an
// otherwise empty app. No setting could be changed, and leaving that empty list left the
// Settings tab blank. On tvOS this row pushes its own option list instead; elsewhere it
// is a plain `Picker`.

struct SettingsPicker<Value: Hashable, OptionLabel: View>: View {
    private let title: Text
    @Binding private var selection: Value
    private let options: [Value]
    private let optionLabel: (Value) -> OptionLabel

    init(
        _ titleKey: LocalizedStringKey,
        selection: Binding<Value>,
        options: [Value],
        @ViewBuilder optionLabel: @escaping (Value) -> OptionLabel
    ) {
        self.init(title: Text(titleKey), selection: selection, options: options, optionLabel: optionLabel)
    }

    @_disfavoredOverload
    init<S: StringProtocol>(
        _ title: S,
        selection: Binding<Value>,
        options: [Value],
        @ViewBuilder optionLabel: @escaping (Value) -> OptionLabel
    ) {
        self.init(title: Text(title), selection: selection, options: options, optionLabel: optionLabel)
    }

    private init(
        title: Text,
        selection: Binding<Value>,
        options: [Value],
        optionLabel: @escaping (Value) -> OptionLabel
    ) {
        self.title = title
        _selection = selection
        self.options = options
        self.optionLabel = optionLabel
    }

    var body: some View {
        #if os(tvOS)
        NavigationLink {
            SettingsOptionList(title: title, selection: $selection, options: options, optionLabel: optionLabel)
        } label: {
            LabeledContent {
                optionLabel(selection)
            } label: {
                title
            }
        }
        #else
        Picker(selection: $selection) {
            ForEach(options, id: \.self) { optionLabel($0).tag($0) }
        } label: {
            title
        }
        #endif
    }
}

#if os(tvOS)
/// The pushed option list: the current value has a checkmark and starts focused; choosing
/// a value sets it and goes back, like the system picker.
private struct SettingsOptionList<Value: Hashable, OptionLabel: View>: View {
    let title: Text
    @Binding var selection: Value
    let options: [Value]
    let optionLabel: (Value) -> OptionLabel

    @Environment(\.dismiss) private var dismiss
    @FocusState private var focusedOption: Value?

    var body: some View {
        List {
            Section {
                ForEach(options, id: \.self) { value in
                    Button {
                        selection = value
                        dismiss()
                    } label: {
                        HStack {
                            optionLabel(value)
                            Spacer()
                            if value == selection {
                                Image(systemName: AppSymbol.checkmark)
                            }
                        }
                    }
                    .focused($focusedOption, equals: value)
                }
            } header: {
                title
            }
        }
        .defaultFocus($focusedOption, selection)
    }
}
#endif
