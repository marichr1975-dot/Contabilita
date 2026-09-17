import SwiftUI
import PDFKit

extension URL: Identifiable {
    public var id: String { absoluteString }
}

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
        "MESSENGER",
        "BAGPACK",
        "TODAY",
        "ACTIVITY",
        "ZAINI MARIN",
        "CLASSY",
        "ZAINO PRO",
        "case marina",
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

    func eliminaBolletta(id: UUID) {
        bollette.removeAll { $0.id == id }
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
    @StateObject private var pdfTransfer = PDFTransferStore()
    @StateObject private var analysisStore = PDFAnalysisStore()
    @Environment(\.scenePhase) private var scenePhase
    @State private var nuovaBolletta = false
    @State private var modificaBolletta = false
    @State private var mostraDatiAnalizzati = false
    @State private var mostraPDF = false
    @State private var pdfImportati = 0

    var body: some View {
        NavigationView {
            VStack(spacing: 16) {
                Spacer(minLength: 8)

                Image(systemName: "bag.fill")
                    .font(.system(size: 52))
                    .foregroundColor(.orange)

                Text("Contabilità")
                    .font(.largeTitle)
                    .fontWeight(.semibold)

                homeButton(title: "NUOVA BOLLETTA", icon: "plus.circle.fill", tint: .green) {
                    nuovaBolletta = true
                }

                homeButton(title: "MODIFICA BOLLETTA", icon: "pencil.circle.fill", tint: .blue) {
                    modificaBolletta = true
                }

                homeButton(title: "DATI ANALIZZATI", icon: "chart.bar.fill", tint: .purple) {
                    mostraDatiAnalizzati = true
                }

                homeButton(
                    title: pdfImportati > 0 ? "FILE AZIENDA  •  \(pdfImportati)" : "IMPORTA FILE AZIENDA",
                    icon: "doc.on.doc.fill",
                    tint: .teal
                ) {
                    mostraPDF = true
                }

                Spacer()
            }
            .padding(28)
            .navigationTitle("Contabilità")
            .sheet(isPresented: $nuovaBolletta) {
                NuovaBollettaView(archivio: archivio)
            }
            .sheet(isPresented: $modificaBolletta) {
                SelezionaDataModificaView(archivio: archivio)
            }
            .sheet(isPresented: $mostraDatiAnalizzati) {
                DatiAnalizzatiView(archivio: archivio, analysisStore: analysisStore)
            }
            .sheet(isPresented: $mostraPDF) {
                PDFImportatiView(store: pdfTransfer, analysisStore: analysisStore)
            }
            .onAppear { aggiornaPDF() }
            .onChange(of: scenePhase) { phase in
                if phase == .active { aggiornaPDF() }
            }
        }
    }

    private func homeButton(title: String, icon: String, tint: Color, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            HStack(spacing: 12) {
                Image(systemName: icon)
                    .font(.system(size: 27))
                    .foregroundColor(tint)

                Text(title)
                    .font(.title3)
                    .fontWeight(.semibold)
                    .foregroundColor(.primary)

                Spacer()

                Image(systemName: "chevron.right")
                    .font(.headline)
                    .foregroundColor(.secondary)
            }
            .frame(maxWidth: .infinity)
            .padding(.horizontal, 18)
            .padding(.vertical, 16)
            .background(tint.opacity(0.10))
            .overlay(
                RoundedRectangle(cornerRadius: 14)
                    .stroke(tint.opacity(0.22), lineWidth: 1)
            )
            .cornerRadius(14)
        }
    }

    private func aggiornaPDF() {
        guard let container = FileManager.default.containerURL(
            forSecurityApplicationGroupIdentifier: "group.com.gotrail.contabilita"
        ) else {
            pdfImportati = 0
            return
        }
        let folder = container.appendingPathComponent("FileAzienda", isDirectory: true)
        let files = (try? FileManager.default.contentsOfDirectory(
            at: folder,
            includingPropertiesForKeys: nil
        )) ?? []
        pdfImportati = files.filter { ["pdf", "xlsx", "xls"].contains($0.pathExtension.lowercased()) }.count
    }
}

struct PDFImportatiView: View {
    @ObservedObject var store: PDFTransferStore
    @ObservedObject var analysisStore: PDFAnalysisStore
    @Environment(\.presentationMode) private var presentationMode
    @State private var pdfDaMostrare: URL?
    @State private var analisiInCorso: URL?
    @State private var messaggioCaricamento = ""
    @State private var mostraConfermaCaricamento = false

    var body: some View {
        NavigationView {
            VStack(spacing: 18) {
                if store.files.isEmpty {
                    Spacer()
                    Image(systemName: "doc.text.magnifyingglass")
                        .font(.system(size: 48))
                        .foregroundColor(.teal)
                    Text("Nessun file azienda ricevuto").font(.title2)
                    Text("Da WhatsApp o File: Condividi → Contabilità")
                        .multilineTextAlignment(.center).foregroundColor(.secondary)
                    Spacer()
                } else {
                    Text("FILE AZIENDA RICEVUTI").font(.title2).fontWeight(.semibold).padding(.top, 8)
                    List(store.files, id: \.self) { file in
                        HStack(spacing: 10) {
                            Image(systemName: "doc.fill").foregroundColor(.teal)
                            Text(file.lastPathComponent).lineLimit(2).foregroundColor(.primary)
                            Spacer()
                            Button("CARICA") {
                                analisiInCorso = file
                                analysisStore.analizza(file: file, bollette: [])
                                analisiInCorso = nil
                                messaggioCaricamento = "✓ FILE CARICATO E ANALIZZATO"
                                mostraConfermaCaricamento = true
                            }
                            .buttonStyle(.borderedProminent)
                            .tint(.green)
                            if file.pathExtension.lowercased() == "pdf" {
                                Button("MOSTRA PDF") { pdfDaMostrare = file }
                                    .buttonStyle(.bordered)
                            } else {
                                Text("EXCEL")
                                    .font(.caption)
                                    .foregroundColor(.secondary)
                            }
                            Button("CANCELLA") {
                                store.elimina(file: file)
                            }
                            .buttonStyle(.bordered)
                            .foregroundColor(.red)
                        }
                        .padding(.vertical, 8)
                    }
                    .listStyle(.plain)
                }
            }
            .padding(18)
            .navigationTitle("File azienda")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .navigationBarLeading) {
                    Button("Chiudi") { presentationMode.wrappedValue.dismiss() }
                }
            }
            .onAppear { store.ricarica() }
            .sheet(item: $pdfDaMostrare) { file in PDFViewer(url: file) }
            .alert(messaggioCaricamento, isPresented: $mostraConfermaCaricamento) {
                Button("OK", role: .cancel) { }
            }
        }
        .navigationViewStyle(.stack)
    }
}


struct PDFViewer: View {
    let url: URL
    @Environment(\.presentationMode) private var presentationMode

    var body: some View {
        NavigationView {
            PDFKitView(url: url)
                .navigationTitle(url.lastPathComponent)
                .navigationBarTitleDisplayMode(.inline)
                .toolbar {
                    ToolbarItem(placement: .navigationBarTrailing) {
                        Button("Chiudi") { presentationMode.wrappedValue.dismiss() }
                    }
                }
        }
    }
}

struct PDFKitView: UIViewRepresentable {
    let url: URL

    func makeUIView(context: Context) -> PDFView {
        let view = PDFView()
        view.autoScales = true
        view.displayMode = .singlePageContinuous
        view.backgroundColor = .systemBackground
        view.document = PDFDocument(url: url)
        return view
    }

    func updateUIView(_ uiView: PDFView, context: Context) {
        if uiView.document?.documentURL != url {
            uiView.document = PDFDocument(url: url)
        }
    }
}


struct VoceLavorazione: Identifiable {
    let id = UUID()
    let nome: String
    var quantita: String = ""
}

struct GruppoLavorazione: Identifiable {
    let id = UUID()
    let nome: String
    var voci: [VoceLavorazione]
}

func gruppiBollettaDaNomi() -> [GruppoLavorazione] {
    // Ordine e nomi presi direttamente dal file Excel aziendale.
    let articoli = [
        "MESSENGER", "BAGPACK", "TODAY", "ACTIVITY", "ZAINI MARIN",
        "CLASSY", "ZAINO PRO", "case marina", "MONEYFUL",
        "BORSA IN STOFFA", "PORTAPC"
    ]
    return articoli.map { GruppoLavorazione(nome: $0, voci: [VoceLavorazione(nome: "")]) }
}

struct NuovaBollettaView: View {
    @ObservedObject var archivio: Archivio
    @Environment(\.presentationMode) private var presentationMode
    private let bollettaDaModificare: Bolletta?

    @State private var data = Date()
    @State private var dataConfermata = false
    @State private var gruppi: [GruppoLavorazione] = []
    @FocusState private var rigaAttiva: Int?
    @State private var mostraConfermaCancella = false
    @State private var nuovoArticolo = ""
    @State private var mostraAggiungiArticolo = false

    init(archivio: Archivio, bollettaDaModificare: Bolletta? = nil) {
        self.archivio = archivio
        self.bollettaDaModificare = bollettaDaModificare
        _data = State(initialValue: bollettaDaModificare?.data ?? Date())
        _dataConfermata = State(initialValue: bollettaDaModificare != nil)
        if let b = bollettaDaModificare {
            var gruppiIniziali = gruppiBollettaDaNomi()
            let lavoriSalvati = b.lavorazioni
            let normalizzaTesto: (String) -> String = { testo in
                testo.folding(options: [.diacriticInsensitive, .caseInsensitive], locale: .current)
                    .replacingOccurrences(of: " ", with: "")
                    .replacingOccurrences(of: "-", with: "")
            }

            for g in gruppiIniziali.indices {
                for v in gruppiIniziali[g].voci.indices {
                    let nomeCompleto = gruppiIniziali[g].voci[v].nome.isEmpty
                        ? gruppiIniziali[g].nome
                        : "\(gruppiIniziali[g].nome) \(gruppiIniziali[g].voci[v].nome)"
                    if let lavoro = lavoriSalvati.first(where: { normalizzaTesto($0.nome) == normalizzaTesto(nomeCompleto) }) {
                        gruppiIniziali[g].voci[v].quantita = lavoro.quantita
                    }
                }
            }

            // Mantiene eventuali articoli personalizzati presenti nella bolletta.
            let nomiStandard = Set(gruppiIniziali.flatMap { g in
                g.voci.map { v in
                    v.nome.isEmpty ? g.nome : "\(g.nome) \(v.nome)"
                }
            }.map(normalizzaTesto))

            for lavoro in lavoriSalvati where !nomiStandard.contains(normalizzaTesto(lavoro.nome)) {
                gruppiIniziali.append(
                    GruppoLavorazione(
                        nome: lavoro.nome,
                        voci: [VoceLavorazione(nome: "", quantita: lavoro.quantita)]
                    )
                )
            }

            _gruppi = State(initialValue: gruppiIniziali)
        } else {
            var iniziali = gruppiBollettaDaNomi()
            let standard = Set(iniziali.map { $0.nome.lowercased() })
            let personalizzati = archivio.nomiLavorazioni.filter { !standard.contains($0.lowercased()) }
            iniziali.append(contentsOf: personalizzati.map { GruppoLavorazione(nome: $0, voci: [VoceLavorazione(nome: "")]) })
            _gruppi = State(initialValue: iniziali)
        }
    }

    var body: some View {
        NavigationView {
            Group {
                if !dataConfermata {
                    scegliData
                } else {
                    mascheraBolletta
                }
            }
            .navigationTitle(dataConfermata ? "Elenco lavori" : (bollettaDaModificare == nil ? "Nuova bolletta" : "Modifica bolletta"))
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .navigationBarLeading) {
                    Button("Annulla") { presentationMode.wrappedValue.dismiss() }
                }
                ToolbarItem(placement: .navigationBarTrailing) {
                    if dataConfermata {
                        HStack(spacing: 14) {
                            if bollettaDaModificare != nil {
                                Button("CANCELLA") {
                                    mostraConfermaCancella = true
                                }
                                .foregroundColor(.red)
                            }
                            Button("SALVA") { salva() }
                                .font(.system(size: 17, weight: .bold))
                        }
                    }
                }
            }
        }
        .alert("Cancella bolletta", isPresented: $mostraConfermaCancella) {
            Button("Cancella", role: .destructive) {
                if let bollettaDaModificare {
                    archivio.eliminaBolletta(id: bollettaDaModificare.id)
                }
                presentationMode.wrappedValue.dismiss()
            }
            Button("Annulla", role: .cancel) { }
        } message: {
            Text("Vuoi cancellare definitivamente questa bolletta?")
        }
        .sheet(isPresented: $mostraAggiungiArticolo) {
            NavigationView {
                Form {
                    Section("NUOVO ARTICOLO") {
                        TextField("Nome articolo", text: $nuovoArticolo)
                            .textInputAutocapitalization(.sentences)
                    }
                    Section {
                        Button("AGGIUNGI") {
                            aggiungiArticolo()
                        }
                        .disabled(nuovoArticolo.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                    }
                }
                .navigationTitle("Aggiungi articolo")
                .toolbar {
                    ToolbarItem(placement: .navigationBarLeading) {
                        Button("Annulla") { mostraAggiungiArticolo = false }
                    }
                }
            }
        }
        .onAppear {
            if gruppi.isEmpty && bollettaDaModificare == nil {
                gruppi = gruppiBollettaDaNomi()
                let standard = Set(gruppi.map { $0.nome.lowercased() })
                gruppi.append(contentsOf: archivio.nomiLavorazioni.filter { !standard.contains($0.lowercased()) }.map { GruppoLavorazione(nome: $0, voci: [VoceLavorazione(nome: "")]) })
            }
        }
    }

    private var scegliData: some View {
        VStack(spacing: 20) {
            Text("SCEGLI LA DATA")
                .font(.title2)

            HStack(spacing: 12) {
                Image(systemName: "calendar")
                    .font(.title2)
                DatePicker("Data", selection: $data, displayedComponents: .date)
                    .datePickerStyle(.compact)
                    .environment(\.locale, Locale(identifier: "it_IT"))
                    .labelsHidden()
                Spacer()
            }
            .padding()
            .background(RoundedRectangle(cornerRadius: 12).stroke(Color.gray.opacity(0.35)))

            Text(data.formatted(.dateTime.day().month(.wide).year()))
                .font(.title3)
                .environment(\.locale, Locale(identifier: "it_IT"))

            Button {
                dataConfermata = true
                rigaAttiva = 0
            } label: {
                Text("OK").font(.title2)
                    .frame(maxWidth: .infinity).padding()
            }
            .buttonStyle(.borderedProminent)

            Spacer()
        }
        .padding(22)
    }

    private var mascheraBolletta: some View {
        VStack(spacing: 0) {
            intestazioneFissa
            Divider()

            ScrollViewReader { proxy in
                ScrollView {
                    VStack(spacing: 10) {
                        ForEach(gruppi.indices, id: \.self) { g in
                            gruppoView(g, proxy: proxy)
                        }

                        Button { mostraAggiungiArticolo = true } label: {
                            HStack {
                                Image(systemName: "plus.circle.fill")
                                Text("AGGIUNGI ARTICOLO")
                                    .fontWeight(.semibold)
                            }
                            .font(.title3)
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 14)
                        }
                        .buttonStyle(.borderedProminent)

                    }
                    .padding(12)
                }
            }
        }
        .toolbar {
            ToolbarItemGroup(placement: .keyboard) {
                Spacer()
                Button("OK") { prossimaRiga() }
                    .font(.headline)
            }
        }
    }

    private var intestazioneFissa: some View {
        VStack(spacing: 5) {
            HStack(alignment: .top) {
                VStack(alignment: .leading) {
                    Text("NOME").font(.caption)
                    Text("data").font(.headline)
                }
                Spacer()
                VStack(spacing: 1) {
                    Text("elenco").font(.headline)
                    Text("lavori").font(.headline)
                }
                .padding(.horizontal, 12).padding(.vertical, 6)
                .background(Color.black).foregroundColor(.white)
                Text("bagful")
                    .font(.system(size: 30, weight: .bold))
                    .frame(maxWidth: .infinity, alignment: .trailing)
            }

            HStack {
                Text(data.formatted(date: .numeric, time: .omitted))
                    .font(.title3)
                    .foregroundColor(.blue)
                Spacer()
                Text("QUANTITÀ").font(.headline)
            }
        }
        .padding(.horizontal, 14).padding(.vertical, 9)
        .background(Color(white: 0.97))
    }

    private func gruppoView(_ g: Int, proxy: ScrollViewProxy) -> some View {
        VStack(spacing: 0) {
            HStack(alignment: .bottom) {
                Text(gruppi[g].nome).font(.headline)
                Spacer()
                Text("quantità").font(.headline)
            }
            .padding(.horizontal, 12).padding(.vertical, 8)

            ForEach(gruppi[g].voci.indices, id: \.self) { v in
                let flat = indicePiatto(g, v)
                HStack(spacing: 8) {
                    Text("□").font(.title3).frame(width: 24)
                    Text(gruppi[g].voci[v].nome)
                        .font(.title3)
                        .frame(maxWidth: .infinity, alignment: .leading)
                    TextField("", text: binding(g: g, v: v))
                        .font(.system(size: 22))
                        .foregroundColor(.blue)
                        .multilineTextAlignment(.center)
                        .keyboardType(.numberPad)
                        .frame(width: 90, height: 44)
                        .textFieldStyle(RoundedBorderTextFieldStyle())
                        .focused($rigaAttiva, equals: flat)
                        .id(flat)
                }
                .padding(.horizontal, 10).padding(.vertical, 5)
            }
        }
        .background(RoundedRectangle(cornerRadius: 3).stroke(Color.gray.opacity(0.65), lineWidth: 1))
    }

    private func binding(g: Int, v: Int) -> Binding<String> {
        Binding(
            get: { gruppi[g].voci[v].quantita },
            set: { gruppi[g].voci[v].quantita = $0 }
        )
    }

    private func indicePiatto(_ g: Int, _ v: Int) -> Int {
        var n = 0
        for i in 0..<g { n += gruppi[i].voci.count }
        return n + v
    }

    private func prossimaRiga() {
        if let r = rigaAttiva { rigaAttiva = r + 1 }
        else { rigaAttiva = 1 }
    }

    private func aggiungiArticolo() {
        let nome = nuovoArticolo.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !nome.isEmpty else { return }
        let esiste = gruppi.contains { $0.nome.caseInsensitiveCompare(nome) == .orderedSame }
        guard !esiste else {
            nuovoArticolo = ""
            mostraAggiungiArticolo = false
            return
        }
        archivio.aggiungiLavorazione(nome)
        gruppi.append(GruppoLavorazione(nome: nome, voci: [VoceLavorazione(nome: "")]))
        nuovoArticolo = ""
        mostraAggiungiArticolo = false
    }

    private func salva() {
        var lista: [Lavorazione] = []
        for g in gruppi {
            for v in g.voci {
                let nome = v.nome.isEmpty ? g.nome : "\(g.nome) \(v.nome)"
                lista.append(Lavorazione(nome: nome, quantita: v.quantita.isEmpty ? "0" : v.quantita))
            }
        }
        archivio.salvaBolletta(Bolletta(id: bollettaDaModificare?.id ?? UUID(), data: data, lavorazioni: lista))
        presentationMode.wrappedValue.dismiss()
    }
}

struct SelezionaDataModificaView: View {
    @ObservedObject var archivio: Archivio
    @Environment(\.presentationMode) private var presentationMode
    @State private var data = Date()
    @State private var bolletteTrovate: [Bolletta] = []
    @State private var mostraScelta = false
    @State private var bollettaSelezionata: Bolletta?

    var body: some View {
        NavigationView {
            VStack(spacing: 20) {
                Text("SCEGLI LA DATA")
                    .font(.title2)

                HStack(spacing: 12) {
                    Image(systemName: "calendar").font(.title2)
                    DatePicker("Data", selection: $data, displayedComponents: .date)
                        .datePickerStyle(.compact)
                        .environment(\.locale, Locale(identifier: "it_IT"))
                        .labelsHidden()
                    Spacer()
                }
                .padding()
                .background(RoundedRectangle(cornerRadius: 12).stroke(Color.gray.opacity(0.35)))
                Text(data.formatted(.dateTime.day().month(.wide).year()))
                    .font(.title3)
                    .environment(\.locale, Locale(identifier: "it_IT"))

                Button("OK") {
                    cercaBollette()
                }
                .font(.title2)
                .frame(maxWidth: .infinity)
                .padding()
                .buttonStyle(.borderedProminent)

                Spacer()
            }
            .padding(22)
            .navigationTitle("Modifica bolletta")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .navigationBarLeading) {
                    Button("Annulla") { presentationMode.wrappedValue.dismiss() }
                }
            }
            .sheet(item: $bollettaSelezionata) { bolletta in
                NuovaBollettaView(archivio: archivio, bollettaDaModificare: bolletta)
            }
            .sheet(isPresented: $mostraScelta) {
                NavigationView {
                    List {
                        Section("BOLLETTE DEL \(data.formatted(date: .numeric, time: .omitted))") {
                            ForEach(bolletteTrovate) { bolletta in
                                Button {
                                    mostraScelta = false
                                    DispatchQueue.main.async {
                                        bollettaSelezionata = bolletta
                                    }
                                } label: {
                                    HStack {
                                        VStack(alignment: .leading, spacing: 4) {
                                            Text("BOLLETTA")
                                                .font(.title3).fontWeight(.semibold)
                                            Text("\(totalePezzi(bolletta)) pezzi")
                                                .foregroundColor(.secondary)
                                        }
                                        Spacer()
                                        Image(systemName: "chevron.right")
                                            .foregroundColor(.secondary)
                                    }
                                    .padding(.vertical, 10)
                                }
                            }
                        }
                    }
                    .navigationTitle("Scegli bolletta")
                    .navigationBarTitleDisplayMode(.inline)
                }
            }
        }
    }

    private func cercaBollette() {
        let cal = Calendar.current
        bolletteTrovate = archivio.bollette.filter { cal.isDate($0.data, inSameDayAs: data) }

        if bolletteTrovate.count == 1 {
            bollettaSelezionata = bolletteTrovate[0]
        } else if bolletteTrovate.count > 1 {
            mostraScelta = true
        }
    }

    private func totalePezzi(_ bolletta: Bolletta) -> Int {
        bolletta.lavorazioni.reduce(0) { $0 + (Int($1.quantita) ?? 0) }
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

struct DatiAnalizzatiView: View {
    @ObservedObject var archivio: Archivio
    @ObservedObject var analysisStore: PDFAnalysisStore
    @Environment(\.presentationMode) private var presentationMode
    @State private var bollettaDaAprire: Bolletta?

    private var giorniAzienda: [PDFAnalysisDay] {
        var perData: [Date: [PDFAnalysisRow]] = [:]
        for giorno in analysisStore.giorniAzienda() {
            perData[giorno.date, default: []].append(contentsOf: giorno.rows)
        }
        return perData.keys.sorted().map { PDFAnalysisDay(date: $0, rows: perData[$0] ?? []) }
    }

    private var tutteLeDate: [Date] {
        let nostre = Set(archivio.bollette.map { giornoSenzaOra($0.data) })
        let azienda = Set(giorniAzienda.map { giornoSenzaOra($0.date) })
        return Array(nostre.union(azienda)).sorted(by: >)
    }

    private func giornoSenzaOra(_ data: Date) -> Date {
        Calendar.current.startOfDay(for: data)
    }

    private func bollettaNostra(per data: Date) -> Bolletta? {
        archivio.bollette.first { giornoSenzaOra($0.data) == giornoSenzaOra(data) }
    }

    private func giornoAzienda(per data: Date) -> PDFAnalysisDay? {
        giorniAzienda.first { giornoSenzaOra($0.date) == giornoSenzaOra(data) }
    }

    private func normalizza(_ testo: String) -> String {
        testo.folding(options: [.diacriticInsensitive, .caseInsensitive], locale: .current)
            .replacingOccurrences(of: " ", with: "")
            .replacingOccurrences(of: "-", with: "")
            .replacingOccurrences(of: "_", with: "")
    }

    private func confronto(_ nostra: Bolletta?, _ azienda: PDFAnalysisDay?) -> (nsOK: Bool, bagfulOK: Bool, bagfulMissing: Bool) {
        guard let nostra else {
            return (false, azienda != nil, false)
        }
        guard let azienda else {
            return (true, false, true)
        }

        var aziendaMap: [String: Int] = [:]
        for riga in azienda.rows {
            aziendaMap[normalizza(riga.article), default: 0] += riga.quantity
        }
        var nostraMap: [String: Int] = [:]
        for lavoro in nostra.lavorazioni {
            let quantita = Int(lavoro.quantita) ?? 0
            // Le celle vuote/zero dell'app equivalgono alle celle vuote
            // dell'Excel aziendale: non devono creare una differenza.
            guard quantita > 0 else { continue }
            nostraMap[normalizza(lavoro.nome), default: 0] += quantita
        }
        return (true, nostraMap == aziendaMap, false)
    }

    private func coloreData(_ data: Date) -> Color {
        let stato = confronto(bollettaNostra(per: data), giornoAzienda(per: data))
        return (stato.nsOK && stato.bagfulOK) ? .green : .red
    }

    private func testoData(_ data: Date) -> String {
        let formatter = DateFormatter()
        formatter.dateFormat = "dd/MM/yyyy"
        return formatter.string(from: data)
    }

    var body: some View {
        NavigationView {
            VStack(spacing: 0) {
                if tutteLeDate.isEmpty {
                    Spacer()
                    Text("Nessuna bolletta caricata.")
                        .font(.title3)
                    Spacer()
                } else {
                    HStack(spacing: 0) {
                        Text("DATA")
                            .font(.headline)
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .padding(.horizontal, 12)
                            .padding(.vertical, 12)

                        Text("NS\nCARICATE")
                            .font(.headline)
                            .multilineTextAlignment(.center)
                            .frame(width: 110)
                            .padding(.vertical, 12)

                        Text("BAGFUL")
                            .font(.headline)
                            .frame(width: 110)
                            .multilineTextAlignment(.center)
                            .padding(.vertical, 12)
                    }
                    .background(Color.gray.opacity(0.15))

                    Divider()

                    List {
                        ForEach(tutteLeDate, id: \.self) { data in
                            let nostra = bollettaNostra(per: data)
                            let azienda = giornoAzienda(per: data)
                            let stato = confronto(nostra, azienda)

                            Button {
                                if let nostra { bollettaDaAprire = nostra }
                            } label: {
                                HStack(spacing: 0) {
                                    Text(testoData(data))
                                        .font(.body)
                                        .foregroundColor(coloreData(data))
                                        .frame(maxWidth: .infinity, alignment: .leading)

                                    Text(stato.nsOK ? "✓" : "X")
                                        .font(.title2.weight(.bold))
                                        .foregroundColor(stato.nsOK ? .green : .red)
                                        .frame(width: 110)

                                    Text(stato.bagfulOK ? "✓" : (stato.bagfulMissing ? "XX" : "X"))
                                        .font(.title2.weight(.bold))
                                        .foregroundColor(stato.bagfulOK ? .green : .red)
                                        .frame(width: 110)
                                }
                                .padding(.vertical, 8)
                                .contentShape(Rectangle())
                            }
                            .buttonStyle(.plain)
                        }
                    }
                    .listStyle(.plain)
                }
            }
            .navigationTitle("Dati analizzati")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .navigationBarLeading) {
                    Button("Chiudi") { presentationMode.wrappedValue.dismiss() }
                }
            }
            .sheet(item: $bollettaDaAprire) { bolletta in
                NuovaBollettaView(archivio: archivio, bollettaDaModificare: bolletta)
            }
        }
        .navigationViewStyle(.stack)
    }
}

struct ConfrontoBollettaView: View {
    let bolletta: Bolletta

    var body: some View {
        VStack(spacing: 0) {
            Text("CONFRONTO")
                .font(.title2)
                
                .padding(.top, 12)

            Text(bolletta.data.formatted(date: .numeric, time: .omitted))
                .font(.headline)
                .padding(.bottom, 12)

            HStack(spacing: 0) {
                Text("CARICATI")
                    .font(.headline)
                    .frame(maxWidth: .infinity)
                    .padding(10)
                    .background(Color.gray.opacity(0.15))

                Text("AZIENDA")
                    .font(.headline)
                    .frame(maxWidth: .infinity)
                    .padding(10)
                    .background(Color.gray.opacity(0.15))

                Text("DIFFERENZA")
                    .font(.headline)
                    .frame(width: 105)
                    .padding(10)
                    .background(Color.gray.opacity(0.15))
            }

            Divider()

            ScrollView {
                LazyVStack(spacing: 0) {
                    ForEach(bolletta.lavorazioni) { lavorazione in
                        let caricato = Int(lavorazione.quantita) ?? 0

                        HStack(spacing: 0) {
                            Text(lavorazione.nome)
                                .frame(maxWidth: .infinity, alignment: .leading)

                            Text("\(caricato)")
                                .frame(maxWidth: .infinity)

                            Text("—")
                                .frame(width: 105)
                        }
                        .padding(.horizontal, 10)
                        .padding(.vertical, 12)

                        Divider()
                    }
                }
            }

            Text("Il confronto con i dati dell'azienda sarà compilato automaticamente quando verrà importato il prospetto.")
                .font(.footnote)
                .multilineTextAlignment(.center)
                .padding(12)
        }
        .navigationTitle("Differenze")
        .navigationBarTitleDisplayMode(.inline)
    }
}

