// swift-tools-version: 5.9
import PackageDescription

let package = Package(
	name: "meeting-engine",
	platforms: [
		// Core Audio process taps require macOS 14.4+.
		.macOS("14.4"),
	],
	targets: [
		// Reusable capture engine (shared by the CLI and the GUI app).
		.target(name: "MeetingEngineCore"),

		// Headless CLI for dev iteration of the capture pipeline. Cannot obtain
		// the system-audio permission (that needs the GUI app), but is useful for
		// exercising the engine and the mic path.
		.executableTarget(
			name: "meeting-engine",
			dependencies: ["MeetingEngineCore"],
			exclude: ["Info.plist"],
			linkerSettings: [
				.unsafeFlags([
					"-Xlinker", "-sectcreate",
					"-Xlinker", "__TEXT",
					"-Xlinker", "__info_plist",
					"-Xlinker", "Sources/meeting-engine/Info.plist",
				]),
			]
		),

		// Real AppKit app - the signed bundle that can request the macOS
		// system-audio-recording permission. Built into a .app by scripts/build-app.sh.
		.executableTarget(
			name: "MeetingEngineApp",
			dependencies: ["MeetingEngineCore"]
		),
	]
)