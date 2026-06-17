// swift-tools-version: 5.9
import PackageDescription

let package = Package(
	name: "meeting-engine",
	platforms: [
		// Core Audio process taps require macOS 14.4+.
		.macOS("14.4"),
	],
	targets: [
		.executableTarget(
			name: "meeting-engine",
			// Info.plist is embedded via the linker below, not bundled as a resource.
			exclude: ["Info.plist"],
			linkerSettings: [
				// Embed an Info.plist so TCC can show the audio-capture permission prompt
				// even though this is a plain SwiftPM executable, not an .app bundle.
				.unsafeFlags([
					"-Xlinker", "-sectcreate",
					"-Xlinker", "__TEXT",
					"-Xlinker", "__info_plist",
					"-Xlinker", "Sources/meeting-engine/Info.plist",
				]),
			]
		),
	]
)