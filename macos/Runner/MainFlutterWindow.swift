import Cocoa
import FlutterMacOS

class MainFlutterWindow: NSWindow {
  override func awakeFromNib() {
    let flutterViewController = FlutterViewController()
    let windowFrame = self.frame
    let defaultWindowSize = NSSize(width: 1510, height: 870)
    let minimumWindowSize = NSSize(width: 960, height: 640)

    self.contentViewController = flutterViewController

    var nextFrame = windowFrame
    if let visibleFrame = screen?.visibleFrame ?? NSScreen.main?.visibleFrame {
      let horizontalMargin: CGFloat = 80
      let verticalMargin: CGFloat = 80
      let size = NSSize(
        width: min(defaultWindowSize.width, max(visibleFrame.width - horizontalMargin, minimumWindowSize.width)),
        height: min(defaultWindowSize.height, max(visibleFrame.height - verticalMargin, minimumWindowSize.height))
      )
      nextFrame.size = size
      nextFrame.origin.x = max(
        visibleFrame.minX,
        visibleFrame.midX - (size.width / 2.0)
      )
      nextFrame.origin.y = max(
        visibleFrame.minY,
        visibleFrame.midY - (size.height / 2.0)
      )
    } else {
      nextFrame.size = defaultWindowSize
    }
    self.setFrame(nextFrame, display: true)
    minSize = minimumWindowSize

    titleVisibility = .hidden
    titlebarAppearsTransparent = true
    isMovableByWindowBackground = true
    styleMask.insert(.fullSizeContentView)
    if #available(macOS 11.0, *) {
      toolbarStyle = .unifiedCompact
    }
    backgroundColor = NSColor(
      calibratedRed: 15.0 / 255.0,
      green: 23.0 / 255.0,
      blue: 42.0 / 255.0,
      alpha: 1.0
    )

    RegisterGeneratedPlugins(registry: flutterViewController)

    super.awakeFromNib()

    makeKeyAndOrderFront(nil)
    orderFrontRegardless()
  }
}
