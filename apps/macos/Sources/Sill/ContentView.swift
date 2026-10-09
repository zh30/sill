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
        .frame(minWidth: 720, minHeight: 480)
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
