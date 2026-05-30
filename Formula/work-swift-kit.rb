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
  depends_on :macos

  def install
    prefix.install Dir["*"]
  end

  def caveats
    <<~EOS
      To launch the interactive setup:
        wsk install

      To re-link your dotfiles without re-collecting accounts:
        wsk relink
    EOS
  end

  def post_install
    (bin/"wsk").write <<~EOS
      #!/usr/bin/env bash
      WSK_DIR="#{prefix}"
      export WSK_DIR
      case "$1" in
        install) exec bash "$WSK_DIR/install.sh" ;;
        relink)  exec bash "$WSK_DIR/install.sh" --relink ;;
        *)
          echo "Usage: wsk [install|relink]"
          exit 1
          ;;
      esac
    EOS
    chmod 0755, bin/"wsk"
  end

  test do
    assert_predicate prefix/"install.sh", :exist?
  end
end
