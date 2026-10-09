import SwiftUI

/// LCD text drawn as a dot matrix (5×7 dots per character, like the date on G-Shock 5000/5600
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

    var body: some View {
        DotShape(text: text, pitch: pitch, dot: dot, advance: advance, narrowAdvance: narrowAdvance)
            .fill(color)
    }

    static let narrow: Set<Character> = [".", "-"]

    /// The character's dots, 7 rows of 5 (`#` = dot); a blank for unknown characters.
    static func glyph(_ character: Character) -> [String] {
        glyphs[character] ?? Array(repeating: ".....", count: 7)
    }

    private static let glyphs: [Character: [String]] = [
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

    func path(in rect: CGRect) -> Path {
        var path = Path()
        var x = rect.minX
        for character in text {
            for (row, line) in DotMatrixText.glyph(character).enumerated() {
                for (col, bit) in line.enumerated() where bit == "#" {
                    path.addRect(
                        CGRect(
                            x: x + CGFloat(col) * pitch.width, y: rect.minY + CGFloat(row) * pitch.height,
                            width: dot.width, height: dot.height))
                }
            }
            x += DotMatrixText.narrow.contains(character) ? narrowAdvance : advance
        }
        return path
    }
}
