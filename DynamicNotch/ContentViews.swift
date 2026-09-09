import Cocoa

// MARK: - Music Content View

class MusicContentView: NSView {

    private let artworkView = NSImageView()
    private let titleLabel = NSTextField(labelWithString: "")
    private let artistLabel = NSTextField(labelWithString: "")

    override init(frame: NSRect) {
        super.init(frame: frame)
        setup()
    }

    required init?(coder: NSCoder) {
        super.init(coder: coder)
        setup()
    }

    private func setup() {
        artworkView.wantsLayer = true
        artworkView.layer?.cornerRadius = 6
        artworkView.layer?.masksToBounds = true
        artworkView.imageScaling = .scaleAxesIndependently
        addSubview(artworkView)

        titleLabel.textColor = .white
        titleLabel.font = .systemFont(ofSize: 12, weight: .semibold)
        titleLabel.lineBreakMode = .byTruncatingTail
        addSubview(titleLabel)

        artistLabel.textColor = NSColor.white.withAlphaComponent(0.65)
        artistLabel.font = .systemFont(ofSize: 11, weight: .regular)
        artistLabel.lineBreakMode = .byTruncatingTail
        addSubview(artistLabel)
    }

    override func layout() {
        super.layout()
        let padding: CGFloat = 10
        let artSize: CGFloat = bounds.height - padding * 2
        artworkView.frame = NSRect(x: padding, y: padding, width: artSize, height: artSize)

        let textX = artworkView.frame.maxX + 8
        let textW = bounds.width - textX - padding
        titleLabel.frame = NSRect(x: textX, y: bounds.midY + 2, width: textW, height: 16)
        artistLabel.frame = NSRect(x: textX, y: bounds.midY - 16, width: textW, height: 14)
    }

    func configure(title: String, artist: String, artwork: NSImage?) {
        titleLabel.stringValue = title
        artistLabel.stringValue = artist
        artworkView.image = artwork ?? NSImage(systemSymbolName: "music.note", accessibilityDescription: nil)
        needsLayout = true
    }
}

// MARK: - Notification Content View

class NotificationContentView: NSView {

    private let iconView = NSImageView()
    private let appNameLabel = NSTextField(labelWithString: "")
    private let messageLabel = NSTextField(labelWithString: "")

    override init(frame: NSRect) {
        super.init(frame: frame)
        setup()
    }

    required init?(coder: NSCoder) {
        super.init(coder: coder)
        setup()
    }

    private func setup() {
        iconView.wantsLayer = true
        iconView.layer?.cornerRadius = 8
        iconView.layer?.masksToBounds = true
        iconView.imageScaling = .scaleAxesIndependently
        addSubview(iconView)

        appNameLabel.textColor = NSColor.white.withAlphaComponent(0.65)
        appNameLabel.font = .systemFont(ofSize: 10, weight: .medium)
        appNameLabel.lineBreakMode = .byTruncatingTail
        addSubview(appNameLabel)

        messageLabel.textColor = .white
        messageLabel.font = .systemFont(ofSize: 12, weight: .regular)
        messageLabel.lineBreakMode = .byTruncatingTail
        addSubview(messageLabel)
    }

    override func layout() {
        super.layout()
        let padding: CGFloat = 10
        let iconSize: CGFloat = bounds.height - padding * 2
        iconView.frame = NSRect(x: padding, y: padding, width: iconSize, height: iconSize)

        let textX = iconView.frame.maxX + 8
        let textW = bounds.width - textX - padding
        appNameLabel.frame = NSRect(x: textX, y: bounds.midY + 2, width: textW, height: 13)
        messageLabel.frame = NSRect(x: textX, y: bounds.midY - 15, width: textW, height: 16)
    }

    func configure(appName: String, message: String, icon: NSImage?) {
        appNameLabel.stringValue = appName.uppercased()
        messageLabel.stringValue = message
        iconView.image = icon ?? NSImage(systemSymbolName: "app.badge", accessibilityDescription: nil)
        needsLayout = true
    }
}

// MARK: - Brightness Content View

class BrightnessContentView: NSView {

    private let sunIcon = NSTextField(labelWithString: "☀︎")
    private let slider = NSSlider(value: 0.5, minValue: 0, maxValue: 1, target: nil, action: nil)
    private let percentLabel = NSTextField(labelWithString: "50%")

    override init(frame: NSRect) {
        super.init(frame: frame)
        setup()
    }

    required init?(coder: NSCoder) {
        super.init(coder: coder)
        setup()
    }

    private func setup() {
        sunIcon.textColor = .white
        sunIcon.font = .systemFont(ofSize: 16)
        addSubview(sunIcon)

        slider.isContinuous = true
        slider.target = self
        slider.action = #selector(sliderChanged)
        // White tint for dark notch background
        slider.appearance = NSAppearance(named: .darkAqua)
        addSubview(slider)

        percentLabel.textColor = NSColor.white.withAlphaComponent(0.7)
        percentLabel.font = .systemFont(ofSize: 11)
        percentLabel.alignment = .right
        addSubview(percentLabel)
    }

    override func layout() {
        super.layout()
        let pad: CGFloat = 12
        let h = bounds.height
        sunIcon.frame = NSRect(x: pad, y: (h - 20) / 2, width: 20, height: 20)
        percentLabel.frame = NSRect(x: bounds.width - 40 - pad, y: (h - 14) / 2, width: 40, height: 14)
        let sliderX = sunIcon.frame.maxX + 6
        let sliderW = percentLabel.frame.minX - sliderX - 4
        slider.frame = NSRect(x: sliderX, y: (h - 20) / 2, width: sliderW, height: 20)
    }

    func refresh() {
        let v = BrightnessController.getInternalBrightness()
        slider.floatValue = v
        percentLabel.stringValue = "\(Int(v * 100))%"
        needsLayout = true
    }

    @objc private func sliderChanged(_ sender: NSSlider) {
        BrightnessController.setInternalBrightness(sender.floatValue)
        percentLabel.stringValue = "\(Int(sender.floatValue * 100))%"
    }
}
