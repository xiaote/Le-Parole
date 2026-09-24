import Foundation
import PDFKit
import AppKit

// Renders one page of a PDF to a PNG at a fixed pixel scale.
//
// The bitmap is allocated explicitly so the output size does not depend on the
// backing scale of the current display (NSImage.lockFocus renders at 2x on a
// Retina Mac and 1x elsewhere). The default of 4 px per PDF point matches the
// resolution that the crop boxes in repair_revealed_diagram_assets.py and
// diagram_crops.py were measured against (an A4 page renders to 2382x3368).

guard CommandLine.arguments.count >= 4 else {
    print("Usage: render_pdf_page <pdf_path> <page_0_indexed> <output_png> [pixels_per_point=4]")
    exit(1)
}

let pdfPath = CommandLine.arguments[1]
guard let pageIndex = Int(CommandLine.arguments[2]) else { exit(1) }
let outPath = CommandLine.arguments[3]
let scale: CGFloat = CommandLine.arguments.count >= 5 ? CGFloat(Double(CommandLine.arguments[4]) ?? 4) : 4

let pdfURL = URL(fileURLWithPath: pdfPath)
guard let doc = PDFDocument(url: pdfURL), let page = doc.page(at: pageIndex) else {
    print("Failed to load page \(pageIndex) from \(pdfPath)")
    exit(1)
}

let bounds = page.bounds(for: .mediaBox)
let pixelWidth = Int((bounds.width * scale).rounded())
let pixelHeight = Int((bounds.height * scale).rounded())

guard let rep = NSBitmapImageRep(
    bitmapDataPlanes: nil,
    pixelsWide: pixelWidth,
    pixelsHigh: pixelHeight,
    bitsPerSample: 8,
    samplesPerPixel: 4,
    hasAlpha: true,
    isPlanar: false,
    colorSpaceName: .deviceRGB,
    bytesPerRow: 0,
    bitsPerPixel: 0
), let graphicsContext = NSGraphicsContext(bitmapImageRep: rep) else { exit(1) }

let context = graphicsContext.cgContext
context.setFillColor(NSColor.white.cgColor)
context.fill(CGRect(x: 0, y: 0, width: pixelWidth, height: pixelHeight))
context.saveGState()
context.scaleBy(x: scale, y: scale)
page.draw(with: .mediaBox, to: context)
context.restoreGState()
graphicsContext.flushGraphics()

guard let pngData = rep.representation(using: .png, properties: [:]) else { exit(1) }

try pngData.write(to: URL(fileURLWithPath: outPath))
print("Successfully rendered page \(pageIndex) to \(outPath) (\(pixelWidth)x\(pixelHeight))")
