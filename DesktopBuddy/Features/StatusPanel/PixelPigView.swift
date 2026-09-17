import SwiftUI

enum PixelPigPalette: Equatable {
    case status
    case desktop
}

enum PixelPigCanvasLayout {
    static func size(pixelSize: CGFloat, pixelSpacing: CGFloat) -> CGSize {
        CGSize(
            width: CGFloat(PixelPigSprite.width) * pixelSize
                + CGFloat(PixelPigSprite.width - 1) * pixelSpacing,
            height: CGFloat(PixelPigSprite.height) * pixelSize
                + CGFloat(PixelPigSprite.height - 1) * pixelSpacing
        )
    }
}

struct PixelPigView: View {
    let severity: DeviceSeverity
    let frameIndex: Int
    let pixelSize: CGFloat
    let pixelSpacing: CGFloat
    let palette: PixelPigPalette

    init(
        severity: DeviceSeverity,
        frameIndex: Int = 0,
        pixelSize: CGFloat = 7,
        pixelSpacing: CGFloat = 2,
        palette: PixelPigPalette = .status
    ) {
        self.severity = severity
        self.frameIndex = frameIndex
        self.pixelSize = pixelSize
        self.pixelSpacing = pixelSpacing
        self.palette = palette
    }

    var body: some View {
        let size = PixelPigCanvasLayout.size(
            pixelSize: pixelSize,
            pixelSpacing: pixelSpacing
        )

        Canvas { context, _ in
            var paths: [Character: Path] = [:]
            let stride = pixelSize + pixelSpacing
            for (rowIndex, row) in PixelPigSprite.rows(frameIndex: frameIndex).enumerated() {
                for (columnIndex, pixel) in row.enumerated() where pixel != "0" {
                    let rectangle = CGRect(
                        x: CGFloat(columnIndex) * stride,
                        y: CGFloat(rowIndex) * stride,
                        width: pixelSize,
                        height: pixelSize
                    )
                    paths[pixel, default: Path()].addRect(rectangle)
                }
            }

            for pixel: Character in ["1", "2", "3", "4", "5"] {
                guard let path = paths[pixel] else { continue }
                context.fill(path, with: .color(color(for: pixel)))
            }
        }
        .frame(width: size.width, height: size.height)
        .accessibilityElement()
        .accessibilityLabel("Pixel pig")
    }

    private func color(for pixel: Character) -> Color {
        if palette == .desktop {
            switch pixel {
            case "1": return Color(red: 0.96, green: 0.48, blue: 0.62)
            case "2": return Color(red: 0.22, green: 0.12, blue: 0.15)
            case "3": return Color(red: 1, green: 0.72, blue: 0.76)
            case "4": return Color(red: 0.86, green: 0.31, blue: 0.48)
            case "5": return Color(red: 1, green: 0.80, blue: 0.49)
            default: return .clear
            }
        }

        switch pixel {
        case "1": return pigColor
        case "2": return .primary.opacity(0.72)
        case "3": return pigColor.opacity(0.45)
        case "4": return pigColor.opacity(0.78)
        case "5": return pigColor.opacity(0.55)
        default: return .clear
        }
    }

    private var pigColor: Color {
        switch severity {
        case .normal: return .green
        case .elevated: return .orange
        case .caution: return .yellow
        case .critical: return .red
        case .unavailable: return .secondary
        }
    }
}
