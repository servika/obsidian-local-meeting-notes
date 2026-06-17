#!/usr/bin/env swift
// Generates the app icon (gradient rounded-square + a mic/waveform glyph) as an
// .icns. Usage: swift make-icon.swift <output.icns>

import AppKit
import Foundation

let outPath = CommandLine.arguments.count > 1 ? CommandLine.arguments[1] : "AppIcon.icns"
let masterSide = 1024

func symbolImage() -> NSImage? {
	let names = ["waveform.badge.mic", "mic.and.signal.meter.fill", "waveform", "mic.fill"]
	let cfg = NSImage.SymbolConfiguration(pointSize: CGFloat(masterSide) * 0.40, weight: .semibold)
		.applying(NSImage.SymbolConfiguration(paletteColors: [.white]))
	for name in names {
		if let s = NSImage(systemSymbolName: name, accessibilityDescription: nil),
			let configured = s.withSymbolConfiguration(cfg) {
			return configured
		}
	}
	return nil
}

func renderMaster() -> NSImage {
	let img = NSImage(size: NSSize(width: masterSide, height: masterSide))
	img.lockFocus()
	let rect = CGRect(x: 0, y: 0, width: masterSide, height: masterSide)
	let radius = CGFloat(masterSide) * 0.22
	let clip = NSBezierPath(roundedRect: rect, xRadius: radius, yRadius: radius)
	clip.addClip()
	let gradient = NSGradient(colors: [
		NSColor(srgbRed: 0.36, green: 0.30, blue: 0.92, alpha: 1),
		NSColor(srgbRed: 0.58, green: 0.26, blue: 0.84, alpha: 1),
	])!
	gradient.draw(in: rect, angle: -90)
	if let sym = symbolImage() {
		let s = sym.size
		let r = CGRect(x: (CGFloat(masterSide) - s.width) / 2,
			y: (CGFloat(masterSide) - s.height) / 2, width: s.width, height: s.height)
		sym.draw(in: r)
	}
	img.unlockFocus()
	return img
}

func png(_ image: NSImage, side: Int) -> Data {
	let rep = NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: side, pixelsHigh: side,
		bitsPerSample: 8, samplesPerPixel: 4, hasAlpha: true, isPlanar: false,
		colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0)!
	rep.size = NSSize(width: side, height: side)
	NSGraphicsContext.saveGraphicsState()
	NSGraphicsContext.current = NSGraphicsContext(bitmapImageRep: rep)
	image.draw(in: CGRect(x: 0, y: 0, width: side, height: side))
	NSGraphicsContext.restoreGraphicsState()
	return rep.representation(using: .png, properties: [:])!
}

let master = renderMaster()
let tmp = NSTemporaryDirectory() + "AppIcon-\(UUID().uuidString).iconset"
try! FileManager.default.createDirectory(atPath: tmp, withIntermediateDirectories: true)

let entries: [(String, Int)] = [
	("icon_16x16.png", 16), ("icon_16x16@2x.png", 32),
	("icon_32x32.png", 32), ("icon_32x32@2x.png", 64),
	("icon_128x128.png", 128), ("icon_128x128@2x.png", 256),
	("icon_256x256.png", 256), ("icon_256x256@2x.png", 512),
	("icon_512x512.png", 512), ("icon_512x512@2x.png", 1024),
]
for (name, side) in entries {
	try! png(master, side: side).write(to: URL(fileURLWithPath: tmp + "/" + name))
}

let p = Process()
p.executableURL = URL(fileURLWithPath: "/usr/bin/iconutil")
p.arguments = ["-c", "icns", tmp, "-o", outPath]
try! p.run()
p.waitUntilExit()
try? FileManager.default.removeItem(atPath: tmp)
print(p.terminationStatus == 0 ? "wrote \(outPath)" : "iconutil failed (\(p.terminationStatus))")
exit(p.terminationStatus)