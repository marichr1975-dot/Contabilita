import SwiftUI

/// Layout dedicato all'iPad.
/// L'iPhone continua a usare ContentView; su iPad evitiamo il vecchio
/// NavigationView a due colonne che lasciava gran parte dello schermo vuota.
struct IPadHomeView: View {
    @StateObject private var archivio = Archivio()
    @Environment(\.scenePhase) private var scenePhase

    @State private var nuovaBolletta = false
    @State private var modificaBolletta = false
    @State private var mostraDatiAnalizzati = false
    @State private var mostraPDF = false
    @State private var pdfImportati = 0

    var body: some View {
        NavigationView {
            GeometryReader { geo in
                ScrollView {
                    VStack(spacing: 0) {
                        header
                            .padding(.top, 34)
                            .padding(.bottom, 30)

                        LazyVGrid(
                            columns: [
                                GridItem(.flexible(), spacing: 20),
                                GridItem(.flexible(), spacing: 20)
                            ],
                            spacing: 20
                        ) {
                            dashboardButton(
                                title: "NUOVA BOLLETTA",
                                subtitle: "Inserisci una nuova giornata di lavoro",
                                icon: "plus.circle.fill",
                                tint: .green
                            ) { nuovaBolletta = true }

                            dashboardButton(
                                title: "MODIFICA BOLLETTA",
                                subtitle: "Apri e modifica una bolletta salvata",
                                icon: "pencil.circle.fill",
                                tint: .blue
                            ) { modificaBolletta = true }

                            dashboardButton(
                                title: "DATI ANALIZZATI",
                                subtitle: "Controlla quantità e riepiloghi",
                                icon: "chart.bar.fill",
                                tint: .purple
                            ) { mostraDatiAnalizzati = true }

                            dashboardButton(
                                title: pdfImportati > 0 ? "PDF AZIENDA  •  \(pdfImportati)" : "IMPORTA PDF AZIENDA",
                                subtitle: "Visualizza i PDF ricevuti dall'azienda",
                                icon: "doc.fill",
                                tint: .teal
                            ) { mostraPDF = true }
                        }
                        .frame(maxWidth: 900)

                        Spacer(minLength: 40)
                    }
                    .frame(minHeight: max(geo.size.height - 20, 600))
                    .frame(maxWidth: .infinity)
                    .padding(.horizontal, 42)
                }
                .background(Color(.systemGroupedBackground).ignoresSafeArea())
            }
            .navigationTitle("Contabilità")
            .navigationBarTitleDisplayMode(.inline)
        }
        .navigationViewStyle(.stack)
        .sheet(isPresented: $nuovaBolletta) {
            NuovaBollettaView(archivio: archivio)
                .navigationViewStyle(.stack)
        }
        .sheet(isPresented: $modificaBolletta) {
            SelezionaDataModificaView(archivio: archivio)
                .navigationViewStyle(.stack)
        }
        .sheet(isPresented: $mostraDatiAnalizzati) {
            DatiAnalizzatiView(archivio: archivio)
                .navigationViewStyle(.stack)
        }
        .sheet(isPresented: $mostraPDF) {
            PDFImportatiView()
                .navigationViewStyle(.stack)
        }
        .onAppear { aggiornaPDF() }
        .onChange(of: scenePhase) { phase in
            if phase == .active { aggiornaPDF() }
        }
    }

    private var header: some View {
        VStack(spacing: 12) {
            Image(systemName: "bag.fill")
                .font(.system(size: 62))
                .foregroundColor(.orange)

            Text("Contabilità")
                .font(.system(size: 38, weight: .bold))

            Text("Gestione delle bollette e delle lavorazioni")
                .font(.title3)
                .foregroundColor(.secondary)
        }
    }

    private func dashboardButton(
        title: String,
        subtitle: String,
        icon: String,
        tint: Color,
        action: @escaping () -> Void
    ) -> some View {
        Button(action: action) {
            HStack(spacing: 18) {
                Image(systemName: icon)
                    .font(.system(size: 38))
                    .foregroundColor(tint)
                    .frame(width: 54)

                VStack(alignment: .leading, spacing: 6) {
                    Text(title)
                        .font(.system(size: 22, weight: .bold))
                        .foregroundColor(.primary)
                        .lineLimit(2)
                        .minimumScaleFactor(0.8)

                    Text(subtitle)
                        .font(.system(size: 16))
                        .foregroundColor(.secondary)
                        .lineLimit(2)
                }

                Spacer(minLength: 8)

                Image(systemName: "chevron.right")
                    .font(.system(size: 18, weight: .semibold))
                    .foregroundColor(.secondary)
            }
            .frame(maxWidth: .infinity, minHeight: 108)
            .padding(.horizontal, 22)
            .background(Color(.secondarySystemGroupedBackground))
            .overlay(
                RoundedRectangle(cornerRadius: 18)
                    .stroke(tint.opacity(0.25), lineWidth: 1)
            )
            .clipShape(RoundedRectangle(cornerRadius: 18))
        }
        .buttonStyle(.plain)
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

struct AdaptiveRootView: View {
    var body: some View {
        Group {
            if UIDevice.current.userInterfaceIdiom == .pad {
                IPadHomeView()
            } else {
                ContentView()
            }
        }
    }
}
