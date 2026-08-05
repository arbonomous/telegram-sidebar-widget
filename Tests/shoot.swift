import CoreGraphics
import Foundation

let did = CGMainDisplayID()
guard let img = CGDisplayCreateImage(did) else {
    fputs("CGDisplayCreateImage returned nil\n", stderr)
    exit(2)
}
let w = CGImageGetWidth(img), h = CGImageGetHeight(img)
print("full capture \(w)x\(h)")

// Crop right-edge strip: logical x=1380..1440 -> physical *2 = 2760..2880 (display is 2880 wide).
let cropX = Int(Double(w) * 2760.0 / 2880.0)
let cropW = w - cropX
guard let strip = img.cropping(to: CGRect(x: cropX, y: 0, width: cropW, height: h)) else {
    fputs("crop failed\n", stderr); exit(3)
}

let url = NSURL.fileURL(withPath: "/tmp/edge_cg.png")
let dest = CGImageDestinationCreateWithURL(url as CFURL, "public.png" as CFString, 1, nil)!
CGImageDestinationAddImage(dest, strip, nil)
guard CGImageDestinationFinalize(dest) else { fputs("finalize failed\n", stderr); exit(4) }
print("wrote /tmp/edge_cg.png (\(cropW)x\(h) of right edge)")
