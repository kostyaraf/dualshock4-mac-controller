import AppKit
import ApplicationServices

let usage = """
ds4mouse — управление Mac геймпадом вместо мыши

Команды:
  ds4mouse [run] [--config путь]   запустить
  ds4mouse test  [--config путь]   только показывать нажатия, курсор не трогать
  ds4mouse info                    возможности и качество связи подключённых геймпадов
  ds4mouse init-config [путь]      сохранить настройки по умолчанию в файл
  ds4mouse help

Файл настроек по умолчанию: \(Config.defaultPath.path)
"""

setvbuf(stdout, nil, _IOLBF, 0)   // line-buffered, so the log file updates live
var args = Array(CommandLine.arguments.dropFirst())
let command = args.first.map { $0.hasPrefix("-") ? "run" : args.removeFirst() } ?? "run"

func configURL() -> URL {
    if let i = args.firstIndex(of: "--config"), i + 1 < args.count {
        return URL(fileURLWithPath: (args[i + 1] as NSString).expandingTildeInPath)
    }
    return Config.defaultPath
}

func fail(_ message: String) -> Never {
    FileHandle.standardError.write(Data("Ошибка: \(message)\n".utf8))
    exit(1)
}

func waitForAccessibility() {
    let options = [kAXTrustedCheckOptionPrompt.takeUnretainedValue() as String: true] as CFDictionary
    guard !AXIsProcessTrustedWithOptions(options) else { return }
    print("""
    Нужен доступ к управлению компьютером.
    Откройте: Системные настройки → Конфиденциальность и безопасность → Универсальный доступ
    и включите DS4Mouse (или Терминал, если запускаете из него).
    Жду разрешения...
    """)
    // Ask once, then wait quietly. If macOS never reports the change, restart after a while
    // (launchd brings us back) — at most one system prompt every 5 minutes.
    for _ in 0..<150 {
        Thread.sleep(forTimeInterval: 2)
        if AXIsProcessTrusted() { print("Доступ получен."); return }
    }
    exit(1)
}

switch command {
case "help", "-h", "--help":
    print(usage)

case "info":
    let info = ControllerInfo(seconds: 6)
    info.run()
    RunLoop.main.run()

case "init-config":
    let url = args.first.map { URL(fileURLWithPath: ($0 as NSString).expandingTildeInPath) } ?? Config.defaultPath
    if FileManager.default.fileExists(atPath: url.path) { fail("файл уже существует: \(url.path)") }
    do { try Config.default.save(to: url) } catch { fail("\(error)") }
    print("Настройки сохранены: \(url.path)")

case "run", "test":
    let url = configURL()
    let config: Config
    do { config = try Config.load(from: url) } catch { fail("\(url.path): \(error)") }
    let dryRun = command == "test"
    if !dryRun { waitForAccessibility() }

    let engine: Engine
    do { engine = try Engine(config: config, dryRun: dryRun) } catch { fail("\(error)") }
    engine.start()

    // Without this macOS may "nap" a background process and delay its timers by up to ~1 s.
    let activity = ProcessInfo.processInfo.beginActivity(
        options: [.userInitiated, .latencyCritical], reason: "Gamepad input must be real-time")
    _ = activity

    // Release held buttons on Ctrl+C so the mouse doesn't stay "pressed".
    signal(SIGINT, SIG_IGN)
    let sigint = DispatchSource.makeSignalSource(signal: SIGINT, queue: .main)
    sigint.setEventHandler { engine.releaseAll(); print("\nВыход."); exit(0) }
    sigint.resume()

    log(dryRun ? "Режим проверки: нажимайте кнопки, курсор двигаться не будет. Ctrl+C — выход."
               : "Работаю. L3 (нажатие левого стика) — пауза. Ctrl+C — выход.")
    RunLoop.main.run()

default:
    print(usage)
    exit(1)
}
