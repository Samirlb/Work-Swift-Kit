class WorkSwiftKit < Formula
  desc "Interactive macOS dev environment setup for multi-account workflows"
  homepage "https://github.com/Samirlb/Work-Swift-Kit"
  url "https://github.com/Samirlb/Work-Swift-Kit/archive/refs/tags/v0.1.0.tar.gz"
  sha256 "bd9def49fa3c65a01cbc6e12c5d25d13f4e754041e24ffdcebcc63553e89302a"
  license "MIT"

  depends_on "gum"
  depends_on "gnu-stow"
  depends_on "fzf"
  depends_on "gettext"

  def install
    libexec.install Dir["*"]
    (bin/"wsk").write <<~EOS
      #!/usr/bin/env bash
      exec "#{libexec}/install.sh" "$@"
    EOS
  end

  test do
    assert_predicate bin/"wsk", :exist?
    assert_predicate bin/"wsk", :executable?
  end
end
