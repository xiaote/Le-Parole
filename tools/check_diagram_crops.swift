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

struct DiagramEntry: Decodable {
    struct Key: Decodable { let text: String }
    let id: String
    let keys: [Key]
    let revealedImageName: String
    let title: String
    let plateName: String
}

let jsonData = try Data(contentsOf: URL(fileURLWithPath: "Le Parole/Data/diagrams.json"))
let entries = try JSONDecoder().decode([DiagramEntry].self, from: jsonData)

print("=== CHECKING ALL \(entries.count) DIAGRAM CROPS FOR KEYWORD MATCH ===")

var suspectList: [(index: Int, id: String, title: String, plate: String, keys: String, texts: [String])] = []

for (index, entry) in entries.enumerated() {
    let id = entry.id
    let revealed = entry.revealedImageName
    let title = entry.title
    let plate = entry.plateName
    let rawKeys = entry.keys.map { $0.text.lowercased() }
    let keysStr = "[" + entry.keys.map { "\"\($0.text)\"" }.joined(separator: ", ") + "]"

    let cropURL = assetDir.appendingPathComponent("\(revealed).imageset/\(revealed).png")
    let texts = ocr(imageURL: cropURL)
    let lowerTexts = texts.map { $0.lowercased() }
    
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
