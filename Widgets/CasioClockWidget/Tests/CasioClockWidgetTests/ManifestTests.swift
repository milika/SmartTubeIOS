import Foundation
import Testing

@testable import CasioClockWidget

/// The reference manifests (references/<Model>.json, read by tools/casio_measure.py check): every
/// registered model has one, it names that model, and its boxes lie on the reference canvas.
@Suite("Reference manifests")
struct ManifestTests {
    private struct Manifest: Decodable {
        struct Canvas: Decodable { let size: [Double] }
        struct Element: Decodable {
            let name: String
            let mask: String
            let box: [Double]
        }
        let model: String
        let image: String
        let time: String
        let canvas: Canvas
        let elements: [Element]
    }

    private static let folder = URL(fileURLWithPath: #filePath)
        .deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()
        .appendingPathComponent("references")

    @Test("every model has a manifest naming it, with elements on its canvas")
    func manifests() throws {
        let files = try FileManager.default.contentsOfDirectory(at: Self.folder, includingPropertiesForKeys: nil)
            .filter { $0.pathExtension == "json" }
        let manifests = try files.map { try JSONDecoder().decode(Manifest.self, from: Data(contentsOf: $0)) }
        let named = Set(manifests.map(\.model))
        for model in CasioModels.all {
            #expect(named.contains("\(model)"), "\(model) has no manifest in references/")
        }
        for manifest in manifests {
            #expect(CasioModels.all.contains { "\($0)" == manifest.model }, "\(manifest.model) is not registered")
            #expect(!manifest.elements.isEmpty, "\(manifest.model) measures nothing")
            let width = manifest.canvas.size[0], height = manifest.canvas.size[1]
            for element in manifest.elements {
                let box = element.box
                #expect(box.count == 4 && box[0] < box[2] && box[1] < box[3], "\(manifest.model) \(element.name)")
                #expect(
                    box[0] >= 0 && box[1] >= 0 && box[2] <= width && box[3] <= height,
                    "\(manifest.model) \(element.name) is off the canvas")
            }
        }
    }
}
