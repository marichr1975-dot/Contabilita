import SwiftUI

struct ContentView: View {
    @State private var showingNewBill = false

    var body: some View {
        NavigationView {
            VStack(spacing: 28) {
                Image(systemName: "bag.fill")
                    .font(.system(size: 64))

                Text("Contabilità")
                    .font(.largeTitle)
                    .fontWeight(.bold)

                Text("Gestione delle lavorazioni")
                    .font(.title3)

                Button(action: { showingNewBill = true }) {
                    Text("Nuova bolletta")
                        .font(.title3)
                        .fontWeight(.bold)
                        .frame(maxWidth: .infinity)
                        .padding()
                }
                .buttonStyle(.borderedProminent)
            }
            .padding(40)
            .navigationTitle("Contabilità")
            .sheet(isPresented: $showingNewBill) {
                NuovaBollettaView()
            }
        }
    }
}

struct NuovaBollettaView: View {
    @Environment(\.presentationMode) private var presentationMode
    @State private var date = Date()
    @State private var article = ""
    @State private var quantity = ""

    var body: some View {
        NavigationView {
            Form {
                DatePicker("Data", selection: $date, displayedComponents: .date)
                TextField("Articolo", text: $article)
                TextField("Quantità", text: $quantity)
                    .keyboardType(.numberPad)
            }
            .navigationTitle("Nuova bolletta")
            .toolbar {
                ToolbarItem(placement: .navigationBarLeading) {
                    Button("Annulla") {
                        presentationMode.wrappedValue.dismiss()
                    }
                }
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button("Salva") {
                        presentationMode.wrappedValue.dismiss()
                    }
                }
            }
        }
    }
}
