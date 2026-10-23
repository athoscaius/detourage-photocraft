// ArtCraft Détourage IA — offline neural matte engine for macOS 14+.
// Build: swiftc -O MattingEngine.swift -o matting-engine
// Apple APIs: https://developer.apple.com/documentation/vision/vngeneratepersonsegmentationrequest
// https://developer.apple.com/documentation/vision/vngenerateforegroundinstancemaskrequest
// Vision anchors human context. BiRefNet-matting supplies the final soft coverage.
// Official model: https://huggingface.co/ZhengPeng7/BiRefNet-matting (MIT).
// The engine writes coverage values directly to an untagged grayscale PNG; a matte
// is data, so it must not pass through an sRGB transfer curve or a binary threshold.

import Foundation
import CoreImage
import CoreVideo
import ImageIO
import UniformTypeIdentifiers
import Vision
import Darwin

enum EngineError: LocalizedError {
    case message(String)
    var errorDescription: String? {
        switch self { case .message(let value): return value }
    }
}

struct Options {
    var input: URL
    var mask: URL
    var cutout: URL?
    var mode: String

    static func parse() throws -> Options {
        let args = Array(CommandLine.arguments.dropFirst())
        if args == ["--help"] || args == ["-h"] {
            print("Usage: matting-engine --input IMAGE --mask MASK.png [--mode person|subject] [--cutout SUBJECT.png]")
            exit(0)
        }
        var values: [String: String] = [:]
        var index = 0
        while index < args.count {
            let key = args[index]
            guard ["--input", "--mask", "--mode", "--cutout"].contains(key), index + 1 < args.count,
                  values[key] == nil else {
                throw EngineError.message("Argument invalide : \(key). Utilisez --help.")
            }
            values[key] = args[index + 1]
            index += 2
        }
        guard let input = values["--input"], let mask = values["--mask"] else {
            throw EngineError.message("Les paramètres --input et --mask sont obligatoires.")
        }
        let mode = values["--mode"] ?? "person"
        guard ["person", "subject"].contains(mode) else {
            throw EngineError.message("Le mode doit être person ou subject.")
        }
        let inputURL = URL(fileURLWithPath: input).standardizedFileURL
        let maskURL = URL(fileURLWithPath: mask).standardizedFileURL
        let cutoutURL = values["--cutout"].map { URL(fileURLWithPath: $0).standardizedFileURL }
        guard inputURL != maskURL, inputURL != cutoutURL, maskURL != cutoutURL else {
            throw EngineError.message("L’image source et les sorties doivent avoir des chemins différents.")
        }
        return Options(input: inputURL, mask: maskURL, cutout: cutoutURL, mode: mode)
    }
}

func savePNG(_ cgImage: CGImage, to url: URL) throws {
    guard url.pathExtension.lowercased() == "png" else {
        throw EngineError.message("La sortie doit être un fichier PNG.")
    }
    let directory = url.deletingLastPathComponent()
    guard FileManager.default.fileExists(atPath: directory.path) else {
        throw EngineError.message("Le dossier de sortie n’existe pas : \(directory.path)")
    }
    // A sibling temporary file keeps an interrupted write from being mistaken for
    // a completed mask. The source image is never changed.
    let temporary = directory.appendingPathComponent(".\(UUID().uuidString).png")
    defer { try? FileManager.default.removeItem(at: temporary) }
    guard let destination = CGImageDestinationCreateWithURL(temporary as CFURL, UTType.png.identifier as CFString, 1, nil) else {
        throw EngineError.message("Impossible de créer la sortie PNG.")
    }
    CGImageDestinationAddImage(destination, cgImage, nil)
    guard CGImageDestinationFinalize(destination) else {
        throw EngineError.message("Échec de l’écriture PNG.")
    }
    if FileManager.default.fileExists(atPath: url.path) {
        _ = try FileManager.default.replaceItemAt(url, withItemAt: temporary)
    } else {
        try FileManager.default.moveItem(at: temporary, to: url)
    }
}

func grayscaleImage(bytes: [UInt8], width: Int, height: Int) throws -> CGImage {
    let data = Data(bytes) as CFData
    guard let provider = CGDataProvider(data: data),
          let image = CGImage(width: width, height: height, bitsPerComponent: 8,
                              bitsPerPixel: 8, bytesPerRow: width,
                              space: CGColorSpaceCreateDeviceGray(),
                              bitmapInfo: CGBitmapInfo(rawValue: CGImageAlphaInfo.none.rawValue),
                              provider: provider, decode: nil,
                              shouldInterpolate: false, intent: .defaultIntent) else {
        throw EngineError.message("Impossible de créer le masque en niveaux de gris.")
    }
    return image
}

func alphaAsLuminance(_ image: CIImage) -> CIImage {
    image.applyingFilter("CIColorMatrix", parameters: [
        "inputRVector": CIVector(x: 0, y: 0, z: 0, w: 1),
        "inputGVector": CIVector(x: 0, y: 0, z: 0, w: 1),
        "inputBVector": CIVector(x: 0, y: 0, z: 0, w: 1),
        "inputAVector": CIVector(x: 0, y: 0, z: 0, w: 0),
        "inputBiasVector": CIVector(x: 0, y: 0, z: 0, w: 1)
    ])
}

func renderFloat(_ image: CIImage, context: CIContext, width: Int, height: Int) -> [Float] {
    var result = [Float](repeating: 0, count: width * height)
    result.withUnsafeMutableBytes { raw in
        context.render(image, toBitmap: raw.baseAddress!, rowBytes: width * MemoryLayout<Float>.size,
                       bounds: CGRect(x: 0, y: 0, width: width, height: height),
                       format: .Rf, colorSpace: nil)
    }
    return result
}

// The inference runtime and pinned model live beside this executable in the
// application bundle. They do not depend on a user/Codex Python installation.
func highDefinitionMatte(input: URL, guide: CIImage?, context: CIContext,
                         width: Int, height: Int) throws -> CIImage {
    let resources = URL(fileURLWithPath: CommandLine.arguments[0]).resolvingSymlinksInPath()
        .deletingLastPathComponent().deletingLastPathComponent()
    let ai = resources.appendingPathComponent("ai")
    let python = ai.appendingPathComponent("python/bin/python3")
    let script = ai.appendingPathComponent("high_resolution_matting.py")
    guard FileManager.default.isExecutableFile(atPath: python.path),
          FileManager.default.fileExists(atPath: script.path),
          FileManager.default.fileExists(atPath: ai.appendingPathComponent("models/BiRefNet-matting-epoch_100.onnx").path) else {
        throw EngineError.message("Le moteur haute définition est incomplet. Réinstallez le compagnon.")
    }
    let temporary = FileManager.default.temporaryDirectory.appendingPathComponent("artcraft-matting-\(UUID().uuidString)", isDirectory: true)
    try FileManager.default.createDirectory(at: temporary, withIntermediateDirectories: false,
                                           attributes: [.posixPermissions: 0o700])
    defer { try? FileManager.default.removeItem(at: temporary) }
    let output = temporary.appendingPathComponent("coverage.png")
    var arguments = ["-I", "-B", script.path, "--input", input.path, "--mask", output.path]
    if let guide = guide {
        let scaled = guide.transformed(by: CGAffineTransform(scaleX: 512 / CGFloat(width), y: 512 / CGFloat(height)))
        let samples = renderFloat(scaled, context: context, width: 512, height: 512)
        guard samples.contains(where: { $0.isFinite && $0 > 0.125 }) else {
            throw EngineError.message("Aucune personne détectée. Essayez le mode Sujet.")
        }
        let bytes = samples.map { UInt8((($0.isFinite ? min(1,max(0,$0)) : 0) * 255).rounded()) }
        let guideURL = temporary.appendingPathComponent("person-guide.png")
        try savePNG(grayscaleImage(bytes: bytes, width: 512, height: 512), to: guideURL)
        arguments += ["--guide", guideURL.path]
    }
    let logURL = temporary.appendingPathComponent("inference.log")
    FileManager.default.createFile(atPath: logURL.path, contents: nil)
    let log = try FileHandle(forWritingTo: logURL)
    defer { try? log.close() }
    let process = Process()
    process.executableURL = python
    process.arguments = arguments
    process.standardOutput = log
    process.standardError = log
    let ended = DispatchSemaphore(value: 0)
    process.terminationHandler = { _ in ended.signal() }
    try process.run()
    if ended.wait(timeout: .now() + 540) == .timedOut {
        process.terminate()
        if ended.wait(timeout: .now() + 5) == .timedOut {
            kill(process.processIdentifier, SIGKILL)
            _ = ended.wait(timeout: .now() + 5)
        }
        throw EngineError.message("Le calcul haute définition a dépassé neuf minutes. Aucun résultat n’a été appliqué.")
    }
    guard process.terminationStatus == 0,
          let source = CGImageSourceCreateWithURL(output as CFURL, nil),
          let decoded = CGImageSourceCreateImageAtIndex(source, 0, nil),
          decoded.width == width, decoded.height == height,
          decoded.bitsPerPixel == 8, decoded.colorSpace?.model == .monochrome else {
        let details = (try? String(contentsOf: logURL, encoding: .utf8)) ?? ""
        throw EngineError.message("Échec du matting haute définition. " + String(details.suffix(1600)))
    }
    return CIImage(cgImage: decoded, options: [.colorSpace: NSNull()])
}

@available(macOS 14.0, *)
func run(_ options: Options) throws {
    let start = Date()
    guard let source = CGImageSourceCreateWithURL(options.input as CFURL, nil),
          let properties = CGImageSourceCopyPropertiesAtIndex(source, 0, nil) as? [CFString: Any],
          let rawWidth = properties[kCGImagePropertyPixelWidth] as? Int,
          let rawHeight = properties[kCGImagePropertyPixelHeight] as? Int,
          rawWidth > 0, rawHeight > 0 else {
        throw EngineError.message("Image illisible ou format non pris en charge.")
    }
    guard rawWidth <= 32768, rawHeight <= 32768,
          Int64(rawWidth) * Int64(rawHeight) <= 64_000_000 else {
        throw EngineError.message("Image trop grande : limite de 64 mégapixels et 32 768 pixels par côté.")
    }
    guard let decoded = CGImageSourceCreateImageAtIndex(source, 0, [kCGImageSourceShouldCacheImmediately: true] as CFDictionary) else {
        throw EngineError.message("Impossible de décoder l’image.")
    }
    let orientation = (properties[kCGImagePropertyOrientation] as? NSNumber)?.int32Value ?? 1
    let oriented = CIImage(cgImage: decoded).oriented(forExifOrientation: orientation)
    let input = oriented.transformed(by: CGAffineTransform(translationX: -oriented.extent.minX,
                                                         y: -oriented.extent.minY))
    let width = Int(input.extent.width)
    let height = Int(input.extent.height)
    let extent = CGRect(x: 0, y: 0, width: width, height: height)
    let context = CIContext(options: [.workingColorSpace: NSNull(), .outputColorSpace: NSNull()])
    let handler = VNImageRequestHandler(ciImage: input, orientation: .up, options: [:])
    var matte: CIImage

    if options.mode == "person" {
        // .accurate includes matting refinement, unlike .balanced/.fast. This is
        // a trained local neural model supplied by macOS, not saliency/GrabCut.
        let request = VNGeneratePersonSegmentationRequest()
        request.qualityLevel = .accurate
        request.outputPixelFormat = kCVPixelFormatType_OneComponent32Float
        try handler.perform([request])
        guard let observation = request.results?.first else {
            throw EngineError.message("Aucune personne détectée. Essayez le mode Sujet.")
        }
        let lowResolution = CIImage(cvPixelBuffer: observation.pixelBuffer)
        let scaleY = CGFloat(height) / lowResolution.extent.height
        let scaleX = CGFloat(width) / lowResolution.extent.width
        // Preserve the soft result; interpolation does not invent hair details.
        matte = lowResolution.applyingFilter("CILanczosScaleTransform", parameters: [
            kCIInputScaleKey: scaleY,
            kCIInputAspectRatioKey: scaleX / scaleY
        ]).cropped(to: extent)
    } else {
        let request = VNGenerateForegroundInstanceMaskRequest()
        try handler.perform([request])
        guard let observation = request.results?.first, !observation.allInstances.isEmpty else {
            throw EngineError.message("Aucun sujet détecté dans cette image.")
        }
        // This API returns a full-resolution, single-channel soft mask. Instance
        // 0 is background; allInstances contains only foreground objects.
        let buffer = try observation.generateScaledMaskForImage(forInstances: observation.allInstances, from: handler)
        matte = CIImage(cvPixelBuffer: buffer).cropped(to: extent)
    }

    // Use the human matte only as a context anchor. The final matte is predicted
    // by a general matting model, which can include a held helmet or equipment.
    matte = try highDefinitionMatte(input: options.input, guide: options.mode == "person" ? matte : nil,
                                   context: context, width: width, height: height)
    let values = renderFloat(matte, context: context, width: width, height: height)
    let sourceAlpha = renderFloat(alphaAsLuminance(input), context: context, width: width, height: height)
    var bytes = [UInt8](repeating: 0, count: width * height)
    var foregroundPixels = 0
    var fractionalPixels = 0
    for index in values.indices {
        let value = values[index].isFinite ? min(1, max(0, values[index])) : 0
        let alpha = sourceAlpha[index].isFinite ? min(1, max(0, sourceAlpha[index])) : 0
        let byte = UInt8((value * alpha * 255).rounded())
        bytes[index] = byte
        if byte > 0 { foregroundPixels += 1 }
        if byte > 0 && byte < 255 { fractionalPixels += 1 }
    }
    guard foregroundPixels > 0 else {
        throw EngineError.message(options.mode == "person"
            ? "Aucune personne détectée. Essayez le mode Sujet."
            : "Le masque du sujet est vide.")
    }
    let gray = try grayscaleImage(bytes: bytes, width: width, height: height)
    try savePNG(gray, to: options.mask)

    if let cutout = options.cutout {
        // The saved mask already includes original alpha. Use an opaque source
        // here, so fractional source alpha is applied exactly once.
        let opaque = input.applyingFilter("CIColorMatrix", parameters: [
            "inputAVector": CIVector(x: 0, y: 0, z: 0, w: 0),
            "inputBiasVector": CIVector(x: 0, y: 0, z: 0, w: 1)
        ])
        let finalMask = CIImage(cgImage: gray, options: [.colorSpace: NSNull()])
        let transparent = CIImage(color: .clear).cropped(to: extent)
        let image = opaque.applyingFilter("CIBlendWithMask", parameters: [
            kCIInputBackgroundImageKey: transparent, kCIInputMaskImageKey: finalMask
        ])
        // RGBA8 requires an RGB output space. A grayscale or CMYK original is
        // valid input, but reusing that profile here would make rendering fail.
        let outputColorSpace: CGColorSpace
        if let originalColorSpace = decoded.colorSpace, originalColorSpace.model == .rgb {
            outputColorSpace = originalColorSpace
        } else {
            outputColorSpace = CGColorSpace(name: CGColorSpace.sRGB)!
        }
        guard let output = context.createCGImage(image, from: extent, format: .RGBA8,
                                                colorSpace: outputColorSpace) else {
            throw EngineError.message("Impossible de créer l’aperçu transparent.")
        }
        try savePNG(output, to: cutout)
    }

    let result: [String: Any] = ["ok": true, "model": "BiRefNet-matting-epoch_100", "inferenceSize": 1024, "mode": options.mode, "width": width, "height": height,
        "foregroundPixels": foregroundPixels, "fractionalPixels": fractionalPixels,
        "seconds": Date().timeIntervalSince(start), "mask": options.mask.path]
    let data = try JSONSerialization.data(withJSONObject: result, options: [.sortedKeys])
    print(String(decoding: data, as: UTF8.self))
}

do {
    let options = try Options.parse()
    guard #available(macOS 14.0, *) else {
        throw EngineError.message("Ce moteur IA nécessite macOS 14 ou une version ultérieure.")
    }
    try autoreleasepool { try run(options) }
} catch {
    fputs("Détourage IA : \(error.localizedDescription)\n", stderr)
    exit(1)
}
