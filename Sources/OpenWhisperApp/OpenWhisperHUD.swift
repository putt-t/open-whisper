import AppKit

@MainActor
final class OpenWhisperHUD {
    private let panel: NSPanel
    private let indicator = PulseIndicatorView(frame: NSRect(x: 0, y: 0, width: 18, height: 18))

    init() {
        panel = NSPanel(
            contentRect: NSRect(x: 0, y: 0, width: 72, height: 56),
            styleMask: [.borderless, .nonactivatingPanel],
            backing: .buffered,
            defer: false
        )
        panel.level = .statusBar
        panel.backgroundColor = .clear
        panel.isOpaque = false
        panel.hasShadow = true
        panel.ignoresMouseEvents = true
        panel.hidesOnDeactivate = false
        panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .ignoresCycle]

        let effect = NSVisualEffectView(frame: panel.contentView?.bounds ?? .zero)
        effect.autoresizingMask = [.width, .height]
        effect.material = .popover
        effect.blendingMode = .withinWindow
        effect.state = .active
        effect.wantsLayer = true
        effect.layer?.cornerRadius = 14
        effect.layer?.masksToBounds = true

        indicator.translatesAutoresizingMaskIntoConstraints = false
        effect.addSubview(indicator)
        NSLayoutConstraint.activate([
            indicator.centerXAnchor.constraint(equalTo: effect.centerXAnchor),
            indicator.centerYAnchor.constraint(equalTo: effect.centerYAnchor),
            indicator.widthAnchor.constraint(equalToConstant: 18),
            indicator.heightAnchor.constraint(equalToConstant: 18),
        ])
        panel.contentView = effect
    }

    func update(state: OpenWhisperController.State) {
        switch state {
        case .idle:
            hide()
        case .recording:
            showRecording()
        case .transcribing:
            showTranscribing()
        case .error:
            show()
            indicator.setErrorStyle()
            DispatchQueue.main.asyncAfter(deadline: .now() + 1.0) { [weak self] in
                self?.hide()
            }
        }
    }

    private func show() {
        positionTopCenter()
        panel.orderFrontRegardless()
    }

    private func showRecording() {
        show()
        indicator.setRecordingStyle()
    }

    private func showTranscribing() {
        show()
        indicator.setTranscribingStyle()
    }

    private func hide() {
        indicator.stopAnimating()
        panel.orderOut(nil)
    }

    private func positionTopCenter() {
        guard let screen = NSScreen.main else { return }
        let visible = screen.visibleFrame
        let panelSize = panel.frame.size
        let x = visible.midX - (panelSize.width / 2.0)
        let y = visible.maxY - panelSize.height - 26
        panel.setFrameOrigin(NSPoint(x: x, y: y))
    }
}

private final class PulseIndicatorView: NSView {
    private let dotLayer = CALayer()
    private let ringLayer = CAShapeLayer()
    private var pulseAnimation: CAAnimationGroup?

    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        wantsLayer = true
        layer?.masksToBounds = false
        setupLayers()
    }

    required init?(coder: NSCoder) {
        nil
    }

    override func layout() {
        super.layout()
        updateLayerFrames()
    }

    func setRecordingStyle() {
        let color = NSColor.systemRed
        dotLayer.backgroundColor = color.cgColor
        ringLayer.strokeColor = color.withAlphaComponent(0.65).cgColor
        startAnimating()
    }

    func setTranscribingStyle() {
        let color = NSColor.systemBlue
        dotLayer.backgroundColor = color.cgColor
        ringLayer.strokeColor = color.withAlphaComponent(0.45).cgColor
        startAnimating()
    }

    func setErrorStyle() {
        let color = NSColor.systemOrange
        dotLayer.backgroundColor = color.cgColor
        ringLayer.strokeColor = color.withAlphaComponent(0.7).cgColor
        startAnimating()
    }

    func stopAnimating() {
        ringLayer.removeAllAnimations()
    }

    private func setupLayers() {
        dotLayer.cornerRadius = 9
        layer?.addSublayer(ringLayer)
        layer?.addSublayer(dotLayer)

        ringLayer.fillColor = NSColor.clear.cgColor
        ringLayer.lineWidth = 2.0
        ringLayer.opacity = 0

        updateLayerFrames()
    }

    private func updateLayerFrames() {
        dotLayer.frame = bounds

        let inset: CGFloat = -2
        let ringRect = bounds.insetBy(dx: inset, dy: inset)
        ringLayer.frame = bounds
        ringLayer.path = CGPath(ellipseIn: ringRect, transform: nil)
    }

    private func startAnimating() {
        guard ringLayer.animation(forKey: "pulse") == nil else { return }

        let scale = CABasicAnimation(keyPath: "transform.scale")
        scale.fromValue = 0.95
        scale.toValue = 1.75

        let opacity = CABasicAnimation(keyPath: "opacity")
        opacity.fromValue = 0.85
        opacity.toValue = 0.0

        let group = CAAnimationGroup()
        group.animations = [scale, opacity]
        group.duration = 0.95
        group.repeatCount = .infinity
        group.timingFunction = CAMediaTimingFunction(name: .easeOut)
        ringLayer.add(group, forKey: "pulse")
        pulseAnimation = group
    }
}
