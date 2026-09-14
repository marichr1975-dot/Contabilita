import UIKit
import SwiftUI

struct Articolo: Identifiable, Codable, Equatable {
    var id = UUID()
    var nome: String
    var prezzo: Double
}

struct RigheBolletta: Identifiable, Codable {
    var id = UUID()
    var data: Date
    var quantita: [String: Int]
}

struct ContentView: View {
    @State private var articoli: [Articolo] = [
        Articolo(nome: "MESSENGER BAGPACK", prezzo: 13.50),
        Articolo(nome: "TODAY", prezzo: 13.50),
        Articolo(nome: "ACTIVITY", prezzo: 14.85),
        Articolo(nome: "ZAINI MARIN", prezzo: 13.50),
        Articolo(nome: "CLASSY", prezzo: 12.82),
        Articolo(nome: "ZAINO PRO", prezzo: 12.15),
        Articolo(nome: "CASE MARINA", prezzo: 24.30),
        Articolo(nome: "MONEYFUL", prezzo: 8.10),
        Articolo(nome: "BORSA IN STOFFA", prezzo: 10.80),
        Articolo(nome: "PORTAPC", prezzo: 7.43)
    ]
    @State private var bollette: [RigheBolletta] = []
    @State private var showingNuova = false

    var body: some View {
        NavigationView {
            List {
                Section {
                    Button {
                        showingNuova = true
                    } label: {
                        HStack {
                            Image(systemName: "plus.circle.fill")
                                .font(.title2)
                            Text("Nuova bolletta")
                                .font(.title3)
                                .bold()
                        }
                        .padding(.vertical, 8)
                    }
                }

                Section(header: Text("Lavorazioni salvate")) {
                    if articoli.isEmpty {
                        Text("Nessun articolo. Premi «Nuova bolletta» per aggiungere il primo.")
                            .foregroundColor(.secondary)
                    } else {
                        ForEach(articoli) { articolo in
                            Text(articolo.nome)
                                .font(.title3)
                                .padding(.vertical, 5)
                        }
                    }
                }

                Section(header: Text("Storico")) {
                    if bollette.isEmpty {
                        Text("Nessuna bolletta registrata.")
                            .foregroundColor(.secondary)
                    } else {
                        ForEach(bollette) { b in
                            VStack(alignment: .leading, spacing: 6) {
                                Text(b.data, style: .date)
                                    .font(.headline)
                                let tot = b.quantita.values.reduce(0, +)
                                Text("\(tot) pezzi lavorati")
                                    .foregroundColor(.secondary)
                            }
                            .padding(.vertical, 4)
                        }
                        .onDelete { offsets in
                            bollette.remove(atOffsets: offsets)
                            save()
                        }
                    }
                }
            }
            .navigationTitle("Contabilità")
            .toolbar { EditButton() }
        }
        .onAppear { load() }
        .sheet(isPresented: $showingNuova) {
            NuovaBollettaView(
                articoli: $articoli,
                onSave: { righe in
                    bollette.append(righe)
                    save()
                    showingNuova = false
                }
            )
        }
    }

    private func save() {
        if let a = try? JSONEncoder().encode(articoli) {
            UserDefaults.standard.set(a, forKey: "articoli")
        }
        if let b = try? JSONEncoder().encode(bollette) {
            UserDefaults.standard.set(b, forKey: "bollette")
        }
    }

    private func load() {
        if let a = UserDefaults.standard.data(forKey: "articoli"),
           let saved = try? JSONDecoder().decode([Articolo].self, from: a),
           !saved.isEmpty {
            articoli = saved
        } else {
            saveArticles()
        }
        if let b = UserDefaults.standard.data(forKey: "bollette"),
           let saved = try? JSONDecoder().decode([RigheBolletta].self, from: b) {
            bollette = saved
        }
    }
}

struct NuovaBollettaView: View {
    @Environment(\.presentationMode) var presentationMode
    @Binding var articoli: [Articolo]
    var onSave: (RigheBolletta) -> Void

    @State private var data = Date()
    @State private var mostraCalendario = false
    @State private var mostraAggiungi = false
    @State private var nuovoArticolo = ""
    @State private var quantita: [String: Int] = [:]

    var body: some View {
        NavigationView {
            VStack(spacing: 0) {
                // Data: nessun numero bolletta e nessuna azienda.
                VStack(spacing: 10) {
                    HStack {
                        Text("Data")
                            .font(.title2)
                            .bold()
                        Spacer()
                        Button {
                            mostraCalendario = true
                        } label: {
                            Text(data.formatted(date: .abbreviated, time: .omitted))
                                .font(.title3)
                        }
                    }
                    .padding(.horizontal)
                    .padding(.top, 14)

                    if mostraCalendario {
                        DatePicker(
                            "Scegli la data",
                            selection: $data,
                            displayedComponents: .date
                        )
                        .datePickerStyle(.graphical)
                        .padding(.horizontal)
                        .onChange(of: data) { _ in
                            mostraCalendario = false
                        }

                        Button("OK") {
                            mostraCalendario = false
                        }
                        .font(.title3)
                        .bold()
                        .padding(.bottom, 8)
                    }
                }
                .background(Color(UIColor.secondarySystemBackground))

                Divider()

                if articoli.isEmpty {
                    VStack(spacing: 15) {
                        Text("Aggiungi il primo articolo")
                            .font(.title2)
                        Button("＋ Aggiungi articolo") {
                            mostraAggiungi = true
                        }
                        .buttonStyle(.borderedProminent)
                        .font(.title3)
                    }
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                } else {
                    List {
                        Section(header: Text("Lavorazioni")) {
                            ForEach(articoli) { articolo in
                                RigaArticolo(
                                    nome: articolo.nome,
                                    prezzo: articolo.prezzo,
                                    valore: Binding(
                                        get: { quantita[articolo.nome, default: 0] },
                                        set: { quantita[articolo.nome] = $0 }
                                    )
                                )
                            }

                            Button {
                                mostraAggiungi = true
                            } label: {
                                HStack {
                                    Image(systemName: "plus.circle.fill")
                                    Text("Aggiungi articolo")
                                }
                                .font(.title3)
                                .padding(.vertical, 8)
                            }
                        }
                    }
                    .listStyle(.insetGrouped)
                }
            }
            .navigationTitle("Nuova bolletta")
            .navigationBarTitleDisplayMode(.inline)
            .navigationBarItems(
                leading: Button("Annulla") {
                    presentationMode.wrappedValue.dismiss()
                },
                trailing: Button("Salva") {
                    onSave(RigheBolletta(data: data, quantita: quantita))
                }
                .fontWeight(.bold)
            )
        }
        .sheet(isPresented: $mostraAggiungi) {
            AggiungiArticoloView { nome, prezzo in
                let pulito = nome.trimmingCharacters(in: .whitespacesAndNewlines)
                if !pulito.isEmpty && !articoli.contains(where: { $0.nome.caseInsensitiveCompare(pulito) == .orderedSame }) {
                    articoli.append(Articolo(nome: pulito, prezzo: prezzo))
                    quantita[pulito] = 0
                    saveArticles()
                }
                mostraAggiungi = false
            }
        }
    }

    private func saveArticles() {
        if let data = try? JSONEncoder().encode(articoli) {
            UserDefaults.standard.set(data, forKey: "articoli")
        }
    }
}

struct RigaArticolo: View {
    let nome: String
    let prezzo: Double
    @Binding var valore: Int

    var body: some View {
        VStack(alignment: .leading, spacing: 9) {
            HStack {
                Text(nome)
                    .font(.title3)
                    .bold()
                Spacer()
                Text(String(format: "€ %.2f", prezzo))
                    .font(.headline)
                    .foregroundColor(.secondary)
            }

            HStack(spacing: 7) {
                ForEach([0, 1, 2, 3, 4, 5], id: \.self) { n in
                    Button {
                        valore = n
                    } label: {
                        Text("\(n)")
                            .font(.title3)
                            .frame(maxWidth: .infinity, minHeight: 44)
                    }
                    .buttonStyle(.borderedProminent)
                    .tint(valore == n ? .green : .gray)
                }
            }

            HStack {
                Text("Quantità: \(valore)")
                    .font(.headline)
                Spacer()
                Stepper("", value: $valore, in: 0...999)
                    .labelsHidden()
            }
        }
        .padding(.vertical, 7)
    }
}

struct AggiungiArticoloView: View {
    @Environment(\.presentationMode) var presentationMode
    @State private var nome = ""
    @State private var prezzo = ""
    var onSave: (String, Double) -> Void

    var body: some View {
        NavigationView {
            Form {
                Section(header: Text("Nuovo articolo")) {
                    TextField("Nome articolo", text: $nome)
                        .font(.title3)
                    TextField("Prezzo unitario (€)", text: $prezzo)
                        .keyboardType(.decimalPad)
                        .font(.title3)
                }

                Text("Il nome resterà memorizzato e comparirà automaticamente nelle prossime bollette.")
                    .foregroundColor(.secondary)
            }
            .navigationTitle("Aggiungi articolo")
            .navigationBarItems(
                leading: Button("Annulla") {
                    presentationMode.wrappedValue.dismiss()
                },
                trailing: Button("Salva") {
                    let p = Double(prezzo.replacingOccurrences(of: ",", with: ".")) ?? 0
                    onSave(nome, p)
                }
                .disabled(nome.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || (Double(prezzo.replacingOccurrences(of: ",", with: ".")) ?? 0) <= 0)
            )
        }
    }
}
