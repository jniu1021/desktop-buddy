enum PixelPigSprite {
    static let width = 16
    static let height = 13

    static func rows(frameIndex: Int) -> [String] {
        earRows(for: frameIndex) + [
            "0111111111111110",
            "1111111111111111",
            "1111211111121111",
            "1151111111111511",
            "1111133333311111",
            "1111132332311111",
            "1111133333311111",
            "1111111111111111",
            "0111111111111110",
            "0011111111111100"
        ]
    }

    private static func earRows(for frameIndex: Int) -> [String] {
        switch frameIndex % 4 {
        case 1:
            return [
                "0000000000000044",
                "0440000000000444",
                "4444000000004444"
            ]
        case 2:
            return [
                "0000000000000000",
                "4400000000000044",
                "4444000000004444"
            ]
        case 3:
            return [
                "4400000000000000",
                "4440000000000440",
                "4444000000004444"
            ]
        default:
            return [
                "4400000000000044",
                "4440000000000444",
                "4444000000004444"
            ]
        }
    }
}
