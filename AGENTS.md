# Paper & Grain

Paper & Grain è un editor nativo per fotolibri di viaggio. Le schermate dell’app sono in italiano e inglese. Il progetto pilota è Namibia. Lavora dalla radice del repository e consulta il [README](README.md) per il flusso utente.

## Punti di ingresso

- `PaperAndGrainApp.swift` e `Workspace.swift` collegano finestre, apertura, autosalvataggio e attività in corso.
- `AlbumPicker.swift` e `PhotoLibrary.swift` collegano selezione, PhotoKit e copia delle immagini.
- `BookModel.swift` e `BookStorage.swift` definiscono i dati, la geometria e il formato dei progetti.
- `EditorView.swift` gestisce il libro aperto, il navigatore, l’ispettore e le interazioni.
- `PageComposition.swift` risolve cornici, ritagli, testo e copertina in punti tipografici. `CanvasObjectControls.swift` gestisce lo spostamento e il ridimensionamento e `CanvasCropControl.swift` la modifica dell’immagine e della cornice durante il ritaglio. I trascinamenti distinguono foto e pagine.
- `CanvasAlignment.swift` calcola l’aggancio fra foto e box. `CanvasAlignmentGuides.swift` disegna le guide temporanee sul canvas.
- `CanvasDeleteShortcut.swift` gestisce Backspace e Canc nella finestra del libro. `EditorPreviewLoader.swift` separa il carico delle anteprime e delle miniature.
- `EditorFilePanels.swift` presenta i selettori file e il controllo di stampa come schede asincrone della finestra. Gli errori operativi rimangono visibili nella finestra senza richiederne l’attivazione.
- `PhotoAnalysis.swift` produce etichette e temi con Vision e ordina i risultati compatibili con un racconto.
- `BookTemplate.swift` definisce carta, geometria editoriale e tipi condivisi tra anteprima ed esportazione. [Modelli](docs/templates.md) documenta le scelte visive.
- `FilmPipeline.swift` condivide sviluppo colore, LUT e grana tra editor e stampa.
- `PhotoAdjustments.swift` analizza la foto e applica le regolazioni prima del look pellicola. `PhotoAdjustmentsPanel.swift` espone gli stessi valori nell’ispettore.
- `FujifilmFilmLooks.swift` identifica le LUT Fujifilm incluse. Aggiorna catalogo, verifiche di integrità e [attribuzione](Resources/FujifilmFilmLooks/CREDITS.md) insieme alle risorse.
- `BookSettingsView.swift`, `PrintSettings.swift` e `BookPDF.swift` gestiscono formato, copertina, prova e stampa. [Architettura](docs/architecture.md) descrive i contratti fra questi componenti.

I sorgenti Swift sono in `Sources/PaperAndGrain/`. `scripts/build-app.sh` compila e prepara il bundle da collaudare.

## Lavorare per incrementi

Prima di modificare un flusso, leggi la parte pertinente della documentazione e guarda quali viste e file chiamano il codice. Mantieni compatibili i progetti salvati. Una modifica dello schema richiede una strategia di lettura dei progetti precedenti. Controlla gli ID delle pagine e il mantenimento degli elementi quando una foto si sposta o cambia l’impaginazione.

Usa i temi e le etichette come suggerimenti che l’autore può scegliere. L’analisi deve restare sul Mac. Usa immagini sintetiche o materiale di prova autorizzato per commit, screenshot e verifiche ripetibili. Apri gli album reali solo durante un collaudo in cui l’utente può scegliere le foto. Le copie private, i progetti locali e le bozze di testo restano fuori da Git.

Verifica ogni nuova etichetta visibile in IT e EN. Usa il catalogo `Resources/Localizable.xcstrings` quando integri nuovi testi condivisi e verifica anche le etichette di accessibilità. La prima build contiene anche traduzioni nelle viste.

## Verifica e documentazione

- Compila con `./scripts/build-app.sh`, esegui `swift test` e prova il percorso a cui appartiene il cambiamento. Usa il libro dimostrativo per i collaudi senza permessi Foto.
- Per una modifica all’esportazione, apri il PDF risultante e controlla dimensioni, testo lungo, foto a tutta pagina e continuità delle doppie pagine.
- Per una modifica ai gesti, prova una doppia pagina con un box di testo e due foto. Verifica trascinamento, selezione, ridimensionamento, riordino dal navigatore e riapertura del progetto.
- Per una modifica all’analisi, prova almeno un racconto italiano, uno inglese e un testo senza corrispondenze. Verifica che i match suggeriti siano spiegabili dalle etichette e che rimangano modificabili.
- Nello stesso commit di una modifica rilevante, aggiorna il README se cambiano avvio o percorso utente. Aggiorna architettura se cambia un contratto. In `docs/status.md` annota cosa hai verificato e che cosa resta da provare.
- Per il passaggio di consegne registra il risultato osservato e la prossima azione concreta. Inserisci nella documentazione i dettagli tecnici durevoli.

Dai ad Astra decisioni trasversali su modello, colore e stampa. Usa Sol per viste o integrazioni con contratti definiti e verifiche ripetibili.
