# Paper & Grain

Paper & Grain è un editor nativo per fotolibri di viaggio. Le schermate dell’app sono in italiano e inglese. Il progetto pilota è Namibia. Lavora dalla radice del repository e consulta il [README](README.md) per il flusso utente.

## Punti di ingresso

- `PaperAndGrainApp.swift` e `Workspace.swift` collegano finestre, apertura, autosalvataggio e attività in corso.
- `AlbumPicker.swift` e `PhotoLibrary.swift` collegano selezione, PhotoKit e copia delle immagini.
- `BookModel.swift` e `BookStorage.swift` definiscono i dati, la geometria e il formato dei progetti.
- `EditorView.swift` gestisce il libro aperto, il navigatore, l’ispettore e le interazioni.
- `PhotoAnalysis.swift` produce etichette e temi con Vision e ordina i risultati compatibili con un racconto.
- `BookPDF.swift` esporta la bozza. [Architettura](docs/architecture.md) descrive i contratti fra questi componenti.

I sorgenti Swift sono in `Sources/PaperAndGrain/`. `scripts/build-app.sh` compila e prepara il bundle da collaudare.

## Lavorare per incrementi

Prima di modificare un flusso, leggi la parte pertinente della documentazione e guarda quali viste e file chiamano il codice. Mantieni compatibili i progetti salvati. Una modifica dello schema richiede una strategia di lettura dei progetti precedenti. Controlla gli ID delle pagine e il mantenimento degli elementi quando una foto si sposta o cambia l’impaginazione.

Usa i temi e le etichette come suggerimenti che l’autore può scegliere. L’analisi deve restare sul Mac. Usa immagini sintetiche o materiale di prova autorizzato per commit, screenshot e verifiche ripetibili. Apri gli album reali solo durante un collaudo in cui l’utente può scegliere le foto. Le copie private, i progetti locali e le bozze di testo restano fuori da Git.

Verifica ogni nuova etichetta visibile in IT e EN. Usa il catalogo `Resources/Localizable.xcstrings` quando integri nuovi testi condivisi e verifica anche le etichette di accessibilità. La prima build contiene anche traduzioni nelle viste.

## Verifica e documentazione

- Compila con `./scripts/build-app.sh` e prova il percorso a cui appartiene il cambiamento. Usa il libro dimostrativo per i collaudi senza permessi Foto.
- Per una modifica all’esportazione, apri il PDF risultante e controlla dimensioni, testo lungo, foto a tutta pagina e continuità delle doppie pagine.
- Per una modifica all’analisi, prova almeno un racconto italiano, uno inglese e un testo senza corrispondenze. Verifica che i match suggeriti siano spiegabili dalle etichette e che rimangano modificabili.
- Nello stesso commit di una modifica rilevante, aggiorna il README se cambiano avvio o percorso utente. Aggiorna architettura se cambia un contratto. In `docs/status.md` annota cosa hai verificato e che cosa resta da provare.
- Per il passaggio di consegne registra il risultato osservato e la prossima azione concreta. Inserisci nella documentazione i dettagli tecnici durevoli.

Dai ad Astra decisioni trasversali su modello, colore e stampa. Usa Sol per viste o integrazioni con contratti definiti e verifiche ripetibili.
