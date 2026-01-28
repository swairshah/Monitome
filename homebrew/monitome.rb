cask "monitome" do
  version "0.1.0"
  sha256 "PLACEHOLDER_SHA256"

  url "https://github.com/swairshah/Monitome/releases/download/v#{version}/Monitome-#{version}.dmg"
  name "Monitome"
  desc "Screenshot activity tracker with AI-powered indexing and search"
  homepage "https://github.com/swairshah/Monitome"

  depends_on macos: ">= :ventura"

  app "Monitome.app"

  postflight do
    # Ensure the activity-agent binary is executable
    set_permissions "#{appdir}/Monitome.app/Contents/MacOS/activity-agent", "755"
  end

  zap trash: [
    "~/Library/Application Support/Monitome",
    "~/Library/Preferences/swair.Monitome.plist",
    "~/Library/Caches/swair.Monitome",
  ]
end
