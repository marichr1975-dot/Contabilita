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
                    title: pdfImportati > 0 ? "PDF AZIENDA  •  \(pdfImportati)" : "IMPORTA PDF AZIENDA",
                    icon: "doc.fill",
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
        let folder = container.appendingPathComponent("PDFImportati", isDirectory: true)
        let files = (try? FileManager.default.contentsOfDirectory(
            at: folder,
            includingPropertiesForKeys: nil
        )) ?? []
        pdfImportati = files.filter { $0.pathExtension.lowercased() == "pdf" }.count
    }
}

struct PDFImportatiView: View {
    @ObservedObject var store: PDFTransferStore
    @ObservedObject var analysisStore: PDFAnalysisStore
    @ObservedObject var archivio: Archivio
    @Environment(\.presentationMode) private var presentationMode
    @State private var pdfDaMostrare: URL?
    @State private var analisiDaMostrare: PDFAnalysisResult?
    @State private var analisiInCorso = false
    @State private var erroreAnalisi: String?

    var body: some View {
        NavigationView {
            VStack(spacing: 12) {
                if store.files.isEmpty {
                    Spacer()
                    Image(systemName: "doc.text.magnifyingglass")
                        .font(.system(size: 48))
                        .foregroundColor(.teal)
                    Text("Nessun PDF ricevuto")
                        .font(.title2)
                    Text("Da WhatsApp o File: Condividi → Contabilità")
                        .multilineTextAlignment(.center)
                        .foregroundColor(.secondary)
                    Spacer()
                } else {
                    Text("PDF RICEVUTI")
                        .font(.title2)
                        .fontWeight(.semibold)
                        .padding(.top, 8)

                    List(store.files, id: \.self) { file in
                        HStack(spacing: 10) {
                            Image(systemName: "doc.fill")
                                .foregroundColor(.teal)

                            Text(file.lastPathComponent)
                                .font(.body)
                                .lineLimit(2)
                                .frame(maxWidth: .infinity, alignment: .leading)

                            Button("CARICA") {
                                analizza(file)
                            }
                            .buttonStyle(.borderedProminent)
                            .tint(.green)
                            .disabled(analisiInCorso)

                            Button("MOSTRA PDF") {
                                pdfDaMostrare = file
                            }
                            .buttonStyle(.bordered)
                        }
                        .padding(.vertical, 8)
                    }
                    .listStyle(.plain)
                }
            }
            .padding(18)
            .navigationTitle("PDF azienda")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .navigationBarLeading) {
                    Button("Chiudi") { presentationMode.wrappedValue.dismiss() }
                }
            }
            .onAppear { store.importaDaCondividi() }
            .overlay {
                if analisiInCorso {
                    ProgressView("Analisi PDF in corso…")
                        .padding(24)
                        .background(.regularMaterial)
                        .cornerRadius(16)
                }
            }
            .alert("Analisi PDF", isPresented: Binding(
                get: { erroreAnalisi != nil },
                set: { if !$0 { erroreAnalisi = nil } }
            )) {
                Button("OK", role: .cancel) { erroreAnalisi = nil }
            } message: {
                Text(erroreAnalisi ?? "")
            }
            .sheet(item: $pdfDaMostrare) { file in
                PDFViewer(url: file)
            }
            .sheet(item: $analisiDaMostrare) { result in
                PDFAnalysisDetailView(result: result, archivio: archivio)
            }
        }
        .navigationViewStyle(.stack)
    }

    private func analizza(_ file: URL) {
        guard !analisiInCorso else { return }
        analisiInCorso = true
        DispatchQueue.global(qos: .userInitiated).async {
            let result = PDFAnalyzer.analyze(url: file)
            DispatchQueue.main.async {
                analisiInCorso = false
                if let result = result {
                    analysisStore.save(result)
                    analisiDaMostrare = result
                } else {
                    erroreAnalisi = "Non riesco a leggere dati utili dal PDF. Il file deve contenere testo selezionabile."
                }
            }
        }
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
    [
        GruppoLavorazione(nome: "classy", voci: [
            VoceLavorazione(nome: "manici corti"),
            VoceLavorazione(nome: "manici corto e tracolla")
        ]),
        GruppoLavorazione(nome: "bagpack", voci: [
            VoceLavorazione(nome: "L"), VoceLavorazione(nome: "M"), VoceLavorazione(nome: "S")
        ]),
        GruppoLavorazione(nome: "training", voci: [
            VoceLavorazione(nome: "L"), VoceLavorazione(nome: "M")
        ]),
        GruppoLavorazione(nome: "messenger", voci: [
            VoceLavorazione(nome: "L"), VoceLavorazione(nome: "M")
        ]),
        GruppoLavorazione(nome: "today", voci: [
            VoceLavorazione(nome: "M"), VoceLavorazione(nome: "S")
        ]),
        GruppoLavorazione(nome: "bagpack PRO", voci: [
            VoceLavorazione(nome: "")
        ]),
        GruppoLavorazione(nome: "activity", voci: [
            VoceLavorazione(nome: "")
        ]),
        GruppoLavorazione(nome: "moneyful", voci: [
            VoceLavorazione(nome: "L"), VoceLavorazione(nome: "M")
        ]),
        GruppoLavorazione(nome: "case", voci: [
            VoceLavorazione(nome: "L"), VoceLavorazione(nome: "M"), VoceLavorazione(nome: "S")
        ]),
        GruppoLavorazione(nome: "essential", voci: [
            VoceLavorazione(nome: "")
        ])
    ]
}

struct NuovaBollettaView: View {
    @ObservedObject var archivio: Archivio
    @Environment(\.presentationMode) private var presentationMode
    let existing: Bolletta?

    @State private var data = Date()
    @State private var dataConfermata = false
    @State private var gruppi: [GruppoLavorazione] = []
    @FocusState private var rigaAttiva: Int?
    @State private var nuovoArticolo = ""
    @State private var mostraNuovoArticolo = false

    init(archivio: Archivio, existing: Bolletta? = nil) {
        self.archivio = archivio
        self.existing = existing
        _data = State(initialValue: existing?.data ?? Date())
        _dataConfermata = State(initialValue: existing != nil)
        if let existing {
            _gruppi = State(initialValue: [GruppoLavorazione(nome: "LAVORAZIONI", voci: existing.lavorazioni.map { VoceLavorazione(nome: $0.nome, quantita: $0.quantita) })])
        } else {
            _gruppi = State(initialValue: gruppiBollettaDaNomi())
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
            .navigationTitle(dataConfermata ? (existing == nil ? "Carica bolletta" : "Modifica bolletta") : "Nuova bolletta")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .navigationBarLeading) {
                    Button("Annulla") { presentationMode.wrappedValue.dismiss() }
                }
                ToolbarItem(placement: .navigationBarTrailing) {
                    if dataConfermata {
                        HStack(spacing: 12) {
                            if existing != nil {
                                Button("CANCELLA") {
                                    if let existing { archivio.eliminaBolletta(id: existing.id) }
                                    presentationMode.wrappedValue.dismiss()
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
        .onAppear {
            if gruppi.isEmpty && existing == nil {
                gruppi = gruppiBollettaDaNomi()
            }
        }
    }

    private var scegliData: some View {
        VStack(spacing: 20) {
            Text("SCEGLI LA DATA")
                .font(.title2)

            DatePicker("Data", selection: $data, displayedComponents: .date)
                .datePickerStyle(.graphical)
                .labelsHidden()

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

                        Button {
                            mostraNuovoArticolo = true
                        } label: {
                            Text("+ AGGIUNGI ARTICOLO")
                                .font(.headline)
                                .frame(maxWidth: .infinity).padding()
                        }
                        .buttonStyle(.bordered)
                    }
                    .padding(12)
                }
            }

        }
        .alert("Nuovo articolo", isPresented: $mostraNuovoArticolo) {
            TextField("Nome articolo", text: $nuovoArticolo)
            Button("Aggiungi") {
                let n = nuovoArticolo.trimmingCharacters(in: .whitespacesAndNewlines)
                if !n.isEmpty {
                    archivio.aggiungiLavorazione(n)
                    gruppi.append(GruppoLavorazione(nome: n, voci: [VoceLavorazione(nome: "")]))
                    nuovoArticolo = ""
                }
            }
            Button("Annulla", role: .cancel) { nuovoArticolo = "" }
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
                Text(gruppi[g].nome)
                    .font(.headline)
                Spacer()
                Text("quantità").font(.headline)
            }
            .padding(.horizontal, 12).padding(.vertical, 8)

            ForEach(gruppi[g].voci.indices, id: \.self) { v in
                let flat = indicePiatto(g, v)
                HStack(spacing: 8) {
                    Text("□")
                        .font(.title3)
                        .frame(width: 24)

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
        .background(
            RoundedRectangle(cornerRadius: 3)
                .stroke(Color.gray.opacity(0.65), lineWidth: 1)
        )
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
        // L'OK della tastiera passa alla voce successiva.
        // La gestione del focus visivo viene completata nel prossimo collegamento del campo.
        if let r = rigaAttiva {
            rigaAttiva = r + 1
        } else {
            rigaAttiva = 1
        }
    }

    private func salva() {
        var lista: [Lavorazione] = []
        for gruppo in gruppi {
            for voce in gruppo.voci {
                let nome: String
                if existing != nil && gruppo.nome == "LAVORAZIONI" {
                    nome = voce.nome
                } else {
                    nome = gruppo.nome + (voce.nome.isEmpty ? "" : " \(voce.nome)")
                }
                lista.append(Lavorazione(nome: nome, quantita: voce.quantita.isEmpty ? "0" : voce.quantita))
            }
        }
        archivio.salvaBolletta(Bolletta(id: existing?.id ?? UUID(), data: data, lavorazioni: lista))
        presentationMode.wrappedValue.dismiss()
    }
}

struct SelezionaDataModificaView: View {
    @ObservedObject var archivio: Archivio
    @Environment(\.presentationMode) private var presentationMode
    @State private var bollettaSelezionata: Bolletta?

    private var bollette: [Bolletta] { archivio.bollette.sorted { $0.data > $1.data } }

    var body: some View {
        NavigationView {
            Group {
                if bollette.isEmpty {
                    VStack(spacing: 20) {
                        Text("Non ci sono ancora bollette salvate.").font(.title3)
                        Button("CHIUDI") { presentationMode.wrappedValue.dismiss() }
                            .buttonStyle(.borderedProminent)
                    }
                    .padding()
                } else if bollette.count == 1 {
                    ProgressView("Apertura bolletta 1…")
                        .onAppear { bollettaSelezionata = bollette[0] }
                } else {
                    List(Array(bollette.enumerated()), id: \.element.id) { indice, bolletta in
                        Button { bollettaSelezionata = bolletta } label: {
                            HStack {
                                Text("BOLLETTA \(indice + 1)").font(.title3).fontWeight(.semibold)
                                Spacer()
                                VStack(alignment: .trailing) {
                                    Text(bolletta.data.formatted(date: .numeric, time: .omitted))
                                    Text("\(totalePezzi(bolletta)) pezzi").foregroundColor(.secondary)
                                }
                                Image(systemName: "chevron.right").foregroundColor(.secondary)
                            }
                            .padding(.vertical, 10)
                        }
                    }
                    .listStyle(.plain)
                }
            }
            .navigationTitle("Modifica bolletta")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .navigationBarLeading) {
                    Button("Annulla") { presentationMode.wrappedValue.dismiss() }
                }
            }
            .sheet(item: $bollettaSelezionata) { bolletta in
                NuovaBollettaView(archivio: archivio, existing: bolletta)
                    .navigationViewStyle(.stack)
            }
        }
        .navigationViewStyle(.stack)
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
    @State private var risultatoSelezionato: PDFAnalysisResult?

    var body: some View {
        NavigationView {
            Group {
                if analysisStore.results.isEmpty {
                    VStack(spacing: 14) {
                        Image(systemName: "doc.text.magnifyingglass").font(.system(size: 50)).foregroundColor(.purple)
                        Text("Nessun PDF analizzato").font(.title2).fontWeight(.semibold)
                        Text("Vai in PDF AZIENDA e premi CARICA sul prospetto ricevuto.")
                            .multilineTextAlignment(.center).foregroundColor(.secondary)
                            .padding(.horizontal, 25)
                    }
                } else {
                    List(analysisStore.results) { result in
                        Button { risultatoSelezionato = result } label: {
                            HStack(spacing: 12) {
                                Image(systemName: "chart.bar.doc.horizontal").foregroundColor(.purple)
                                VStack(alignment: .leading, spacing: 4) {
                                    Text(result.fileName).font(.headline).lineLimit(2)
                                    Text(result.date?.formatted(date: .numeric, time: .omitted) ?? "Data non trovata")
                                        .font(.subheadline).foregroundColor(.secondary)
                                }
                                Spacer()
                                Text("\(result.rows.count) righe").foregroundColor(.secondary)
                                Image(systemName: "chevron.right").foregroundColor(.secondary)
                            }
                            .padding(.vertical, 8)
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
            .sheet(item: $risultatoSelezionato) { result in
                PDFAnalysisDetailView(result: result, archivio: archivio)
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

