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
        "GLAM",
        "GLAM XL",
        "ESSENTIAL",
        "CLOSE",
        "CASE",
        "TRAINING",
        "MESSENGER",
        "BAGPACK",
        "TODAY",
        "ACTIVITY",
        "ZAINI MARINA",
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
        aggiornaFileNostreBollette()
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
        aggiornaFileNostreBollette()
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

    /// File Excel sempre aggiornato con tutte le bollette inserite/modificate.
    /// Viene riscritto ad ogni salvataggio, mantenendo tutte le date, gli articoli
    /// e le quantità presenti nell'archivio.
    func fileNostreBollette() -> URL? {
        let url = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("NOSTRE_BOLLETTE.xlsx")
        if !FileManager.default.fileExists(atPath: url.path) {
            aggiornaFileNostreBollette()
        }
        return FileManager.default.fileExists(atPath: url.path) ? url : nil
    }

    private func aggiornaFileNostreBollette() {
        let url = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("NOSTRE_BOLLETTE.xlsx")

        do {
            try NostreBolletteExcel.creaFile(bollette: bollette, nomiLavorazioni: nomiLavorazioni, url: url)
        } catch {
            print("Errore creazione NOSTRE_BOLLETTE.xlsx: \(error)")
        }
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
    @State private var mostraArchivioAnalisi = false
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

                homeButton(title: "ANALISI", icon: "chart.bar.fill", tint: .purple) {
                    mostraDatiAnalizzati = true
                }

                homeButton(title: "ARCHIVIO CONTEGGI", icon: "archivebox.fill", tint: .indigo) {
                    mostraArchivioAnalisi = true
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
                DatiAnalizzatiView(archivio: archivio, analysisStore: analysisStore, fileStore: pdfTransfer)
            }
            .sheet(isPresented: $mostraArchivioAnalisi) {
                ArchivioAnalisiView(analysisStore: analysisStore)
            }
            .sheet(isPresented: $mostraPDF) {
                PDFImportatiView(store: pdfTransfer, analysisStore: analysisStore, archivio: archivio)
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
    @ObservedObject var archivio: Archivio
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
                                analysisStore.analizza(file: file, bollette: archivio.bollette)
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
        VStack(spacing: 16) {
            DataMeseSelector(data: $data)
            Button {
                dataConfermata = true
                rigaAttiva = 0
            } label: {
                Text("CONFERMA DATA").font(.title2.weight(.semibold))
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

struct DataMeseSelector: View {
    @Binding var data: Date
    private let cal = Calendar(identifier: .gregorian)
    private let mesi = ["GENNAIO", "FEBBRAIO", "MARZO", "APRILE", "MAGGIO", "GIUGNO", "LUGLIO", "AGOSTO", "SETTEMBRE", "OTTOBRE", "NOVEMBRE", "DICEMBRE"]

    private var mese: Int { cal.component(.month, from: data) }
    private var anno: Int { cal.component(.year, from: data) }
    private var primoGiorno: Date { cal.date(from: DateComponents(year: anno, month: mese, day: 1))! }
    private var giorniNelMese: Int { cal.range(of: .day, in: .month, for: primoGiorno)!.count }
    private var offset: Int { (cal.component(.weekday, from: primoGiorno) + 5) % 7 }

    private func cambiaMese(_ delta: Int) {
        guard let nuovoMese = cal.date(byAdding: .month, value: delta, to: primoGiorno) else { return }
        let y = cal.component(.year, from: nuovoMese)
        let m = cal.component(.month, from: nuovoMese)
        let giorno = min(cal.component(.day, from: data), cal.range(of: .day, in: .month, for: nuovoMese)!.count)
        data = cal.date(from: DateComponents(year: y, month: m, day: giorno))!
    }

    var body: some View {
        VStack(spacing: 14) {
            Text("SCEGLI LA DATA")
                .font(.title2.weight(.semibold))

            HStack {
                Button { cambiaMese(-1) } label: {
                    Image(systemName: "chevron.left.circle.fill").font(.system(size: 34))
                }
                .accessibilityLabel("Mese precedente")
                Spacer()
                VStack(spacing: 2) {
                    Text(mesi[mese - 1]).font(.title3.weight(.bold))
                    Text(String(anno)).font(.headline).foregroundColor(.secondary)
                }
                Spacer()
                Button { cambiaMese(1) } label: {
                    Image(systemName: "chevron.right.circle.fill").font(.system(size: 34))
                }
                .accessibilityLabel("Mese successivo")
            }
            .padding(.horizontal, 8)

            HStack(spacing: 0) {
                ForEach(["L", "M", "M", "G", "V", "S", "D"], id: \.self) { g in
                    Text(g).font(.caption.weight(.bold)).frame(maxWidth: .infinity)
                }
            }

            LazyVGrid(columns: Array(repeating: GridItem(.flexible()), count: 7), spacing: 8) {
                ForEach(0..<(offset + giorniNelMese), id: \.self) { indice in
                    if indice < offset {
                        Color.clear.frame(height: 40)
                    } else {
                        let giorno = indice - offset + 1
                        Button {
                            data = cal.date(from: DateComponents(year: anno, month: mese, day: giorno))!
                        } label: {
                            Text(String(giorno))
                                .font(.headline)
                                .frame(maxWidth: .infinity, minHeight: 40)
                                .background(cal.component(.day, from: data) == giorno ? Color.accentColor : Color.gray.opacity(0.12))
                                .foregroundColor(cal.component(.day, from: data) == giorno ? .white : .primary)
                                .clipShape(RoundedRectangle(cornerRadius: 9))
                        }
                    }
                }
            }

            Text(data.formatted(.dateTime.day().month(.wide).year()))
                .font(.title3.weight(.semibold))
                .environment(\.locale, Locale(identifier: "it_IT"))
                .frame(maxWidth: .infinity)
                .padding(.vertical, 10)
                .background(Color.gray.opacity(0.10))
                .clipShape(RoundedRectangle(cornerRadius: 10))
        }
        .environment(\.locale, Locale(identifier: "it_IT"))
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
                DataMeseSelector(data: $data)

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
    @ObservedObject var fileStore: PDFTransferStore
    @Environment(\.presentationMode) private var presentationMode
    @State private var mostraCondivisione = false
    @State private var messaggio = ""

    private var fileNostre: URL? {
        archivio.fileNostreBollette()
    }

    private var fileAzienda: URL? {
        fileStore.files.first
    }

    private var testoAnalisi: String {
        """
        ANALIZZA QUESTI DUE FILE.

        Il primo file (NOSTRE_BOLLETTE.xlsx) contiene le bollette inserite manualmente da noi, con date, articoli e quantità.
        Il secondo file è il prospetto ricevuto dall'azienda.

        Confronta i due file in modo intelligente, verificando:
        1. date delle bollette;
        2. articoli;
        3. quantità dei pezzi;
        4. eventuali bollette presenti da una parte e mancanti dall'altra;
        5. casi in cui una bolletta mancante nel file aziendale sia stata eventualmente accorpata nella bolletta/data successiva;
        6. casi inversi, cioè quantità presenti nel nostro archivio ma non correttamente attribuite dall'azienda.

        Non fermarti al semplice confronto dei totali: ricostruisci le corrispondenze tra date e quantità quando è possibile.

        Mostra SOLO le incongruenze effettivamente trovate, spiegandole in modo chiaro con data, articolo e quantità coinvolte.

        Se i dati coincidono, indica chiaramente che il confronto è OK.

        Infine calcola, quando i dati aziendali lo permettono, il TOTALE MATURATO / FATTURABILE.

        Non modificare i file originali.
        """
    }

    var body: some View {
        NavigationView {
            VStack(spacing: 18) {
                ScrollView {
                    VStack(spacing: 16) {
                        Text("ANALISI")
                            .font(.title2.weight(.bold))
                            .padding(.top, 8)

                        Text("Qui trovi i due file da confrontare. Il file delle nostre bollette viene aggiornato automaticamente ogni volta che salvi o modifichi una bolletta.")
                            .font(.subheadline)
                            .foregroundColor(.secondary)
                            .multilineTextAlignment(.center)
                            .padding(.horizontal, 8)

                        fileCard(
                            title: "NOSTRE BOLLETTE",
                            subtitle: fileNostre?.lastPathComponent ?? "File non ancora creato",
                            icon: "doc.text.fill",
                            tint: .purple,
                            available: fileNostre != nil
                        )

                        fileCard(
                            title: "FILE AZIENDA",
                            subtitle: fileAzienda?.lastPathComponent ?? "Nessun file azienda caricato",
                            icon: "building.2.fill",
                            tint: .teal,
                            available: fileAzienda != nil
                        )

                        if fileNostre != nil && fileAzienda != nil {
                            VStack(spacing: 12) {
                                Image(systemName: "arrow.left.arrow.right.circle.fill")
                                    .font(.system(size: 38))
                                    .foregroundColor(.green)

                                Text("PRONTI PER IL CONFRONTO")
                                    .font(.headline)

                                Text("Premi il pulsante per inviare insieme i due file e la richiesta di analisi.")
                                    .font(.subheadline)
                                    .foregroundColor(.secondary)
                                    .multilineTextAlignment(.center)

                                Button {
                                    mostraCondivisione = true
                                } label: {
                                    Label("INVIA A CHATGPT PER ANALISI", systemImage: "paperplane.fill")
                                        .font(.headline)
                                        .frame(maxWidth: .infinity)
                                        .padding(.vertical, 15)
                                }
                                .buttonStyle(.borderedProminent)
                                .tint(.green)
                            }
                            .padding(16)
                            .frame(maxWidth: .infinity)
                            .background(Color.green.opacity(0.08))
                            .overlay(
                                RoundedRectangle(cornerRadius: 14)
                                    .stroke(Color.green.opacity(0.25), lineWidth: 1)
                            )
                            .cornerRadius(14)
                        } else {
                            VStack(spacing: 8) {
                                Image(systemName: "exclamationmark.triangle.fill")
                                    .foregroundColor(.orange)
                                Text("Per fare l'analisi servono entrambi i file.")
                                    .font(.headline)
                                Text("Inserisci/modifica le nostre bollette e carica il file dell'azienda dal menu dedicato.")
                                    .font(.subheadline)
                                    .foregroundColor(.secondary)
                                    .multilineTextAlignment(.center)
                            }
                            .padding(16)
                            .frame(maxWidth: .infinity)
                            .background(Color.orange.opacity(0.08))
                            .cornerRadius(14)
                        }

                        VStack(alignment: .leading, spacing: 8) {
                            Text("TESTO INVIATO PER L'ANALISI")
                                .font(.headline)

                            Text(testoAnalisi)
                                .font(.footnote)
                                .foregroundColor(.secondary)
                                .frame(maxWidth: .infinity, alignment: .leading)
                                .padding(12)
                                .background(Color.gray.opacity(0.08))
                                .cornerRadius(10)
                        }
                    }
                    .padding(14)
                }
            }
            .navigationTitle("Analisi")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .navigationBarLeading) {
                    Button("Chiudi") { presentationMode.wrappedValue.dismiss() }
                }
            }
            .sheet(isPresented: $mostraCondivisione) {
                if let nostro = fileNostre, let azienda = fileAzienda {
                    CondivisioneAnalisiView(
                        files: [nostro, azienda],
                        testo: testoAnalisi
                    )
                }
            }
            .alert("ANALISI", isPresented: Binding(
                get: { !messaggio.isEmpty },
                set: { if !$0 { messaggio = "" } }
            )) {
                Button("OK", role: .cancel) { }
            } message: {
                Text(messaggio)
            }
        }
        .navigationViewStyle(.stack)
    }

    @ViewBuilder
    private func fileCard(
        title: String,
        subtitle: String,
        icon: String,
        tint: Color,
        available: Bool
    ) -> some View {
        HStack(spacing: 14) {
            Image(systemName: icon)
                .font(.system(size: 30))
                .foregroundColor(available ? tint : .gray)

            VStack(alignment: .leading, spacing: 4) {
                Text(title)
                    .font(.headline)
                Text(subtitle)
                    .font(.subheadline)
                    .foregroundColor(.secondary)
                    .lineLimit(2)
            }

            Spacer()

            Image(systemName: available ? "checkmark.circle.fill" : "xmark.circle.fill")
                .foregroundColor(available ? .green : .red)
                .font(.title3)
        }
        .padding(14)
        .background(tint.opacity(0.08))
        .cornerRadius(12)
    }
}

struct CondivisioneAnalisiView: UIViewControllerRepresentable {
    let files: [URL]
    let testo: String

    func makeUIViewController(context: Context) -> UIActivityViewController {
        let controller = UIActivityViewController(
            activityItems: files + [testo],
            applicationActivities: nil
        )
        return controller
    }

    func updateUIViewController(_ uiViewController: UIActivityViewController, context: Context) { }
}

struct ArchivioAnalisiView: View {
    @ObservedObject var analysisStore: PDFAnalysisStore
    @Environment(\.presentationMode) private var presentationMode

    private var gruppiAnno: [(anno: Int, analisi: [PDFAnalysisResult])] {
        let cal = Calendar.current
        let grouped = Dictionary(grouping: analysisStore.analyses) {
            cal.component(.year, from: $0.date ?? $0.days.first?.date ?? Date())
        }
        return grouped.keys.sorted(by: >).map { anno in
            (anno, grouped[anno]!.sorted {
                ($0.date ?? $0.days.first?.date ?? .distantPast) >
                ($1.date ?? $1.days.first?.date ?? .distantPast)
            })
        }
    }

    private func periodo(_ a: PDFAnalysisResult) -> String {
        let dates = a.days.map(\.date)
        let start = dates.min() ?? a.date
        let end = dates.max() ?? a.date
        guard let start else { return "Periodo non disponibile" }
        let f = DateFormatter()
        f.locale = Locale(identifier: "it_IT")
        f.dateFormat = "dd MMM yyyy"
        if let end, !Calendar.current.isDate(start, inSameDayAs: end) {
            return "\(f.string(from: start)) – \(f.string(from: end))"
        }
        return f.string(from: start)
    }

    private func totale(_ a: PDFAnalysisResult) -> Double {
        a.days.flatMap(\.rows).compactMap(\.total).reduce(0, +)
    }

    private func totaleAnno(_ analisi: [PDFAnalysisResult]) -> Double {
        analisi.reduce(0) { $0 + totale($1) }
    }

    private func euro(_ value: Double) -> String {
        value.formatted(.currency(code: "EUR"))
    }

    var body: some View {
        NavigationView {
            Group {
                if gruppiAnno.isEmpty {
                    VStack(spacing: 14) {
                        Image(systemName: "archivebox")
                            .font(.system(size: 48))
                            .foregroundColor(.indigo)
                        Text("ARCHIVIO ANALISI")
                            .font(.title2.weight(.semibold))
                        Text("Le analisi salvate compariranno qui, raggruppate per anno.")
                            .multilineTextAlignment(.center)
                            .foregroundColor(.secondary)
                    }
                    .padding(28)
                } else {
                    List {
                        ForEach(gruppiAnno, id: \.anno) { gruppo in
                            Section {
                                VStack(alignment: .leading, spacing: 4) {
                                    Text("TOTALE ANNUO")
                                        .font(.caption.weight(.semibold))
                                        .foregroundColor(.secondary)
                                    Text(euro(totaleAnno(gruppo.analisi)))
                                        .font(.system(size: 28, weight: .bold))
                                        .foregroundColor(.green)
                                }
                                .padding(.vertical, 6)

                                ForEach(gruppo.analisi) { analisi in
                                    VStack(alignment: .leading, spacing: 6) {
                                        HStack {
                                            Image(systemName: "doc.text.fill")
                                                .foregroundColor(.indigo)
                                            Text(analisi.fileName)
                                                .font(.headline)
                                                .lineLimit(2)
                                            Spacer()
                                        }
                                        Text(periodo(analisi))
                                            .font(.subheadline)
                                            .foregroundColor(.secondary)
                                        HStack {
                                            Text("Totale maturato")
                                                .foregroundColor(.secondary)
                                            Spacer()
                                            Text(euro(totale(analisi)))
                                                .font(.headline.weight(.semibold))
                                        }
                                    }
                                    .padding(.vertical, 7)
                                }
                            } header: {
                                HStack {
                                    Text(String(gruppo.anno))
                                        .font(.title2.weight(.bold))
                                    Spacer()
                                    Text(euro(totaleAnno(gruppo.analisi)))
                                        .font(.headline.weight(.bold))
                                        .foregroundColor(.green)
                                }
                            }
                        }
                    }
                    .listStyle(.insetGrouped)
                }
            }
            .navigationTitle("Archivio analisi")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .navigationBarLeading) {
                    Button("Chiudi") { presentationMode.wrappedValue.dismiss() }
                }
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

