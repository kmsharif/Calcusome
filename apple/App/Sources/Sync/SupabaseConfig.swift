import Foundation

/// The local `supabase start` stack. Replace with the hosted project before TestFlight.
/// The anon key is public by design: row-level security guards the data.
enum SupabaseConfig {
    static let url = URL(string: "http://127.0.0.1:54321")!
    static let anonKey = "eyJhbGciOiJIUzI1NiIsInR5cCI6IkpXVCJ9.eyJpc3MiOiJzdXBhYmFzZS1kZW1vIiwicm9sZSI6ImFub24iLCJleHAiOjE5ODM4MTI5OTZ9.CRXP1A7WOeoJeXxjNni43kdQwgnWNReilDMblYTn_I0"
}
