# Homebrew Cask formula for Uttr (SpeechToTextApp)
#
# To use this formula, you need to create a Homebrew tap:
#   1. Create a new GitHub repo named: homebrew-uttr
#   2. Copy this file to: Casks/uttr.rb in that repo
#   3. Users can then install via:
#      brew tap Rakk301/uttr
#      brew install --cask uttr
#
# Before publishing, update:
#   - version: Match your GitHub release tag (without 'v' prefix)
#   - sha256: Run `shasum -a 256 SpeechToTextApp.zip` on your release artifact

cask "uttr" do
  version "0.1.0"
  sha256 "63ad3382781467923dd25c64a8a4a4cca914608b203f5f27b27baaea15410e08"

  url "https://github.com/Rakk301/homebrew-uttr/releases/download/v#{version}/SpeechToTextApp.zip"
  name "Uttr"
  desc "macOS speech-to-text utility with Whisper and optional LLM post-processing"
  homepage "https://github.com/Rakk301/homebrew-uttr"

  depends_on formula: "uv"
  depends_on macos: ">= :sonoma"

  app "uttr.app"

  caveats <<~EOS
    On first launch, you may need to allow the app in:
      System Settings → Privacy & Security → Open Anyway

    Grant these permissions when prompted:
      - Microphone access (for speech recording)
      - Accessibility access (for global hotkey and paste-at-cursor)
  EOS

  zap trash: [
    "~/Library/Application Support/uttr",
  ]
end
