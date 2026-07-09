import AppKit
import ApplicationServices
import CoreGraphics
import Foundation

private func rgb(_ red: CGFloat, _ green: CGFloat, _ blue: CGFloat, _ alpha: CGFloat = 1) -> NSColor {
    NSColor(calibratedRed: red / 255, green: green / 255, blue: blue / 255, alpha: alpha)
}

private func clamp<T: Comparable>(_ value: T, _ minimum: T, _ maximum: T) -> T {
    min(max(value, minimum), maximum)
}

private func fill(_ rect: CGRect, _ color: NSColor) {
    color.setFill()
    NSBezierPath(rect: rect).fill()
}

private func stroke(_ rect: CGRect, _ color: NSColor, width: CGFloat = 1) {
    color.setStroke()
    let path = NSBezierPath(rect: rect)
    path.lineWidth = width
    path.stroke()
}

private func line(from start: CGPoint, to end: CGPoint, color: NSColor, width: CGFloat = 1) {
    color.setStroke()
    let path = NSBezierPath()
    path.lineWidth = width
    path.move(to: start)
    path.line(to: end)
    path.stroke()
}

private func ellipse(_ rect: CGRect, fill color: NSColor) {
    color.setFill()
    NSBezierPath(ovalIn: rect).fill()
}

private enum VerticalTextAlignment {
    case top
    case center
}

private func drawText(
    _ text: String,
    font: NSFont,
    color: NSColor,
    in rect: CGRect,
    alignment: NSTextAlignment = .left,
    vertical: VerticalTextAlignment = .top
) {
    guard rect.width > 0, rect.height > 0, !text.isEmpty else {
        return
    }

    let paragraph = NSMutableParagraphStyle()
    paragraph.alignment = alignment
    paragraph.lineBreakMode = .byTruncatingTail

    let attributes: [NSAttributedString.Key: Any] = [
        .font: font,
        .foregroundColor: color,
        .paragraphStyle: paragraph
    ]

    let lineHeight = font.ascender - font.descender + font.leading
    let y: CGFloat = switch vertical {
    case .top:
        rect.minY
    case .center:
        rect.minY + max(0, (rect.height - lineHeight) / 2) - 1
    }

    let drawRect = CGRect(x: rect.minX, y: y, width: rect.width, height: max(rect.height, lineHeight + 4))
    (text as NSString).draw(
        with: drawRect,
        options: [.usesLineFragmentOrigin, .truncatesLastVisibleLine],
        attributes: attributes
    )
}

private func measureText(_ text: String, font: NSFont) -> CGFloat {
    guard !text.isEmpty else {
        return 0
    }

    return (text as NSString).size(withAttributes: [.font: font]).width
}

private struct InputModifiers {
    var control = false
    var shift = false
    var command = false
    var option = false

    init() {}

    init(_ flags: NSEvent.ModifierFlags) {
        control = flags.contains(.control)
        shift = flags.contains(.shift)
        command = flags.contains(.command)
        option = flags.contains(.option)
    }

    init(_ flags: CGEventFlags) {
        control = flags.contains(.maskControl)
        shift = flags.contains(.maskShift)
        command = flags.contains(.maskCommand)
        option = flags.contains(.maskAlternate)
    }
}

private enum MacKeyCode {
    static let q = 12
    static let tab = 48
    static let space = 49
    static let delete = 51
    static let returnKey = 36
    static let keypadEnter = 76

    static let modifiers: Set<Int> = [54, 55, 56, 57, 58, 59, 60, 61, 62, 63]
}

private struct ProjectInfo {
    let name: String
    let detail: String
    let baseProgress: Int
    let files: [String]
}

private enum ParticleMode {
    case stars
    case dots
    case blocks
    case pluses
}

private struct ParticleOption {
    let label: String
    let mode: ParticleMode
    let palette: [NSColor]
}

private struct DiffLine {
    let marker: Character
    let text: String
}

private struct Sparkle {
    var position: CGPoint
    var velocity: CGVector
    var age: Int
    var lifespan: Int
    var size: CGFloat
    var color: NSColor
    var mode: ParticleMode
}

private final class ToddlerCoderView: NSView {
    private let kioskMode: Bool
    private let requestAdultExit: () -> Void

    private var lines: [String] = [""]
    private var sparkles: [Sparkle] = []
    private var particleButtonBounds: [CGRect] = Array(repeating: .zero, count: 4)
    private var terminalLines: [String] = []
    private var diffLines: [DiffLine] = []
    private var random = SystemRandomNumberGenerator()
    private var timer: Timer?
    private var scriptIndex = 0
    private var typedLength = 0
    private var keyCount = 0
    private var pulse = 0
    private var activeProjectIndex = 0
    private var particleOptionIndex = 0
    private var typingParticleOrigin: CGPoint = .zero
    private var currentBanner = ""
    private var bannerTicks = 0
    private var exitHoldProgress: CGFloat = 0
    private var exitHoldStartedAt: Date?
    private var didRequestExit = false
    private var pressedKeyCodes: Set<Int> = []
    private var currentModifiers = InputModifiers()
    private var guardStatus = "local guard"

    private let codeFont = NSFont.monospacedSystemFont(ofSize: 30, weight: .regular)
    private let diffFont = NSFont.monospacedSystemFont(ofSize: 18, weight: .regular)
    private let smallFont = NSFont.systemFont(ofSize: 16)
    private let tinyFont = NSFont.systemFont(ofSize: 13)
    private let titleFont = NSFont.systemFont(ofSize: 20, weight: .semibold)
    private let bannerFont = NSFont.systemFont(ofSize: 30, weight: .semibold)

    private let appBackground = rgb(13, 17, 23)
    private let panel = rgb(22, 27, 34)
    private let panelSoft = rgb(28, 34, 43)
    private let sidebar = rgb(18, 22, 29)
    private let gutter = rgb(17, 21, 27)
    private let lineNumber = rgb(99, 113, 128)
    private let normalCode = rgb(214, 223, 231)
    private let keyword = rgb(111, 211, 187)
    private let stringColor = rgb(242, 191, 111)
    private let comment = rgb(119, 139, 151)
    private let number = rgb(169, 205, 255)
    private let accent = rgb(139, 171, 255)
    private let softText = rgb(159, 172, 184)
    private let mutedText = rgb(114, 127, 140)
    private let active = rgb(39, 48, 61)
    private let plusBackground = rgb(22, 54, 42)
    private let minusBackground = rgb(61, 35, 37)
    private let plusText = rgb(151, 235, 178)
    private let minusText = rgb(255, 165, 165)
    private let divider = rgb(47, 57, 69)
    private let softDivider = rgb(34, 42, 52)
    private let cursor = rgb(242, 191, 111)

    private static let projects: [ProjectInfo] = [
        ProjectInfo(name: "blocks-bot", detail: "build helper", baseProgress: 42, files: ["Builder.cs", "Robot.cs", "Blocks.test.cs", "Tower.cs", "StackRules.cs", "BuildSounds.cs", "BlockColors.cs"]),
        ProjectInfo(name: "moon-lights", detail: "soft glow", baseProgress: 68, files: ["Glow.cs", "Moon.cs", "NightMode.cs", "Stars.cs", "SleepySky.cs", "Dimmer.cs", "Clouds.cs"]),
        ProjectInfo(name: "snack-timer", detail: "very important", baseProgress: 17, files: ["Timer.cs", "Crackers.cs", "Milk.cs", "SnackBell.cs", "TinyPlate.cs", "Napkin.cs", "Refill.cs"]),
        ProjectInfo(name: "train-builder", detail: "tiny engine", baseProgress: 84, files: ["Track.cs", "Engine.cs", "Tunnel.cs", "Signals.cs", "Carriages.cs", "Bridge.cs", "Station.cs"]),
        ProjectInfo(name: "button-lab", detail: "tap tests", baseProgress: 31, files: ["Buttons.cs", "Beep.cs", "Squish.cs", "Knobs.cs", "Switches.cs", "ButtonTests.cs", "Lights.cs"])
    ]

    private static let particleOptions: [ParticleOption] = [
        ParticleOption(label: "sunny", mode: .stars, palette: [rgb(255, 220, 112), rgb(242, 191, 111), rgb(255, 243, 181)]),
        ParticleOption(label: "ocean", mode: .dots, palette: [rgb(118, 198, 255), rgb(139, 171, 255), rgb(111, 211, 187)]),
        ParticleOption(label: "garden", mode: .blocks, palette: [rgb(132, 222, 151), rgb(111, 211, 187), rgb(190, 230, 125)]),
        ParticleOption(label: "candy", mode: .pluses, palette: [rgb(255, 159, 203), rgb(199, 160, 255), rgb(255, 196, 222)])
    ]

    private static let script = [
        "using TinyHands.Playground;",
        "using TinyHands.Review;",
        "",
        "var plan = new ProjectPlan(\"blocks-bot\");",
        "plan.AddStep(\"open workspace\");",
        "plan.AddStep(\"write helpful code\");",
        "plan.AddStep(\"make daddy proud\");",
        "",
        "while (keyboard.IsMashing)",
        "{",
        "    editor.TypeLikeDaddy();",
        "    diff.ShowTinyChanges();",
        "    tests.RunSoftly();",
        "    build.SaveProgress();",
        "}",
        "",
        "if (snackTime.IsReady)",
        "{",
        "    console.WriteLine(\"ship snack timer\");",
        "    project.Status = Status.Ready;",
        "}",
        "",
        "for (var block = 0; block < 10; block++)",
        "{",
        "    tower.Place(block);",
        "    lights.GlowSoftly();",
        "    robot.Wave();",
        "}",
        "",
        "// review notes from the tiny teammate",
        "review.MarkNice(\"gentle colors\");",
        "review.MarkNice(\"good button noises\");",
        "review.Approve();",
        "",
        "await cloud.SendHighFiveAsync();",
        "workspace.Commit(\"tiny coder changes\");",
        "console.WriteLine(\"build succeeded\");"
    ]

    private static let terminalMessages = [
        "[ok] saved blocks-bot",
        "[run] drawing calm stars",
        "[test] buttons are working",
        "[build] checking tiny project",
        "[ok] robot wave complete",
        "[run] reviewing changes",
        "[ok] build succeeded",
        "[save] all work tucked in"
    ]

    private static let diffSnippets: [(minus: String, plus: String)] = [
        ("robot.Speed = Fast;", "robot.Speed = Gentle;"),
        ("screen.Theme = Theme.Bright;", "screen.Theme = Theme.Calm;"),
        ("tower.Blocks = 4;", "tower.Blocks = 10;"),
        ("snack.Ready = false;", "snack.Ready = true;"),
        ("button.Sound = Loud;", "button.Sound = SoftBeep;"),
        ("review.Status = Pending;", "review.Status = Approved;"),
        ("lights.Mode = Flash;", "lights.Mode = Glow;"),
        ("train.Cars = 1;", "train.Cars = 3;")
    ]

    private static let keywords: Set<String> = [
        "await", "bool", "class", "const", "false", "for", "if", "int", "new",
        "return", "static", "string", "true", "using", "var", "while"
    ]

    private let exitHoldSeconds: TimeInterval = 3

    override var isFlipped: Bool { true }
    override var acceptsFirstResponder: Bool { true }

    init(kioskMode: Bool, requestAdultExit: @escaping () -> Void) {
        self.kioskMode = kioskMode
        self.requestAdultExit = requestAdultExit
        super.init(frame: .zero)

        wantsLayer = true
        layer?.backgroundColor = appBackground.cgColor
        terminalLines = ["[ready] workspace opened", "[hint] keyboard connected"]
        seedDiff()

        timer = Timer.scheduledTimer(withTimeInterval: 0.12, repeats: true) { [weak self] _ in
            self?.tick()
        }
        if let timer {
            RunLoop.main.add(timer, forMode: .common)
        }
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    deinit {
        timer?.invalidate()
    }

    func setGuardStatus(_ status: String) {
        guardStatus = status
        needsDisplay = true
    }

    func guardedKeyDown(keyCode: Int, modifiers: InputModifiers) {
        currentModifiers = modifiers
        pressedKeyCodes.insert(keyCode)

        if isExitChordDown {
            startExitHold()
            needsDisplay = true
            return
        }

        if MacKeyCode.modifiers.contains(keyCode) {
            return
        }

        handleMash(keyCode: keyCode)
    }

    func guardedKeyUp(keyCode: Int, modifiers: InputModifiers) {
        currentModifiers = modifiers
        pressedKeyCodes.remove(keyCode)
        refreshExitHoldState()
    }

    func guardedFlagsChanged(modifiers: InputModifiers) {
        currentModifiers = modifiers
        refreshExitHoldState()
    }

    override func viewDidMoveToWindow() {
        super.viewDidMoveToWindow()
        window?.makeFirstResponder(self)
    }

    override func keyDown(with event: NSEvent) {
        guardedKeyDown(keyCode: Int(event.keyCode), modifiers: InputModifiers(event.modifierFlags))
    }

    override func keyUp(with event: NSEvent) {
        guardedKeyUp(keyCode: Int(event.keyCode), modifiers: InputModifiers(event.modifierFlags))
    }

    override func flagsChanged(with event: NSEvent) {
        guardedFlagsChanged(modifiers: InputModifiers(event.modifierFlags))
    }

    override func mouseMoved(with event: NSEvent) {
        let location = convert(event.locationInWindow, from: nil)
        addSparkles(at: location)
        needsDisplay = true
    }

    override func mouseDragged(with event: NSEvent) {
        mouseMoved(with: event)
    }

    override func mouseDown(with event: NSEvent) {
        let location = convert(event.locationInWindow, from: nil)
        _ = trySelectParticleMode(at: location)
        addSparkles(at: location, countOverride: Int.random(in: 20...25, using: &random))
        needsDisplay = true
    }

    override func draw(_ dirtyRect: NSRect) {
        super.draw(dirtyRect)

        fill(bounds, appBackground)

        let width = bounds.width
        let height = bounds.height
        let headerHeight: CGFloat = 50
        let statusHeight: CGFloat = 32
        let sidebarWidth = clamp(width / 5, 210, 300)
        var diffWidth = clamp(width * 0.38, 360, 600)

        if width - sidebarWidth - diffWidth < 390 {
            diffWidth = max(300, width - sidebarWidth - 390)
        }

        let header = CGRect(x: 0, y: 0, width: width, height: headerHeight)
        let status = CGRect(x: 0, y: height - statusHeight, width: width, height: statusHeight)
        let sidebarRect = CGRect(x: 0, y: header.maxY, width: sidebarWidth, height: height - headerHeight - statusHeight)
        let diff = CGRect(x: width - diffWidth, y: header.maxY, width: diffWidth, height: height - headerHeight - statusHeight)
        let center = CGRect(x: sidebarRect.maxX, y: header.maxY, width: max(0, diff.minX - sidebarRect.maxX), height: height - headerHeight - statusHeight)

        drawHeader(in: header)
        drawSidebar(in: sidebarRect)
        drawWorkspace(in: center)
        drawDiffPane(in: diff)
        drawStatus(in: status)
        drawSparkles()
        drawBanner(width: width)
    }

    private func tick() {
        pulse += 1
        updateSparkles()
        updateExitHold()

        if bannerTicks > 0 {
            bannerTicks -= 1
        }

        needsDisplay = true
    }

    private var isExitChordDown: Bool {
        pressedKeyCodes.contains(MacKeyCode.q) && currentModifiers.control && currentModifiers.shift
    }

    private func startExitHold() {
        if exitHoldStartedAt == nil {
            exitHoldStartedAt = Date()
        }
    }

    private func refreshExitHoldState() {
        if isExitChordDown {
            startExitHold()
        } else {
            exitHoldStartedAt = nil
            exitHoldProgress = 0
        }
    }

    private func updateExitHold() {
        guard !didRequestExit else {
            return
        }

        guard isExitChordDown else {
            exitHoldStartedAt = nil
            exitHoldProgress = 0
            return
        }

        startExitHold()

        guard let exitHoldStartedAt else {
            return
        }

        let elapsed = Date().timeIntervalSince(exitHoldStartedAt)
        exitHoldProgress = clamp(CGFloat(elapsed / exitHoldSeconds), 0, 1)

        if exitHoldProgress >= 1 {
            didRequestExit = true
            requestAdultExit()
        }
    }

    private func handleMash(keyCode: Int) {
        keyCount += 1

        let amount: Int = switch keyCode {
        case MacKeyCode.returnKey, MacKeyCode.keypadEnter:
            12
        case MacKeyCode.space:
            8
        case MacKeyCode.delete:
            3
        case MacKeyCode.tab:
            10
        default:
            Int.random(in: 2...6, using: &random)
        }

        advanceTyping(amount: amount)
        addSparkles(at: typingOrigin(), countOverride: Int.random(in: 5...10, using: &random))

        if keyCount % 4 == 0 {
            addDiffChange()
        }

        if keyCount % 7 == 0 {
            addTerminalMessage(Self.terminalMessages.randomElement(using: &random) ?? "[ok] saved")
        }

        if keyCount % 17 == 0 {
            activeProjectIndex = (activeProjectIndex + 1) % Self.projects.count
            addDiffHeader(project: Self.projects[activeProjectIndex])
        }

        if keyCount % 31 == 0 {
            currentBanner = ["build succeeded", "review approved", "project saved"].randomElement(using: &random) ?? "project saved"
            bannerTicks = 28
        }

        needsDisplay = true
    }

    private func advanceTyping(amount: Int) {
        for _ in 0..<amount {
            let target = Self.script[scriptIndex]

            if typedLength >= target.count {
                moveToNextLine()
                continue
            }

            let index = target.index(target.startIndex, offsetBy: typedLength + 1)
            lines[lines.count - 1] = String(target[..<index])
            typedLength += 1
        }
    }

    private func moveToNextLine() {
        scriptIndex = (scriptIndex + 1) % Self.script.count
        typedLength = 0
        lines.append("")

        while lines.count > 160 {
            lines.removeFirst()
        }
    }

    private func addTerminalMessage(_ message: String) {
        terminalLines.append(message)

        while terminalLines.count > 5 {
            terminalLines.removeFirst()
        }
    }

    private func trySelectParticleMode(at location: CGPoint) -> Bool {
        for index in 0..<min(particleButtonBounds.count, Self.particleOptions.count) {
            if particleButtonBounds[index].contains(location) {
                particleOptionIndex = index
                sparkles.removeAll()
                return true
            }
        }

        return false
    }

    private func addSparkles(at location: CGPoint, countOverride: Int = 0) {
        let count = countOverride > 0 ? countOverride : Int.random(in: 1...2, using: &random)
        let option = Self.particleOptions[particleOptionIndex]

        for _ in 0..<count {
            let angle = CGFloat.random(in: 0..<(CGFloat.pi * 2), using: &random)
            let speed = CGFloat.random(in: 0.7...2.1, using: &random)
            let color = option.palette.randomElement(using: &random) ?? option.palette[0]
            let offsetX = CGFloat(Int.random(in: -6...6, using: &random))
            let offsetY = CGFloat(Int.random(in: -6...6, using: &random))

            sparkles.append(Sparkle(
                position: CGPoint(x: location.x + offsetX, y: location.y + offsetY),
                velocity: CGVector(dx: cos(angle) * speed, dy: sin(angle) * speed - 0.4),
                age: 0,
                lifespan: Int.random(in: 14...23, using: &random),
                size: CGFloat.random(in: 3.5...8.0, using: &random),
                color: color,
                mode: option.mode
            ))
        }

        while sparkles.count > 90 {
            sparkles.removeFirst()
        }
    }

    private func updateSparkles() {
        guard !sparkles.isEmpty else {
            return
        }

        for index in stride(from: sparkles.count - 1, through: 0, by: -1) {
            sparkles[index].age += 1
            sparkles[index].position.x += sparkles[index].velocity.dx
            sparkles[index].position.y += sparkles[index].velocity.dy
            sparkles[index].velocity.dx *= 0.93
            sparkles[index].velocity.dy = sparkles[index].velocity.dy * 0.93 + 0.03

            if sparkles[index].age >= sparkles[index].lifespan {
                sparkles.remove(at: index)
            }
        }
    }

    private func seedDiff() {
        addDiffHeader(project: Self.projects[0])
        diffLines.append(DiffLine(marker: " ", text: "  while (keyboard.IsMashing)"))
        diffLines.append(DiffLine(marker: "-", text: "      screen.Theme = Theme.Bright;"))
        diffLines.append(DiffLine(marker: "+", text: "      screen.Theme = Theme.Calm;"))
        diffLines.append(DiffLine(marker: "+", text: "      diff.ShowTinyChanges();"))
    }

    private func addDiffHeader(project: ProjectInfo) {
        diffLines.append(DiffLine(marker: " ", text: "diff --git a/\(project.name)/Builder.cs b/\(project.name)/Builder.cs"))
        diffLines.append(DiffLine(marker: " ", text: "@@ tiny workspace @@"))
        trimDiff()
    }

    private func addDiffChange() {
        let snippet = Self.diffSnippets.randomElement(using: &random) ?? Self.diffSnippets[0]
        diffLines.append(DiffLine(marker: " ", text: "  tiny.ChangeSet.Apply();"))
        diffLines.append(DiffLine(marker: "-", text: "  \(snippet.minus)"))
        diffLines.append(DiffLine(marker: "+", text: "  \(snippet.plus)"))
        trimDiff()
    }

    private func trimDiff() {
        while diffLines.count > 60 {
            diffLines.removeFirst()
        }
    }

    private func drawHeader(in rect: CGRect) {
        fill(rect, panel)
        line(from: CGPoint(x: rect.minX, y: rect.maxY - 1), to: CGPoint(x: rect.maxX, y: rect.maxY - 1), color: divider)

        ellipse(CGRect(x: 18, y: 19, width: 12, height: 12), fill: rgb(239, 112, 112))
        ellipse(CGRect(x: 38, y: 19, width: 12, height: 12), fill: rgb(242, 191, 111))
        ellipse(CGRect(x: 58, y: 19, width: 12, height: 12), fill: rgb(112, 211, 151))

        let logo = CGRect(x: 88, y: 11, width: 104, height: 28)
        fill(logo, rgb(36, 45, 57))
        drawText("tiny codex", font: smallFont, color: normalCode, in: logo, alignment: .center, vertical: .center)

        let title = CGRect(x: 212, y: 12, width: max(100, rect.width - 480), height: 28)
        drawText("workspace / little-coder", font: titleFont, color: normalCode, in: title)

        let mode = kioskMode ? "kid mode" : "debug windowed"
        let modeRect = CGRect(x: rect.maxX - 180, y: 14, width: 150, height: 24)
        drawText(mode, font: smallFont, color: softText, in: modeRect, alignment: .right)
    }

    private func drawSidebar(in rect: CGRect) {
        fill(rect, sidebar)
        line(from: CGPoint(x: rect.maxX - 1, y: rect.minY), to: CGPoint(x: rect.maxX - 1, y: rect.maxY), color: divider)

        drawText("Projects", font: titleFont, color: normalCode, in: CGRect(x: rect.minX + 18, y: rect.minY + 18, width: rect.width - 36, height: 24))
        drawText("tiny workspaces", font: smallFont, color: mutedText, in: CGRect(x: rect.minX + 18, y: rect.minY + 45, width: rect.width - 36, height: 20))

        var y = rect.minY + 82
        for index in Self.projects.indices {
            drawProjectItem(Self.projects[index], index: index, sidebar: rect, y: y)
            y += 72
        }

        let fileTop = y + 20
        line(from: CGPoint(x: rect.minX + 18, y: fileTop), to: CGPoint(x: rect.maxX - 18, y: fileTop), color: softDivider)
        drawText("Files", font: smallFont, color: softText, in: CGRect(x: rect.minX + 18, y: fileTop + 18, width: rect.width - 36, height: 22))

        y = fileTop + 50
        for file in Self.projects[activeProjectIndex].files {
            if y + 24 > rect.maxY - 12 {
                break
            }

            drawText(file, font: smallFont, color: normalCode, in: CGRect(x: rect.minX + 28, y: y, width: rect.width - 46, height: 24))
            y += 26
        }
    }

    private func drawProjectItem(_ project: ProjectInfo, index: Int, sidebar: CGRect, y: CGFloat) {
        let item = CGRect(x: sidebar.minX + 10, y: y, width: sidebar.width - 20, height: 60)
        let isActive = index == activeProjectIndex

        if isActive {
            fill(item, active)
        }

        drawText(project.name, font: smallFont, color: isActive ? normalCode : softText, in: CGRect(x: item.minX + 14, y: item.minY + 9, width: item.width - 28, height: 20))
        drawText(project.detail, font: tinyFont, color: mutedText, in: CGRect(x: item.minX + 14, y: item.minY + 30, width: item.width - 28, height: 18))

        let progress = clamp(project.baseProgress + (isActive ? keyCount % 30 : 0), 0, 98)
        let track = CGRect(x: item.minX + 14, y: item.maxY - 8, width: item.width - 28, height: 3)
        fill(track, rgb(43, 52, 63))
        fill(CGRect(x: track.minX, y: track.minY, width: max(4, track.width * CGFloat(progress) / 100), height: track.height), isActive ? rgb(111, 211, 187) : rgb(91, 107, 123))
    }

    private func drawWorkspace(in rect: CGRect) {
        fill(rect, appBackground)
        line(from: CGPoint(x: rect.maxX - 1, y: rect.minY), to: CGPoint(x: rect.maxX - 1, y: rect.maxY), color: divider)

        let terminalHeight = clamp(rect.height / 4, 120, 178)
        let editorHeader = CGRect(x: rect.minX, y: rect.minY, width: rect.width, height: 42)
        let editor = CGRect(x: rect.minX, y: editorHeader.maxY, width: rect.width, height: rect.height - terminalHeight - editorHeader.height)
        let terminal = CGRect(x: rect.minX, y: editor.maxY, width: rect.width, height: terminalHeight)

        drawEditorHeader(in: editorHeader)
        drawEditor(in: editor)
        drawTerminal(in: terminal)
    }

    private func drawEditorHeader(in rect: CGRect) {
        fill(rect, panel)
        line(from: CGPoint(x: rect.minX, y: rect.maxY - 1), to: CGPoint(x: rect.maxX, y: rect.maxY - 1), color: softDivider)

        let tab = CGRect(x: rect.minX + 16, y: rect.minY + 7, width: min(320, rect.width - 32), height: 30)
        fill(tab, rgb(31, 39, 50))
        drawText("\(Self.projects[activeProjectIndex].name)/Builder.cs", font: smallFont, color: normalCode, in: tab.insetBy(dx: 12, dy: 5))
    }

    private func drawEditor(in rect: CGRect) {
        let gutterWidth = clamp(rect.width / 10, 58, 92)
        let gutterRect = CGRect(x: rect.minX, y: rect.minY, width: gutterWidth, height: rect.height)
        let codeArea = CGRect(x: gutterRect.maxX, y: rect.minY, width: rect.width - gutterWidth, height: rect.height)

        fill(rect, appBackground)
        fill(gutterRect, gutter)
        line(from: CGPoint(x: gutterRect.maxX, y: gutterRect.minY), to: CGPoint(x: gutterRect.maxX, y: gutterRect.maxY), color: softDivider)

        NSGraphicsContext.saveGraphicsState()
        NSBezierPath(rect: rect).addClip()

        let lineHeight = codeFont.ascender - codeFont.descender + 8
        let maxLines = max(1, Int((rect.height - 24) / lineHeight))
        let start = max(0, lines.count - maxLines)
        var y = rect.minY + 14

        for index in start..<lines.count {
            let numberText = "\(index + 1)"
            let numberWidth = measureText(numberText, font: tinyFont)
            drawText(numberText, font: tinyFont, color: lineNumber, in: CGRect(x: gutterRect.maxX - numberWidth - 14, y: y + 5, width: numberWidth + 2, height: 18))
            drawCodeLine(lines[index], x: codeArea.minX + 20, y: y)
            y += lineHeight
        }

        let currentLine = lines.last ?? ""
        let cursorX = codeArea.minX + 20 + measureCode(currentLine)
        let cursorY = rect.minY + 14 + CGFloat(lines.count - start - 1) * lineHeight
        typingParticleOrigin = CGPoint(
            x: clamp(cursorX + 4, rect.minX + 12, rect.maxX - 12),
            y: clamp(cursorY + lineHeight / 2, rect.minY + 12, rect.maxY - 12)
        )

        if (pulse / 4) % 2 == 0 {
            line(from: CGPoint(x: cursorX + 3, y: cursorY + 3), to: CGPoint(x: cursorX + 3, y: cursorY + lineHeight - 5), color: cursor, width: 2)
        }

        NSGraphicsContext.restoreGraphicsState()
    }

    private func drawCodeLine(_ text: String, x: CGFloat, y: CGFloat) {
        guard !text.isEmpty else {
            return
        }

        if text.trimmingCharacters(in: .whitespaces).hasPrefix("//") {
            drawRawCode(text, color: comment, x: x, y: y)
            return
        }

        var cursorX = x
        var index = text.startIndex

        while index < text.endIndex {
            let character = text[index]

            if character == "\"" {
                var end = text.index(after: index)
                while end < text.endIndex, text[end] != "\"" {
                    end = text.index(after: end)
                }
                if end < text.endIndex {
                    end = text.index(after: end)
                }

                let token = String(text[index..<end])
                drawRawCode(token, color: stringColor, x: cursorX, y: y)
                cursorX += measureCode(token)
                index = end
                continue
            }

            if character.isLetter || character == "_" {
                var end = index
                while end < text.endIndex, text[end].isLetter || text[end].isNumber || text[end] == "_" {
                    end = text.index(after: end)
                }

                let token = String(text[index..<end])
                drawRawCode(token, color: Self.keywords.contains(token) ? keyword : normalCode, x: cursorX, y: y)
                cursorX += measureCode(token)
                index = end
                continue
            }

            if character.isNumber {
                var end = index
                while end < text.endIndex, text[end].isNumber {
                    end = text.index(after: end)
                }

                let token = String(text[index..<end])
                drawRawCode(token, color: number, x: cursorX, y: y)
                cursorX += measureCode(token)
                index = end
                continue
            }

            let symbol = String(character)
            let symbolColor: NSColor = ["(", ")", "{", "}", "[", "]"].contains(symbol) ? accent : normalCode
            drawRawCode(symbol, color: symbolColor, x: cursorX, y: y)
            cursorX += measureCode(symbol)
            index = text.index(after: index)
        }
    }

    private func drawRawCode(_ text: String, color: NSColor, x: CGFloat, y: CGFloat) {
        (text as NSString).draw(at: CGPoint(x: x, y: y), withAttributes: [.font: codeFont, .foregroundColor: color])
    }

    private func measureCode(_ text: String) -> CGFloat {
        if text.allSatisfy(\.isWhitespace) {
            return measureText("0", font: codeFont) * CGFloat(text.count)
        }

        return measureText(text, font: codeFont)
    }

    private func drawTerminal(in rect: CGRect) {
        fill(rect, rgb(9, 13, 18))
        line(from: CGPoint(x: rect.minX, y: rect.minY), to: CGPoint(x: rect.maxX, y: rect.minY), color: divider)

        drawText("output", font: smallFont, color: softText, in: CGRect(x: rect.minX + 18, y: rect.minY + 12, width: rect.width - 36, height: 20))

        var y = rect.minY + 40
        for terminalLine in terminalLines {
            (terminalLine as NSString).draw(at: CGPoint(x: rect.minX + 20, y: y), withAttributes: [.font: diffFont, .foregroundColor: normalCode])
            y += diffFont.ascender - diffFont.descender + 5
        }
    }

    private func drawDiffPane(in rect: CGRect) {
        fill(rect, panel)

        let header = CGRect(x: rect.minX, y: rect.minY, width: rect.width, height: 78)
        fill(header, panelSoft)
        line(from: CGPoint(x: rect.minX, y: header.maxY - 1), to: CGPoint(x: rect.maxX, y: header.maxY - 1), color: divider)

        drawText("Review", font: titleFont, color: normalCode, in: CGRect(x: header.minX + 18, y: header.minY + 16, width: header.width - 36, height: 24))
        drawText("live diff", font: smallFont, color: mutedText, in: CGRect(x: header.minX + 18, y: header.minY + 42, width: header.width - 36, height: 20))

        let fileBadge = CGRect(x: rect.minX + 18, y: header.maxY + 14, width: rect.width - 36, height: 28)
        fill(fileBadge, rgb(33, 41, 52))
        drawText("\(Self.projects[activeProjectIndex].name)/Builder.cs", font: smallFont, color: softText, in: fileBadge.insetBy(dx: 12, dy: 5))

        let particlePanel = CGRect(x: rect.minX + 14, y: rect.maxY - 162, width: rect.width - 28, height: 146)
        let diffArea = CGRect(x: rect.minX, y: fileBadge.maxY + 14, width: rect.width, height: particlePanel.minY - fileBadge.maxY - 24)

        NSGraphicsContext.saveGraphicsState()
        NSBezierPath(rect: diffArea).addClip()

        let lineHeight = diffFont.ascender - diffFont.descender + 7
        let maxLines = max(1, Int((diffArea.height - 16) / lineHeight))
        let start = max(0, diffLines.count - maxLines)
        var y = diffArea.minY + 8

        for index in start..<diffLines.count {
            drawDiffLine(diffLines[index], in: diffArea, y: y, lineHeight: lineHeight)
            y += lineHeight
        }

        NSGraphicsContext.restoreGraphicsState()

        drawParticleControls(in: particlePanel)
    }

    private func drawParticleControls(in rect: CGRect) {
        fill(rect, rgb(18, 24, 31))
        stroke(rect, softDivider)
        drawText("mouse trail colors", font: smallFont, color: softText, in: CGRect(x: rect.minX + 14, y: rect.minY + 10, width: rect.width - 28, height: 22))

        let gap: CGFloat = 10
        let columnCount = 2
        let buttonWidth = max(100, (rect.width - 28 - gap) / CGFloat(columnCount))
        let buttonHeight: CGFloat = 42
        let startY = rect.minY + 44
        let startX = rect.minX + 14

        for index in Self.particleOptions.indices {
            let option = Self.particleOptions[index]
            let row = index / columnCount
            let column = index % columnCount
            let button = CGRect(
                x: startX + CGFloat(column) * (buttonWidth + gap),
                y: startY + CGFloat(row) * (buttonHeight + gap),
                width: buttonWidth,
                height: buttonHeight
            )
            particleButtonBounds[index] = button

            let isActive = index == particleOptionIndex
            fill(button, isActive ? rgb(45, 58, 72) : rgb(28, 35, 44))
            stroke(button, isActive ? rgb(111, 211, 187) : rgb(53, 64, 77))

            drawParticleShape(
                mode: option.mode,
                center: CGPoint(x: button.minX + 22, y: button.midY),
                size: 13,
                strokeColor: option.palette[0],
                fillColor: option.palette[0],
                lineWidth: 1.8
            )

            for swatch in option.palette.indices {
                let swatchX = button.maxX - 42 + CGFloat(swatch) * 11
                ellipse(CGRect(x: swatchX, y: button.minY + 12, width: 8, height: 8), fill: option.palette[swatch])
            }

            drawText(option.label, font: smallFont, color: isActive ? normalCode : softText, in: CGRect(x: button.minX + 42, y: button.minY + 10, width: button.width - 88, height: 22))
        }
    }

    private func drawDiffLine(_ line: DiffLine, in rect: CGRect, y: CGFloat, lineHeight: CGFloat) {
        let row = CGRect(x: rect.minX, y: y - 1, width: rect.width, height: lineHeight)
        var color = softText

        if line.marker == "+" {
            fill(row, plusBackground)
            color = plusText
        } else if line.marker == "-" {
            fill(row, minusBackground)
            color = minusText
        }

        drawText(String(line.marker), font: diffFont, color: color, in: CGRect(x: rect.minX + 14, y: y + 3, width: 18, height: lineHeight))
        drawText(line.text, font: diffFont, color: color, in: CGRect(x: rect.minX + 36, y: y + 3, width: rect.width - 50, height: lineHeight))
    }

    private func drawStatus(in rect: CGRect) {
        fill(rect, rgb(28, 49, 58))

        let left = "keys: \(keyCount)"
        let middle = "project: \(Self.projects[activeProjectIndex].name)"
        let adultNote = exitHoldProgress > 0 ? "Exit hold: \(Int(exitHoldProgress * 100))%" : "Adults: hold Ctrl+Shift+Q 3s"
        let right = kioskMode ? "kid mode" : "debug windowed"

        drawText(left, font: smallFont, color: .white, in: CGRect(x: rect.minX + 18, y: rect.minY + 7, width: 130, height: rect.height - 8))
        drawText(middle, font: smallFont, color: .white, in: CGRect(x: rect.minX + 160, y: rect.minY + 7, width: max(80, rect.width - 690), height: rect.height - 8))
        drawText(guardStatus, font: tinyFont, color: softText, in: CGRect(x: rect.maxX - 520, y: rect.minY + 9, width: 150, height: rect.height - 8), alignment: .right)
        drawText(adultNote, font: tinyFont, color: softText, in: CGRect(x: rect.maxX - 360, y: rect.minY + 9, width: 200, height: rect.height - 8), alignment: .right)
        drawText(right, font: smallFont, color: .white, in: CGRect(x: rect.maxX - 150, y: rect.minY + 7, width: 130, height: rect.height - 8), alignment: .right)
    }

    private func drawBanner(width: CGFloat) {
        guard bannerTicks > 0, !currentBanner.isEmpty else {
            return
        }

        let alpha = clamp(CGFloat(bannerTicks * 8), 0, 176) / 255
        let bannerBrush = rgb(34, 52, 61, alpha)
        let textColor = rgb(242, 247, 250, clamp(CGFloat(bannerTicks * 8 + 45), 0, 255) / 255)
        let textWidth = measureText(currentBanner, font: bannerFont)
        let box = CGRect(x: (width - textWidth) / 2 - 28, y: 84, width: textWidth + 56, height: 64)

        fill(box, bannerBrush)
        drawText(currentBanner, font: bannerFont, color: textColor, in: CGRect(x: box.minX + 28, y: box.minY + 16, width: box.width - 56, height: 34))
    }

    private func drawSparkles() {
        guard !sparkles.isEmpty else {
            return
        }

        for sparkle in sparkles {
            let progress = CGFloat(sparkle.age) / CGFloat(sparkle.lifespan)
            let alpha = clamp(190 * (1 - progress), 0, 190) / 255
            let size = sparkle.size * (1 - progress * 0.35)

            drawParticleShape(
                mode: sparkle.mode,
                center: sparkle.position,
                size: size,
                strokeColor: sparkle.color.withAlphaComponent(alpha),
                fillColor: sparkle.color.withAlphaComponent(clamp(alpha + CGFloat(35.0 / 255.0), 0, CGFloat(210.0 / 255.0))),
                lineWidth: max(1.2, size / 3)
            )
        }
    }

    private func typingOrigin() -> CGPoint {
        if typingParticleOrigin != .zero {
            return typingParticleOrigin
        }

        return CGPoint(x: bounds.midX, y: bounds.midY)
    }

    private func drawParticleShape(
        mode: ParticleMode,
        center: CGPoint,
        size: CGFloat,
        strokeColor: NSColor,
        fillColor: NSColor,
        lineWidth: CGFloat
    ) {
        let half = size / 2

        switch mode {
        case .dots:
            ellipse(CGRect(x: center.x - half, y: center.y - half, width: size, height: size), fill: fillColor)
        case .blocks:
            fill(CGRect(x: center.x - half, y: center.y - half, width: size, height: size), fillColor)
            stroke(CGRect(x: center.x - half, y: center.y - half, width: size, height: size), strokeColor, width: lineWidth)
        case .pluses:
            line(from: CGPoint(x: center.x - half, y: center.y), to: CGPoint(x: center.x + half, y: center.y), color: strokeColor, width: lineWidth)
            line(from: CGPoint(x: center.x, y: center.y - half), to: CGPoint(x: center.x, y: center.y + half), color: strokeColor, width: lineWidth)
        case .stars:
            line(from: CGPoint(x: center.x - half, y: center.y), to: CGPoint(x: center.x + half, y: center.y), color: strokeColor, width: lineWidth)
            line(from: CGPoint(x: center.x, y: center.y - half), to: CGPoint(x: center.x, y: center.y + half), color: strokeColor, width: lineWidth)
            line(from: CGPoint(x: center.x - half * 0.7, y: center.y - half * 0.7), to: CGPoint(x: center.x + half * 0.7, y: center.y + half * 0.7), color: strokeColor, width: lineWidth)
            line(from: CGPoint(x: center.x - half * 0.7, y: center.y + half * 0.7), to: CGPoint(x: center.x + half * 0.7, y: center.y - half * 0.7), color: strokeColor, width: lineWidth)

            if size > 5 {
                let dotSize = max(1.5, size / 3)
                ellipse(CGRect(x: center.x - dotSize / 2, y: center.y - dotSize / 2, width: dotSize, height: dotSize), fill: fillColor)
            }
        }
    }
}

private final class KeyboardGuard {
    private weak var view: ToddlerCoderView?
    private var eventTap: CFMachPort?
    private var runLoopSource: CFRunLoopSource?

    init(view: ToddlerCoderView) {
        self.view = view
    }

    func start() -> Bool {
        let promptKey = kAXTrustedCheckOptionPrompt.takeUnretainedValue() as String
        _ = AXIsProcessTrustedWithOptions([promptKey: true] as CFDictionary)

        let events = [CGEventType.keyDown, .keyUp, .flagsChanged]
        let eventMask = events.reduce(CGEventMask(0)) { partial, type in
            partial | (CGEventMask(1) << Int(type.rawValue))
        }

        let selfPointer = Unmanaged.passUnretained(self).toOpaque()
        guard let tap = CGEvent.tapCreate(
            tap: .cgSessionEventTap,
            place: .headInsertEventTap,
            options: .defaultTap,
            eventsOfInterest: eventMask,
            callback: KeyboardGuard.handleEvent,
            userInfo: selfPointer
        ) else {
            return false
        }

        eventTap = tap
        guard let source = CFMachPortCreateRunLoopSource(kCFAllocatorDefault, tap, 0) else {
            eventTap = nil
            return false
        }

        runLoopSource = source
        CFRunLoopAddSource(CFRunLoopGetMain(), source, .commonModes)
        CGEvent.tapEnable(tap: tap, enable: true)
        return true
    }

    func stop() {
        if let eventTap {
            CGEvent.tapEnable(tap: eventTap, enable: false)
        }

        if let runLoopSource {
            CFRunLoopRemoveSource(CFRunLoopGetMain(), runLoopSource, .commonModes)
        }

        runLoopSource = nil
        eventTap = nil
    }

    private static let handleEvent: CGEventTapCallBack = { _, type, event, userInfo in
        guard let userInfo else {
            return Unmanaged.passUnretained(event)
        }

        let guardInstance = Unmanaged<KeyboardGuard>.fromOpaque(userInfo).takeUnretainedValue()
        return guardInstance.handle(type: type, event: event)
    }

    private func handle(type: CGEventType, event: CGEvent) -> Unmanaged<CGEvent>? {
        if type == .tapDisabledByTimeout || type == .tapDisabledByUserInput {
            if let eventTap {
                CGEvent.tapEnable(tap: eventTap, enable: true)
            }
            return Unmanaged.passUnretained(event)
        }

        let keyCode = Int(event.getIntegerValueField(.keyboardEventKeycode))
        let modifiers = InputModifiers(event.flags)

        DispatchQueue.main.async { [weak self] in
            guard let view = self?.view else {
                return
            }

            switch type {
            case .keyDown:
                view.guardedKeyDown(keyCode: keyCode, modifiers: modifiers)
            case .keyUp:
                view.guardedKeyUp(keyCode: keyCode, modifiers: modifiers)
            case .flagsChanged:
                view.guardedFlagsChanged(modifiers: modifiers)
            default:
                break
            }
        }

        return nil
    }
}

private final class AppDelegate: NSObject, NSApplicationDelegate, NSWindowDelegate {
    private var window: NSWindow?
    private var toddlerView: ToddlerCoderView?
    private var keyboardGuard: KeyboardGuard?
    private var allowTerminate = false
    private let kioskMode: Bool

    override init() {
        kioskMode = !CommandLine.arguments.dropFirst().contains { argument in
            argument.caseInsensitiveCompare("--debug-windowed") == .orderedSame
        }
        super.init()
    }

    func applicationDidFinishLaunching(_ notification: Notification) {
        createMenu()
        createWindow()
    }

    func applicationShouldTerminate(_ sender: NSApplication) -> NSApplication.TerminateReply {
        if kioskMode && !allowTerminate {
            return .terminateCancel
        }

        return .terminateNow
    }

    func windowShouldClose(_ sender: NSWindow) -> Bool {
        !kioskMode || allowTerminate
    }

    private func createMenu() {
        let mainMenu = NSMenu()
        let appItem = NSMenuItem()
        mainMenu.addItem(appItem)

        let appMenu = NSMenu()
        appMenu.addItem(NSMenuItem(title: "Quit Toddler Coder", action: #selector(NSApplication.terminate(_:)), keyEquivalent: "q"))
        appItem.submenu = appMenu
        NSApp.mainMenu = mainMenu
    }

    private func createWindow() {
        let screenFrame = NSScreen.main?.frame ?? CGRect(x: 0, y: 0, width: 1280, height: 800)
        let contentRect = kioskMode ? screenFrame : CGRect(x: 0, y: 0, width: 1280, height: 800)
        let styleMask: NSWindow.StyleMask = kioskMode ? [.borderless] : [.titled, .closable, .miniaturizable, .resizable]

        let window = NSWindow(contentRect: contentRect, styleMask: styleMask, backing: .buffered, defer: false)
        window.title = kioskMode ? "Toddler Coder" : "Toddler Coder - Debug Windowed"
        window.backgroundColor = rgb(13, 17, 23)
        window.delegate = self
        window.acceptsMouseMovedEvents = true
        window.isReleasedWhenClosed = false

        if kioskMode {
            window.collectionBehavior = [.canJoinAllSpaces, .stationary, .ignoresCycle]
            window.setFrame(screenFrame, display: true)
        } else {
            window.center()
            window.minSize = NSSize(width: 980, height: 620)
        }

        let view = ToddlerCoderView(kioskMode: kioskMode) { [weak self] in
            self?.adultExit()
        }
        window.contentView = view
        self.window = window
        toddlerView = view

        window.makeKeyAndOrderFront(nil)
        window.makeFirstResponder(view)
        NSApp.activate(ignoringOtherApps: true)

        if kioskMode {
            let guardInstance = KeyboardGuard(view: view)
            keyboardGuard = guardInstance
            if guardInstance.start() {
                enableKioskPresentation(for: window)
                view.setGuardStatus("keyboard guard active")
            } else {
                view.setGuardStatus("grant input permission")
            }
        } else {
            view.setGuardStatus("local guard")
        }
    }

    private func enableKioskPresentation(for window: NSWindow) {
        window.level = .screenSaver
        NSApp.presentationOptions = [
            .fullScreen,
            .hideDock,
            .hideMenuBar,
            .disableProcessSwitching,
            .disableForceQuit,
            .disableSessionTermination,
            .disableHideApplication
        ]
    }

    private func adultExit() {
        allowTerminate = true
        keyboardGuard?.stop()
        keyboardGuard = nil
        NSApp.presentationOptions = []
        NSApp.terminate(nil)
    }
}

let app = NSApplication.shared
private let delegate = AppDelegate()
app.delegate = delegate
app.setActivationPolicy(.regular)
app.run()
