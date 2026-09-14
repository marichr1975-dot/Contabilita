import SwiftUI

@main
struct ContabilitaApp: App {
    var body: some Scene {
        WindowGroup {
            Group {
                if isPad {
                    dashboardPad
                } else {
                    NavigationView {
                        dashboardPhone
                            .navigationTitle("Contabilità")
                            .navigationBarTitleDisplayMode(.inline)
                    }
                    .navigationViewStyle(.stack)
                }
            }
            .sheet(isPresented: $nuovaBolletta) {
                NavigationView {
                    NuovaBollettaView(archivio: archivio)
                }
                .navigationViewStyle(.stack)
            }
            .sheet(isPresented: $modificaBolletta) {
                NavigationView {
                    SelezionaDataModificaView(archivio: archivio)
                }
                .navigationViewStyle(.stack)
            }
            .sheet(isPresented: $mostraDatiAnalizzati) {
                NavigationView {
                    DatiAnalizzatiView(archivio: archivio)
                }
                .navigationViewStyle(.stack)
            }
            .sheet(isPresented: $mostraPDF) {
                NavigationView {
                    PDFLocaliView(store: pdfTransfer)
                }
                .navigationViewStyle(.stack)
            }
            .onAppear { pdfTransfer.importaDaCondividi() }
            .onOpenURL { _ in pdfTransfer.importaDaCondividi() }
            .onChange(of: scenePhase) { phase in
                if phase == .active {
                    pdfTransfer.importaDaCondividi()
                }
            }
        }
    }

    private var dashboardPad: some View {
        GeometryReader { geo in
            ScrollView {
                VStack(spacing: 28) {
                    header

                    LazyVGrid(
                        columns: [
                            GridItem(.flexible(), spacing: 22),
                            GridItem(.flexible(), spacing: 22)
                        ],
                        spacing: 22
                    ) {
                        dashboardButton("NUOVA BOLLETTA", icon: "plus.circle.fill", tint: .green) {
                            nuovaBolletta = true
                        }
                        dashboardButton("MODIFICA BOLLETTA", icon: "pencil.circle.fill", tint: .blue) {
                            modificaBolletta = true
                        }
                        dashboardButton("DATI ANALIZZATI", icon: "chart.bar.fill", tint: .purple) {
                            mostraDatiAnalizzati = true
                        }
                        dashboardButton(
                            pdfTransfer.files.count > 0 ? "PDF AZIENDA  •  \(pdfTransfer.files.count)" : "IMPORTA PDF AZIENDA",
                            icon: "doc.fill",
                            tint: .teal
                        ) {
                            pdfTransfer.importaDaCondividi()
                            mostraPDF = true
                        }
                    }
                    .frame(maxWidth: min(900, geo.size.width - 80))
                }
                .frame(maxWidth: .infinity)
                .padding(.horizontal, 40)
                .padding(.vertical, 34)
            }
        }
    }

    private var dashboardPhone: some View {
        ScrollView {
            VStack(spacing: 16) {
                header
                dashboardButton("NUOVA BOLLETTA", icon: "plus.circle.fill", tint: .green) {
                    nuovaBolletta = true
                }
                dashboardButton("MODIFICA BOLLETTA", icon: "pencil.circle.fill", tint: .blue) {
                    modificaBolletta = true
                }
                dashboardButton("DATI ANALIZZATI", icon: "chart.bar.fill", tint: .purple) {
                    mostraDatiAnalizzati = true
                }
                dashboardButton(
                    pdfTransfer.files.count > 0 ? "PDF AZIENDA  •  \(pdfTransfer.files.count)" : "IMPORTA PDF AZIENDA",
                    icon: "doc.fill",
                    tint: .teal
                ) {
                    pdfTransfer.importaDaCondividi()
                    mostraPDF = true
                }
            }
            .padding(24)
        }
    }

    private var header: some View {
        VStack(spacing: 10) {
            Image(systemName: "bag.fill")
                .font(.system(size: isPad ? 62 : 52))
                .foregroundColor(.orange)
            Text("Contabilità")
                .font(isPad ? .largeTitle : .title)
                .fontWeight(.semibold)
        }
        .padding(.bottom, 8)
    }

    private func dashboardButton(_ title: String, icon: String, tint: Color, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            HStack(spacing: 14) {
                Image(systemName: icon)
                    .font(.system(size: isPad ? 32 : 27))
                    .foregroundColor(tint)

                Text(title)
                    .font(isPad ? .title2 : .title3)
                    .fontWeight(.semibold)
                    .foregroundColor(.primary)
                    .lineLimit(2)
                    .minimumScaleFactor(0.75)

                Spacer(minLength: 8)
                Image(systemName: "chevron.right")
                    .font(.headline)
                    .foregroundColor(.secondary)
            }
            .frame(maxWidth: .infinity, minHeight: isPad ? 118 : 68)
            .padding(.horizontal, 22)
            .background(tint.opacity(0.10))
            .overlay(
                RoundedRectangle(cornerRadius: 18)
                    .stroke(tint.opacity(0.22), lineWidth: 1)
            )
            .cornerRadius(18)
        }
    }
}
