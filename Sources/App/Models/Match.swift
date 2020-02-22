import Vapor
import FluentSQLite
import HiveEngine

enum MatchStatus: Int, SQLiteEnumType {
	/// A match that has an opponent but has not started
	case notStarted = 1
	/// A match in progress
	case active = 2
	/// A match that has ended
	case ended = 3

	static func reflectDecoded() throws -> (MatchStatus, MatchStatus) {
		return (.active, .notStarted)
	}
}

final class Match: SQLiteUUIDModel, Content, Migration, Parameter {
	var id: UUID?

	/// ID of the user that created the match
	private(set) var hostId: User.ID
	/// ID of the user the match is played against
	private(set) var opponentId: User.ID?

	/// ELO of the host at the start of the game
	private(set) var hostElo: Double?
	/// ELO of the opponent at the start of the game
	private(set) var opponentElo: Double?

	/// `true` if the host is White, `false` if the host is Black
	private(set) var hostIsWhite: Bool
	/// Winner of the game. White, Black, or nil for a tie
	private(set) var winner: String?

	/// Options that were used in the game
	private(set) var options: String

	/// Date that the game was started at
	private(set) var createdAt: Date?
	/// Total duration of the game
	private(set) var duration: TimeInterval?

	/// Status of the game, if it has begun or ended
	private(set) var status: MatchStatus
	/// `true` if the game is being played asynchronously turn based.
	private(set) var isAsyncPlay: Bool

	static var createdAtKey: TimestampKey? {
		\.createdAt
	}

	init(withHost host: User) throws {
		self.hostId = try host.requireID()
		self.hostIsWhite = true
		self.status = .notStarted
		self.isAsyncPlay = false

		let newState = GameState()
		self.options = GameState.Option.encode(newState.options)
	}

	func generateSocketUrl() throws -> URL {
		try Constants.SOCKET_URL
			.appendingPathComponent("\(requireID())")
			.appendingPathComponent("play")
	}

	func otherPlayer(from userId: User.ID) -> User.ID? {
		if hostId == userId {
			return opponentId
		} else if opponentId == userId {
			return hostId
		}

		return nil
	}
}

// MARK: - Modifiers

extension Match {
	func addOpponent(_ opponent: User.ID, on conn: DatabaseConnectable) -> Future<Match> {
		self.opponentId = opponent
		return self.save(on: conn)
	}

	func begin(on conn: DatabaseConnectable) throws -> Future<Match> {
		let matchId = try requireID()

		guard status == .notStarted,
			opponentId != nil else {
			throw Abort(.internalServerError, reason: #"Match "\#(matchId)" is not ready to begin (\#(status))"#)
		}

		#warning("TODO: get host and opponent's ELO")

		status = .active
		return self.save(on: conn)
	}

	func end(on conn: DatabaseConnectable) throws -> Future<Match> {
		let matchId = try requireID()

		guard status == .active else {
			throw Abort(.internalServerError, reason: #"Match "\#(matchId)" is not ready to end (\#(status)"#)
		}

		status = .ended
		if #available(OSX 10.15, *) {
			duration = createdAt?.distance(to: Date())
		}
		return self.save(on: conn)
	}
}

// MARK: - Response

struct CreateMatchResponse: Content {
	let id: Match.ID
	let socketUrl: URL
	let details: MatchDetailsResponse

	init(from match: Match) throws {
		self.id = try match.requireID()
		self.socketUrl = try match.generateSocketUrl()
		self.details = try MatchDetailsResponse(from: match)
	}
}

typealias JoinMatchResponse = CreateMatchResponse

struct MatchDetailsResponse: Content {
	let id: Match.ID
	let hostElo: Double?
	let opponentElo: Double?
	let hostIsWhite: Bool
	let winner: String?
	let options: String
	let createdAt: Date?
	let duration: TimeInterval?
	let status: MatchStatus
	let isAsyncPlay: Bool

	var host: UserSummaryResponse?
	var opponent: UserSummaryResponse?
	var moves: [MatchMovementResponse] = []

	init(from match: Match) throws {
		self.id = try match.requireID()
		self.hostElo = match.hostElo
		self.opponentElo = match.opponentElo
		self.hostIsWhite = match.hostIsWhite
		self.winner = match.winner
		self.options = match.options
		self.createdAt = match.createdAt
		self.duration = match.duration
		self.status = match.status
		self.isAsyncPlay = match.isAsyncPlay
	}
}
