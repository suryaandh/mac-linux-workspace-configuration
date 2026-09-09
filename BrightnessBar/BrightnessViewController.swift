import Cocoa

class BrightnessViewController: NSViewController {

    private var internalSlider: NSSlider!
    private var internalLabel: NSTextField!
    private var externalStackView: NSStackView!
    private var externalSliders: [(slider: NSSlider, label: NSTextField, displayID: CGDirectDisplayID)] = []

    // Debounce timers: one per external display, keyed by displayID.
    // DDC writes fire only after 300ms of slider inactivity to avoid flooding the monitor MCU.
    private var ddcDebounceTimers: [CGDirectDisplayID: Timer] = [:]

    override func loadView() {
        view = NSView(frame: NSRect(x: 0, y: 0, width: 260, height: 160))
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
        container.edgeInsets = NSEdgeInsets(top: 14, left: 16, bottom: 14, right: 16)
        container.translatesAutoresizingMaskIntoConstraints = false
        view.addSubview(container)
        NSLayoutConstraint.activate([
            container.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            container.trailingAnchor.constraint(equalTo: view.trailingAnchor),
            container.topAnchor.constraint(equalTo: view.topAnchor),
            container.bottomAnchor.constraint(equalTo: view.bottomAnchor),
        ])

        // Internal display row
        let internalRow = makeRow(labelText: "Internal Display")
        internalSlider = internalRow.slider
        internalLabel = internalRow.valueLabel
        internalSlider.action = #selector(internalSliderChanged)
        internalSlider.target = self
        container.addArrangedSubview(internalRow.stack)

        // Separator
        let sep = NSBox()
        sep.boxType = .separator
        container.addArrangedSubview(sep)

        // External displays
        externalStackView = NSStackView()
        externalStackView.orientation = .vertical
        externalStackView.spacing = 8
        container.addArrangedSubview(externalStackView)

        buildExternalRows()
    }

    private func buildExternalRows() {
        externalStackView.arrangedSubviews.forEach { $0.removeFromSuperview() }
        externalSliders.removeAll()

        let ids = BrightnessController.externalDisplayIDs()
        if ids.isEmpty {
            let placeholder = makeLabel("No external display detected", size: 11, color: .secondaryLabelColor)
            externalStackView.addArrangedSubview(placeholder)
        } else {
            for (i, id) in ids.enumerated() {
                let name = BrightnessController.displayName(for: id)
                let row = makeRow(labelText: name.isEmpty ? "Display \(i + 1)" : name)
                row.slider.action = #selector(externalSliderChanged)
                row.slider.target = self
                row.slider.tag = i
                externalSliders.append((slider: row.slider, label: row.valueLabel, displayID: id))
                externalStackView.addArrangedSubview(row.stack)
            }
        }

        // Resize popover height dynamically
        let baseHeight: CGFloat = 100
        let rowHeight: CGFloat = 36
        let count = CGFloat(max(1, ids.count))
        let newHeight = baseHeight + count * rowHeight
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
        // Update cache immediately so the label stays responsive during drag.
        BrightnessController.updateExternalBrightnessCache(displayID: entry.displayID, value: value)

        // Debounce: cancel any pending DDC write for this display and reschedule.
        // This ensures only ONE write fires per drag (300ms after finger lifts),
        // preventing the monitor MCU from wedging due to DDC flooding.
        ddcDebounceTimers[entry.displayID]?.invalidate()
        ddcDebounceTimers[entry.displayID] = Timer.scheduledTimer(withTimeInterval: 0.3, repeats: false) { [weak self] _ in
            guard self != nil else { return }
            BrightnessController.bbLogPublic("ddc debounce fired displayID=\(entry.displayID) value=\(value)")
            BrightnessController.setExternalBrightness(displayID: entry.displayID, value: value)
        }
    }

    // MARK: - Helpers

    private typealias SliderRow = (stack: NSStackView, slider: NSSlider, valueLabel: NSTextField)

    private func makeRow(labelText: String) -> SliderRow {
        let row = NSStackView()
        row.orientation = .horizontal
        row.spacing = 8

        let title = makeLabel(labelText, size: 12, color: .labelColor)
        title.setContentHuggingPriority(.defaultHigh, for: .horizontal)

        let slider = NSSlider(value: 0.5, minValue: 0, maxValue: 1, target: nil, action: nil)
        slider.sliderType = .linear
        slider.isContinuous = true
        slider.setContentCompressionResistancePriority(.defaultLow, for: .horizontal)

        let valueLabel = makeLabel("50%", size: 11, color: .secondaryLabelColor)
        valueLabel.alignment = .right
        valueLabel.setContentHuggingPriority(.defaultHigh, for: .horizontal)

        row.addArrangedSubview(title)
        row.addArrangedSubview(slider)
        row.addArrangedSubview(valueLabel)

        NSLayoutConstraint.activate([
            title.widthAnchor.constraint(equalToConstant: 90),
            valueLabel.widthAnchor.constraint(equalToConstant: 34),
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
