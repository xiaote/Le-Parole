import Foundation
import PDFKit
import AppKit

guard CommandLine.arguments.count >= 4 else {
    print("Usage: render_pdf_page <pdf_path> <page_0_indexed> <output_png>")
    exit(1)
}

let pdfPath = CommandLine.arguments[1]
guard let pageIndex = Int(CommandLine.arguments[2]) else { exit(1) }
let outPath = CommandLine.arguments[3]

let pdfURL = URL(fileURLWithPath: pdfPath)
guard let doc = PDFDocument(url: pdfURL), let page = doc.page(at: pageIndex) else {
    print("Failed to load page \(pageIndex) from \(pdfPath)")
    exit(1)
}

let bounds = page.bounds(for: .mediaBox)
let scale: CGFloat = 2.0
let targetSize = NSSize(width: bounds.width * scale, height: bounds.height * scale)
let image = NSImage(size: targetSize)
image.lockFocus()

guard let context = NSGraphicsContext.current?.cgContext else { exit(1) }
context.setFillColor(NSColor.white.cgColor)
context.fill(CGRect(origin: .zero, size: targetSize))
context.saveGState()
context.scaleBy(x: scale, y: scale)
page.draw(with: .mediaBox, to: context)
context.restoreGState()
image.unlockFocus()

guard let tiffData = image.tiffRepresentation,
      let rep = NSBitmapImageRep(data: tiffData),
      let pngData = rep.representation(using: .png, properties: [:]) else { exit(1) }

try pngData.write(to: URL(fileURLWithPath: outPath))
print("Successfully rendered page \(pageIndex) to \(outPath)")
