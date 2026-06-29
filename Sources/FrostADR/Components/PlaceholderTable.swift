import SwiftUI

struct PlaceholderTable: View {
  let columns: [String]
  let emptyTitle: String
  let emptyMessage: String
  var minHeight: CGFloat = 240

  var body: some View {
    VStack(spacing: 0) {
      HStack(spacing: 0) {
        ForEach(columns, id: \.self) { column in
          Text(column)
            .font(.system(size: 11, weight: .semibold))
            .foregroundStyle(FrostTheme.mutedText)
            .textCase(.uppercase)
            .lineLimit(1)
            .truncationMode(.tail)
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.horizontal, 12)
            .padding(.vertical, 11)
        }
      }
      .background(FrostTheme.tableHeaderBackground)

      Divider()

      EmptyStateView(
        title: emptyTitle,
        message: emptyMessage,
        systemImage: "tablecells",
        compact: false
      )
      .frame(maxWidth: .infinity, minHeight: minHeight)
      .background(FrostTheme.tableRowBackground)
    }
    .background(
      RoundedRectangle(cornerRadius: FrostTheme.radius, style: .continuous)
        .fill(FrostTheme.secondaryCardBackground)
    )
    .clipShape(RoundedRectangle(cornerRadius: FrostTheme.radius, style: .continuous))
    .overlay(
      RoundedRectangle(cornerRadius: FrostTheme.radius, style: .continuous)
        .stroke(FrostTheme.subtleBorder, lineWidth: 1)
    )
  }
}

struct PlaceholderTable_Previews: PreviewProvider {
  static var previews: some View {
    PlaceholderTable(
      columns: ["Name", "Type", "Status"],
      emptyTitle: "等待端上数据接入",
      emptyMessage: "表格结构已就绪。"
    )
    .padding()
  }
}
