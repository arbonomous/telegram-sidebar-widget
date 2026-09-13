import Cocoa

let root = URL(fileURLWithPath: FileManager.default.currentDirectoryPath)
let sidePieceSVG = root.appendingPathComponent("SidePiece.svg")
let logoSVG = root.appendingPathComponent("Logo.svg")
let icnsURL = root.appendingPathComponent("build/AppIcon.icns")
let logoPNGURL = root.appendingPathComponent("Logo.png")

guard let sidePieceImage = NSImage(contentsOf: sidePieceSVG) else {
    print("Error: Could not load SidePiece.svg")
    exit(1)
}

func renderPNGData(image: NSImage, pixelSize: Int) -> Data? {
    guard let rep = NSBitmapImageRep(bitmapDataPlanes: nil,
                                     pixelsWide: pixelSize,
                                     pixelsHigh: pixelSize,
                                     bitsPerSample: 8,
                                     samplesPerPixel: 4,
                                     hasAlpha: true,
                                     isPlanar: false,
                                     colorSpaceName: .calibratedRGB,
                                     bytesPerRow: 0,
                                     bitsPerPixel: 0) else { return nil }
    rep.size = NSSize(width: pixelSize, height: pixelSize)
    
    NSGraphicsContext.saveGraphicsState()
    NSGraphicsContext.current = NSGraphicsContext(bitmapImageRep: rep)
    image.draw(in: NSRect(x: 0, y: 0, width: pixelSize, height: pixelSize),
               from: .zero,
               operation: .copy,
               fraction: 1.0)
    NSGraphicsContext.restoreGraphicsState()
    
    return rep.representation(using: .png, properties: [:])
}

// Complete Apple ICNS chunk specifications for macOS app icons
let tagSizes: [(String, Int)] = [
    ("ic11", 32),    // 16x16@2x
    ("ic12", 64),    // 32x32@2x
    ("ic07", 128),   // 128x128
    ("ic13", 256),   // 128x128@2x
    ("ic08", 256),   // 256x256
    ("ic14", 512),   // 256x256@2x
    ("ic09", 512),   // 512x512
    ("ic10", 1024)   // 512x512@2x (Retina)
]

var chunks = Data()
for (tag, size) in tagSizes {
    guard let pngData = renderPNGData(image: sidePieceImage, pixelSize: size) else { continue }
    let tagBytes = Array(tag.utf8)
    var chunkLen = UInt32(8 + pngData.count).bigEndian
    chunks.append(contentsOf: tagBytes)
    chunks.append(Data(bytes: &chunkLen, count: 4))
    chunks.append(pngData)
}

var icnsData = Data()
icnsData.append(contentsOf: [0x69, 0x63, 0x6E, 0x73]) // 'icns'
var totalLen = UInt32(8 + chunks.count).bigEndian
icnsData.append(Data(bytes: &totalLen, count: 4))
icnsData.append(chunks)

try? FileManager.default.createDirectory(at: root.appendingPathComponent("build"), withIntermediateDirectories: true)
try? icnsData.write(to: icnsURL)
print("Built \(icnsURL.path) (\(icnsData.count) bytes)")

// Render Logo.png from Logo.svg
if let logoImg = NSImage(contentsOf: logoSVG), let logoPNGData = renderPNGData(image: logoImg, pixelSize: 512) {
    try? logoPNGData.write(to: logoPNGURL)
    print("Built \(logoPNGURL.path) (\(logoPNGData.count) bytes)")
}
