import Foundation

#if canImport(Darwin)
import Darwin
#elseif canImport(Glibc)
import Glibc
#endif

// MARK: - ANSI Escape Codes

/// ANSI terminal escape code constants and helpers.
///
/// Used by ``TerminalRenderer`` to produce colored, styled terminal output
/// matching the Claude Code CLI's visual style.
enum ANSI {

    // MARK: Text Styles
    static let reset    = "\u{001B}[0m"
    static let bold     = "\u{001B}[1m"
    static let dim      = "\u{001B}[2m"
    static let italic   = "\u{001B}[3m"

    // MARK: Foreground Colors
    static let red      = "\u{001B}[31m"
    static let green    = "\u{001B}[32m"
    static let yellow   = "\u{001B}[33m"
    static let blue     = "\u{001B}[34m"
    static let magenta  = "\u{001B}[35m"
    static let cyan     = "\u{001B}[36m"
    static let white    = "\u{001B}[37m"
    /// Bright black — renders as dark gray in most terminals.
    static let gray     = "\u{001B}[90m"

    // MARK: Cursor / Line Control
    /// Carriage return + erase to end of line. Use to overwrite the current line.
    static let crClear  = "\r\u{001B}[K"
    /// Move cursor up one line.
    static let cursorUp = "\u{001B}[1A"

    // MARK: Spinner Frames
    /// Braille dot spinner frames — same set used by Claude Code.
    static let spinnerFrames = ["⠋", "⠙", "⠹", "⠸", "⠼", "⠴", "⠦", "⠧", "⠇", "⠏"]

    // MARK: TTY Detection
    /// Returns `true` when stdout is connected to an interactive terminal.
    static var isTTY: Bool { isatty(STDOUT_FILENO) != 0 }

    // MARK: Terminal Width
    /// Returns the current terminal column width, defaulting to 80.
    static var terminalWidth: Int {
        var ws = winsize()
        if ioctl(STDOUT_FILENO, TIOCGWINSZ, &ws) == 0, ws.ws_col > 0 {
            return Int(ws.ws_col)
        }
        return 80
    }
}

// MARK: - Styled String Builder

/// Wraps text in ANSI codes when colors are enabled.
struct StyledText {
    private let useColors: Bool

    init(useColors: Bool) {
        self.useColors = useColors
    }

    func apply(_ codes: String..., to text: String) -> String {
        guard useColors, !codes.isEmpty else { return text }
        return codes.joined() + text + ANSI.reset
    }

    // Convenience wrappers

    func bold(_ text: String)    -> String { apply(ANSI.bold, to: text) }
    func dim(_ text: String)     -> String { apply(ANSI.dim, to: text) }
    func italic(_ text: String)  -> String { apply(ANSI.italic, to: text) }
    func red(_ text: String)     -> String { apply(ANSI.red, to: text) }
    func green(_ text: String)   -> String { apply(ANSI.green, to: text) }
    func yellow(_ text: String)  -> String { apply(ANSI.yellow, to: text) }
    func blue(_ text: String)    -> String { apply(ANSI.blue, to: text) }
    func magenta(_ text: String) -> String { apply(ANSI.magenta, to: text) }
    func cyan(_ text: String)    -> String { apply(ANSI.cyan, to: text) }
    func gray(_ text: String)    -> String { apply(ANSI.gray, to: text) }
    func boldCyan(_ text: String)   -> String { apply(ANSI.bold, ANSI.cyan, to: text) }
    func boldGreen(_ text: String)  -> String { apply(ANSI.bold, ANSI.green, to: text) }
    func boldRed(_ text: String)    -> String { apply(ANSI.bold, ANSI.red, to: text) }
    func boldYellow(_ text: String) -> String { apply(ANSI.bold, ANSI.yellow, to: text) }
}
