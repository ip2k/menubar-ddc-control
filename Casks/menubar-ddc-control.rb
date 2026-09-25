# Updated automatically by .github/workflows/release.yml after each release.
cask "menubar-ddc-control" do
  version "0.1.0"
  sha256 "a3106319502066b82e1220976109b85960be7ccc0556e55b61c91800e6ee8ec5"

  url "https://github.com/ip2k/menubar-ddc-control/releases/download/v#{version}/Menubar-DDC-Control-#{version}.dmg"
  name "Menubar DDC Control"
  desc "Control DDC/CI monitors, including the CORSAIR XENEON EDGE, from the menu bar"
  homepage "https://github.com/ip2k/menubar-ddc-control"

  livecheck do
    url :url
    strategy :github_latest
  end

  depends_on arch: :arm64
  depends_on macos: ">= :sonoma"

  app "Menubar DDC Control.app"
  binary "#{appdir}/Menubar DDC Control.app/Contents/Resources/ddc-control"

  zap trash: "~/Library/Preferences/com.ip2k.MenubarDDCControl.plist"

  caveats <<~EOS
    Menubar DDC Control is not notarized. If macOS refuses to open it, run:
      xattr -dr com.apple.quarantine "#{appdir}/Menubar DDC Control.app"
  EOS
end
