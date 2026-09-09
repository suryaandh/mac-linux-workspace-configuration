import Cocoa

// MARK: - Custom Slider Cell

class TallSliderCell: NSSliderCell {
    private let trackHeight: CGFloat = 14
    private let knobSize: CGFloat = 22
    private let knobShadowRadius: CGFloat = 3.5
    private let knobShadowOffset = NSSize(width: 0, height: -1.5)

    override func barRect(flipped: Bool) -> NSRect {
        guard let control = controlView else {
            return super.barRect(flipped: flipped)
        }
        let bounds = control.bounds
        let inset = knobSize / 2
        return NSRect(
            x: inset,
            y: (bounds.height - trackHeight) / 2,
            width: bounds.width - inset * 2,
            height: trackHeight
        )
    }

    override func drawBar(inside rect: NSRect, flipped: Bool) {
        let r = trackHeight / 2
        let path = NSBezierPath(roundedRect: rect, xRadius: r, yRadius: r)

        NSColor.white.withAlphaComponent(0.18).setFill()
        path.fill()

        let pct = CGFloat((doubleValue - minValue) / (maxValue - minValue))
        let fillWidth = rect.width * pct
        if fillWidth > 0 {
            let filled = NSRect(x: rect.minX, y: rect.minY, width: fillWidth, height: rect.height)
            let filledPath = NSBezierPath(roundedRect: filled, xRadius: r, yRadius: r)
            NSColor.white.setFill()
            filledPath.fill()
        }
    }

    override func drawKnob(_ knobRect: NSRect) {
        let bar = barRect(flipped: false)
        let pct = CGFloat((doubleValue - minValue) / (maxValue - minValue))
        let centerX = bar.minX + pct * bar.width
        let centerY = bar.midY

        let knob = NSRect(
            x: centerX - knobSize / 2,
            y: centerY - knobSize / 2,
            width: knobSize,
            height: knobSize
        )

        let shadow = NSShadow()
        shadow.shadowColor = NSColor.black.withAlphaComponent(0.32)
        shadow.shadowBlurRadius = knobShadowRadius
        shadow.shadowOffset = knobShadowOffset
        shadow.set()

        let pill = NSBezierPath(ovalIn: knob)
        NSColor.white.setFill()
        pill.fill()

        NSColor.black.withAlphaComponent(0.1).setStroke()
        pill.lineWidth = 0.5
        pill.stroke()

        NSShadow().set()
    }

    override func knobRect(flipped: Bool) -> NSRect {
        let bar = barRect(flipped: flipped)
        let pct = CGFloat((doubleValue - minValue) / (maxValue - minValue))
        let centerX = bar.minX + pct * bar.width
        return NSRect(
            x: centerX - knobSize / 2,
            y: bar.midY - knobSize / 2,
            width: knobSize,
            height: knobSize
        )
    }

    override var controlSize: NSControl.ControlSize {
        get { .regular }
        set {}
    }
}

class BrightnessViewController: NSViewController {

    private var internalSlider: NSSlider!
    private var internalLabel: NSTextField!
    private var externalStackView: NSStackView!
    private var externalSliders: [(slider: NSSlider, label: NSTextField, displayID: CGDirectDisplayID)] = []

    override func loadView() {
        let vev = NSVisualEffectView(frame: NSRect(x: 0, y: 0, width: 260, height: 160))
        vev.material = .hudWindow
        vev.blendingMode = .behindWindow
        vev.state = .active
        view = vev
    }

    override func viewDidLoad() {
        super.viewDidLoad()
        buildUI()
    }

    override func viewWillAppear() {
        super.viewWillAppear()
        refreshValues()
    }

    // MARK: - UI Construction

    private func buildUI() {
        let container = NSStackView()
        container.orientation = .vertical
        container.spacing = 10
        container.alignment = .leading
        container.distribution = .fill
        container.edgeInsets = NSEdgeInsets(top: 14, left: 14, bottom: 52, right: 14)
        container.translatesAutoresizingMaskIntoConstraints = false
        view.addSubview(container)
        NSLayoutConstraint.activate([
            container.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            container.trailingAnchor.constraint(equalTo: view.trailingAnchor),
            container.topAnchor.constraint(equalTo: view.topAnchor),
            container.bottomAnchor.constraint(equalTo: view.bottomAnchor),
        ])

        // Internal display row
        let internalName: String
        if let id = BrightnessController.internalDisplayID() {
            let name = BrightnessController.displayName(for: id)
            internalName = name.isEmpty ? "Built-in Display" : name
        } else {
            internalName = "Built-in Display"
        }
        let internalRow = makeRow(labelText: internalName)
        internalSlider = internalRow.slider
        internalLabel = internalRow.valueLabel
        internalSlider.action = #selector(internalSliderChanged)
        internalSlider.target = self
        container.addArrangedSubview(internalRow.stack)

        internalRow.stack.widthAnchor.constraint(equalTo: view.widthAnchor, constant: -28).isActive = true

        // Separator
        let sep = NSView()
        sep.wantsLayer = true
        sep.layer?.backgroundColor = NSColor.white.withAlphaComponent(0.15).cgColor
        sep.translatesAutoresizingMaskIntoConstraints = false
        sep.heightAnchor.constraint(equalToConstant: 1).isActive = true
        container.addArrangedSubview(sep)
        sep.widthAnchor.constraint(equalTo: view.widthAnchor, constant: -28).isActive = true

        // External displays
        externalStackView = NSStackView()
        externalStackView.orientation = .vertical
        externalStackView.spacing = 8
        externalStackView.alignment = .leading
        externalStackView.distribution = .fill
        container.addArrangedSubview(externalStackView)
        externalStackView.widthAnchor.constraint(equalTo: view.widthAnchor, constant: -28).isActive = true

        buildExternalRows()

        // Glassmorphism quit button anchored to bottom-right
        let glassQuit = NSVisualEffectView()
        glassQuit.material = .hudWindow
        glassQuit.blendingMode = .withinWindow
        glassQuit.state = .active
        glassQuit.wantsLayer = true
        glassQuit.layer?.cornerRadius = 10
        glassQuit.layer?.masksToBounds = true
        glassQuit.layer?.borderColor = NSColor.white.withAlphaComponent(0.25).cgColor
        glassQuit.layer?.borderWidth = 0.5
        glassQuit.translatesAutoresizingMaskIntoConstraints = false

        let quitButton = NSButton(frame: .zero)
        quitButton.bezelStyle = .inline
        quitButton.isBordered = false
        quitButton.attributedTitle = NSAttributedString(string: "Quit", attributes: [
            .font: NSFont.systemFont(ofSize: 12),
            .foregroundColor: NSColor.white.withAlphaComponent(0.80),
        ])
        quitButton.target = self
        quitButton.action = #selector(quitApp)
        quitButton.translatesAutoresizingMaskIntoConstraints = false

        glassQuit.addSubview(quitButton)
        view.addSubview(glassQuit)

        NSLayoutConstraint.activate([
            glassQuit.trailingAnchor.constraint(equalTo: view.trailingAnchor, constant: -14),
            glassQuit.bottomAnchor.constraint(equalTo: view.bottomAnchor, constant: -12),
            quitButton.leadingAnchor.constraint(equalTo: glassQuit.leadingAnchor, constant: 10),
            quitButton.trailingAnchor.constraint(equalTo: glassQuit.trailingAnchor, constant: -10),
            quitButton.topAnchor.constraint(equalTo: glassQuit.topAnchor, constant: 4),
            quitButton.bottomAnchor.constraint(equalTo: glassQuit.bottomAnchor, constant: -4),
        ])
    }

    private func buildExternalRows() {
        externalStackView.arrangedSubviews.forEach { $0.removeFromSuperview() }
        externalSliders.removeAll()

        let ids = BrightnessController.externalDisplayIDs()
        if ids.isEmpty {
            let placeholder = makeLabel("No external display detected", size: 11, color: NSColor.white.withAlphaComponent(0.45))
            externalStackView.addArrangedSubview(placeholder)
            placeholder.widthAnchor.constraint(equalTo: externalStackView.widthAnchor).isActive = true
        } else {
            for (i, id) in ids.enumerated() {
                let name = BrightnessController.displayName(for: id)
                let row = makeRow(labelText: name.isEmpty ? "Display \(i + 1)" : name)
                row.slider.action = #selector(externalSliderChanged)
                row.slider.target = self
                row.slider.tag = i
                externalSliders.append((slider: row.slider, label: row.valueLabel, displayID: id))
                externalStackView.addArrangedSubview(row.stack)

                // Full width
                row.stack.widthAnchor.constraint(equalTo: externalStackView.widthAnchor).isActive = true
                row.slider.widthAnchor.constraint(equalTo: externalStackView.widthAnchor).isActive = true
            }
        }

        let topPadding: CGFloat = 28
        let rowHeight: CGFloat = 60
        let sepHeight: CGFloat = 16
        let externalCount = CGFloat(max(1, ids.count))
        let newHeight = topPadding + rowHeight + sepHeight + externalCount * rowHeight + 28
        view.window?.setContentSize(NSSize(width: 260, height: newHeight))
        preferredContentSize = NSSize(width: 260, height: newHeight)
    }

    // MARK: - Value Refresh

    private func refreshValues() {
        NSLog("DEBUG: refreshValues called")
        let internal_ = BrightnessController.getInternalBrightness()
        NSLog("DEBUG: internal brightness = \(internal_)")
        internalSlider.floatValue = internal_
        internalLabel.stringValue = "\(Int(internal_ * 100))%"

        for entry in externalSliders {
            let v = BrightnessController.getExternalBrightness(displayID: entry.displayID)
            let safe = v < 0 ? 0 : v
            entry.slider.floatValue = safe
            entry.label.stringValue = "\(Int(safe * 100))%"
        }
    }

    // MARK: - Actions

    @objc private func quitApp() {
        NSApplication.shared.terminate(nil)
    }

    @objc private func internalSliderChanged(_ sender: NSSlider) {
        NSLog("DEBUG: internalSliderChanged value=\(sender.floatValue)")
        BrightnessController.setInternalBrightness(sender.floatValue)
        internalLabel.stringValue = "\(Int(sender.floatValue * 100))%"
    }

    @objc private func externalSliderChanged(_ sender: NSSlider) {
        guard sender.tag < externalSliders.count else { return }
        let entry = externalSliders[sender.tag]
        let value = sender.floatValue
        entry.label.stringValue = "\(Int(value * 100))%"
        BrightnessController.updateExternalBrightnessCache(displayID: entry.displayID, value: value)
        BrightnessController.setExternalBrightness(displayID: entry.displayID, value: value)
    }

    // MARK: - Helpers

    private typealias SliderRow = (stack: NSStackView, slider: NSSlider, valueLabel: NSTextField)

    private func makeRow(labelText: String) -> SliderRow {
        let row = NSStackView()
        row.orientation = .vertical
        row.spacing = 4
        row.alignment = .leading
        row.distribution = .fill

        let header = NSView()
        header.translatesAutoresizingMaskIntoConstraints = false

        let title = makeLabel(labelText, size: 12, color: NSColor.white.withAlphaComponent(0.90))
        let valueLabel = makeLabel("50%", size: 11, color: NSColor.white.withAlphaComponent(0.55))
        valueLabel.alignment = .right

        header.addSubview(title)
        header.addSubview(valueLabel)

        NSLayoutConstraint.activate([
            title.leadingAnchor.constraint(equalTo: header.leadingAnchor),
            title.centerYAnchor.constraint(equalTo: header.centerYAnchor),
            valueLabel.trailingAnchor.constraint(equalTo: header.trailingAnchor),
            valueLabel.centerYAnchor.constraint(equalTo: header.centerYAnchor),
            // title tidak boleh overlap valueLabel
            title.trailingAnchor.constraint(lessThanOrEqualTo: valueLabel.leadingAnchor, constant: -8),
            header.heightAnchor.constraint(equalToConstant: 16),
        ])

        let slider = NSSlider(value: 0.5, minValue: 0, maxValue: 1, target: nil, action: nil)
        slider.sliderType = .linear
        slider.isContinuous = true
        slider.cell = TallSliderCell()
        slider.wantsLayer = true

        row.addArrangedSubview(header)
        row.addArrangedSubview(slider)

        NSLayoutConstraint.activate([
            header.widthAnchor.constraint(equalTo: row.widthAnchor),
            slider.widthAnchor.constraint(equalTo: row.widthAnchor),
            slider.heightAnchor.constraint(equalToConstant: 28),
        ])

        return (row, slider, valueLabel)
    }

    private func makeLabel(_ text: String, size: CGFloat, color: NSColor) -> NSTextField {
        let label = NSTextField(labelWithString: text)
        label.font = NSFont.systemFont(ofSize: size)
        label.textColor = color
        label.translatesAutoresizingMaskIntoConstraints = false
        return label
    }
}