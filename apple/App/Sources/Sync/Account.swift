import AuthenticationServices
import CalcCore
import CryptoKit
import Foundation
import Observation
import Supabase

enum AccountError: LocalizedError {
    case unsynced(Int)

    var errorDescription: String? {
        switch self {
        case .unsynced(let n): "\(n) history \(n == 1 ? "change hasn't" : "changes haven't") synced yet."
        }
    }
}

/// The signed-in Supabase account and the history sync that runs while it is signed in.
@MainActor @Observable final class Account {
    enum State: Equatable { case signedOut, signedIn(email: String?, userID: UUID) }

    private(set) var state = State.signedOut
    private(set) var sync: SyncEngine?

    @ObservationIgnored private let store: HistoryStore
    @ObservationIgnored private let client = SupabaseClient(
        supabaseURL: SupabaseConfig.url,
        supabaseKey: SupabaseConfig.anonKey,
        options: .init(
            db: .init(encoder: .history, decoder: .history),
            // Signed in from the stored session even when offline; a refresh that fails for good emits `.signedOut`.
            auth: .init(emitLocalSessionAsInitialSession: true)
        )
    )
    @ObservationIgnored private var channel: RealtimeChannelV2?
    @ObservationIgnored private var realtime: Task<Void, Never>?
    @ObservationIgnored private var pendingNonce: String?

    init(store: HistoryStore) {
        self.store = store
        Task { [weak self, client] in
            for await (event, session) in client.auth.authStateChanges {
                switch event {
                case .initialSession, .signedIn:
                    if let session { await self?.didSignIn(session.user) }
                case .signedOut:
                    await self?.tearDown()
                default:
                    break
                }
            }
        }
    }

    // MARK: Sign in

    func configureAppleRequest(_ request: ASAuthorizationAppleIDRequest) {
        let raw = (0..<32).map { _ in String(format: "%02x", UInt8.random(in: .min ... .max)) }.joined()
        pendingNonce = raw
        request.requestedScopes = [.email]
        request.nonce = SHA256.hash(data: Data(raw.utf8)).map { String(format: "%02x", $0) }.joined()
    }

    func signInWithApple(_ result: Result<ASAuthorization, Error>) async throws {
        let authorization: ASAuthorization
        do {
            authorization = try result.get()
        } catch let error as ASAuthorizationError where error.code == .canceled {
            return
        }
        guard let credential = authorization.credential as? ASAuthorizationAppleIDCredential,
              let token = credential.identityToken.flatMap({ String(data: $0, encoding: .utf8) }) else {
            throw ASAuthorizationError(.failed)
        }
        try await client.auth.signInWithIdToken(credentials: .init(provider: .apple, idToken: token, nonce: pendingNonce))
    }

    /// Runs in `ASWebAuthenticationSession`, so the redirect scheme needs no URL type registration.
    func signInWithGoogle() async throws {
        do {
            try await client.auth.signInWithOAuth(provider: .google, redirectTo: URL(string: "calcusome://auth-callback"))
        } catch let error as ASWebAuthenticationSessionError where error.code == .canceledLogin {
            return
        }
    }

    private func didSignIn(_ user: User) async {
        if case .signedIn(_, let current) = state {
            if current == user.id { return }  // `.signedIn` repeats the initial session
            await tearDown()
        }
        try? store.adopt(userID: user.id)  // sets userID before saving; a failed save is retried by the next one
        let sync = SyncEngine(store: store, remote: SupabaseHistoryRemote(client: client), cursorKey: Self.cursorKey(user.id))
        self.sync = sync
        store.onLocalChange = { [weak self] in self?.sync?.scheduleSync() }

        // The event is only a ping: the pull fetches the actual rows.
        let channel = client.channel("history")
        let changes = channel.postgresChange(
            AnyAction.self, schema: "public", table: "history_entries", filter: .eq("user_id", value: user.id)
        )
        self.channel = channel
        realtime = Task { [weak self] in
            // ponytail: a failed subscribe leaves Realtime off until the next sign-in or launch; edits and
            // foregrounding still sync. Resubscribe on failure if pings matter offline-to-online.
            do { try await channel.subscribeWithError() } catch { return }
            for await _ in changes { self?.sync?.scheduleSync(after: .zero) }
        }

        state = .signedIn(email: user.email, userID: user.id)
        await sync.sync()
    }

    // MARK: Sign out

    /// Tries one last sync. Throws `.unsynced` if changes would be lost, unless `discardingUnsynced`.
    func signOut(discardingUnsynced: Bool = false) async throws {
        await sync?.sync()
        let pending = try store.pendingCount()
        if !discardingUnsynced, pending > 0 { throw AccountError.unsynced(pending) }
        // The SDK drops the local session before calling the server, so a failed revoke still signs out here.
        try? await client.auth.signOut()
        await tearDown()
    }

    func deleteAccount() async throws {
        try await client.rpc("delete_my_account").execute()
        try? await client.auth.signOut()  // the user is gone, so the server call fails
        await tearDown()
    }

    /// Idempotent: the `.signedOut` event follows the app's own `signOut()`.
    private func tearDown() async {
        guard case .signedIn(_, let userID) = state else { return }
        state = .signedOut
        realtime?.cancel()
        realtime = nil
        store.onLocalChange = nil
        sync = nil
        try? store.purge(userID: userID)
        UserDefaults.standard.removeObject(forKey: Self.cursorKey(userID))
        if let channel {
            self.channel = nil
            await client.removeChannel(channel)
        }
    }

    private static func cursorKey(_ userID: UUID) -> String { "syncCursor.\(userID)" }
}
