import Foundation
import Vision
import AppKit

let assetDir = URL(fileURLWithPath: "Le Parole/Assets.xcassets")

func ocr(imageURL: URL) -> [String] {
    guard let image = NSImage(contentsOf: imageURL),
          let cgImage = image.cgImage(forProposedRect: nil, context: nil, hints: nil) else {
        return []
    }
    var results: [String] = []
    let request = VNRecognizeTextRequest { req, err in
        guard let observations = req.results as? [VNRecognizedTextObservation] else { return }
        for obs in observations {
            if let top = obs.topCandidates(1).first {
                results.append(top.string)
            }
        }
    }
    request.recognitionLevel = .accurate
    request.recognitionLanguages = ["it-IT", "en-US"]
    let handler = VNImageRequestHandler(cgImage: cgImage, options: [:])
    try? handler.perform([request])
    return results
}

let swiftFile = try String(contentsOfFile: "Le Parole/Services/SailingDiagramService.swift", encoding: .utf8)
let pattern = #"add\(\s*keys:\s*(\[[^\]]+\]),\s*id:\s*"([^"]+)",\s*prompt:\s*"([^"]+)",\s*revealed:\s*"([^"]+)",\s*title:\s*"([^"]+)",\s*plate:\s*"([^"]+)",\s*plateTitle:\s*"([^"]+)",\s*caption:\s*"([^"]+)""#
let regex = try NSRegularExpression(pattern: pattern, options: [])
let nsString = swiftFile as NSString
let matches = regex.matches(in: swiftFile, options: [], range: NSRange(location: 0, length: nsString.length))

print("=== CHECKING ALL 96 DIAGRAM CROPS FOR KEYWORD MATCH ===")

var suspectList: [(index: Int, id: String, title: String, plate: String, keys: String, texts: [String])] = []

for (index, match) in matches.enumerated() {
    let keysStr = nsString.substring(with: match.range(at: 1))
    let id = nsString.substring(with: match.range(at: 2))
    let prompt = nsString.substring(with: match.range(at: 3))
    let revealed = nsString.substring(with: match.range(at: 4))
    let title = nsString.substring(with: match.range(at: 5))
    let plate = nsString.substring(with: match.range(at: 6))
    
    let cropURL = assetDir.appendingPathComponent("\(revealed).imageset/\(revealed).png")
    let texts = ocr(imageURL: cropURL)
    let lowerTexts = texts.map { $0.lowercased() }
    
    // Parse keys array
    let rawKeys = keysStr.replacingOccurrences(of: "[", with: "")
        .replacingOccurrences(of: "]", with: "")
        .split(separator: ",")
        .map { $0.trimmingCharacters(in: .whitespacesAndNewlines).replacingOccurrences(of: "\"", with: "").lowercased() }
    
    // Check if any key or the id is a substring of any OCR text
    var matched = false
    for key in rawKeys {
        let words = key.split(separator: " ").map(String.init)
        for w in words where w.count >= 4 {
            if lowerTexts.contains(where: { $0.contains(w) }) {
                matched = true
                break
            }
        }
        if matched { break }
    }
    
    let idWords = id.split(separator: "_").map(String.init)
    for w in idWords where w.count >= 4 {
        if lowerTexts.contains(where: { $0.contains(w) }) {
            matched = true
            break
        }
    }
    
    if !matched {
        suspectList.append((index + 1, id, title, plate, keysStr, texts))
    }
}

print("Suspect count: \(suspectList.count)")
for item in suspectList {
    print("--------------------------------------------------")
    print("#\(item.index) [\(item.id)] '\(item.title)' (plate: \(item.plate))")
    print("  Keys: \(item.keys)")
    print("  Crop OCR: \(item.texts.joined(separator: " | "))")
}
