import Foundation

/// Works out what an app is built with from its bundle alone — nothing is run
/// and nothing leaves the Mac.
///
/// The marker rules (which files prove Electron, why Qt is asked before
/// Chromium, the Tauri plist gate) are taken from DuoUpdater's
/// `AppRuntimeDetector` (https://github.com/jizhi0v0/duo-updater, MIT License
/// © jizhi0v0). The implementation is our own and much smaller: DuoUpdater
/// parses Mach-O load commands properly, Sift only looks for framework paths
/// inside them.
enum AppRuntimeDetector {
    /// Injected so the rules can be tested without a real binary on disk.
    /// Returns the raw load-command bytes of the executable, or nil.
    typealias LoadCommandReader = (URL) -> Data?

    static func detect(
        bundlePath: String,
        infoPlist: [String: Any],
        fileManager fm: FileManager = .default,
        loadCommands: LoadCommandReader = AppRuntimeDetector.loadCommands(of:)
    ) -> AppRuntime? {
        let contents = URL(fileURLWithPath: bundlePath).appendingPathComponent("Contents")
        let frameworkNames = (try? fm.contentsOfDirectory(
            atPath: contents.appendingPathComponent("Frameworks").path)) ?? []

        // Electron. The framework can be renamed (QQ ships `QQNT.framework`), so
        // the JavaScript payload counts too. Helper apps are NOT a marker — CEF
        // lays its helpers out the same way.
        let electronMarkers = ["Resources/app.asar", "Resources/app-update.yml", "Resources/app/package.json"]
        if frameworkNames.contains("Electron Framework.framework")
            || electronMarkers.contains(where: { fm.fileExists(atPath: contents.appendingPathComponent($0).path) }) {
            return .electron
        }

        if frameworkNames.contains("FlutterMacOS.framework") { return .flutter }

        // Qt before Chromium: an app that ships both draws its windows with Qt.
        if frameworkNames.contains(where: isQtComponent) { return .qt }

        if isJavaBundle(contents: contents, infoPlist: infoPlist, fm: fm) { return .java }

        // CEF, and the browsers themselves (`Google Chrome Framework.framework`).
        // Electron's own framework matches too, which is why it is asked first.
        if frameworkNames.contains(where: { $0.hasSuffix(" Framework.framework") }) { return .chromium }

        guard let executable = executableURL(bundlePath: bundlePath, infoPlist: infoPlist, fm: fm),
              let commands = loadCommands(executable) else {
            return nil
        }

        func links(_ frameworkPath: String) -> Bool {
            commands.range(of: Data(frameworkPath.utf8)) != nil
        }

        // Tauri is compiled into the executable, so the bundle layout says
        // nothing. Its bundler writes these two plist keys; the crate name in
        // the binary is the proof, and the gate keeps that read rare.
        if infoPlist["LSRequiresCarbon"] as? Bool == true,
           infoPlist["CSResourcesFileMapped"] as? Bool == true,
           links("/System/Library/Frameworks/WebKit.framework/"),
           binaryMentionsTauri(executable) {
            return .tauri
        }

        if links("/System/iOSSupport/System/Library/Frameworks/UIKit.framework/") { return .catalyst }
        if links("/System/Library/Frameworks/SwiftUI.framework/") { return .swiftUI }
        if links("/System/Library/Frameworks/AppKit.framework/") { return .appKit }
        return nil
    }

    private static func isQtComponent(_ name: String) -> Bool {
        (name.hasPrefix("Qt") && name.hasSuffix(".framework"))
            || (name.hasPrefix("libQt") && name.hasSuffix(".dylib"))
    }

    private static func isJavaBundle(contents: URL, infoPlist: [String: Any], fm: FileManager) -> Bool {
        for directory in ["Java", "runtime", "jbr"] {
            var isDirectory: ObjCBool = false
            if fm.fileExists(atPath: contents.appendingPathComponent(directory).path, isDirectory: &isDirectory),
               isDirectory.boolValue {
                return true
            }
        }
        let executable = infoPlist["CFBundleExecutable"] as? String
        return executable == "JavaAppLauncher" || executable == "JavaApplicationStub"
    }

    private static func executableURL(bundlePath: String, infoPlist: [String: Any], fm: FileManager) -> URL? {
        let bundleURL = URL(fileURLWithPath: bundlePath)
        let declared = (infoPlist["CFBundleExecutable"] as? String).flatMap { $0.isEmpty ? nil : $0 }
        let name = declared ?? bundleURL.deletingPathExtension().lastPathComponent
        guard !name.isEmpty else { return nil }
        let url = bundleURL.appendingPathComponent("Contents/MacOS").appendingPathComponent(name)
        return fm.fileExists(atPath: url.path) ? url : nil
    }

    // MARK: - Reading the executable

    /// The load commands of the executable's first architecture slice. Linked
    /// framework paths sit in there as plain text, so callers search the bytes
    /// instead of walking each command. Reads a few KB, never the whole binary.
    static func loadCommands(of executable: URL) -> Data? {
        guard let handle = try? FileHandle(forReadingFrom: executable) else { return nil }
        defer { try? handle.close() }

        func read(at offset: UInt64, count: Int) -> Data? {
            guard (try? handle.seek(toOffset: offset)) != nil,
                  let data = try? handle.read(upToCount: count), data.count == count else { return nil }
            return data
        }
        func uint32(_ data: Data, at index: Int, bigEndian: Bool) -> UInt32 {
            let value = data.subdata(in: index..<index + 4).withUnsafeBytes { $0.loadUnaligned(as: UInt32.self) }
            return bigEndian ? UInt32(bigEndian: value) : UInt32(littleEndian: value)
        }

        guard let head = read(at: 0, count: 8) else { return nil }
        var sliceOffset: UInt64 = 0
        let magic = uint32(head, at: 0, bigEndian: true)
        if magic == 0xCAFE_BABE || magic == 0xCAFE_BABF {
            // Universal binary: take the first slice. Entries are big-endian;
            // the 64-bit form widens offset and size.
            guard uint32(head, at: 4, bigEndian: true) > 0 else { return nil }
            if magic == 0xCAFE_BABE {
                guard let arch = read(at: 8, count: 20) else { return nil }
                sliceOffset = UInt64(uint32(arch, at: 8, bigEndian: true))
            } else {
                guard let arch = read(at: 8, count: 32) else { return nil }
                sliceOffset = UInt64(uint32(arch, at: 8, bigEndian: true)) << 32
                    | UInt64(uint32(arch, at: 12, bigEndian: true))
            }
        }

        // mach_header_64: magic, cputype, cpusubtype, filetype, ncmds, sizeofcmds, …
        guard let header = read(at: sliceOffset, count: 32),
              uint32(header, at: 0, bigEndian: false) == 0xFEED_FACF else { return nil }
        let sizeOfCommands = Int(uint32(header, at: 20, bigEndian: false))
        guard sizeOfCommands > 0, sizeOfCommands <= 1_048_576 else { return nil }
        return read(at: sliceOffset + 32, count: sizeOfCommands)
    }

    /// Rust keeps crate source paths (`tauri-2.1.0/src/…`) in the binary.
    private static func binaryMentionsTauri(_ executable: URL) -> Bool {
        guard let data = try? Data(contentsOf: executable, options: .alwaysMapped) else { return false }
        return data.range(of: Data("/tauri-".utf8)) != nil
    }
}
