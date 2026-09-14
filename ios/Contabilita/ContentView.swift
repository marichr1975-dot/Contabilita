import SwiftUI

struct ContentView: View {
    var body: some View {
        NavigationStack {
            VStack(spacing: 24) {
                Image(systemName: "bag.fill")
                    .font(.system(size: 64))
                Text("Contabilità")
                    .font(.largeTitle)
                    .bold()
                Text("Gestione delle lavorazioni")
                    .font(.title3)
                Button("Nuova bolletta") {}
                    .buttonStyle(.borderedProminent)
                    .font(.title3)
            }
            .padding(40)
            .navigationTitle("Contabilità")
        }
    }
}
