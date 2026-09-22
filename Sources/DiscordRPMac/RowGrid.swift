import SwiftUI

private let rowGridLabelColumn: CGFloat = 132
private let rowGridColumnGap: CGFloat = 10
private let rowGridCardPadding: CGFloat = 14
private let rowGridCardSpacing: CGFloat = 8
let rowGridControlIndent = rowGridLabelColumn + rowGridColumnGap

/// The single row primitive: label in the fixed column, control in the control column.
///
/// Alignment is `.top`, not `.firstTextBaseline`: tall children without a text baseline should keep
/// their top edge aligned with the row label. `help` is attached to both halves so explanatory text
/// costs no vertical space; warning, error and status text can still use `hint`.
func row<Content: View>(_ label: String, help: String? = nil,
                        @ViewBuilder content: () -> Content) -> some View {
    HStack(alignment: .top, spacing: rowGridColumnGap) {
        Text(label)
            .foregroundStyle(.secondary)
            .frame(width: rowGridLabelColumn, alignment: .trailing)
            .padding(.top, 3)
            .optionalHelp(help)
        content()
            .optionalHelp(help)
        Spacer(minLength: 0)
    }
    .frame(minHeight: 24)
}

/// Helper/status text sits under its control, in the control column.
func hint(_ text: String, color: Color = .secondary) -> some View {
    Text(text)
        .font(.system(size: 11))
        .foregroundStyle(color)
        .fixedSize(horizontal: false, vertical: true)
        .padding(.leading, rowGridControlIndent)
}

func card<Content: View>(_ title: String, help: String? = nil,
                         @ViewBuilder content: () -> Content) -> some View {
    cardChrome(help: help) {
        Text(title)
            .font(.system(size: 11, weight: .semibold))
            .foregroundStyle(.secondary)
    } content: {
        content()
    }
}

func cardChrome<Header: View, Content: View>(
    help: String? = nil,
    @ViewBuilder header: () -> Header,
    @ViewBuilder content: () -> Content
) -> some View {
    VStack(alignment: .leading, spacing: 8) {
        header()
            .optionalHelp(help)
        VStack(alignment: .leading, spacing: rowGridCardSpacing) {
            content()
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(rowGridCardPadding)
        .background(
            RoundedRectangle(cornerRadius: 10, style: .continuous)
                .fill(Color(nsColor: .controlBackgroundColor))
        )
        .overlay(
            RoundedRectangle(cornerRadius: 10, style: .continuous)
                .stroke(Color(nsColor: .separatorColor), lineWidth: 1)
        )
    }
}
