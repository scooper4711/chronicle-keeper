import ChronicleKeeperKit
import SwiftUI

/// Asks for the paizo.com email address and password, or offers the demo account.
struct SignInView: View {
    @Environment(AccountSession.self) private var session
    @State private var email = ""
    @State private var password = ""

    var body: some View {
        VStack(spacing: 20) {
            header
            fields
            if let error = session.signInError {
                Label(error, systemImage: "exclamationmark.triangle.fill")
                    .foregroundStyle(.orange)
                    .fixedSize(horizontal: false, vertical: true)
            }
            buttons
            Text("Your password stays in your Keychain and is only ever sent to paizo.com.")
                .font(.footnote)
                .foregroundStyle(.secondary)
        }
        .multilineTextAlignment(.center)
        .frame(maxWidth: 380)
        .padding(32)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private var header: some View {
        VStack(spacing: 8) {
            Image(systemName: "person.text.rectangle")
                .font(.system(size: 48))
                .foregroundStyle(.tint)
            Text("Chronicle Keeper").font(.largeTitle.bold())
            Text("Sign in with your paizo.com account to read your characters from My Organized Play.")
                .foregroundStyle(.secondary)
        }
    }

    private var fields: some View {
        VStack(spacing: 10) {
            TextField("Email Address", text: $email)
                .textContentType(.username)
            #if os(iOS)
                .keyboardType(.emailAddress)
                .textInputAutocapitalization(.never)
            #endif
            SecureField("Password", text: $password)
                .textContentType(.password)
                .onSubmit(signIn)
        }
        .textFieldStyle(.roundedBorder)
        .multilineTextAlignment(.leading)
        .disabled(session.isSigningIn)
    }

    private var buttons: some View {
        VStack(spacing: 10) {
            Button(action: signIn) {
                if session.isSigningIn { ProgressView().controlSize(.small) } else { Text("Sign In") }
            }
            .buttonStyle(.borderedProminent)
            .keyboardShortcut(.defaultAction)
            .disabled(!credentials.isComplete || session.isSigningIn)
            Button("Try the Demo Account") { session.startDemo() }
                .buttonStyle(.borderless)
                .foregroundStyle(.tint)
        }
    }

    private var credentials: Credentials {
        Credentials(email: email.trimmingCharacters(in: .whitespaces), password: password)
    }

    private func signIn() {
        guard credentials.isComplete else { return }
        let account = credentials
        Task {
            await session.signIn(account)
            if session.signInError == nil { password = "" }
        }
    }
}
