import AVFoundation
import Foundation
import FluidAudio

struct BenchRow {
    let clip: String
    let duration: Double
    let processing: Double
    let rtfx: Float
    let transcript: String
}

@main
struct Benchmark {
    static func main() async {
        do {
            try await run()
            exit(0)
        } catch {
            fputs("error: \(error.localizedDescription)\n", stderr)
            exit(1)
        }
    }

    static func run() async throws {
        let args = Array(CommandLine.arguments.dropFirst())
        var version: AsrModelVersion = .v3
        var markdown = false
        var tsv = false
        var audioPaths: [String] = []

        var i = 0
        while i < args.count {
            switch args[i] {
            case "--v2":       version = .v2
            case "--v3":       version = .v3
            case "--markdown": markdown = true
            case "--tsv":      tsv = true
            default:           audioPaths.append(args[i])
            }
            i += 1
        }

        guard !audioPaths.isEmpty else {
            fputs("usage: bench [--v2|--v3] [--markdown|--tsv] <clip.aiff> ...\n", stderr)
            exit(1)
        }

        let versionLabel = version == .v3
            ? "Parakeet v3 (FluidAudio/ANE)"
            : "Parakeet v2 (FluidAudio/ANE)"

        // Warm load — assumes models are already downloaded
        printErr("Loading \(versionLabel) from cache…")
        let loadStart = Date()
        let models = try await AsrModels.loadFromCache(version: version)
        let loadTime = Date().timeIntervalSince(loadStart)
        let asr = AsrManager(config: .default, models: models)
        printErr("Loaded in \(String(format: "%.2f", loadTime))s\n")

        var rows: [BenchRow] = []
        for path in audioPaths {
            let url = URL(fileURLWithPath: path)
            printErr("Transcribing \(url.lastPathComponent)…")

            // Measure duration independently — ASRResult.duration is 0 on the streaming
            // path (files > 30s), so we read it from the file header directly.
            let audioFile = try AVAudioFile(forReading: url)
            let duration = Double(audioFile.length) / audioFile.processingFormat.sampleRate

            var state = TdtDecoderState.make()
            let r = try await asr.transcribe(url, decoderState: &state)
            let rtfx = Float(duration / r.processingTime)
            rows.append(BenchRow(
                clip: url.lastPathComponent,
                duration: duration,
                processing: r.processingTime,
                rtfx: rtfx,
                transcript: r.text
            ))
        }

        if tsv {
            printTSV(version: versionLabel, rows: rows)
        } else if markdown {
            printMarkdown(version: versionLabel, loadTime: loadTime, rows: rows)
        } else {
            printTable(version: versionLabel, loadTime: loadTime, rows: rows)
        }
    }
}

// MARK: - Output

// TSV format: model \t clip \t duration \t inferTime \t rtfx
// Used by run.sh to assemble the combined comparison table.
private func printTSV(version: String, rows: [BenchRow]) {
    for r in rows {
        print("\(version)\t\(r.clip)\t\(String(format: "%.1f", r.duration))\t\(String(format: "%.2f", r.processing))\t\(String(format: "%.1f", r.rtfx))")
    }
}

private func printTable(version: String, loadTime: Double, rows: [BenchRow]) {
    let divider = String(repeating: "─", count: 88)
    print("FluidAudio  \(version)")
    print(String(format: "Model load (warm)   %.2fs", loadTime))
    print("")
    print(String(format: "  %-22s  %8s  %10s  %6s  %s",
        "Clip", "Duration", "Infer", "RTFx", "Transcript"))
    print(divider)
    for r in rows {
        let preview = String(r.transcript.prefix(46)).replacingOccurrences(of: "\n", with: " ")
        let ellipsis = r.transcript.count > 46 ? "…" : ""
        print(String(format: "  %-22s  %7.1fs  %9.2fs  %5.1fx  \"%s%s\"",
            r.clip, r.duration, r.processing, r.rtfx, preview, ellipsis))
    }
    print(divider)
    if rows.count > 1 {
        let avgRtfx = rows.map(\.rtfx).reduce(0, +) / Float(rows.count)
        print(String(format: "  %-22s  %8s  %10s  %5.1fx", "average", "─", "─", avgRtfx))
    }
}

private func printMarkdown(version: String, loadTime: Double, rows: [BenchRow]) {
    print("### FluidAudio benchmark — \(version)")
    print("")
    print(String(format: "**Model load (warm):** %.2fs", loadTime))
    print("")
    print("| Clip | Duration | Infer time | RTFx |")
    print("|------|----------|------------|------|")
    for r in rows {
        print(String(format: "| %@ | %.1fs | %.2fs | %.1fx |",
            r.clip, r.duration, r.processing, r.rtfx))
    }
    if rows.count > 1 {
        let avgRtfx = rows.map(\.rtfx).reduce(0, +) / Float(rows.count)
        print(String(format: "| **avg** | — | — | **%.1fx** |", avgRtfx))
    }
    print("")
    print("<details><summary>Transcripts</summary>")
    print("")
    for r in rows {
        print("**\(r.clip)**")
        print("> \(r.transcript)")
        print("")
    }
    print("</details>")
}

private func printErr(_ s: String) {
    fputs(s + "\n", stderr)
}
