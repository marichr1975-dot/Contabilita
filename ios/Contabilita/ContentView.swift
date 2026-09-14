import SwiftUI

struct Lavorazione: Identifiable, Codable {
    let id: UUID
    var nome: String
    var quantita: String

    init(id: UUID = UUID(), nome: String, quantita: String = "") {
        self.id = id
        self.nome = nome
        self.quantita = quantita
    }
}

struct Bolletta: Identifiable, Codable {
    let id: UUID
    var data: Date
    var lavorazioni: [Lavorazione]

    init(id: UUID = UUID(), data: Date, lavorazioni: [Lavorazione]) {
        self.id = id
        self.data = data
        self.lavorazioni = lavorazioni
    }
}

final class Archivio: ObservableObject {
    @Published var bollette: [Bolletta] = []
    @Published var nomiLavorazioni: [String] = [
        "MESSENGER BAGPACK",
        "TODAY",
        "ACTIVITY",
        "ZAINI MARIN",
        "CLASSY",
        "ZAINO PRO",
        "CASE MARINA",
        "MONEYFUL",
        "BORSA IN STOFFA",
        "PORTAPC"
    ]

    private let bolletteKey = "contabilita_bollette"
    private let nomiKey = "contabilita_nomi_lavorazioni"

    init() {
        carica()
    }

    func carica() {
        if let data = UserDefaults.standard.data(forKey: bolletteKey),
           let value = try? JSONDecoder().decode([Bolletta].self, from: data) {
            bollette = value
        }
        if let data = UserDefaults.standard.data(forKey: nomiKey),
           let value = try? JSONDecoder().decode([String].self, from: data),
           !value.isEmpty {
            nomiLavorazioni = value
        }
    }

    func salvaDati() {
        if let data = try? JSONEncoder().encode(bollette) {
            UserDefaults.standard.set(data, forKey: bolletteKey)
        }
        if let data = try? JSONEncoder().encode(nomiLavorazioni) {
            UserDefaults.standard.set(data, forKey: nomiKey)
        }
    }

    func salvaBolletta(_ bolletta: Bolletta) {
        if let i = bollette.firstIndex(where: { $0.id == bolletta.id }) {
            bollette[i] = bolletta
        } else {
            bollette.append(bolletta)
        }
        bollette.sort { $0.data > $1.data }
        salvaDati()
    }

    var ultimaBolletta: Bolletta? {
        bollette.sorted { $0.data > $1.data }.first
    }

    func aggiungiLavorazione(_ nome: String) {
        let nomePulito = nome.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !nomePulito.isEmpty else { return }
        guard !nomiLavorazioni.contains(where: { $0.caseInsensitiveCompare(nomePulito) == .orderedSame }) else { return }
        nomiLavorazioni.append(nomePulito)
        salvaDati()
    }
}

struct ContentView: View {
    @StateObject private var archivio = Archivio()
    @State private var nuovaBolletta = false
    @State private var modificaBolletta = false
    @State private var mostraCaricaProspetto = false

    var body: some View {
        NavigationView {
            VStack(spacing: 18) {
                Spacer()

                Image(systemName: "bag.fill")
                    .font(.system(size: 58))

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

                Button {
                    modificaBolletta = true
                } label: {
                    Text("MODIFICA ULTIMA BOLLETTA")
                        .font(.title2)
                        .bold()
                        .frame(maxWidth: .infinity)
                        .padding()
                }
                .buttonStyle(.bordered)

                Button {
                    mostraCaricaProspetto = true
                } label: {
                    Text("CARICA PROSPETTO")
                        .font(.title2)
                        .bold()
                        .frame(maxWidth: .infinity)
                        .padding()
                }
                .buttonStyle(.bordered)

                Spacer()
            }
            .padding(30)
            .navigationTitle("Contabilità")
            .sheet(isPresented: $nuovaBolletta) {
                NuovaBollettaView(archivio: archivio)
            }
            .sheet(isPresented: $modificaBolletta) {
                if let ultima = archivio.ultimaBolletta {
                    ModificaBollettaView(archivio: archivio, bolletta: ultima)
                } else {
                    NessunaBollettaView()
                }
            }
            .sheet(isPresented: $mostraCaricaProspetto) {
                CaricaProspettoView()
            }
        }
    }
}

struct NuovaBollettaView: View {
    @ObservedObject var archivio: Archivio
    @Environment(\.presentationMode) private var presentationMode

    @State private var data = Date()
    @State private var dataConfermata = false
    @State private var lavorazioni: [Lavorazione] = []
    @State private var nuovoArticolo = ""
    @State private var mostraNuovoArticolo = false
    @FocusState private var rigaAttiva: Int?

    var body: some View {
        NavigationView {
            Group {
                if !dataConfermata {
                    scegliData
                } else {
                    lista
                }
            }
            .navigationTitle(dataConfermata ? "Lavorazioni" : "Nuova bolletta")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .navigationBarLeading) {
                    Button("Annulla") { presentationMode.wrappedValue.dismiss() }
                }
            }
        }
        .onAppear {
            lavorazioni = archivio.nomiLavorazioni.map { Lavorazione(nome: $0) }
        }
    }

    private var scegliData: some View {
        VStack(spacing: 22) {
            Text("SCEGLI LA DATA").font(.title2).bold()

            DatePicker("Data", selection: $data, displayedComponents: .date)
                .datePickerStyle(.graphical)
                .labelsHidden()

            Button {
                dataConfermata = true
                DispatchQueue.main.async { rigaAttiva = 0 }
            } label: {
                Text("OK").font(.title2).bold()
                    .frame(maxWidth: .infinity).padding()
            }
            .buttonStyle(.borderedProminent)

            Spacer()
        }
        .padding(22)
    }

    private var lista: some View {
        VStack(spacing: 0) {
            HStack {
                Text(data.formatted(date: .numeric, time: .omitted)).font(.headline)
                Spacer()
                Text("QUANTITÀ").font(.headline).frame(width: 110)
            }
            .padding(.horizontal, 16).padding(.vertical, 12)

            Divider()

            ScrollViewReader { proxy in
                ScrollView {
                    LazyVStack(spacing: 0) {
                        ForEach(lavorazioni.indices, id: \.self) { index in
                            riga(index, proxy: proxy)
                            Divider()
                        }

                        Button {
                            mostraNuovoArticolo = true
                        } label: {
                            Text("+ AGGIUNGI ARTICOLO")
                                .font(.headline)
                                .frame(maxWidth: .infinity)
                                .padding()
                        }
                    }
                }
            }

            Button {
                let normalizzate = lavorazioni.map {
                    Lavorazione(id: $0.id, nome: $0.nome, quantita: $0.quantita.isEmpty ? "0" : $0.quantita)
                }
                archivio.salvaBolletta(Bolletta(data: data, lavorazioni: normalizzate))
                presentationMode.wrappedValue.dismiss()
            } label: {
                Text("SALVA").font(.title2).bold()
                    .frame(maxWidth: .infinity).padding()
            }
            .buttonStyle(.borderedProminent)
            .padding(14)
        }
        .alert("Nuovo articolo", isPresented: $mostraNuovoArticolo) {
            TextField("Nome articolo", text: $nuovoArticolo)
            Button("Aggiungi") {
                let nome = nuovoArticolo.trimmingCharacters(in: .whitespacesAndNewlines)
                if !nome.isEmpty {
                    archivio.aggiungiLavorazione(nome)
                    lavorazioni.append(Lavorazione(nome: nome))
                    nuovoArticolo = ""
                }
            }
            Button("Annulla", role: .cancel) { nuovoArticolo = "" }
        }
    }

    @ViewBuilder
    private func riga(_ index: Int, proxy: ScrollViewProxy) -> some View {
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
                    if index + 1 < lavorazioni.count {
                        rigaAttiva = index + 1
                        withAnimation { proxy.scrollTo(index + 1, anchor: .center) }
                    } else {
                        rigaAttiva = nil
                    }
                }
        }
        .padding(.horizontal, 16).padding(.vertical, 9)
        .id(index)
    }
}

struct ModificaBollettaView: View {
    @ObservedObject var archivio: Archivio
    @Environment(\.presentationMode) private var presentationMode
    let bolletta: Bolletta

    @State private var lavorazioni: [Lavorazione]
    @FocusState private var rigaAttiva: Int?

    init(archivio: Archivio, bolletta: Bolletta) {
        self.archivio = archivio
        self.bolletta = bolletta
        _lavorazioni = State(initialValue: bolletta.lavorazioni)
    }

    var body: some View {
        NavigationView {
            VStack(spacing: 0) {
                HStack {
                    Text("Data: \(bolletta.data.formatted(date: .numeric, time: .omitted))")
                        .font(.headline)
                    Spacer()
                }
                .padding(16)

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
                                            if index + 1 < lavorazioni.count {
                                                rigaAttiva = index + 1
                                                withAnimation { proxy.scrollTo(index + 1, anchor: .center) }
                                            } else {
                                                rigaAttiva = nil
                                            }
                                        }
                                }
                                .padding(.horizontal, 16).padding(.vertical, 9)
                                .id(index)

                                Divider()
                            }
                        }
                    }
                }

                Button {
                    archivio.salvaBolletta(Bolletta(id: bolletta.id, data: bolletta.data, lavorazioni: lavorazioni.map {
                        Lavorazione(id: $0.id, nome: $0.nome, quantita: $0.quantita.isEmpty ? "0" : $0.quantita)
                    }))
                    presentationMode.wrappedValue.dismiss()
                } label: {
                    Text("SALVA MODIFICHE")
                        .font(.title2).bold()
                        .frame(maxWidth: .infinity).padding()
                }
                .buttonStyle(.borderedProminent)
                .padding(14)
            }
            .navigationTitle("Modifica")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .navigationBarLeading) {
                    Button("Annulla") { presentationMode.wrappedValue.dismiss() }
                }
            }
        }
    }
}

struct NessunaBollettaView: View {
    @Environment(\.presentationMode) private var presentationMode
    var body: some View {
        NavigationView {
            VStack(spacing: 20) {
                Text("Non ci sono ancora bollette salvate.")
                    .font(.title3)
                    .multilineTextAlignment(.center)
                Button("OK") { presentationMode.wrappedValue.dismiss() }
                    .buttonStyle(.borderedProminent)
            }
            .padding()
        }
    }
}

struct CaricaProspettoView: View {
    @Environment(\.presentationMode) private var presentationMode

    var body: some View {
        NavigationView {
            VStack(spacing: 24) {
                Image(systemName: "tablecells")
                    .font(.system(size: 55))

                Text("CARICA PROSPETTO")
                    .font(.title2)
                    .bold()

                Text("Qui verrà caricata la tabella Excel ricevuta dall'azienda.")
                    .font(.title3)
                    .multilineTextAlignment(.center)

                Button("Scegli file Excel") {
                    // Collegamento all'importazione Excel nel prossimo passaggio.
                }
                .font(.title3)
                .buttonStyle(.borderedProminent)

                Spacer()
            }
            .padding(30)
            .navigationTitle("Prospetto")
            .toolbar {
                ToolbarItem(placement: .navigationBarLeading) {
                    Button("Chiudi") { presentationMode.wrappedValue.dismiss() }
                }
            }
        }
    }
}
