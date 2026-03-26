import Cocoa
import CoreGraphics

print("🎤 Voice Hotkey Daemon Starting...")
print("Hold Right Command (⌘) to record, release to transcribe")
print("Press Ctrl+C to quit")

var recordingProcess: Process?
var isRecording = false

// Use unique file per recording
func audioPath() -> String {
    "/tmp/voice_ptt_\(Int(Date().timeIntervalSince1970)).wav"
}

var currentAudioFile = audioPath()

// Monitor Right Command key
let monitor = NSEvent.addGlobalMonitorForEvents(matching: .flagsChanged) { event in
    let flags = event.modifierFlags

    // Right Command: keyCode 0x36 (54). Left Command is 0x37 (55).
    let isRightCommand = event.keyCode == 0x36

    // Right Command pressed
    if isRightCommand && flags.contains(.command) && !isRecording {
        isRecording = true
        currentAudioFile = audioPath()
        print("🔴 Recording...")

        recordingProcess = Process()
        recordingProcess?.executableURL = URL(fileURLWithPath: "/opt/homebrew/bin/sox")
        recordingProcess?.arguments = ["-t", "coreaudio", "default", "-r", "16000", "-c", "1", currentAudioFile]

        do {
            try recordingProcess?.run()
        } catch {
            print("❌ Failed to start recording: \(error)")
            isRecording = false
        }
    }
    // Right Command released
    else if isRightCommand && !flags.contains(.command) && isRecording {
        isRecording = false
        print("⏹ Stopped, transcribing...")

        recordingProcess?.terminate()
        recordingProcess = nil

        let file = currentAudioFile

        // Transcribe locally with whisper.cpp
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
            let text = String(data: data, encoding: .utf8)?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""

            print("⏱ \(String(format: "%.2f", elapsed))s")

            if !text.isEmpty {
                print("✅ \(text)")

                // Copy to clipboard
                let pasteboard = NSPasteboard.general
                pasteboard.clearContents()
                pasteboard.setString(text, forType: .string)

                // Auto-paste via CGEvent (Cmd+V) — no osascript dependency
                let src = CGEventSource(stateID: .hidSystemState)
                let vKeyCode: CGKeyCode = 0x09  // 'v'
                if let keyDown = CGEvent(keyboardEventSource: src, virtualKey: vKeyCode, keyDown: true),
                   let keyUp = CGEvent(keyboardEventSource: src, virtualKey: vKeyCode, keyDown: false) {
                    keyDown.flags = .maskCommand
                    keyUp.flags = .maskCommand
                    keyDown.post(tap: .cghidEventTap)
                    keyUp.post(tap: .cghidEventTap)
                }
            } else {
                print("❌ Empty transcription")
            }
        } catch {
            print("❌ Transcription failed: \(error)")
        }

        // Cleanup
        try? FileManager.default.removeItem(atPath: file)
    }
}

// Verify TCC granted Input Monitoring — nil means denied
if monitor == nil {
    print("❌ FATAL: Input monitoring denied by macOS.")
    print("   Grant in: System Settings > Privacy & Security > Input Monitoring → VoiceHotkey.app")
    print("   If already granted, reset with: tccutil reset InputMonitoring")
    exit(1)  // KeepAlive/SuccessfulExit:false will restart after you grant permission
}

print("✅ Input monitoring active. Listening for Right Command key...")

// Keep running
RunLoop.main.run()
