// swift-tools-version: 5.9
import PackageDescription

let package = Package(
    name: "pdfpack",
    platforms: [
        .macOS(.v12)
    ],
    products: [
        .executable(name: "pdfpack", targets: ["PDFPackApp"])
    ],
    targets: [
        .executableTarget(
            name: "PDFPackApp",
            path: "Sources/PDFPackApp"
        )
    ]
)
