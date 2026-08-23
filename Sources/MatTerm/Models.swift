import Foundation
import Combine

struct SSHProfile: Identifiable, Codable, Hashable {
    var id: UUID
    var name: String
    var host: String
    var port: Int
    var username: String
    var identityPath: String

    init(
        id: UUID = UUID(),
        name: String = "New Host",
        host: String = "",
        port: Int = 22,
        username: String = "",
        identityPath: String = ""
    ) {
        self.id = id
        self.name = name
        self.host = host
        self.port = port
        self.username = username
        self.identityPath = identityPath
    }

    var target: String {
        username.isEmpty ? host : "\(username)@\(host)"
    }

    var tabHostName: String {
        let trimmedName = name.trimmingCharacters(in: .whitespacesAndNewlines)
        if !trimmedName.isEmpty, trimmedName.caseInsensitiveCompare("New Host") != .orderedSame {
            return trimmedName
        }
        return host.isEmpty ? "SSH" : host
    }

    var subtitle: String {
        let portSuffix = port == 22 ? "" : ":\(port)"
        return "\(target)\(portSuffix)"
    }
}

@MainActor
final class SSHProfileStore: ObservableObject {
    @Published private(set) var profiles: [SSHProfile] = []

    private let fileManager = FileManager.default
    private let fileURL: URL
    private let openSSHConfigURL: URL

    init() {
        let applicationSupport = fileManager.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
        let directory = applicationSupport.appendingPathComponent("MatTerm", isDirectory: true)
        fileURL = directory.appendingPathComponent("ssh-profiles.json")
        openSSHConfigURL = fileManager.homeDirectoryForCurrentUser
            .appendingPathComponent(".ssh", isDirectory: true)
            .appendingPathComponent("config")
        load()
        synchronizeFromOpenSSHConfig()
    }

    func upsert(_ profile: SSHProfile) {
        let previousProfile = profiles.first { $0.id == profile.id }
        if let index = profiles.firstIndex(where: { $0.id == profile.id }) {
            profiles[index] = profile
        } else {
            profiles.append(profile)
        }
        profiles.sort { $0.name.localizedStandardCompare($1.name) == .orderedAscending }
        save()
        writeOpenSSHConfig(profile, replacing: previousProfile?.name)
    }

    func delete(_ profile: SSHProfile) {
        profiles.removeAll { $0.id == profile.id }
        save()
    }

    @discardableResult
    func importOpenSSHConfig() -> Int {
        synchronizeFromOpenSSHConfig()
    }

    @discardableResult
    func synchronizeFromOpenSSHConfig() -> Int {
        guard let contents = try? String(contentsOf: openSSHConfigURL, encoding: .utf8) else {
            return 0
        }

        let imported = parseOpenSSHConfig(contents)
        guard !imported.isEmpty else { return 0 }

        var changes = 0
        for importedProfile in imported {
            if let index = profiles.firstIndex(where: {
                $0.name.caseInsensitiveCompare(importedProfile.name) == .orderedSame
            }) {
                let existing = profiles[index]
                let synchronized = SSHProfile(
                    id: existing.id,
                    name: importedProfile.name,
                    host: importedProfile.host,
                    port: importedProfile.port,
                    username: importedProfile.username,
                    identityPath: importedProfile.identityPath
                )
                if existing != synchronized {
                    profiles[index] = synchronized
                    changes += 1
                }
            } else {
                profiles.append(importedProfile)
                changes += 1
            }
        }

        profiles.sort { $0.name.localizedStandardCompare($1.name) == .orderedAscending }
        if changes > 0 { save() }
        return changes
    }

    private func parseOpenSSHConfig(_ contents: String) -> [SSHProfile] {
        var imported: [SSHProfile] = []
        var current: SSHProfile?

        func finishCurrent() {
            guard let current, !current.name.isEmpty else { return }
            imported.append(current)
        }

        for rawLine in contents.split(whereSeparator: \.isNewline) {
            let line = rawLine.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !line.isEmpty, !line.hasPrefix("#") else { continue }

            let fields = line.split(maxSplits: 1, whereSeparator: { $0 == " " || $0 == "\t" })
            guard fields.count == 2 else { continue }

            let key = fields[0].lowercased()
            let value = unquoteConfigValue(String(fields[1]).trimmingCharacters(in: .whitespacesAndNewlines))

            if key == "host" {
                finishCurrent()
                let aliases = value.split(whereSeparator: { $0 == " " || $0 == "\t" })
                guard let alias = aliases.first,
                      !alias.contains("*"),
                      !alias.contains("?"),
                      !alias.hasPrefix("!") else {
                    current = nil
                    continue
                }
                current = SSHProfile(name: String(alias), host: String(alias))
                continue
            }

            guard var profile = current else { continue }
            switch key {
            case "hostname":
                profile.host = value
            case "user":
                profile.username = value
            case "port":
                profile.port = Int(value) ?? profile.port
            case "identityfile":
                profile.identityPath = value
            default:
                break
            }
            current = profile
        }
        finishCurrent()
        return imported
    }

    private func writeOpenSSHConfig(_ profile: SSHProfile, replacing oldName: String?) {
        let directory = openSSHConfigURL.deletingLastPathComponent()
        do {
            try fileManager.createDirectory(at: directory, withIntermediateDirectories: true)

            let existingContents = (try? String(contentsOf: openSSHConfigURL, encoding: .utf8)) ?? ""
            var lines = existingContents.components(separatedBy: .newlines)
            if existingContents.isEmpty { lines = [] }

            let aliases = [oldName, profile.name]
                .compactMap { $0?.trimmingCharacters(in: .whitespacesAndNewlines) }
                .filter { !$0.isEmpty }
            if let block = findHostBlock(in: lines, aliases: aliases) {
                let updatedBlock = updateHostBlock(
                    Array(lines[block.start..<block.end]),
                    profile: profile,
                    replacing: oldName
                )
                lines.replaceSubrange(block.start..<block.end, with: updatedBlock)
            } else {
                if let last = lines.last, !last.isEmpty { lines.append("") }
                lines.append(contentsOf: makeHostBlock(for: profile))
            }

            let output = lines.joined(separator: "\n")
            try output.data(using: .utf8)?.write(to: openSSHConfigURL, options: .atomic)
            try fileManager.setAttributes([.posixPermissions: NSNumber(value: 0o600)], ofItemAtPath: openSSHConfigURL.path)
        } catch {
            print("Unable to update ~/.ssh/config: \(error.localizedDescription)")
        }
    }

    private func findHostBlock(in lines: [String], aliases: [String]) -> (start: Int, end: Int)? {
        for index in lines.indices {
            guard let directive = parseDirective(lines[index]), directive.key == "host" else { continue }
            var end = lines.count
            if index + 1 < lines.count {
                for nextIndex in (index + 1)..<lines.count where parseDirective(lines[nextIndex])?.key == "host" {
                    end = nextIndex
                    break
                }
            }
            let hostAliases = directive.value.split(whereSeparator: { $0 == " " || $0 == "\t" }).map(String.init)
            if aliases.contains(where: { alias in hostAliases.contains(alias) }) {
                return (index, end)
            }
        }
        return nil
    }

    private func updateHostBlock(
        _ block: [String],
        profile: SSHProfile,
        replacing oldName: String?
    ) -> [String] {
        guard let hostDirective = block.first.flatMap(parseDirective) else {
            return makeHostBlock(for: profile)
        }

        let oldName = oldName?.trimmingCharacters(in: .whitespacesAndNewlines)
        var hostAliases = hostDirective.value.split(whereSeparator: { $0 == " " || $0 == "\t" }).map(String.init)
        if let oldName, !oldName.isEmpty, oldName != profile.name {
            hostAliases = hostAliases.map { $0 == oldName ? profile.name : $0 }
        } else if !hostAliases.contains(profile.name) {
            hostAliases.append(profile.name)
        }

        let values: [String: String?] = [
            "hostname": configValue(profile.host),
            "user": profile.username.isEmpty ? nil : profile.username,
            "port": profile.port == 22 ? nil : String(profile.port),
            "identityfile": profile.identityPath.isEmpty ? nil : configValue(profile.identityPath)
        ]
        var seen = Set<String>()
        var updated: [String] = []
        for (index, line) in block.enumerated() {
            guard let directive = parseDirective(line) else {
                updated.append(line)
                continue
            }
            if index == 0, directive.key == "host" {
                let indentation = line.prefix { $0 == " " || $0 == "\t" }
                updated.append("\(indentation)Host \(hostAliases.joined(separator: " "))")
                continue
            }
            guard let value = values[directive.key] else {
                updated.append(line)
                continue
            }
            if seen.contains(directive.key) { continue }
            seen.insert(directive.key)
            if let value { updated.append("    \(canonicalKey(for: directive.key)) \(value)") }
        }

        for key in ["hostname", "user", "port", "identityfile"] where !seen.contains(key) {
            guard let value = values[key], let value else { continue }
            updated.append("    \(canonicalKey(for: key)) \(value)")
        }
        return updated
    }

    private func makeHostBlock(for profile: SSHProfile) -> [String] {
        var block = ["Host \(profile.name)", "    HostName \(configValue(profile.host))"]
        if !profile.username.isEmpty { block.append("    User \(configValue(profile.username))") }
        if profile.port != 22 { block.append("    Port \(profile.port)") }
        if !profile.identityPath.isEmpty { block.append("    IdentityFile \(configValue(profile.identityPath))") }
        return block
    }

    private func parseDirective(_ line: String) -> (key: String, value: String)? {
        let trimmed = line.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty, !trimmed.hasPrefix("#") else { return nil }
        let fields = trimmed.split(maxSplits: 1, whereSeparator: { $0 == " " || $0 == "\t" })
        guard fields.count == 2 else { return nil }
        return (String(fields[0]).lowercased(), String(fields[1]).trimmingCharacters(in: .whitespacesAndNewlines))
    }

    private func canonicalKey(for key: String) -> String {
        switch key {
        case "hostname": return "HostName"
        case "identityfile": return "IdentityFile"
        default: return key.capitalized
        }
    }

    private func configValue(_ value: String) -> String {
        guard value.contains(where: { $0.isWhitespace || $0 == "#" }) else { return value }
        return "\"\(value.replacingOccurrences(of: "\"", with: "\\\""))\""
    }

    private func unquoteConfigValue(_ value: String) -> String {
        guard value.count >= 2, value.first == "\"", value.last == "\"" else { return value }
        return String(value.dropFirst().dropLast()).replacingOccurrences(of: "\\\"", with: "\"")
    }

    private func load() {
        guard let data = try? Data(contentsOf: fileURL),
              let decoded = try? JSONDecoder().decode([SSHProfile].self, from: data) else {
            return
        }
        profiles = decoded.sorted {
            $0.name.localizedStandardCompare($1.name) == .orderedAscending
        }
    }

    private func save() {
        let directory = fileURL.deletingLastPathComponent()
        do {
            try fileManager.createDirectory(at: directory, withIntermediateDirectories: true)
            let data = try JSONEncoder().encode(profiles)
            try data.write(to: fileURL, options: .atomic)
        } catch {
            print("Unable to save SSH profiles: \(error.localizedDescription)")
        }
    }
}
