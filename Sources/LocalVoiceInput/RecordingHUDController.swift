import AppKit

@MainActor
final class RecordingHUDController {
    private let window: NSPanel
    private let levelFill = NSView()
    private let spinner = SpinnerView()
    private var levelFillBaseColor = NSColor.white

    init() {
        let content = NSView(frame: NSRect(x: 0, y: 0, width: 28, height: 28))
        content.wantsLayer = true
        content.layer?.backgroundColor = NSColor.black.withAlphaComponent(0.48).cgColor
        content.layer?.cornerRadius = 14

        levelFill.frame = NSRect(x: 11, y: 11, width: 6, height: 6)
        levelFill.wantsLayer = true
        levelFill.layer?.backgroundColor = NSColor.white.withAlphaComponent(0.38).cgColor
        levelFill.layer?.cornerRadius = 3

        spinner.frame = NSRect(x: 6, y: 6, width: 16, height: 16)
        spinner.isHidden = true

        content.addSubview(levelFill)
        content.addSubview(spinner)

        self.window = NSPanel(
            contentRect: content.frame,
            styleMask: [.borderless, .nonactivatingPanel],
            backing: .buffered,
            defer: true
        )
        window.contentView = content
        window.backgroundColor = .clear
        window.isOpaque = false
        window.hasShadow = false
        window.level = .floating
        window.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .transient]
        window.ignoresMouseEvents = true
    }

    func show() {
        showRecording()
    }

    func showRecording() {
        showRecording(fillColor: .white)
    }

    func showVoiceInstructionRecording() {
        showRecording(fillColor: .systemBlue)
    }

    private func showRecording(fillColor: NSColor) {
        levelFillBaseColor = fillColor
        position()
        spinner.stop()
        spinner.isHidden = true
        levelFill.isHidden = false
        update(level: 0)
        window.orderFrontRegardless()
    }

    func showTranscribing() {
        showTranscribing(isWarmup: false)
    }

    func showTranscribing(isWarmup: Bool) {
        showTranscribing(color: isWarmup
            ? NSColor.systemOrange.withAlphaComponent(0.86)
            : NSColor.white.withAlphaComponent(0.62)
        )
    }

    func showVoiceInstructionTranscribing() {
        showTranscribing(color: NSColor.systemBlue.withAlphaComponent(0.78))
    }

    private func showTranscribing(color: NSColor) {
        position()
        levelFill.isHidden = true
        spinner.isHidden = false
        spinner.color = color
        spinner.start()
        window.orderFrontRegardless()
    }

    func hide() {
        spinner.stop()
        window.orderOut(nil)
    }

    func update(level: Float) {
        let normalized = CGFloat(min(1, max(0, level)))
        let eased = min(1, pow(normalized, 0.85) * 0.88)
        let diameter = max(4, 6 + 15 * eased)
        let origin = (28 - diameter) / 2
        levelFill.frame = NSRect(x: origin, y: origin, width: diameter, height: diameter)
        levelFill.layer?.cornerRadius = diameter / 2
        levelFill.layer?.backgroundColor = levelFillBaseColor.withAlphaComponent(0.12 + 0.34 * eased).cgColor
    }

    private func position() {
        guard let screen = NSScreen.main else { return }
        let frame = screen.frame
        let size = window.frame.size
        let x = frame.midX - size.width / 2
        let y = screen.visibleFrame.minY + 22
        window.setFrameOrigin(NSPoint(x: x, y: y))
    }
}

private final class SpinnerView: NSView {
    private var angle: CGFloat = 0
    private var timer: Timer?
    var color = NSColor.white.withAlphaComponent(0.62) {
        didSet {
            needsDisplay = true
        }
    }

    func start() {
        timer?.invalidate()
        timer = Timer.scheduledTimer(withTimeInterval: 1.0 / 30.0, repeats: true) { [weak self] _ in
            guard let self else { return }
            self.angle = (self.angle + 12).truncatingRemainder(dividingBy: 360)
            self.needsDisplay = true
        }
    }

    func stop() {
        timer?.invalidate()
        timer = nil
        angle = 0
        needsDisplay = true
    }

    override func draw(_ dirtyRect: NSRect) {
        super.draw(dirtyRect)

        let inset: CGFloat = 2.2
        let rect = bounds.insetBy(dx: inset, dy: inset)
        let center = NSPoint(x: bounds.midX, y: bounds.midY)
        let radius = min(rect.width, rect.height) / 2
        let path = NSBezierPath()
        path.lineWidth = 2.0
        path.lineCapStyle = .round
        path.appendArc(
            withCenter: center,
            radius: radius,
            startAngle: angle,
            endAngle: angle + 265,
            clockwise: false
        )
        color.setStroke()
        path.stroke()
    }
}
