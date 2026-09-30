CONTABILITA - aggiornamento 30/09/2026

Modifiche:
- NUOVA BOLLETTA apre la fotocamera.
- OCR Vision legge data, numero e quantità degli articoli e propone una schermata di controllo prima del salvataggio.
- La foto originale viene salvata in FotoBollette.
- Il modello Bolletta mantiene compatibilità con le bollette già presenti.
- ANALISI AI sostituisce la vecchia schermata di confronto.
- L'analisi confronta tutte le bollette con il file aziendale e cerca quantità spostate/accorpate nelle date successive.
- Una data mancante nel file aziendale non viene considerata automaticamente come pezzi mancanti se le quantità vengono trovate successivamente.
- FILE AZIENDA resta invariato.
- Aggiunta autorizzazione fotocamera.
- PUSH_CONTABILITA_GITHUB.bat inizializza il repository se necessario e fa push su origin/main.

Nota:
Prima di usare Sideloadly, lascia terminare GitHub Actions e scarica l'IPA unsigned dall'artifact.
