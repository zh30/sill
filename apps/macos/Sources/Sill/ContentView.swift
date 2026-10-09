import SwiftUI

/// Root: Home Canvas or Workspace. Sheets carry New Session and the Palette.
struct ContentView: View {
    @ObservedObject var appState: AppState

    var body: some View {
        Group {
            if appState.showHome {
                HomeView(appState: appState)
            } else {
                WorkspaceView(appState: appState)
            }
        }
        // Matches AppDelegate's window.contentMinSize — the two minimums
        // must agree or the window shrinks below what the root view draws.
        .frame(minWidth: 560, minHeight: 400)
        .background(T.bg)
        .preferredColorScheme(.dark)
        .sheet(isPresented: $appState.showNewSession) {
            NewSessionView(appState: appState)
        }
        .sheet(isPresented: $appState.showPalette) {
            PaletteView(appState: appState)
        }
    }
}
