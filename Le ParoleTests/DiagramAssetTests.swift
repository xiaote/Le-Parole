import CoreGraphics
import Foundation
import Testing
import UIKit
@testable import Le_Parole

/// Guards the sailing diagram assets referenced by `Data/diagrams.json` against
/// missing or blank images (e.g. the all-black gavitello crop that shipped once
/// after a repair script cropped an already-cropped image).
@Suite("Diagram assets")
struct DiagramAssetTests {
    private nonisolated struct Entry: Decodable, Sendable {
        let id: String
        let promptImageName: String
        let revealedImageName: String
        let plateName: String
    }

    private nonisolated static let entries: [Entry] = {
        guard let url = Bundle.main.url(forResource: "diagrams", withExtension: "json"),
              let data = try? Data(contentsOf: url),
              let entries = try? JSONDecoder().decode([Entry].self, from: data) else {
            return []
        }
        return entries
    }()

    nonisolated static let imageNames: [String] = Array(Set(entries.flatMap {
        [$0.promptImageName, $0.revealedImageName, $0.plateName]
    })).sorted()

    /// (quiz, full) pairs. No diagram currently uses the same image for both, so none are exempt.
    nonisolated static let quizFullPairs: [QuizFullPair] = entries.map {
        QuizFullPair(quiz: $0.promptImageName, full: $0.revealedImageName)
    }

    nonisolated struct QuizFullPair: Sendable, CustomTestStringConvertible {
        let quiz: String
        let full: String
        var testDescription: String { quiz }
    }

    // Thresholds measured on a 32x32 downsample drawn over white:
    // - current assets: at most 2.5% near-black and 94.4% near-uniform pixels
    //   (sparse line drawings on white are very uniform);
    // - the broken black gavitello crops: 98.2%/100% near-black, 98.1%/100% near-uniform.
    private static let maxNearBlackFraction = 0.90
    private static let maxNearUniformFraction = 0.97

    @Test func catalogueLoads() {
        #expect(Self.entries.count > 0)
        #expect(Self.imageNames.count > 0)
    }

    @Test("Image is present and not blank", arguments: imageNames)
    func imageIsNotBlank(name: String) throws {
        let image = try #require(UIImage(named: name), "Missing image asset \(name)")
        let pixels = try #require(Self.rgbPixels(of: image, side: 32))
        let count = pixels.count / 4

        var sum = (r: 0, g: 0, b: 0)
        for i in 0..<count {
            sum.r += Int(pixels[i * 4]); sum.g += Int(pixels[i * 4 + 1]); sum.b += Int(pixels[i * 4 + 2])
        }
        let mean = (r: sum.r / count, g: sum.g / count, b: sum.b / count)

        var nearBlack = 0
        var nearUniform = 0
        for i in 0..<count {
            let r = Int(pixels[i * 4]), g = Int(pixels[i * 4 + 1]), b = Int(pixels[i * 4 + 2])
            if max(r, g, b) < 32 { nearBlack += 1 }
            if abs(r - mean.r) < 16, abs(g - mean.g) < 16, abs(b - mean.b) < 16 { nearUniform += 1 }
        }

        let blackFraction = Double(nearBlack) / Double(count)
        let uniformFraction = Double(nearUniform) / Double(count)
        #expect(blackFraction < Self.maxNearBlackFraction, "\(name) is \(Int(blackFraction * 100))% near-black")
        #expect(uniformFraction < Self.maxNearUniformFraction, "\(name) is \(Int(uniformFraction * 100))% near-uniform")
    }

    @Test("Quiz image differs from full image", arguments: quizFullPairs)
    func quizDiffersFromFull(pair: QuizFullPair) throws {
        let quiz = try #require(UIImage(named: pair.quiz))
        let full = try #require(UIImage(named: pair.full))
        let side = 64
        let a = try #require(Self.rgbPixels(of: quiz, side: side))
        let b = try #require(Self.rgbPixels(of: full, side: side))

        // The quiz variant carries a "?" badge; currently every pair has at least 62 channel samples
        // differing by more than 32 at 64x64.
        var differing = 0
        for i in 0..<a.count where i % 4 != 3 && abs(Int(a[i]) - Int(b[i])) > 32 {
            differing += 1
        }
        #expect(differing >= 16, "\(pair.quiz) looks identical to \(pair.full)")
    }

    /// Draws the image over white into a `side`x`side` sRGB RGBA buffer.
    private static func rgbPixels(of image: UIImage, side: Int) -> [UInt8]? {
        guard let cgImage = image.cgImage,
              let space = CGColorSpace(name: CGColorSpace.sRGB) else { return nil }
        var buffer = [UInt8](repeating: 0, count: side * side * 4)
        let drawn: Bool = buffer.withUnsafeMutableBytes { raw in
            guard let context = CGContext(
                data: raw.baseAddress, width: side, height: side, bitsPerComponent: 8,
                bytesPerRow: side * 4, space: space,
                bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
            ) else { return false }
            let rect = CGRect(x: 0, y: 0, width: side, height: side)
            context.setFillColor(CGColor(red: 1, green: 1, blue: 1, alpha: 1))
            context.fill(rect)
            context.interpolationQuality = .medium
            context.draw(cgImage, in: rect)
            return true
        }
        return drawn ? buffer : nil
    }
}
