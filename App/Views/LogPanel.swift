import SwiftUI

/// What the runs did, newest at the bottom.
struct LogPanel: View {
    let controller: FlowController

    private static let time: DateFormatter = {
        let f = DateFormatter()
        f.dateFormat = "HH:mm:ss"
        return f
    }()

    var body: some View {
        ScrollViewReader { proxy in
            ScrollView {
                LazyVStack(alignment: .leading, spacing: 3) {
                    if controller.log.isEmpty {
                        Text("Runs are logged here: each hand-off, each condition's answer, and why a run stopped.")
                            .foregroundStyle(.secondary)
                    }
                    ForEach(controller.log) { line in
                        HStack(alignment: .firstTextBaseline, spacing: 8) {
                            Text(Self.time.string(from: line.date))
                                .foregroundStyle(.tertiary)
                            Text(line.text)
                                .textSelection(.enabled)
                        }
                        .id(line.id)
                    }
                }
                .font(.system(size: 11.5, design: .monospaced))
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(10)
            }
            .onChange(of: controller.log.count) {
                if let last = controller.log.last { proxy.scrollTo(last.id, anchor: .bottom) }
            }
        }
        .background(.background)
    }
}
