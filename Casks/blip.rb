cask "blip" do
  version "1.4.2"
  sha256 :no_check

  url "https://github.com/blaineam/blip/releases/download/v#{version}/Blip.dmg"
  name "Blip"
  desc "Featherlight macOS menu bar system monitor"
  homepage "https://blip.wemiller.com"

  depends_on macos: ">= :sonoma"
  depends_on arch: :arm64

  app "Blip.app"

  zap trash: [
    "~/Library/Preferences/com.blainemiller.Blip.plist",
    "~/Library/Saved Application State/com.blainemiller.Blip.savedState",
  ]
end
