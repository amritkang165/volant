// swift-tools-version: 5.9
import PackageDescription

// A WASI command that answers one launcher query with VolantCore's own calculator, for the
// website's "Try Volant" spike. It reads a JSON request on stdin and writes JSON answers to stdout.
let package = Package(
    name: "VolantAnswers",
    dependencies: [.package(path: "../../Core")],
    targets: [
        .executableTarget(name: "VolantAnswers", dependencies: [.product(name: "VolantCore", package: "Core")])
    ]
)
