import SwiftUI

/// LCD text drawn as a dot matrix (7 rows of dots per character, like the date on G-Shock 5000/5600
/// displays). The dots are drawn as shapes, so no font is needed. `.` and `-` are narrow.
struct DotMatrixText: View {
    let text: String
    /// Distance between dot columns and rows.
    let pitch: CGSize
    /// Size of one dot.
    let dot: CGSize
    /// Advance of a full-width character and of a narrow one (`.`, `-`).
    let advance: CGFloat
    let narrowAdvance: CGFloat
    let color: Color
    var glyphs: Glyphs = .round5x7
    /// Italic lean: each row up moves right by this fraction of the row pitch.
    var slant: CGFloat = 0

    /// The character shapes: rounded 5×7 digits (GMW-B5000) or bold square ones with two-dot strokes
    /// (GW-B5600).
    enum Glyphs {
        case round5x7, bold5x7

        /// The character's dots, 7 rows (`#` = dot); a blank for unknown characters.
        func glyph(_ character: Character) -> [String] {
            switch self {
            case .round5x7: DotMatrixText.round[character] ?? Array(repeating: ".....", count: 7)
            case .bold5x7: DotMatrixText.bold[character] ?? Array(repeating: ".....", count: 7)
            }
        }
    }

    var body: some View {
        DotShape(
            text: text, pitch: pitch, dot: dot, advance: advance, narrowAdvance: narrowAdvance, glyphs: glyphs,
            slant: slant
        )
        .fill(color)
    }

    static let narrow: Set<Character> = [".", "-"]

    static func glyph(_ character: Character) -> [String] { Glyphs.round5x7.glyph(character) }

    private static let bold: [Character: [String]] = [
        "0": ["#####", "##.##", "##.##", "##.##", "##.##", "##.##", "#####"],
        "1": ["...##", "...##", "...##", "...##", "...##", "...##", "...##"],
        "2": ["#####", "...##", "...##", "#####", "##...", "##...", "#####"],
        "3": ["#####", "...##", "...##", "#####", "...##", "...##", "#####"],
        "4": ["##.##", "##.##", "##.##", "#####", "...##", "...##", "...##"],
        "5": ["#####", "##...", "##...", "#####", "...##", "...##", "#####"],
        "6": ["#####", "##...", "##...", "#####", "##.##", "##.##", "#####"],
        "7": ["#####", "...##", "...##", "...##", "...##", "...##", "...##"],
        "8": ["#####", "##.##", "##.##", "#####", "##.##", "##.##", "#####"],
        "9": ["#####", "##.##", "##.##", "#####", "...##", "...##", "#####"],
        ".": [".....", ".....", ".....", ".....", ".....", ".....", "#...."],
        "-": [".....", ".....", ".....", "#####", ".....", ".....", "....."],
    ]

    private static let round: [Character: [String]] = [
        "0": [".###.", "#...#", "#..##", "#.#.#", "##..#", "#...#", ".###."],
        "1": ["..#..", ".##..", "..#..", "..#..", "..#..", "..#..", ".###."],
        "2": [".###.", "#...#", "....#", "...#.", "..#..", ".#...", "#####"],
        "3": ["#####", "...#.", "..#..", "...#.", "....#", "#...#", ".###."],
        "4": ["...#.", "..##.", ".#.#.", "#..#.", "#####", "...#.", "...#."],
        "5": ["#####", "#....", "####.", "....#", "....#", "#...#", ".###."],
        "6": ["..##.", ".#...", "#....", "####.", "#...#", "#...#", ".###."],
        "7": ["#####", "....#", "...#.", "..#..", ".#...", ".#...", ".#..."],
        "8": [".###.", "#...#", "#...#", ".###.", "#...#", "#...#", ".###."],
        "9": [".###.", "#...#", "#...#", ".####", "....#", "...#.", ".##.."],
        ".": [".....", ".....", ".....", ".....", ".....", ".....", "#...."],
        "-": [".....", ".....", ".....", "###..", ".....", ".....", "....."],
    ]
}

private struct DotShape: Shape {
    let text: String
    let pitch: CGSize
    let dot: CGSize
    let advance: CGFloat
    let narrowAdvance: CGFloat
    let glyphs: DotMatrixText.Glyphs
    let slant: CGFloat

    func path(in rect: CGRect) -> Path {
        var path = Path()
        var x = rect.minX
        for character in text {
            for (row, line) in glyphs.glyph(character).enumerated() {
                for (col, bit) in line.enumerated() where bit == "#" {
                    path.addRect(
                        CGRect(
                            x: x + CGFloat(col) * pitch.width + slant * CGFloat(6 - row) * pitch.height,
                            y: rect.minY + CGFloat(row) * pitch.height,
                            width: dot.width, height: dot.height))
                }
            }
            x += DotMatrixText.narrow.contains(character) ? narrowAdvance : advance
        }
        return path
    }
}
