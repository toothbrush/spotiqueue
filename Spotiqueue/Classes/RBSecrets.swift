//
//  Secrets.swift
//  Spotiqueue
//
//  Created by Paul on 18/5/21.
//  Copyright © 2021 Rustling Broccoli. All rights reserved.
//

import Cocoa
import KeychainSwift

class RBSecrets: NSObject {
    enum Secret: String {
        case clientId = "spotiqueue_client_id"
        case clientSecret = "spotiqueue_client_secret"
        case username = "spotiqueue_username"
        case password = "spotiqueue_password"
        case authorizationManager = "spotiqueue_authorization_manager"
    }
    static let keychain = KeychainSwift()

    // let's use this to collect some secrets
    static func getSecret(s: Secret) -> String? {
        #if DEBUG
        let appSupportDir = FileManager.default.urls(for: .applicationSupportDirectory,
                                                     in: .userDomainMask).first!
        let fileURL = appSupportDir.appendingPathComponent("\(s.rawValue).txt")
        logger.info("DEBUG mode - does \(fileURL) exist?")
        if FileManager.default.fileExists(atPath: fileURL.path) {
            logger.info("Attempting to read \(fileURL) because DEBUG is set.")
            do {
                let contentFromFile = try String(contentsOfFile: fileURL.path,
                                                 encoding: .utf8)
                return contentFromFile
            }
            catch let error {
                logger.error("Error reading file: \(error)")
            }
        }
        #endif

        logger.info("Retrieving <\(s.rawValue)> from keychain.")
        if let key = keychain.get(s.rawValue) {
            return key
        }
        logger.critical("Failure to read <\(s.rawValue)> from keychain")
        return nil
    }

    static func setSecret(s: Secret, v: Data) {
        #if DEBUG
        let appSupportDir = FileManager.default.urls(for: .applicationSupportDirectory,
                                                     in: .userDomainMask).first!
        let fileURL = appSupportDir.appendingPathComponent("\(s.rawValue).txt")
        logger.info("DEBUG mode - writing to \(fileURL).")
        do {
            try String(decoding: v, as: UTF8.self).write(toFile: fileURL.path,
                                                         atomically: true,
                                                         encoding: .utf8)
        }
        catch let error {
            logger.error("Error writing file: \(error)")
        }
        #endif

        if !keychain.set(v, forKey: s.rawValue, withAccess: .accessibleAfterFirstUnlock) {
            logger.critical("Failure to save <\(s.rawValue)> to keychain")
        }
    }

    static func deleteSecret(s: Secret) {
        if !keychain.delete(s.rawValue) {
            logger.critical("Failure to remove <\(s.rawValue)> from keychain")
        }
    }
}