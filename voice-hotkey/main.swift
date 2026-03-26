import Cocoa
import CoreGraphics

print("🎤 Voice Hotkey Daemon Starting...")
print("Hold Right Command (⌘) to record, release to transcribe")
print("Press Ctrl+C to quit")

// State — guarded by isRecording flag
var recordingProcess: Process?
var isRecording = false
var isTranscribing = false

// Unique temp file per recording with random suffix
func audioPath() -> String {
    let random = String(Int.random(in: 100000...999999))
    return "/tmp/voice_ptt_\(Int(Date().timeIntervalSince1970))_\(random).wav"
}

var currentAudioFile = audioPath()

// Cleanup recording process safely
func stopRecording() {
    if let proc = recordingProcess, proc.isRunning {
        proc.terminate()
    }
    recordingProcess = nil
}

// Clean up temp file
func cleanupAudio(_ path: String) {
    try? FileManager.default.removeItem(atPath: path)
}

// Graceful shutdown
func shutdown() {
    stopRecording()
    cleanupAudio(currentAudioFile)
    exit(0)
}

signal(SIGTERM) { _ in shutdown() }
signal(SIGINT) { _ in shutdown() }

// Transcribe and paste — runs on background queue
func transcribeAndPaste(file: String) {
    guard !isTranscribing else {
        print("⚠️ Already transcribing, skipping")
        cleanupAudio(file)
        return
    }
    isTranscribing = true

    DispatchQueue.global(qos: .userInitiated).async {
        defer {
            isTranscribing = false
            cleanupAudio(file)
        }

        // Verify file exists and has content
        guard FileManager.default.fileExists(atPath: file),
              let attrs = try? FileManager.default.attributesOfItem(atPath: file),
              let size = attrs[.size] as? Int, size > 1000 else {
            print("❌ Audio file too small or missing — skipped")
            return
        }

        let transcribe = Process()
        transcribe.executableURL = URL(fileURLWithPath: "/opt/homebrew/opt/whisper-cpp/bin/whisper-cli")
        transcribe.arguments = [
            "-m", "/opt/homebrew/share/whisper-cpp/models/ggml-tiny.en.bin",
            "-f", file,
            "--no-prints",
            "--no-timestamps",
            "-l", "en"
        ]

        let pipe = Pipe()
        transcribe.standardOutput = pipe
        transcribe.standardError = FileHandle.nullDevice

        do {
            let start = Date()
            try transcribe.run()
            transcribe.waitUntilExit()
            let elapsed = Date().timeIntervalSince(start)

            let data = pipe.fileHandleForReading.readDataToEndOfFile()
            let text = String(data: data, encoding: .utf8)?
                .trimmingCharacters(in: .whitespacesAndNewlines) ?? ""

            print("⏱ \(String(format: "%.2f", elapsed))s")

            guard !text.isEmpty else {
                print("❌ Empty transcription")
                return
            }

            print("✅ \(text)")

            // Clipboard + paste must happen on main thread
            DispatchQueue.main.async {
                let pasteboard = NSPasteboard.general
                pasteboard.clearContents()
                pasteboard.setString(text, forType: .string)

                // Small delay to ensure clipboard is ready
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.05) {
                    let src = CGEventSource(stateID: .hidSystemState)
                    let vKeyCode: CGKeyCode = 0x09  // 'v'
                    if let keyDown = CGEvent(keyboardEventSource: src, virtualKey: vKeyCode, keyDown: true),
                       let keyUp = CGEvent(keyboardEventSource: src, virtualKey: vKeyCode, keyDown: false) {
                        keyDown.flags = .maskCommand
                        keyUp.flags = .maskCommand
                        keyDown.post(tap: .cghidEventTap)
                        keyUp.post(tap: .cghidEventTap)
                    }
                }
            }
        } catch {
            print("❌ Transcription failed: \(error)")
        }
    }
}

// Monitor Right Command key
let monitor = NSEvent.addGlobalMonitorForEvents(matching: .flagsChanged) { event in
    let isRightCommand = event.keyCode == 0x36
    let flags = event.modifierFlags

    // Right Command pressed — start recording
    if isRightCommand && flags.contains(.command) && !isRecording {
        // Guard against starting while transcribing
        guard !isTranscribing else { return }

        isRecording = true
        currentAudioFile = audioPath()
        print("🔴 Recording...")

        let proc = Process()
        proc.executableURL = URL(fileURLWithPath: "/opt/homebrew/bin/sox")
        proc.arguments = ["-t", "coreaudio", "default", "-r", "16000", "-c", "1", currentAudioFile]

        do {
            try proc.run()
            recordingProcess = proc
        } catch {
            print("❌ Failed to start recording: \(error)")
            isRecording = false
            cleanupAudio(currentAudioFile)
        }
    }
    // Right Command released — stop and transcribe
    else if isRightCommand && !flags.contains(.command) && isRecording {
        isRecording = false
        print("⏹ Stopped, transcribing...")

        stopRecording()

        // Brief delay for sox to flush the file
        let file = currentAudioFile
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) {
            transcribeAndPaste(file: file)
        }
    }
}

// Verify TCC granted Input Monitoring
if monitor == nil {
    print("❌ FATAL: Input monitoring denied by macOS.")
    print("   Grant in: System Settings > Privacy & Security > Input Monitoring → VoiceHotkey.app")
    print("   If already granted, reset with: tccutil reset InputMonitoring")
    exit(1)
}

print("✅ Input monitoring active. Listening for Right Command key...")

RunLoop.main.run()
