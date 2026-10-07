import SwiftUI
import UIKit
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
            .fullScreenCover(isPresented: $nuovaBolletta) {
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
                                analysisStore.verificaFileAzienda(file: file)
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

struct FormArticolo: Identifiable {
    let id: String
    let nome: String
    let varianti: [String]
    let x: CGFloat
    let y: CGFloat
    let width: CGFloat
    let height: CGFloat
}

struct NuovaBollettaView: View {
    @ObservedObject var archivio: Archivio
    @Environment(\.presentationMode) private var presentationMode
    private let bollettaDaModificare: Bolletta?

    @State private var data: Date
    @State private var mostraCalendario = false
    @State private var quantita: [String: String]
    @State private var nuoviArticoli: [Lavorazione]
    @State private var mostraConfermaCancella = false
    @State private var mostraAggiungiArticolo = false
    @State private var nuovoNomeArticolo = ""

    private let canvasW: CGFloat = 768
    private let canvasH: CGFloat = 1024

    init(archivio: Archivio, bollettaDaModificare: Bolletta? = nil) {
        self.archivio = archivio
        self.bollettaDaModificare = bollettaDaModificare
        _data = State(initialValue: bollettaDaModificare?.data ?? Date())

        var valori: [String: String] = [:]
        var personalizzati: [Lavorazione] = []
        let standard = Self.chiaviStandard
        let normalizza: (String) -> String = { testo in
            testo.folding(options: [.diacriticInsensitive, .caseInsensitive], locale: .current)
                .replacingOccurrences(of: " ", with: "")
                .replacingOccurrences(of: "-", with: "")
        }

        if let b = bollettaDaModificare {
            for lavoro in b.lavorazioni {
                let n = normalizza(lavoro.nome)
                if let chiave = standard.first(where: { normalizza($0) == n }) {
                    valori[chiave] = lavoro.quantita == "0" ? "" : lavoro.quantita
                } else {
                    personalizzati.append(lavoro)
                }
            }
        }
        _quantita = State(initialValue: valori)
        _nuoviArticoli = State(initialValue: personalizzati)
    }

    private static var chiaviStandard: [String] {
        [
            "CLASSY manici corti", "CLASSY manici corto e tracolla",
            "BAGPACK L", "BAGPACK M", "BAGPACK S",
            "TRAINING L", "TRAINING M",
            "MESSENGER L", "MESSENGER M",
            "TODAY M", "TODAY S",
            "BAGPACK PRO", "ACTIVITY",
            "MONEYFUL L", "MONEYFUL M",
            "CASE L", "CASE M", "CASE S", "ESSENTIAL"
        ]
    }

    var body: some View {
        GeometryReader { geo in
            let scale = min(geo.size.width / canvasW, geo.size.height / canvasH)

            ZStack {
                Color.white.ignoresSafeArea()

                ZStack {
                    // La maschera approvata: identica alla schermata mostrata dall'utente.
                    Image("BollettaUI")
                        .resizable()
                        .frame(width: canvasW, height: canvasH)

                    // Titolo dinamico.
                    Rectangle()
                        .fill(Color.white.opacity(0.97))
                        .frame(width: 310, height: 45)
                        .position(x: 385, y: 52)
                    Text(bollettaDaModificare == nil ? "Nuova Bolletta" : "Modifica Bolletta")
                        .font(.system(size: 20, weight: .semibold))
                        .foregroundColor(.black)
                        .position(x: 385, y: 52)

                    // Data: campo reale, mantenendo esattamente l'aspetto della maschera.
                    Rectangle()
                        .fill(Color.white.opacity(0.98))
                        .frame(width: 185, height: 46)
                        .position(x: 180, y: 112)
                    RoundedRectangle(cornerRadius: 5)
                        .stroke(Color.gray.opacity(0.55), lineWidth: 1)
                        .frame(width: 185, height: 46)
                        .position(x: 180, y: 112)
                    HStack(spacing: 8) {
                        Text(dataString)
                            .font(.system(size: 18, weight: .regular))
                            .foregroundColor(.primary)
                        Image(systemName: "calendar")
                            .font(.system(size: 20))
                            .foregroundColor(.blue)
                    }
                    .position(x: 180, y: 112)
                    Button { mostraCalendario = true } label: {
                        Color.clear.frame(width: 185, height: 46)
                    }
                    .position(x: 180, y: 112)

                    // Quantità: le caselle sono quelle della maschera; il valore digitato è rosso.
                    quantityField("CLASSY manici corti", x: 652, y: 208, w: 104, h: 34)
                    quantityField("CLASSY manici corto e tracolla", x: 652, y: 250, w: 104, h: 34)

                    quantityField("BAGPACK L", x: 330, y: 352, w: 80, h: 34)
                    quantityField("BAGPACK M", x: 330, y: 395, w: 80, h: 34)
                    quantityField("BAGPACK S", x: 330, y: 438, w: 80, h: 34)

                    quantityField("TRAINING L", x: 330, y: 520, w: 80, h: 34)
                    quantityField("TRAINING M", x: 330, y: 563, w: 80, h: 34)

                    quantityField("MESSENGER L", x: 330, y: 645, w: 80, h: 34)
                    quantityField("MESSENGER M", x: 330, y: 688, w: 80, h: 34)

                    quantityField("TODAY M", x: 330, y: 785, w: 80, h: 34)
                    quantityField("TODAY S", x: 330, y: 828, w: 80, h: 34)

                    quantityField("BAGPACK PRO", x: 672, y: 395, w: 104, h: 34)
                    quantityField("ACTIVITY", x: 672, y: 520, w: 104, h: 34)

                    quantityField("MONEYFUL L", x: 674, y: 622, w: 100, h: 34)
                    quantityField("MONEYFUL M", x: 674, y: 669, w: 100, h: 34)

                    quantityField("CASE L", x: 674, y: 740, w: 100, h: 34)
                    quantityField("CASE M", x: 674, y: 785, w: 100, h: 34)
                    quantityField("CASE S", x: 674, y: 829, w: 100, h: 34)
                    quantityField("ESSENTIAL", x: 674, y: 888, w: 100, h: 34)

                    // Spazio inferiore lasciato alla scrittura degli articoli nuovi.
                    nuoviArticoliOverlay()

                    // Bottoni trasparenti sopra quelli disegnati nella maschera.
                    Button { presentationMode.wrappedValue.dismiss() } label: {
                        Color.clear.frame(width: 115, height: 48)
                    }
                    .position(x: 70, y: 51)
                    .accessibilityLabel("Indietro")

                    Button { salva() } label: {
                        Color.clear.frame(width: 95, height: 48)
                    }
                    .position(x: 710, y: 51)
                    .accessibilityLabel("Salva")
                }
                .frame(width: canvasW, height: canvasH)
                .scaleEffect(scale)
                .position(x: geo.size.width / 2, y: geo.size.height / 2)
            }
        }
        .ignoresSafeArea()
        .statusBar(hidden: true)
        .sheet(isPresented: $mostraCalendario) {
            NavigationView {
                VStack {
                    DatePicker("Data bolletta", selection: $data, displayedComponents: [.date])
                        .datePickerStyle(.graphical)
                        .padding()
                    Spacer()
                }
                .navigationTitle("Scegli data")
                .toolbar {
                    ToolbarItem(placement: .navigationBarTrailing) {
                        Button("FINE") { mostraCalendario = false }
                            .font(.headline)
                    }
                }
            }
        }
        .sheet(isPresented: $mostraAggiungiArticolo) {
            NavigationView {
                Form {
                    Section("NUOVO ARTICOLO") {
                        TextField("Nome articolo", text: $nuovoNomeArticolo)
                    }
                    Section {
                        Button("AGGIUNGI") { aggiungiArticolo() }
                            .disabled(nuovoNomeArticolo.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                    }
                }
                .navigationTitle("Nuovo articolo")
                .toolbar {
                    ToolbarItem(placement: .navigationBarLeading) {
                        Button("Annulla") { mostraAggiungiArticolo = false }
                    }
                }
            }
        }
        .alert("Cancella bolletta", isPresented: $mostraConfermaCancella) {
            Button("Cancella", role: .destructive) {
                if let b = bollettaDaModificare { archivio.eliminaBolletta(id: b.id) }
                presentationMode.wrappedValue.dismiss()
            }
            Button("Annulla", role: .cancel) { }
        } message: {
            Text("Vuoi cancellare definitivamente questa bolletta?")
        }
    }

    private var dataString: String {
        let f = DateFormatter()
        f.locale = Locale(identifier: "it_IT")
        f.dateFormat = "dd/MM/yyyy"
        return f.string(from: data)
    }

    @ViewBuilder
    private func quantityField(_ key: String, x: CGFloat, y: CGFloat, w: CGFloat, h: CGFloat) -> some View {
        TextField("", text: bindingQuantita(key))
            .keyboardType(.numberPad)
            .multilineTextAlignment(.center)
            .font(.system(size: 20, weight: .bold))
            .foregroundColor(.red)
            .frame(width: w, height: h)
            .background(Color.clear)
            .position(x: x, y: y)
    }

    @ViewBuilder
    private func nuoviArticoliOverlay() -> some View {
        if nuoviArticoli.isEmpty {
            Button {
                mostraAggiungiArticolo = true
            } label: {
                Color.clear.frame(width: 680, height: 55)
            }
            .position(x: 384, y: 968)
            .accessibilityLabel("Aggiungi articolo")
        } else {
            VStack(spacing: 4) {
                ForEach($nuoviArticoli) { $articolo in
                    HStack(spacing: 10) {
                        TextField("articolo", text: $articolo.nome)
                            .font(.system(size: 16))
                            .frame(width: 560)
                        TextField("", text: $articolo.quantita)
                            .keyboardType(.numberPad)
                            .multilineTextAlignment(.center)
                            .font(.system(size: 18, weight: .bold))
                            .foregroundColor(.red)
                            .frame(width: 75)
                    }
                }
            }
            .padding(.horizontal, 18)
            .frame(width: 690, height: 60, alignment: .top)
            .position(x: 384, y: 968)
        }
    }

    private func bindingQuantita(_ key: String) -> Binding<String> {
        Binding(
            get: { quantita[key] ?? "" },
            set: { quantita[key] = $0.filter(\.isNumber) }
        )
    }

    private func aggiungiArticolo() {
        let nome = nuovoNomeArticolo.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !nome.isEmpty else { return }
        guard !nuoviArticoli.contains(where: { $0.nome.caseInsensitiveCompare(nome) == .orderedSame }) else {
            nuovoNomeArticolo = ""
            mostraAggiungiArticolo = false
            return
        }
        nuoviArticoli.append(Lavorazione(nome: nome, quantita: ""))
        archivio.aggiungiLavorazione(nome)
        nuovoNomeArticolo = ""
        mostraAggiungiArticolo = false
    }

    private func salva() {
        var lista: [Lavorazione] = []
        for key in Self.chiaviStandard {
            lista.append(Lavorazione(nome: key, quantita: quantita[key].flatMap { $0.isEmpty ? nil : $0 } ?? "0"))
        }
        lista.append(contentsOf: nuoviArticoli.map {
            Lavorazione(nome: $0.nome, quantita: $0.quantita.isEmpty ? "0" : $0.quantita)
        })
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
            .fullScreenCover(item: $bollettaSelezionata) { bolletta in
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
    @State private var mostraConfrontoManuale = false

    private var fileNostre: URL? {
        guard !archivio.bollette.isEmpty else { return nil }
        return archivio.fileNostreBollette()
    }

    private var fileAzienda: URL? {
        fileStore.files.first
    }

    // IMPORTANTE: qui contiamo esclusivamente le quantità presenti nelle caselle
    // delle nostre bollette. Il testo libero/righe aggiunte manualmente non entra.
    private var totalePezziNostre: Int {
        archivio.bollette.reduce(0) { totale, bolletta in
            totale + bolletta.lavorazioni.reduce(0) { parziale, lavorazione in
                parziale + (Int(lavorazione.quantita.trimmingCharacters(in: .whitespacesAndNewlines)) ?? 0)
            }
        }
    }

    // Totale delle quantità presenti nel file azienda.
    private var totalePezziAzienda: Int {
        analysisStore.giorniAzienda().reduce(0) { totale, giorno in
            totale + giorno.rows.reduce(0) { $0 + $1.quantity }
        }
    }

    private var pezziCombaciano: Bool {
        totalePezziNostre == totalePezziAzienda
    }

    var body: some View {
        NavigationView {
            ScrollView {
                analysisPage
                    .padding(14)
            }
            .navigationTitle("Analisi")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .navigationBarLeading) {
                    Button("Chiudi") { presentationMode.wrappedValue.dismiss() }
                }
            }
            .sheet(isPresented: $mostraConfrontoManuale) {
                ConfrontoManualeView(
                    archivio: archivio,
                    analysisStore: analysisStore
                )
            }
        }
        .navigationViewStyle(.stack)
    }

    @ViewBuilder
    private var analysisPage: some View {
        VStack(spacing: 14) {
            Text("ANALISI")
                .font(.title2.weight(.bold))
                .padding(.top, 8)

            if fileNostre != nil && fileAzienda != nil && !analysisStore.giorniAzienda().isEmpty {
                VStack(spacing: 12) {
                    Text("CONTROLLO PEZZI")
                        .font(.headline)

                    HStack(spacing: 12) {
                        VStack {
                            Text("TOTALE PEZZI BOLLETTE")
                                .font(.caption)
                                .foregroundColor(.secondary)
                                .multilineTextAlignment(.center)
                            Text("\(totalePezziNostre)")
                                .font(.title.bold())
                        }
                        .frame(maxWidth: .infinity)

                        VStack {
                            Text("TOTALE PEZZI FILE AZIENDA")
                                .font(.caption)
                                .foregroundColor(.secondary)
                                .multilineTextAlignment(.center)
                            Text("\(totalePezziAzienda)")
                                .font(.title.bold())
                        }
                        .frame(maxWidth: .infinity)
                    }

                    Text(pezziCombaciano ? "PEZZI COMBACIANTI" : "PEZZI NON COMBACIANTE")
                        .font(.headline.weight(.bold))
                        .foregroundColor(pezziCombaciano ? .green : .red)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 10)
                        .background((pezziCombaciano ? Color.green : Color.red).opacity(0.10))
                        .cornerRadius(10)
                }
                .padding(16)
                .frame(maxWidth: .infinity)
                .background(Color.gray.opacity(0.06))
                .cornerRadius(14)
            }

            if fileNostre != nil && fileAzienda != nil {
                Button {
                    mostraConfrontoManuale = true
                } label: {
                    HStack {
                        Image(systemName: "checklist")
                        Text("INIZIA CONFRONTO").font(.headline)
                        Spacer()
                        Image(systemName: "arrow.right")
                    }
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 14)
                }
                .buttonStyle(.borderedProminent)
                .tint(.blue)
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
        }
    }
}

struct RisultatoConfrontoPezziView: View {
    let totaleNostre: Int
    let totaleAzienda: Int
    @Environment(\.presentationMode) private var presentationMode

    private var combaciano: Bool { totaleNostre == totaleAzienda }

    var body: some View {
        NavigationView {
            VStack(spacing: 22) {
                Image(systemName: combaciano ? "checkmark.circle.fill" : "xmark.circle.fill")
                    .font(.system(size: 64))
                    .foregroundColor(combaciano ? .green : .red)

                Text(combaciano ? "PEZZI COMBACIANTI" : "PEZZI NON COMBACIANTE")
                    .font(.title2.bold())
                    .foregroundColor(combaciano ? .green : .red)

                HStack(spacing: 20) {
                    VStack {
                        Text("BOLLETTE")
                            .font(.caption)
                            .foregroundColor(.secondary)
                        Text("\(totaleNostre)")
                            .font(.largeTitle.bold())
                    }
                    VStack {
                        Text("FILE AZIENDA")
                            .font(.caption)
                            .foregroundColor(.secondary)
                        Text("\(totaleAzienda)")
                            .font(.largeTitle.bold())
                    }
                }

                Text(combaciano
                     ? "Il totale dei pezzi delle nostre bollette coincide con quello del file azienda."
                     : "Il totale dei pezzi delle nostre bollette non coincide con quello del file azienda.")
                    .multilineTextAlignment(.center)
                    .foregroundColor(.secondary)
                    .padding(.horizontal)

                Spacer()
            }
            .padding(24)
            .navigationTitle("Confronto")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button("Chiudi") { presentationMode.wrappedValue.dismiss() }
                }
            }
        }
        .navigationViewStyle(.stack)
    }
}

struct ConfrontoManualeView: View {
    @ObservedObject var archivio: Archivio
    @ObservedObject var analysisStore: PDFAnalysisStore
    @Environment(\.presentationMode) private var presentationMode

    @State private var indice = 0
    @State private var esiti: [Date: Bool] = [:]
    @State private var mostraRisultato = false

    private var calendario: Calendar {
        var c = Calendar(identifier: .gregorian)
        c.locale = Locale(identifier: "it_IT")
        return c
    }

    private var giorni: [Date] {
        var dates: Set<Date> = []
        for day in analysisStore.giorniAzienda() {
            dates.insert(calendario.startOfDay(for: day.date))
        }
        for bolletta in archivio.bollette {
            dates.insert(calendario.startOfDay(for: bolletta.data))
        }
        return dates.sorted()
    }

    private var giornoCorrente: Date? {
        guard indice < giorni.count else { return nil }
        return giorni[indice]
    }

    private var nostraBolletta: Bolletta? {
        guard let data = giornoCorrente else { return nil }
        return archivio.bollette.first { calendario.isDate($0.data, inSameDayAs: data) }
    }

    private var giornoAzienda: PDFAnalysisDay? {
        guard let data = giornoCorrente else { return nil }
        return analysisStore.giorniAzienda().first { calendario.isDate($0.date, inSameDayAs: data) }
    }

    private var righeDaMostrare: [Lavorazione] {
        guard let bolletta = nostraBolletta else { return [] }
        return bolletta.lavorazioni.filter {
            let nome = $0.nome.trimmingCharacters(in: .whitespacesAndNewlines)
            let q = Int($0.quantita.trimmingCharacters(in: .whitespacesAndNewlines)) ?? 0
            return !nome.isEmpty && q > 0
        }
    }

    private var totaleNostro: Int {
        righeDaMostrare.reduce(0) { $0 + (Int($1.quantita.trimmingCharacters(in: .whitespacesAndNewlines)) ?? 0) }
    }

    private var totaleAzienda: Int {
        giornoAzienda?.rows.reduce(0) { $0 + $1.quantity } ?? 0
    }

    // Ordine IDENTICO alle colonne del file Excel della ditta.
    private let ordineArticoliDitta: [String] = [
        "GLAM", "GLAM XL", "ESSENTIAL", "CLOSE", "CASE", "TRAINING",
        "MESSENGER", "BAGPACK", "TODAY", "ACTIVITY", "ZAINI MARINA",
        "CLASSY", "ZAINO PRO", "case marina", "MONEYFUL",
        "BORSA IN STOFFA", "PORTAPC"
    ]

    private func articoloRiepilogo(_ nome: String) -> String? {
        let n = normalizza(nome)
        if n.hasPrefix("classy") { return "CLASSY" }
        if n.hasPrefix("messenger") { return "MESSENGER" }
        if n.hasPrefix("bagpack") { return "BAGPACK" }
        if n == "case" { return "CASE" }
        return ordineArticoliDitta.first { normalizza($0) == n }
    }

    private var righeConfrontoArticoli: [(nome: String, nostre: Int, azienda: Int)] {
        var nostre: [String: Int] = [:]
        var azienda: [String: Int] = [:]

        if let data = giornoCorrente {
            for b in archivio.bollette where calendario.isDate(b.data, inSameDayAs: data) {
                for l in b.lavorazioni {
                    guard let nome = articoloRiepilogo(l.nome) else { continue }
                    let q = Int(l.quantita.trimmingCharacters(in: .whitespacesAndNewlines)) ?? 0
                    if q > 0 { nostre[nome, default: 0] += q }
                }
            }
            for day in analysisStore.giorniAzienda() where calendario.isDate(day.date, inSameDayAs: data) {
                for row in day.rows {
                    guard let nome = articoloRiepilogo(row.article) else { continue }
                    azienda[nome, default: 0] += row.quantity
                }
            }
        }

        return ordineArticoliDitta.compactMap { nome in
            let n = nostre[nome, default: 0]
            let a = azienda[nome, default: 0]
            guard n != 0 || a != 0 else { return nil }
            return (nome, n, a)
        }
    }

    private var checkRapidoOK: Bool {
        let nostre = aggregaNostre(laData: giornoCorrente)
        let azienda = aggregaAzienda(laData: giornoCorrente)
        return !nostre.isEmpty && !azienda.isEmpty && nostre == azienda
    }

    private var dateMancanti: [Date] {
        giorni.filter { data in
            let hasNostre = archivio.bollette.contains { calendario.isDate($0.data, inSameDayAs: data) }
            let hasAzienda = analysisStore.giorniAzienda().contains { calendario.isDate($0.date, inSameDayAs: data) }
            return hasNostre != hasAzienda
        }
    }

    private var differenzeRapide: [Date] {
        giorni.filter { data in
            let n = aggregaNostre(laData: data)
            let a = aggregaAzienda(laData: data)
            return !n.isEmpty && !a.isEmpty && n != a
        }
    }

    private var totaleNostroGenerale: Int {
        archivio.bollette.reduce(0) { partial, b in
            partial + b.lavorazioni.reduce(0) { $0 + (Int($1.quantita.trimmingCharacters(in: .whitespacesAndNewlines)) ?? 0) }
        }
    }

    private var totaleAziendaGenerale: Int {
        analysisStore.giorniAzienda().reduce(0) { $0 + $1.rows.reduce(0) { $0 + $1.quantity } }
    }

    private func normalizza(_ nome: String) -> String {
        nome.folding(options: [.diacriticInsensitive, .caseInsensitive], locale: .current)
            .trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private func aggregaNostre(laData data: Date?) -> [String: Int] {
        guard let data else { return [:] }
        var out: [String: Int] = [:]
        for b in archivio.bollette where calendario.isDate(b.data, inSameDayAs: data) {
            for l in b.lavorazioni {
                let nome = normalizza(l.nome)
                let q = Int(l.quantita.trimmingCharacters(in: .whitespacesAndNewlines)) ?? 0
                if !nome.isEmpty && q != 0 { out[nome, default: 0] += q }
            }
        }
        return out
    }

    private func aggregaAzienda(laData data: Date?) -> [String: Int] {
        guard let data else { return [:] }
        var out: [String: Int] = [:]
        for day in analysisStore.giorniAzienda() where calendario.isDate(day.date, inSameDayAs: data) {
            for row in day.rows {
                let nome = normalizza(row.article)
                if !nome.isEmpty { out[nome, default: 0] += row.quantity }
            }
        }
        return out
    }

    private func formatData(_ date: Date) -> String {
        let f = DateFormatter()
        f.locale = Locale(identifier: "it_IT")
        f.dateFormat = "dd/MM/yyyy"
        return f.string(from: date)
    }

    private func nomeMese(_ date: Date) -> String {
        let f = DateFormatter()
        f.locale = Locale(identifier: "it_IT")
        f.dateFormat = "dd MMMM yyyy"
        return f.string(from: date).uppercased()
    }

    private func vaiAvanti() {
        if let data = giornoCorrente, esiti[data] == nil {
            esiti[data] = false
        }
        if indice + 1 < giorni.count {
            indice += 1
        } else {
            mostraRisultato = true
        }
    }

    private func registra(_ esito: Bool) {
        guard let data = giornoCorrente else { return }
        esiti[data] = esito
        if indice + 1 < giorni.count {
            indice += 1
        } else {
            mostraRisultato = true
        }
    }

    var body: some View {
        NavigationView {
            Group {
                if giorni.isEmpty {
                    VStack(spacing: 14) {
                        Image(systemName: "doc.text.magnifyingglass")
                            .font(.system(size: 48))
                            .foregroundColor(.blue)
                        Text("NESSUN CONFRONTO DISPONIBILE")
                            .font(.title2.weight(.bold))
                            .multilineTextAlignment(.center)
                        Text("Prima importa il file della ditta e assicurati che le nostre bollette siano presenti nell'archivio.")
                            .multilineTextAlignment(.center)
                            .foregroundColor(.secondary)
                    }
                    .padding(30)
                } else if let data = giornoCorrente {
                    VStack(spacing: 12) {
                        HStack {
                            VStack(alignment: .leading, spacing: 3) {
                                Text("CONFRONTO \(indice + 1) / \(giorni.count)")
                                    .font(.caption.weight(.bold))
                                    .foregroundColor(.secondary)
                                Text(formatData(data))
                                    .font(.system(size: 28, weight: .bold))
                            }
                            Spacer()
                            VStack(alignment: .trailing, spacing: 3) {
                                Text("PEZZI")
                                    .font(.caption.weight(.bold))
                                    .foregroundColor(.secondary)
                                Text("\(totaleNostro)")
                                    .font(.title2.weight(.bold))
                            }
                        }
                        .padding(.horizontal, 16)
                        .padding(.top, 12)

                        Text(nomeMese(data))
                            .font(.caption.weight(.semibold))
                            .foregroundColor(.blue)

                        // Articoli nell'ESATTO ordine del file Excel della ditta.
                        // CLASSY e MESSENGER sono aggregati: le varianti della maschera
                        // (taglie/manici) confluiscono in un unico totale.
                        ScrollView {
                            VStack(spacing: 8) {
                                HStack {
                                    Text("ARTICOLO").frame(maxWidth: .infinity, alignment: .leading)
                                    Text("BOLLETTE").frame(width: 82, alignment: .trailing)
                                    Text("DITTA").frame(width: 72, alignment: .trailing)
                                }
                                .font(.caption.weight(.bold))
                                .foregroundColor(.secondary)

                                ForEach(Array(righeConfrontoArticoli.enumerated()), id: \.offset) { _, riga in
                                    let diverso = riga.nostre != riga.azienda
                                    HStack {
                                        Text(riga.nome)
                                            .font(.subheadline.weight(.semibold))
                                            .frame(maxWidth: .infinity, alignment: .leading)
                                        Text("\(riga.nostre)")
                                            .font(.headline.weight(.bold))
                                            .frame(width: 82, alignment: .trailing)
                                        Text("\(riga.azienda)")
                                            .font(.headline.weight(.bold))
                                            .frame(width: 72, alignment: .trailing)
                                    }
                                    .padding(.horizontal, 12)
                                    .padding(.vertical, 10)
                                    .background(diverso ? Color.red.opacity(0.22) : Color.blue.opacity(0.08))
                                    .cornerRadius(10)
                                }
                            }
                            .padding(.horizontal, 16)
                        }

                        HStack(spacing: 12) {
                            Label("Nostre: \(totaleNostro)", systemImage: "bag.fill")
                            Label("Ditta: \(totaleAzienda)", systemImage: "building.2.fill")
                            Spacer()
                        }
                        .font(.footnote.weight(.semibold))
                        .padding(.horizontal, 16)

                        Text("Confronta questa riga con il foglio Excel stampato della ditta.")
                            .font(.footnote)
                            .foregroundColor(.secondary)
                            .multilineTextAlignment(.center)
                            .padding(.horizontal, 20)

                        Spacer(minLength: 8)

                        HStack(spacing: 14) {
                            Button {
                                registra(false)
                            } label: {
                                Label("NO", systemImage: "xmark.circle.fill")
                                    .font(.title3.weight(.bold))
                                    .frame(maxWidth: .infinity)
                                    .padding(.vertical, 16)
                            }
                            .buttonStyle(.borderedProminent)
                            .tint(.red)

                            Button {
                                registra(true)
                            } label: {
                                Label("SÌ", systemImage: "checkmark.circle.fill")
                                    .font(.title3.weight(.bold))
                                    .frame(maxWidth: .infinity)
                                    .padding(.vertical, 16)
                            }
                            .buttonStyle(.borderedProminent)
                            .tint(.green)
                        }
                        .padding(.horizontal, 16)
                        .padding(.bottom, 8)
                    }
                }
            }
            .navigationTitle("Confronto manuale")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .navigationBarLeading) {
                    Button("Chiudi") { presentationMode.wrappedValue.dismiss() }
                }
            }
            .sheet(isPresented: $mostraRisultato) {
                RisultatoConfrontoManualeView(
                    giorni: giorni,
                    esiti: esiti,
                    totaleNostro: totaleNostroGenerale,
                    totaleAzienda: totaleAziendaGenerale,
                    dateMancanti: dateMancanti,
                    differenzeRapide: differenzeRapide
                )
            }
        }
        .navigationViewStyle(.stack)
    }

    @ViewBuilder
    private func cella(_ titolo: String, _ valore: String, larghezza: CGFloat) -> some View {
        VStack(alignment: .leading, spacing: 5) {
            Text(titolo)
                .font(.caption.weight(.bold))
                .foregroundColor(.secondary)
            Text(valore)
                .font(.subheadline.weight(.semibold))
        }
        .frame(width: larghezza, alignment: .leading)
        .padding(10)
        .background(Color.gray.opacity(0.10))
        .cornerRadius(10)
    }
}

struct RisultatoConfrontoManualeView: View {
    let giorni: [Date]
    let esiti: [Date: Bool]
    let totaleNostro: Int
    let totaleAzienda: Int
    let dateMancanti: [Date]
    let differenzeRapide: [Date]

    @Environment(\.presentationMode) private var presentationMode

    private var okCount: Int {
        esiti.values.filter { $0 }.count
    }

    private var noCount: Int {
        esiti.values.filter { !$0 }.count
    }

    private func data(_ d: Date) -> String {
        let f = DateFormatter()
        f.locale = Locale(identifier: "it_IT")
        f.dateFormat = "dd/MM/yyyy"
        return f.string(from: d)
    }

    var body: some View {
        NavigationView {
            List {
                Section("VERIFICA MANUALE") {
                    HStack {
                        Label("OK", systemImage: "checkmark.circle.fill")
                            .foregroundColor(.green)
                        Spacer()
                        Text("\(okCount)")
                            .font(.headline)
                    }
                    HStack {
                        Label("Differenze", systemImage: "xmark.circle.fill")
                            .foregroundColor(.red)
                        Spacer()
                        Text("\(noCount)")
                            .font(.headline)
                    }
                }

                Section("CONTROLLO TOTALE PEZZI") {
                    HStack {
                        Text("Nostre bollette")
                        Spacer()
                        Text("\(totaleNostro)")
                    }
                    HStack {
                        Text("File ditta")
                        Spacer()
                        Text("\(totaleAzienda)")
                    }
                    HStack {
                        Text("Totale")
                        Spacer()
                        Text(totaleNostro == totaleAzienda ? "COMBACIA" : "NON COMBACIA")
                            .fontWeight(.bold)
                            .foregroundColor(totaleNostro == totaleAzienda ? .green : .red)
                    }
                }

            }
            .navigationTitle("Risultato finale")
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

private struct APIKeyView: View {
    @Binding var apiKey: String
    @Environment(\.presentationMode) private var presentationMode
    @State private var valore = ""

    var body: some View {
        NavigationView {
            Form {
                Section {
                    SecureField("sk-...", text: $valore)
                    Button("Salva") {
                        apiKey = valore.trimmingCharacters(in: .whitespacesAndNewlines)
                        presentationMode.wrappedValue.dismiss()
                    }
                    .disabled(valore.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                } header: {
                    Text("API KEY OPENAI")
                } footer: {
                    Text("La chiave viene salvata solo nell'app su questo iPad. L'uso dell'API viene addebitato separatamente secondo il tuo account API OpenAI.")
                }

                if !apiKey.isEmpty {
                    Section {
                        Button("Rimuovi API key", role: .destructive) {
                            apiKey = ""
                            presentationMode.wrappedValue.dismiss()
                        }
                    }
                }
            }
            .navigationTitle("ChatGPT")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .navigationBarLeading) {
                    Button("Chiudi") { presentationMode.wrappedValue.dismiss() }
                }
            }
            .onAppear { valore = apiKey }
        }
    }
}

private struct ChatMessaggio: Identifiable {
    let id = UUID()
    let testo: String
    let utente: Bool
}

private struct ChatAnalisiView: View {
    let fileNostre: URL
    let fileAzienda: URL
    let testoIniziale: String
    let apiKey: String

    @Environment(\.presentationMode) private var presentationMode
    @State private var messaggi: [ChatMessaggio] = []
    @State private var testo = ""
    @State private var inCorso = false
    @State private var errore = ""
    @State private var fileIDs: [String] = []
    @State private var previousResponseID: String?
    @State private var avviata = false

    var body: some View {
        NavigationView {
            VStack(spacing: 0) {
                ScrollViewReader { proxy in
                    ScrollView {
                        LazyVStack(alignment: .leading, spacing: 12) {
                            HStack(spacing: 10) {
                                Image(systemName: "brain.head.profile")
                                    .font(.title2)
                                    .foregroundColor(.green)
                                VStack(alignment: .leading) {
                                    Text("ChatGPT").font(.headline)
                                    Text("Analisi delle due bollette").font(.caption).foregroundColor(.secondary)
                                }
                            }
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .padding(.horizontal)
                            .padding(.top, 12)

                            HStack(spacing: 8) {
                                Label(fileNostre.lastPathComponent, systemImage: "doc.text")
                                Label(fileAzienda.lastPathComponent, systemImage: "building.2")
                            }
                            .font(.caption)
                            .foregroundColor(.secondary)
                            .padding(.horizontal)

                            ForEach(messaggi) { messaggio in
                                HStack {
                                    if messaggio.utente { Spacer() }
                                    Text(messaggio.testo)
                                        .padding(12)
                                        .background(messaggio.utente ? Color.blue.opacity(0.12) : Color.gray.opacity(0.12))
                                        .cornerRadius(14)
                                        .frame(maxWidth: 330, alignment: messaggio.utente ? .trailing : .leading)
                                    if !messaggio.utente { Spacer() }
                                }
                                .id(messaggio.id)
                            }

                            if inCorso {
                                HStack(spacing: 8) {
                                    ProgressView()
                                    Text("Sto analizzando...").foregroundColor(.secondary)
                                }
                                .padding(.horizontal)
                                .id("loading")
                            }
                        }
                        .padding(.bottom, 16)
                    }
                    .onChange(of: messaggi.count) { _ in
                        if let id = messaggi.last?.id { withAnimation { proxy.scrollTo(id, anchor: .bottom) } }
                    }
                }

                Divider()
                HStack(alignment: .bottom, spacing: 8) {
                    TextField("Scrivi una domanda...", text: $testo)
                        .textFieldStyle(.roundedBorder)

                    Button {
                        invia()
                    } label: {
                        Image(systemName: "arrow.up.circle.fill")
                            .font(.system(size: 34))
                    }
                    .disabled(inCorso || testo.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                }
                .padding(10)
                .background(.thinMaterial)
            }
            .navigationTitle("Analisi ChatGPT")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .navigationBarLeading) {
                    Button("Chiudi") { presentationMode.wrappedValue.dismiss() }
                }
            }
            .alert("ChatGPT", isPresented: Binding(
                get: { !errore.isEmpty },
                set: { if !$0 { errore = "" } }
            )) {
                Button("OK", role: .cancel) { }
            } message: {
                Text(errore)
            }
            .onAppear {
                guard !avviata else { return }
                avviata = true
                invia(testoIniziale)
            }
        }
        .navigationViewStyle(.stack)
    }

    private func invia(_ testoDaInviare: String? = nil) {
        let domanda = (testoDaInviare ?? testo).trimmingCharacters(in: .whitespacesAndNewlines)
        guard !domanda.isEmpty, !inCorso else { return }
        if testoDaInviare == nil { testo = "" }
        messaggi.append(ChatMessaggio(testo: domanda, utente: true))
        inCorso = true

        Task {
            do {
                guard !apiKey.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
                    throw OpenAIAPIError(message: "Manca la API key OpenAI. Torna in ANALISI e premi CONFIGURA API KEY.")
                }

                if fileIDs.isEmpty {
                    let id1 = try await OpenAIAnalysisService.shared.uploadFile(url: fileNostre, apiKey: apiKey)
                    let id2 = try await OpenAIAnalysisService.shared.uploadFile(url: fileAzienda, apiKey: apiKey)
                    fileIDs = [id1, id2]
                }

                let result = try await OpenAIAnalysisService.shared.respond(
                    apiKey: apiKey,
                    prompt: domanda,
                    fileIDs: fileIDs,
                    previousResponseID: previousResponseID
                )
                previousResponseID = result.id
                await MainActor.run {
                    messaggi.append(ChatMessaggio(testo: result.text, utente: false))
                    inCorso = false
                }
            } catch {
                await MainActor.run {
                    inCorso = false
                    errore = error.localizedDescription
                }
            }
        }
    }
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

