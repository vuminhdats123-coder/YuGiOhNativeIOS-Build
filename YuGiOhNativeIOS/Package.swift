// swift-tools-version: 5.9
import PackageDescription

let package = Package(
    name: "YuGiOhNativeIOS",
    platforms: [.iOS(.v16)],
    products: [.library(name: "YuGiOhNativeIOS", targets: ["YuGiOhNativeIOS"])],
    targets: [.target(name: "YuGiOhNativeIOS", resources: [.process("../../Resources")])]
)
