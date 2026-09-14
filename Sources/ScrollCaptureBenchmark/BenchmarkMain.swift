import Foundation
import ScrollCaptureCore

struct StepReport: Codable {
    let index: Int
    let fixtureOffset: Int
    let expectedStatus: String
    let observedStatus: String
    let expectedOffset: Int
    let observedOffset: Int
    let expectedEarliestOffset: Int
    let observedEarliestOffset: Int
    let expectedFurthestOffset: Int
    let observedFurthestOffset: Int
    let expectedPlacement: String
    let observedPlacement: String
    let expectedSourceRows: [Int]?
    let observedSourceRows: [Int]?
    let expectedPixelRows: Int
    let observedPixelRows: Int
    let expectedRejection: String?
    let observedRejection: String?
    let pixelExact: Bool
    let confidence: Double
    let elapsedMilliseconds: Double
}

struct CaseReport: Codable {
    let id: String
    let group: String
    let pattern: String
    let variant: String
    let seed: Int
    let width: Int
    let viewportHeight: Int
    let topInset: Int
    let bottomInset: Int
    let screenDepth: Int
    let period: Int?
    let minimumOverlap: Double
    let maximumMeanAbsoluteError: Double
    let ambiguityMargin: Double
    let historyLimit: Int
    let expectedClassification: String
    let observedClassification: String
    let expectedRetainedPixelRows: Int
    let observedRetainedPixelRows: Int
    let expectedPixelsFNV1a64: String
    let observedPixelsFNV1a64: String
    let pixelExact: Bool
    let maximumReferenceCount: Int
    let totalMatchingMilliseconds: Double
    let maximumFrameMilliseconds: Double
    let passed: Bool
    let failures: [String]
    let steps: [StepReport]
}

struct BenchmarkReport: Codable {
    let schemaVersion: Int
    let fixtureVersion: Int
    let generatedAt: String
    let evidenceKind: String
    let limitations: [String]
    let operatingSystem: String
    let totalCases: Int
    let coreCases: Int
    let stressCases: Int
    let passedCases: Int
    let failedCases: Int
    let frames: Int
    let totalWallMilliseconds: Double
    let totalMatchingMilliseconds: Double
    let cases: [CaseReport]
}

@main
struct BenchmarkMain {
    static func main() {
        do {
            let arguments = Array(CommandLine.arguments.dropFirst())
            if arguments == ["--help"] || arguments == ["-h"] {
                print("Usage: ScrollCaptureBenchmark [--output DIRECTORY]\nWrites deterministic synthetic report.json and report.md. Exits 1 when any case fails.")
                return
            }
            let directory: String
            if arguments.isEmpty {
                directory = ".work/core-benchmark"
            } else if arguments.count == 2 && arguments[0] == "--output" {
                directory = arguments[1]
            } else {
                throw CLIError.usage
            }
            let start = ContinuousClock.now
            var cases: [CaseReport] = []
            for fixture in Fixture.all() {
                let result = try run(fixture)
                cases.append(result)
                if !result.passed {
                    print("FAIL \(result.id) \(result.pattern)/\(result.variant): \(result.failures.prefix(3).joined(separator: "; "))")
                }
            }
            let report = BenchmarkReport(
                schemaVersion: 2, fixtureVersion: 2,
                generatedAt: ISO8601DateFormatter().string(from: Date()), evidenceKind: "deterministic_synthetic_core_only",
                limitations: [
                    "Synthetic grayscale canvases; not real G1 acceptance cases, ReplayKit captures, user sessions or device tests.",
                    "Timing is local host matching time and cannot establish iPhone latency, extension memory, energy or thermal budgets.",
                    "Exact output checks compare retained pixels against independently generated ground-truth document canvases.",
                    "Fixtures cover vertical translation and selected failure classes, not universal layouts, transparency, animation or app compatibility.",
                    "Cases are controlled parameter combinations, not independent samples; their pass rate cannot estimate real-world reliability."
                ],
                operatingSystem: ProcessInfo.processInfo.operatingSystemVersionString,
                totalCases: cases.count, coreCases: cases.filter { $0.group == "core" }.count,
                stressCases: cases.filter { $0.group == "stress" }.count,
                passedCases: cases.filter(\.passed).count, failedCases: cases.filter { !$0.passed }.count,
                frames: cases.reduce(0) { $0 + $1.steps.count }, totalWallMilliseconds: elapsed(since: start),
                totalMatchingMilliseconds: cases.reduce(0) { $0 + $1.totalMatchingMilliseconds }, cases: cases)
            let output = URL(fileURLWithPath: directory, isDirectory: true).standardizedFileURL
            try FileManager.default.createDirectory(at: output, withIntermediateDirectories: true)
            let encoder = JSONEncoder()
            encoder.outputFormatting = [.prettyPrinted, .sortedKeys, .withoutEscapingSlashes]
            try encoder.encode(report).write(to: output.appendingPathComponent("report.json"), options: .atomic)
            try markdown(report).write(to: output.appendingPathComponent("report.md"), atomically: true, encoding: .utf8)
            print("Synthetic benchmark: \(report.passedCases)/\(report.totalCases) passed; \(report.coreCases) core + \(report.stressCases) stress; \(report.frames) frames; \(format(report.totalWallMilliseconds)) ms wall.")
            print("Report: \(output.appendingPathComponent("report.json").path)")
            print("Report: \(output.appendingPathComponent("report.md").path)")
            if report.failedCases > 0 { exit(1) }
        } catch {
            FileHandle.standardError.write(Data("Benchmark error: \(error)\n".utf8))
            exit(2)
        }
    }

    private static func run(_ fixture: Fixture) throws -> CaseReport {
        let canvas = Canvas(width: fixture.width, height: fixture.bodyHeight * fixture.depth,
                            pattern: fixture.pattern, seed: fixture.seed, period: fixture.period)
        var stitcher = StreamStitcher(configuration: .init(topInset: fixture.top, bottomInset: fixture.bottom))
        var reports: [StepReport] = []
        var output: [UInt8] = []
        var failures: [String] = []
        var expectedOffset = 0
        var expectedFurthest = 0
        var expectedEarliest = 0
        let origin = fixture.steps.first?.offset ?? 0
        var maximumReferences = 0

        for (index, step) in fixture.steps.enumerated() {
            let frame: GrayFrame
            switch step.input {
            case .document:
                frame = try canvas.frame(offset: step.offset, bodyHeight: fixture.bodyHeight,
                                         top: fixture.top, bottom: fixture.bottom)
            case .animatedDocument:
                let clean = try canvas.frame(offset: step.offset, bodyHeight: fixture.bodyHeight,
                                             top: fixture.top, bottom: fixture.bottom)
                var pixels = clean.pixels
                // Controlled loading changes and a moving thin indicator stay
                // in overlap so emitted strips have an independent clean oracle.
                let patchStart = fixture.top + fixture.bodyHeight / 2
                for y in patchStart..<(patchStart + fixture.bodyHeight / 20) {
                    for x in (fixture.width / 4)..<(fixture.width / 2) {
                        pixels[y * fixture.width + x] = UInt8(100 + index % 60)
                    }
                }
                let indicatorStart = fixture.top + fixture.bodyHeight / 3 + index * 7
                for y in indicatorStart..<(indicatorStart + fixture.bodyHeight / 12) {
                    for x in (fixture.width - 4)..<fixture.width {
                        pixels[y * fixture.width + x] = UInt8(30 + index % 20)
                    }
                }
                frame = try GrayFrame(width: clean.width, height: clean.height, pixels: pixels)
            case .changedScene:
                let other = Canvas(width: fixture.width, height: fixture.bodyHeight * fixture.depth,
                                   pattern: fixture.pattern, seed: fixture.seed + 90_001)
                frame = try other.frame(offset: step.offset, bodyHeight: fixture.bodyHeight,
                                        top: fixture.top, bottom: fixture.bottom)
            case .changedGeometry:
                let other = Canvas(width: fixture.width + 1, height: fixture.bodyHeight * fixture.depth,
                                   pattern: fixture.pattern, seed: fixture.seed)
                frame = try other.frame(offset: step.offset, bodyHeight: fixture.bodyHeight,
                                        top: fixture.top, bottom: fixture.bottom)
            }

            let expectedStatus: StitchDecision.Status
            let expectedRows: Range<Int>?
            let expectedPlacement: StitchDecision.Placement
            let relativeOffset = step.offset - origin
            expectedPlacement = step.expectedRejection == nil && relativeOffset < expectedEarliest ? .prepend : .append
            if step.expectedRejection != nil {
                expectedStatus = .rejected
                expectedRows = nil
            } else if index == 0 {
                expectedStatus = .started
                expectedRows = fixture.top..<(fixture.top + fixture.bodyHeight)
            } else if relativeOffset < expectedEarliest {
                expectedStatus = .advanced
                expectedRows = fixture.top..<(fixture.top + expectedEarliest - relativeOffset)
            } else if relativeOffset > expectedFurthest {
                expectedStatus = .advanced
                expectedRows = (fixture.top + fixture.bodyHeight - (relativeOffset - expectedFurthest))..<(fixture.top + fixture.bodyHeight)
            } else {
                expectedStatus = relativeOffset == expectedOffset ? .unchanged : .backtracked
                expectedRows = nil
            }
            if step.expectedRejection == nil {
                expectedOffset = relativeOffset
                expectedEarliest = min(expectedEarliest, relativeOffset)
                expectedFurthest = max(expectedFurthest, relativeOffset)
            }

            let start = ContinuousClock.now
            let decision = stitcher.ingest(frame)
            let duration = elapsed(since: start)
            maximumReferences = max(maximumReferences, stitcher.referenceCount)
            if let rows = decision.sourceRows {
                if rows.lowerBound >= 0 && rows.upperBound <= frame.height {
                    let pixels = frame.pixels[(rows.lowerBound * frame.width)..<(rows.upperBound * frame.width)]
                    switch decision.placement {
                    case .append: output.append(contentsOf: pixels)
                    case .prepend: output.insert(contentsOf: pixels, at: 0)
                    }
                } else {
                    failures.append("step \(index): output row range outside frame")
                }
            }
            if decision.status != expectedStatus {
                failures.append("step \(index): expected \(expectedStatus.rawValue), got \(decision.status.rawValue)")
            }
            if decision.rejection != step.expectedRejection {
                failures.append("step \(index): rejection expected \(step.expectedRejection?.rawValue ?? "none"), got \(decision.rejection?.rawValue ?? "none")")
            }
            if decision.sourceRows != expectedRows {
                failures.append("step \(index): retained row range differs from ground truth")
            }
            if decision.placement != expectedPlacement {
                failures.append("step \(index): expected placement \(expectedPlacement.rawValue), got \(decision.placement.rawValue)")
            }
            if decision.contentOffset != expectedOffset || decision.furthestOffset != expectedFurthest
                || decision.earliestOffset != expectedEarliest {
                failures.append("step \(index): expected offset/earliest/furthest \(expectedOffset)/\(expectedEarliest)/\(expectedFurthest), got \(decision.contentOffset)/\(decision.earliestOffset)/\(decision.furthestOffset)")
            }
            let expectedRange = ((origin + expectedEarliest) * fixture.width)..<((origin + expectedFurthest + fixture.bodyHeight) * fixture.width)
            let stepPixelExact = output.elementsEqual(canvas.pixels[expectedRange])
            if !stepPixelExact { failures.append("step \(index): output pixels differ from independent document interval") }
            reports.append(StepReport(index: index, fixtureOffset: step.offset,
                                      expectedStatus: expectedStatus.rawValue, observedStatus: decision.status.rawValue,
                                      expectedOffset: expectedOffset, observedOffset: decision.contentOffset,
                                      expectedEarliestOffset: expectedEarliest, observedEarliestOffset: decision.earliestOffset,
                                      expectedFurthestOffset: expectedFurthest, observedFurthestOffset: decision.furthestOffset,
                                      expectedPlacement: expectedPlacement.rawValue, observedPlacement: decision.placement.rawValue,
                                      expectedSourceRows: expectedRows.map { [$0.lowerBound, $0.upperBound] },
                                      observedSourceRows: decision.sourceRows.map { [$0.lowerBound, $0.upperBound] },
                                      expectedPixelRows: expectedRows?.count ?? 0,
                                      observedPixelRows: decision.sourceRows?.count ?? 0,
                                      expectedRejection: step.expectedRejection?.rawValue,
                                      observedRejection: decision.rejection?.rawValue,
                                      pixelExact: stepPixelExact,
                                      confidence: decision.confidence, elapsedMilliseconds: duration))
        }
        let expectedPixelRows = fixture.bodyHeight + expectedFurthest - expectedEarliest
        let expectedPixels = Array(canvas.pixels[((origin + expectedEarliest) * fixture.width)..<((origin + expectedFurthest + fixture.bodyHeight) * fixture.width)])
        let exact = expectedPixels == output
        if !exact { failures.append("retained output pixels differ from ground-truth canvas interval") }
        if maximumReferences > 3 { failures.append("reference count exceeded configured history limit") }

        return CaseReport(id: fixture.id, group: fixture.group, pattern: fixture.pattern.rawValue,
                          variant: fixture.variant, seed: fixture.seed, width: fixture.width,
                          viewportHeight: fixture.bodyHeight, topInset: fixture.top, bottomInset: fixture.bottom,
                          screenDepth: fixture.depth, period: fixture.pattern == .periodic ? fixture.period : nil,
                          minimumOverlap: 0.4, maximumMeanAbsoluteError: 15, ambiguityMargin: 2, historyLimit: 3,
                          expectedClassification: classification(reports.compactMap(\.expectedRejection)),
                          observedClassification: classification(reports.compactMap(\.observedRejection)),
                          expectedRetainedPixelRows: expectedPixelRows, observedRetainedPixelRows: output.count / fixture.width,
                          expectedPixelsFNV1a64: fingerprint(expectedPixels), observedPixelsFNV1a64: fingerprint(output),
                          pixelExact: exact, maximumReferenceCount: maximumReferences,
                          totalMatchingMilliseconds: reports.reduce(0) { $0 + $1.elapsedMilliseconds },
                          maximumFrameMilliseconds: reports.map(\.elapsedMilliseconds).max() ?? 0,
                          passed: failures.isEmpty, failures: failures, steps: reports)
    }

    private static func classification(_ rejections: [String]) -> String {
        if rejections.contains("ambiguous") { return "ambiguous" }
        return rejections.isEmpty ? "complete" : "rejected"
    }

    private static func fingerprint(_ pixels: [UInt8]) -> String {
        var value: UInt64 = 14_695_981_039_346_656_037
        for pixel in pixels { value = (value ^ UInt64(pixel)) &* 1_099_511_628_211 }
        return String(format: "%016llx", value)
    }

    private static func elapsed(since start: ContinuousClock.Instant) -> Double {
        let duration = start.duration(to: .now).components
        return Double(duration.seconds) * 1_000 + Double(duration.attoseconds) / 1_000_000_000_000_000
    }

    private static func format(_ value: Double) -> String { String(format: "%.3f", value) }

    private static func markdown(_ report: BenchmarkReport) -> String {
        var lines = [
            "# 长截图核心算法合成基准报告", "",
            "**证据类型：确定性合成灰度测试，不是 G1 实机验收、用户测试或兼容性通过记录。**", "",
            "- 生成时间：\(report.generatedAt)", "- 夹具版本：\(report.fixtureVersion)",
            "- 运行系统：\(report.operatingSystem)",
            "- 通过：\(report.passedCases) / \(report.totalCases)；失败：\(report.failedCases)",
            "- 常规：\(report.coreCases)；压力：\(report.stressCases)；处理帧数：\(report.frames)",
            "- 总耗时：\(format(report.totalWallMilliseconds)) ms；其中匹配：\(format(report.totalMatchingMilliseconds)) ms", "",
            "常规用例为 7 类画布 × 5 / 10 / 20 屏深度 × 8 种滚动、裁剪或回退方式，包括向上起步、双向穿越与稀疏文字大空白。压力用例覆盖周期歧义、双向断层后恢复、新场景、尺寸变化、重叠不足和低对比度歧义；另有 144×2556 分析区的文字/图文/纹理用例，含停顿、有限加载变化和细滚动条，记录本机匹配耗时。预期拒绝属于通过条件。", "",
            "每帧输出逐像素与独立生成的原始画布已覆盖区间比较，允许在头部添加新内容并保持自然阅读顺序；FNV-1a 64 位指纹便于复核，不用于安全校验。每帧预期/实际位置、两端边界、插入方向、条带行、置信度、拒绝原因和时间在同目录 report.json。", "",
            "分类说明：complete 表示序列没有拒绝；rejected 表示至少一次非歧义拒绝（可能随后恢复）；ambiguous 表示至少一次歧义拒绝。分类不是质量分数，应结合通过列与逐像素一致性。", "",
            "本机时间不代表 iPhone 性能；未测 ReplayKit、内存、耗电、真实页面加载、透明导航栏或视觉接缝。\(report.totalCases) 项是受控参数组合，不是独立现实样本，通过比例不能估计真实成功率。总耗时涵盖夹具生成和验证，不含编译和报告落盘。", "",
            "| 用例 | 组 / 图案 / 方式 | 深度 | 帧 | 预期 / 实际分类 | 预期 / 实际保留行 | 像素一致 | 通过 | 最慢帧 ms |",
            "| --- | --- | ---: | ---: | --- | ---: | --- | --- | ---: |"
        ]
        for item in report.cases {
            lines.append("| \(item.id) | \(item.group) / \(item.pattern) / \(item.variant) | \(item.screenDepth) | \(item.steps.count) | \(item.expectedClassification) / \(item.observedClassification) | \(item.expectedRetainedPixelRows) / \(item.observedRetainedPixelRows) | \(item.pixelExact ? "是" : "否") | \(item.passed ? "通过" : "失败") | \(format(item.maximumFrameMilliseconds)) |")
        }
        for item in report.cases where !item.passed {
            lines += ["", "## \(item.id) 失败详情", ""] + item.failures.map { "- \($0)" }
        }
        return lines.joined(separator: "\n") + "\n"
    }

    private enum CLIError: Error {
        case usage
    }
}
