import AuthenticationServices
import CalcCore
import SwiftUI

/// Sign-in, sync status, sign-out and account deletion: the first section of Settings.
struct AccountSection: View {
    let store: HistoryStore
    @Environment(Account.self) private var account
    @Environment(\.colorScheme) private var colorScheme
    @State private var unsynced: Int?
    @State private var deleting = false
    @State private var failure: (title: String, message: String)?

    var body: some View {
        Section {
            switch account.state {
            case .signedOut:
                SignInWithAppleButton(.signIn, onRequest: account.configureAppleRequest) { result in
                    run("Couldn't sign in") { try await account.signInWithApple(result) }
                }
                .signInWithAppleButtonStyle(colorScheme == .dark ? .white : .black)
                .frame(height: 36)
                Button("Continue with Google") { run("Couldn't sign in") { try await account.signInWithGoogle() } }
            case .signedIn(let email, _):
                LabeledContent("Signed in as", value: email ?? "Apple ID")
                statusLine.accessibilityElement(children: .combine)
                Button("Sign Out") { signOut() }
                Button("Delete Account…", role: .destructive) { deleting = true }
            }
        } header: {
            Text("Account")
        } footer: {
            if case .signedOut = account.state {
                Text("Sign in to keep your history in step on all your devices. Without an account, history stays on this device.")
            }
        }
        .confirmationDialog("Sign out without syncing?", isPresented: Binding(get: { unsynced != nil }, set: { if !$0 { unsynced = nil } }),
                            titleVisibility: .visible) {
            Button("Sign Out Anyway", role: .destructive) { signOut(discardingUnsynced: true) }
        } message: {
            Text("\(unsynced ?? 0) changes on this device haven't synced and will be lost.")
        }
        .confirmationDialog("Delete your account?", isPresented: $deleting, titleVisibility: .visible) {
            Button("Delete Account", role: .destructive) { run("Couldn't delete account") { try await account.deleteAccount() } }
        } message: {
            Text("This deletes your account and its history from every device. This can't be undone.")
        }
        .alert(failure?.title ?? "", isPresented: Binding(get: { failure != nil }, set: { if !$0 { failure = nil } })) {
        } message: {
            Text(failure?.message ?? "")
        }
    }

    private var statusLine: Text {
        _ = store.revision  // `pendingCount()` isn't observable; the store's revision bump re-renders this
        var line = switch account.sync?.status {
        case .syncing: Text("Syncing…")
        case .failed: Text("Can't reach the server. Will retry.")
        default:
            if let date = account.sync?.lastSynced {
                Text("Synced \(date, format: .relative(presentation: .named))")
            } else {
                Text("Synced")
            }
        }
        if let n = try? store.pendingCount(), n > 0 { line = line + Text(" · \(n) waiting") }
        return line.font(.callout).foregroundStyle(.secondary)
    }

    private func signOut(discardingUnsynced: Bool = false) {
        Task {
            do {
                try await account.signOut(discardingUnsynced: discardingUnsynced)
            } catch AccountError.unsynced(let n) {
                unsynced = n
            } catch {
                failure = ("Couldn't sign out", error.localizedDescription)
            }
        }
    }

    private func run(_ title: String, _ action: @escaping () async throws -> Void) {
        Task {
            do { try await action() } catch { failure = (title, error.localizedDescription) }
        }
    }
}
