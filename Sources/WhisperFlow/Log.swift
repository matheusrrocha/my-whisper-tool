import os

enum Log {
    static let app = Logger(subsystem: "dev.matheus.whisperflow", category: "app")
    static let hotkey = Logger(subsystem: "dev.matheus.whisperflow", category: "hotkey")
    static let audio = Logger(subsystem: "dev.matheus.whisperflow", category: "audio")
    static let engine = Logger(subsystem: "dev.matheus.whisperflow", category: "engine")
    static let insert = Logger(subsystem: "dev.matheus.whisperflow", category: "insert")
}
