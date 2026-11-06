# frozen_string_literal: true

cask "infravibe" do
  version "2.13.0"
  sha256 "606c93eef38f385558c592566f498ac69b0c3d394e18bcb978c008db8eeca951"

  url "https://github.com/netsecdevio/infravibe/releases/download/v#{version}/infravibe-#{version}.dmg"
  name "infravibe"
  desc "Infrastructure, remote terminals, and DevOps monitoring"
  homepage "https://github.com/netsecdevio/infravibe"

  auto_updates true
  depends_on macos: :sequoia

  app "infravibe.app"

  caveats do
    <<~EOS
      infravibe requires macOS 15.5 or later.
      Provider tools and tmux are optional and installed separately.
      Use the in-app updater, or brew upgrade --cask --greedy infravibe.
    EOS
  end
end
