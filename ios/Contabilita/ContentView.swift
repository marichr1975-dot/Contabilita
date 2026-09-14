import SwiftUI

struct Bolletta: Identifiable, Codable {
    var id = UUID()
    var date: Date
    var number: String
    var company: String
    var article: String
    var quantity: Int
    var unitPrice: Double

    var total: Double { Double(quantity) * unitPrice }
}

struct ContentView: View {
    @State private var bollette: [Bolletta] = []
    @State private var showingNew = false
    @State private var selectedTab = 0

    private let money = { (v: Double) -> String in
        String(format: "€ %.2f", v)
    }

    var body: some View {
        TabView(selection: $selectedTab) {
            NavigationView {
                List {
                    Section {
                        Button(action: { showingNew = true }) {
                            Label("Nuova bolletta", systemImage: "plus.circle.fill")
                                .font(.title3)
                                .padding(.vertical, 8)
                        }
                    }

                    Section(header: Text("Riepilogo")) {
                        HStack {
                            Text("Bolletta")
                            Spacer()
                            Text("\(bollette.count)")
                        }
                        HStack {
                            Text("Pezzi lavorati")
                            Spacer()
                            Text("\(bollette.reduce(0) { $0 + $1.quantity })")
                        }
                        HStack {
                            Text("Totale")
                            Spacer()
                            Text(money(bollette.reduce(0) { $0 + $1.total }))
                                .bold()
                        }
                    }

                    Section(header: Text("Ultime bollette")) {
                        if bollette.isEmpty {
                            Text("Nessuna bolletta inserita. Premi «Nuova bolletta».")
                                .foregroundColor(.secondary)
                        } else {
                            ForEach(bollette) { b in
                                VStack(alignment: .leading, spacing: 5) {
                                    Text(b.article).font(.headline)
                                    Text("\(b.company) • \(b.quantity) pezzi • \(money(b.unitPrice))/pz")
                                        .font(.subheadline)
                                        .foregroundColor(.secondary)
                                    Text(money(b.total)).bold()
                                }
                                .padding(.vertical, 4)
                            }
                            .onDelete(perform: delete)
                        }
                    }
                }
                .navigationTitle("Contabilità")
                .toolbar { EditButton() }
            }
            .tabItem { Label("Home", systemImage: "house.fill") }
            .tag(0)

            NavigationView {
                List {
                    if bollette.isEmpty {
                        Text("Nessuna lavorazione registrata.")
                            .foregroundColor(.secondary)
                    } else {
                        ForEach(bollette) { b in
                            VStack(alignment: .leading, spacing: 5) {
                                Text(b.article).font(.headline)
                                Text(b.date, style: .date)
                                    .foregroundColor(.secondary)
                                HStack {
                                    Text("\(b.quantity) pezzi")
                                    Spacer()
                                    Text(money(b.total)).bold()
                                }
                            }
                            .padding(.vertical, 5)
                        }
                    }
                }
                .navigationTitle("Storico")
            }
            .tabItem { Label("Storico", systemImage: "clock.fill") }
            .tag(1)
        }
        .sheet(isPresented: $showingNew) {
            NuovaBollettaView { nuova in
                bollette.append(nuova)
                save()
                showingNew = false
            }
        }
        .onAppear { load() }
    }

    private func delete(at offsets: IndexSet) {
        bollette.remove(atOffsets: offsets)
        save()
    }

    private func save() {
        if let data = try? JSONEncoder().encode(bollette) {
            UserDefaults.standard.set(data, forKey: "bollette")
        }
    }

    private func load() {
        if let data = UserDefaults.standard.data(forKey: "bollette"),
           let saved = try? JSONDecoder().decode([Bolletta].self, from: data) {
            bollette = saved
        }
    }
}

struct NuovaBollettaView: View {
    @Environment(\.presentationMode) var presentationMode
    var onSave: (Bolletta) -> Void

    @State private var date = Date()
    @State private var number = ""
    @State private var company = ""
    @State private var article = ""
    @State private var quantity = ""
    @State private var unitPrice = ""

    var valid: Bool {
        !article.trimmingCharacters(in: .whitespaces).isEmpty &&
        (Int(quantity) ?? 0) > 0 &&
        (Double(unitPrice.replacingOccurrences(of: ",", with: ".")) ?? 0) >= 0
    }

    var body: some View {
        NavigationView {
            Form {
                Section(header: Text("Bolletta")) {
                    DatePicker("Data", selection: $date, displayedComponents: .date)
                    TextField("Numero bolletta", text: $number)
                    TextField("Azienda", text: $company)
                }

                Section(header: Text("Articolo lavorato")) {
                    TextField("Codice / nome articolo", text: $article)
                    TextField("Quantità lavorata", text: $quantity)
                        .keyboardType(.numberPad)
                    TextField("Prezzo unitario (€)", text: $unitPrice)
                        .keyboardType(.decimalPad)
                }

                Section {
                    if valid {
                        let q = Int(quantity) ?? 0
                        let p = Double(unitPrice.replacingOccurrences(of: ",", with: ".")) ?? 0
                        HStack {
                            Text("Totale")
                            Spacer()
                            Text(String(format: "€ %.2f", Double(q) * p)).bold()
                        }
                    } else {
                        Text("Inserisci articolo, quantità e prezzo.")
                            .foregroundColor(.secondary)
                    }
                }
            }
            .navigationTitle("Nuova bolletta")
            .navigationBarItems(
                leading: Button("Annulla") { presentationMode.wrappedValue.dismiss() },
                trailing: Button("Salva") {
                    let p = Double(unitPrice.replacingOccurrences(of: ",", with: ".")) ?? 0
                    onSave(Bolletta(date: date, number: number, company: company,
                                    article: article, quantity: Int(quantity) ?? 0,
                                    unitPrice: p))
                }.disabled(!valid)
            )
        }
    }
}
