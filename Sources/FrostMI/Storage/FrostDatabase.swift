import Foundation
import SQLite3

final class FrostDatabase {
  private let db: OpaquePointer?
  let url: URL

  init(url: URL = FrostDatabase.defaultURL()) throws {
    self.url = url
    try FileManager.default.createDirectory(
      at: url.deletingLastPathComponent(), withIntermediateDirectories: true)

    var handle: OpaquePointer?
    guard sqlite3_open(url.path, &handle) == SQLITE_OK else {
      throw StorageError.openFailed(String(cString: sqlite3_errmsg(handle)))
    }
    db = handle
    try execute(
      """
      CREATE TABLE IF NOT EXISTS records (
        kind TEXT NOT NULL,
        key TEXT NOT NULL,
        payload TEXT NOT NULL,
        updated_at REAL NOT NULL,
        PRIMARY KEY (kind, key)
      );
      """)
    try execute(
      """
      CREATE INDEX IF NOT EXISTS idx_records_kind ON records(kind);
      """)
  }

  deinit {
    sqlite3_close(db)
  }

  static func defaultURL() -> URL {
    let base =
      FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first
      ?? FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent(
        "Library/Application Support")
    return base.appendingPathComponent("FrostADR", isDirectory: true).appendingPathComponent(
      "FrostADR.sqlite")
  }

  func upsert<T: Encodable>(_ value: T, kind: RecordKind, key: String, updatedAt: Date = Date())
    throws
  {
    let data = try JSONEncoder.frost.encode(value)
    guard let payload = String(data: data, encoding: .utf8) else {
      throw StorageError.encodeFailed
    }
    let sql = "INSERT OR REPLACE INTO records(kind, key, payload, updated_at) VALUES (?, ?, ?, ?);"
    try withStatement(sql) { statement in
      sqlite3_bind_text(statement, 1, kind.rawValue, -1, sqliteTransient)
      sqlite3_bind_text(statement, 2, key, -1, sqliteTransient)
      sqlite3_bind_text(statement, 3, payload, -1, sqliteTransient)
      sqlite3_bind_double(statement, 4, updatedAt.timeIntervalSince1970)
      guard sqlite3_step(statement) == SQLITE_DONE else {
        throw StorageError.writeFailed(errorMessage)
      }
    }
  }

  func loadAll<T: Decodable>(_ type: T.Type, kind: RecordKind) throws -> [T] {
    let sql = "SELECT payload FROM records WHERE kind = ? ORDER BY updated_at DESC;"
    return try withStatement(sql) { statement in
      sqlite3_bind_text(statement, 1, kind.rawValue, -1, sqliteTransient)
      var results: [T] = []
      while sqlite3_step(statement) == SQLITE_ROW {
        guard let cString = sqlite3_column_text(statement, 0) else {
          continue
        }
        let payload = String(cString: cString)
        if let data = payload.data(using: .utf8) {
          results.append(try JSONDecoder.frost.decode(T.self, from: data))
        }
      }
      return results
    }
  }

  func deleteAll() throws {
    try execute("DELETE FROM records;")
  }

  func delete(kind: RecordKind) throws {
    let sql = "DELETE FROM records WHERE kind = ?;"
    try withStatement(sql) { statement in
      sqlite3_bind_text(statement, 1, kind.rawValue, -1, sqliteTransient)
      guard sqlite3_step(statement) == SQLITE_DONE else {
        throw StorageError.executeFailed(errorMessage)
      }
    }
  }

  func execute(_ sql: String) throws {
    guard sqlite3_exec(db, sql, nil, nil, nil) == SQLITE_OK else {
      throw StorageError.executeFailed(errorMessage)
    }
  }

  private func withStatement<T>(_ sql: String, body: (OpaquePointer?) throws -> T) throws -> T {
    var statement: OpaquePointer?
    guard sqlite3_prepare_v2(db, sql, -1, &statement, nil) == SQLITE_OK else {
      throw StorageError.prepareFailed(errorMessage)
    }
    defer { sqlite3_finalize(statement) }
    return try body(statement)
  }

  private var errorMessage: String {
    guard let db else { return "SQLite database is closed" }
    return String(cString: sqlite3_errmsg(db))
  }
}

enum RecordKind: String {
  case agent
  case mcpServer
  case skill
  case contextFile
  case memory
  case runtimeProcess
  case evidence
  case permissionState
  case event
}

enum StorageError: Error, LocalizedError {
  case openFailed(String)
  case prepareFailed(String)
  case executeFailed(String)
  case writeFailed(String)
  case encodeFailed

  var errorDescription: String? {
    switch self {
    case .openFailed(let message):
      "Failed to open FrostADR Runtime database: \(message)"
    case .prepareFailed(let message):
      "Failed to prepare FrostADR Runtime database statement: \(message)"
    case .executeFailed(let message):
      "Failed to execute FrostADR Runtime database statement: \(message)"
    case .writeFailed(let message):
      "Failed to write FrostADR Runtime database record: \(message)"
    case .encodeFailed:
      "Failed to encode FrostADR Runtime database payload"
    }
  }
}

let sqliteTransient = unsafeBitCast(-1, to: sqlite3_destructor_type.self)

extension JSONEncoder {
  static var frost: JSONEncoder {
    let encoder = JSONEncoder()
    encoder.dateEncodingStrategy = .iso8601
    encoder.outputFormatting = [.sortedKeys]
    return encoder
  }
}

extension JSONDecoder {
  static var frost: JSONDecoder {
    let decoder = JSONDecoder()
    decoder.dateDecodingStrategy = .iso8601
    return decoder
  }
}
