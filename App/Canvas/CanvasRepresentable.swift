import SwiftUI

/// Hosts the AppKit canvas in the SwiftUI window. The canvas watches the flow itself,
/// so SwiftUI only has to create it and hand out a reference for menu commands.
struct CanvasRepresentable: NSViewRepresentable {
    let controller: FlowController

    func makeNSView(context: Context) -> CanvasView {
        let view = CanvasView(controller: controller)
        controller.canvas = view
        return view
    }

    func updateNSView(_ view: CanvasView, context: Context) {}
}
