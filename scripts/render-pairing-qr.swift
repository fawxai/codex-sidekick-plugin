#!/usr/bin/env swift

import AppKit
import CoreImage
import CoreImage.CIFilterBuiltins
import Foundation

guard CommandLine.arguments.count == 3 else {
    fputs("usage: render-pairing-qr.swift <pairing-link> <output.png>\n", stderr)
    exit(1)
}

let pairingLink = CommandLine.arguments[1]
let outputURL = URL(fileURLWithPath: CommandLine.arguments[2])

guard let messageData = pairingLink.data(using: .utf8) else {
    fputs("could not encode pairing link\n", stderr)
    exit(1)
}

let filter = CIFilter.qrCodeGenerator()
filter.message = messageData
filter.correctionLevel = "M"

guard let outputImage = filter.outputImage else {
    fputs("could not generate QR image\n", stderr)
    exit(1)
}

let scaledImage = outputImage.transformed(by: CGAffineTransform(scaleX: 16, y: 16))
let context = CIContext()

guard let cgImage = context.createCGImage(scaledImage, from: scaledImage.extent) else {
    fputs("could not render QR image\n", stderr)
    exit(1)
}

let directoryURL = outputURL.deletingLastPathComponent()
try FileManager.default.createDirectory(at: directoryURL, withIntermediateDirectories: true)

let bitmap = NSBitmapImageRep(cgImage: cgImage)
guard let pngData = bitmap.representation(using: NSBitmapImageRep.FileType.png, properties: [:]) else {
    fputs("could not encode QR image as PNG\n", stderr)
    exit(1)
}

try pngData.write(to: outputURL, options: Data.WritingOptions.atomic)
