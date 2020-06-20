//
//  User.swift
//  Hive-for-Mobile-Server
//
//  Created by Joseph Roque on 2020-04-04.
//  Copyright © 2020 Joseph Roque. All rights reserved.
//

import Fluent
import Vapor

final class User: Model, Content {
	static let schema = "users"

	@ID(key: .id)
	var id: UUID?

	/// Unique ID of the user
	@Field(key: "email")
	var email: String

	/// Hashed password
	@Field(key: "password")
	var password: String

	/// Display name of the user
	@Field(key: "display_name")
	var displayName: String

	/// Calculated ELO of the user
	@Field(key: "elo")
	var elo: Int

	/// Link to the user's avatar
	@OptionalField(key: "avatar_url")
	var avatarUrl: String?

	/// `true` if the user has admin priveleges
	@Field(key: "is_admin")
	var isAdmin: Bool

	init() { }

	init(email: String, password: String, displayName: String) {
		self.email = email
		self.password = password
		self.displayName = displayName
		self.elo = Elo.Rating.default
		self.isAdmin = false
	}

	init(
		id: User.IDValue? = nil,
		email: String,
		password: String,
		displayName: String,
		elo: Int,
		avatarUrl: String?,
		isAdmin: Bool
	) {
		self.id = id
		self.email = email
		self.password = password
		self.displayName = displayName
		self.elo = elo
		self.avatarUrl = avatarUrl
		self.isAdmin = isAdmin
	}
}

// MARK: - Modifiers

extension User {
	func recordWin(againstPlayerRated opponentElo: Int, on req: Request) -> EventLoopFuture<User> {
		elo = Elo.Rating(playerRating: elo, opponentRating: opponentElo, outcome: .win).updated
		return self.update(on: req.db)
			.map { self }
	}

	func recordLoss(againstPlayerRated opponentElo: Int, on req: Request) -> EventLoopFuture<User> {
		elo = Elo.Rating(playerRating: elo, opponentRating: opponentElo, outcome: .loss).updated
		return self.update(on: req.db)
			.map { self }
	}

	func recordDraw(againstPlayerRated opponentElo: Int, on req: Request) -> EventLoopFuture<User> {
		elo = Elo.Rating(playerRating: elo, opponentRating: opponentElo, outcome: .draw).updated
		return self.update(on: req.db)
			.map { self }
	}
}

// MARK: - Authentication

extension User: ModelAuthenticatable {
	static let usernameKey = \User.$email
	static let passwordHashKey = \User.$password

	func verify(password: String) throws -> Bool {
		try Bcrypt.verify(password, created: self.password)
	}
}

// MARK: - Create

extension User {
	struct Create: Content {
		let email: String
		let displayName: String
		let password: String
		let verifyPassword: String
		let avatarUrl: String?
	}
}

extension User.Create: Validatable {
	static func validations(_ validations: inout Validations) {
		validations.add("displayName", as: String.self, is: !.empty && .alphanumeric && .count(3...24))
		validations.add("email", as: String.self, is: .email)
		validations.add("avatarUrl", as: String?.self, is: .nil || .url, required: false)
	}
}

extension User.Create {
	struct Response: Content {
		let id: User.IDValue
		let email: String
		let displayName: String
		let avatarUrl: String?
		let token: SessionToken

		init(from user: User, withToken token: Token) throws {
			self.id = try user.requireID()
			self.email = user.email
			self.displayName = user.displayName
			self.avatarUrl = user.avatarUrl
			self.token = try SessionToken(user: user, token: token)
		}
	}
}

// MARK: - Summary

extension User {
	struct Summary: Content {
		let id: User.IDValue
		let displayName: String
		let elo: Int
		let avatarUrl: String?

		init(from user: User) throws {
			self.id = try user.requireID()
			self.displayName = user.displayName
			self.elo = user.elo
			self.avatarUrl = user.avatarUrl
		}

		init?(from user: User?) throws {
			guard let user = user else { return nil }
			try self.init(from: user)
		}
	}
}

// MARK: - Details

extension User {
	struct Details: Content {
		let id: User.IDValue
		let displayName: String
		let elo: Int
		let avatarUrl: String?
		var activeMatches: [Match.Details] = []
		var pastMatches: [Match.Details] = []

		init(from user: User) throws {
			self.id = try user.requireID()
			self.displayName = user.displayName
			self.elo = user.elo
			self.avatarUrl = user.avatarUrl
		}
	}
}
