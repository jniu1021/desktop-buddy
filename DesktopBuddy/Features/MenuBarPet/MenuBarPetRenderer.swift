import AppKit

enum MenuBarPetRenderer {
    struct OverlayPixel: Equatable {
        let column: Int
        let row: Int
    }

    static func image(
        for severity: DeviceSeverity,
        frameIndex: Int = 0,
        presentation: PetPresentation = .menuIdle
    ) -> NSImage {
        let size = NSSize(width: 20, height: 18)
        let image = NSImage(size: size, flipped: false) { _ in
            drawPig(severity: severity, frameIndex: frameIndex)
            drawSeverityPattern(severity)
            drawPresentationPattern(presentation)
            return true
        }

        image.isTemplate = false
        image.accessibilityDescription = "Desktop Buddy pixel pig"
        return image
    }

    private static func drawPresentationPattern(_ presentation: PetPresentation) {
        let pixels = presentationOverlayPixels(for: presentation)
        let color: NSColor

        switch presentation {
        case .menuIdle:
            color = .labelColor
        case .emerging:
            color = .labelColor
        case .edgeIdle:
            color = .labelColor
        case .retreating:
            color = .labelColor
        case .focusHidden:
            color = .secondaryLabelColor
        case .deviceNotice:
            color = .systemRed
        case .speaking:
            color = .labelColor
        }

        color.setFill()
        pixels.forEach { pixel in
            NSRect(
                x: 2 + pixel.column,
                y: 2 + (PixelPigSprite.height - 1 - pixel.row),
                width: 1,
                height: 1
            ).fill()
        }
    }

    static func presentationOverlayPixels(for presentation: PetPresentation) -> [OverlayPixel] {
        switch presentation {
        case .menuIdle:
            []
        case .emerging:
            [OverlayPixel(column: 1, row: 3)]
        case .edgeIdle:
            [OverlayPixel(column: 1, row: 4), OverlayPixel(column: 14, row: 4)]
        case .retreating:
            [OverlayPixel(column: 14, row: 3)]
        case .focusHidden:
            [OverlayPixel(column: 4, row: 5), OverlayPixel(column: 11, row: 5)]
        case .deviceNotice:
            [OverlayPixel(column: 1, row: 6), OverlayPixel(column: 14, row: 6)]
        case .speaking:
            [OverlayPixel(column: 6, row: 9), OverlayPixel(column: 9, row: 9)]
        }
    }

    private static func drawPig(severity: DeviceSeverity, frameIndex: Int) {
        let rows = PixelPigSprite.rows(frameIndex: frameIndex)
        let originX = 2
        let originY = 2

        for (rowIndex, row) in rows.enumerated() {
            for (columnIndex, pixel) in row.enumerated() where pixel != "0" {
                let x = originX + columnIndex
                let y = originY + (rows.count - 1 - rowIndex)

                if severity == .unavailable, (x + y).isMultiple(of: 2) {
                    continue
                }

                pixelColor(for: pixel, severity: severity).setFill()
                NSRect(x: x, y: y, width: 1, height: 1).fill()
            }
        }
    }

    private static func drawSeverityPattern(_ severity: DeviceSeverity) {
        let pixels: [(Int, Int)]

        switch severity {
        case .normal, .unavailable:
            pixels = []
        case .elevated, .caution:
            pixels = [(18, 12), (18, 11), (18, 9)]
        case .critical:
            pixels = [(18, 13), (18, 12), (18, 11), (18, 8)]
        }

        color(for: severity).setFill()
        pixels.forEach { x, y in
            NSRect(x: x, y: y, width: 1, height: 1).fill()
        }
    }

    private static func pixelColor(for pixel: Character, severity: DeviceSeverity) -> NSColor {
        switch pixel {
        case "2":
            return .labelColor
        case "3":
            let bodyColor = color(for: severity)
            return bodyColor.blended(withFraction: 0.55, of: .white) ?? bodyColor
        case "4":
            let bodyColor = color(for: severity)
            return bodyColor.blended(withFraction: 0.18, of: .black) ?? bodyColor
        case "5":
            let bodyColor = color(for: severity)
            return bodyColor.blended(withFraction: 0.4, of: .white) ?? bodyColor
        default:
            return color(for: severity)
        }
    }

    private static func color(for severity: DeviceSeverity) -> NSColor {
        switch severity {
        case .normal: return .systemGreen
        case .elevated: return .systemOrange
        case .caution: return .systemYellow
        case .critical: return .systemRed
        case .unavailable: return .secondaryLabelColor
        }
    }
}

// The button's spoken status follows the same selected metric as its visual color.
enum MenuBarStatusAccessibility {
    static func label(
        metric: StatusMetric,
        battery: BatteryState,
        memory: MemoryUsageState,
        memoryLevel: MemoryUsageLevel,
        codex: CodexAllowanceState,
        presentation: PetPresentation = .menuIdle
    ) -> String {
        let status: String
        switch metric {
        case .battery:
            if let percent = battery.chargePercent {
                let level = switch battery.condition {
                case .normal: "normal"
                case .low: "low"
                case .critical: "critical"
                case .unavailable: "unavailable"
                }
                if let estimate = battery.estimatedUsageSeconds,
                   let duration = BatteryUsageEstimateFormatter.accessibilityString(seconds: estimate) {
                    status = "Battery estimated usage left " + duration + ", " + String(percent) + " percent, " + level
                } else {
                    status = "Battery " + String(percent) + " percent, " + level
                }
            } else {
                status = "Battery unavailable"
            }
        case .memoryUsage:
            status = memory.isAvailable
                ? "Memory " + String(memory.usagePercent) + " percent used, " + memoryLevel.displayName.lowercased()
                : "Memory unavailable"
        case .codexAllowance:
            if let primary = codex.primary, codex.availability == .available {
                let level = switch codex.condition {
                case .normal: "normal"
                case .low: "low remaining"
                case .exhausted: "critical remaining"
                case .unavailable: "unavailable"
                }
                status = "Codex " + primary.label + " allowance " + String(primary.remainingPercent) + " percent left, " + level
            } else {
                status = "Codex allowance unavailable"
            }
        }
        return "Desktop Buddy. " + status + ". " + presentation.accessibilityName + "."
    }
}
