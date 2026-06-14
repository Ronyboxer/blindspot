//
//  SupabaseClientProvider.swift
//  Blind Spot
//
//  Builds the shared `SupabaseClient`. Authentication uses Supabase's
//  Third-Party Auth: instead of Supabase's own session, every request carries
//  the current Firebase ID token (via the `accessToken` closure), so RLS sees
//  the Firebase UID as `auth.jwt() ->> 'sub'`.
//
//  Construction does no network work and does NOT touch Firebase, so it's safe
//  to build at app launch. The `accessToken` closure is invoked lazily per
//  request, by which time Firebase is configured.
//

import Foundation
import Supabase

enum SupabaseClientProvider {

    /// Create the client. `tokenProvider` returns the current Firebase ID token
    /// (or nil when signed out — those requests hit RLS as an anonymous role).
    static func make(tokenProvider: @escaping @Sendable () async -> String?) -> SupabaseClient {
        SupabaseClient(
            supabaseURL: URL(string: Secrets.supabaseURL)!,
            supabaseKey: Secrets.supabaseAnonKey,
            options: SupabaseClientOptions(
                auth: SupabaseClientOptions.AuthOptions(
                    accessToken: { await tokenProvider() }
                )
            )
        )
    }
}
