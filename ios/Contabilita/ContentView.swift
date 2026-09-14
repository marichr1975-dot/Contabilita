import SwiftUI

struct Lavorazione: Identifiable {
    let id = UUID()
    var nome: String
    var quantita: String = ""
}

struct ContentView: View {
    @State private var nuovaBolletta = false

    var body: some View {
        NavigationView {
            VStack(spacing: 28) {
                Spacer()

                Image(systemName: "bag.fill")
                    .font(.system(size: 60))

                Text("Contabilità")
                    .font(.largeTitle)
                    .bold()

                Button {
                    nuovaBolletta = true
                } label: {
                    Text("NUOVA BOLLETTA")
                        .font(.title2)
                        .bold()
                        .frame(maxWidth: .infinity)
                        .padding()
                }
                .buttonStyle(.borderedProminent)

                Spacer()
            }
            .padding(35)
            .navigationTitle("Contabilità")
            .sheet(isPresented: $nuovaBolletta) {
                NuovaBollettaView()
            }
        }
    }
}

struct NuovaBollettaView: View {
    @Environment(\.presentationMode) private var presentationMode

    @State private var data = Date()
    @State private var dataConfermata = false
    @State private var lavorazioni: [Lavorazione] = [
        Lavorazione(nome: "MESSENGER BAGPACK"),
        Lavorazione(nome: "TODAY"),
        Lavorazione(nome: "ACTIVITY"),
        Lavorazione(nome: "ZAINI MARIN"),
        Lavorazione(nome: "CLASSY"),
        Lavorazione(nome: "ZAINO PRO"),
        Lavorazione(nome: "CASE MARINA"),
        Lavorazione(nome: "MONEYFUL"),
        Lavorazione(nome: "BORSA IN STOFFA"),
        Lavorazione(nome: "PORTAPC")
    ]

    @FocusState private var rigaAttiva: Int?

    var body: some View {
        NavigationView {
            Group {
                if !dataConfermata {
                    scegliData
                } else {
                    listaLavorazioni
                }
            }
            .navigationTitle(dataConfermata ? "Lavorazioni" : "Nuova bolletta")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .navigationBarLeading) {
                    Button("Annulla") {
                        presentationMode.wrappedValue.dismiss()
                    }
                }
            }
        }
    }

    private var scegliData: some View {
        VStack(spacing: 22) {
            Text("SCEGLI LA DATA")
                .font(.title2)
                .bold()

            DatePicker(
                "Data",
                selection: $data,
                displayedComponents: .date
            )
            .datePickerStyle(.graphical)
            .labelsHidden()

            Button {
                dataConfermata = true
                DispatchQueue.main.async {
                    rigaAttiva = 0
                }
            } label: {
                Text("OK")
                    .font(.title2)
                    .bold()
                    .frame(maxWidth: .infinity)
                    .padding()
            }
            .buttonStyle(.borderedProminent)

            Spacer()
        }
        .padding(22)
    }

    private var listaLavorazioni: some View {
        VStack(spacing: 0) {
            HStack {
                Text(data.formatted(date: .numeric, time: .omitted))
                    .font(.headline)
                Spacer()
                Text("QUANTITÀ")
                    .font(.headline)
                    .frame(width: 110)
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 12)

            Divider()

            ScrollViewReader { proxy in
                ScrollView {
                    LazyVStack(spacing: 0) {
                        ForEach(lavorazioni.indices, id: \.self) { index in
                            HStack(spacing: 12) {
                                Text(lavorazioni[index].nome)
                                    .font(.title3)
                                    .frame(maxWidth: .infinity, alignment: .leading)

                                TextField("0", text: $lavorazioni[index].quantita)
                                    .font(.title2)
                                    .multilineTextAlignment(.center)
                                    .keyboardType(.numberPad)
                                    .frame(width: 90, height: 52)
                                    .textFieldStyle(RoundedBorderTextFieldStyle())
                                    .focused($rigaAttiva, equals: index)
                                    .onSubmit {
                                        passaAllaProssima(index: index, proxy: proxy)
                                    }
                            }
                            .padding(.horizontal, 16)
                            .padding(.vertical, 9)
                            .id(index)

                            Divider()
                        }
                    }
                }
            }

            Button {
                salva()
            } label: {
                Text("SALVA")
                    .font(.title2)
                    .bold()
                    .frame(maxWidth: .infinity)
                    .padding()
            }
            .buttonStyle(.borderedProminent)
            .padding(14)
        }
    }

    private func passaAllaProssima(index: Int, proxy: ScrollViewProxy) {
        if index + 1 < lavorazioni.count {
            rigaAttiva = index + 1
            withAnimation {
                proxy.scrollTo(index + 1, anchor: .center)
            }
        } else {
            rigaAttiva = nil
        }
    }

    private func salva() {
        presentationMode.wrappedValue.dismiss()
    }
}
