# Paper & Grain

Paper & Grain è un editor nativo per fotolibri di viaggio. Le schermate dell’app sono in italiano e inglese. Il progetto pilota è Namibia. Lavora dalla radice del repository e consulta il [README](README.md) per il flusso utente.

## Punti di ingresso

- `PaperAndGrainApp.swift` e `Workspace.swift` collegano finestre, apertura, autosalvataggio e attività in corso.
- `BookCLI.swift` collega composizione e comandi terminale. `BookCLIEditing.swift` applica patch e crea varianti, `BookCLIMedia.swift` gestisce importazione ed export, `BookCLIPhotoIndex.swift` espone il catalogo e la ricerca. Aggiorna il contratto in [CLI](docs/cli.md) quando cambiano argomenti, input o output.
- `AlbumPicker.swift` e `PhotoLibrary.swift` collegano selezione, PhotoKit e copia delle immagini. `DroppedPhotos.swift` importa file nella libreria del libro aperto. `PhotoPromiseDropTarget.swift` riceve i file promessi dalle app macOS.
- `BookModel.swift` e `BookStorage.swift` definiscono i dati, la geometria e il formato dei progetti.
- `EditorView.swift` contiene lo stato del libro aperto, la struttura della finestra e gli strumenti condivisi. Le estensioni `EditorView+*.swift` lo dividono per area: `Navigator` (pagine e riordino), `Canvas` (doppia, HUD, controlli di vista), `Cover`, `Inspector`, `PhotoTray` (fototeca), `Film`, `Adjustments`, `Selection` (clic, tastiera, eliminazione), `PageEditing` (modelli e testi), `PhotoPlacement` (trascinamento, ritaglio, spostamento delle foto), `Commands` (barra, menu del titolo, comandi di menu) e `Browser` (Sfoglia). Lo stato resta nella struttura principale, quindi le estensioni non dichiarano proprietà memorizzate.
- `EditorCommands.swift` definisce le azioni dell’app passate all’editor, i menu Inserisci, Pagina, Foto e Vista (tramite `focusedSceneValue`) e il divisore ridimensionabile. `Theme.swift` raccoglie i colori semantici chiaro/scuro e i pannelli in Liquid Glass con il ripiego a materiali. `BookFormatPresets.swift` elenca i formati predefiniti dei fotolibri senza cambiare lo schema del documento.
- `PageComposition.swift` risolve cornici, ritagli, testo e copertina in punti tipografici. `CanvasObjectControls.swift` gestisce lo spostamento e il ridimensionamento e `CanvasCropControl.swift` la modifica dell’immagine e della cornice durante il ritaglio. Le due facce della copertina usano gli stessi controlli del canvas e conservano separatamente posizione e ritaglio nel documento. `CanvasStoryGroup.swift` sposta insieme titolo, racconto e sfondo.
- `CanvasAlignment.swift` calcola l’aggancio fra foto e box. `CanvasAlignmentGuides.swift` disegna le guide temporanee sul canvas. `CanvasPhotoSwap.swift` individua la foto sotto il puntatore durante il trascinamento e scambia le due cornici.
- `CanvasDeleteShortcut.swift` osserva clic, rotella e tasto destro e inoltra i comandi della tastiera nella finestra del libro. `EditorView+Layers.swift` costruisce il menu contestuale del canvas e cambia l’ordine dei livelli salvato in `BookPage.layerOrder`. La mappa in `EditorPhotoHitTest.swift` usa la geometria di disegno per selezionare l’oggetto visibile. `EditorPreviewLoader.swift` separa il carico delle anteprime e delle miniature.
- `EditorFilePanels.swift` presenta i selettori file e il controllo di stampa come schede asincrone della finestra. Gli errori operativi rimangono visibili nella finestra senza richiederne l’attivazione.
- `InspectorPhotoLibraryCache.swift` filtra la libreria. `PhotoLibraryOrdering.swift` raggruppa le foto per data, luogo, argomento e utilizzo. I luoghi provengono dai metadati locali o dalle foto originali già autorizzate.
- `PhotoAnalysis.swift` produce etichette, rilevamenti e OCR con Vision e ordina i risultati compatibili con un racconto. `PhotoVisualSignals.swift` misura palette, luminosità, contrasto, dettaglio e somiglianza di pixel.
- `BookTemplate.swift` definisce carta, geometria editoriale e tipi condivisi tra anteprima ed esportazione. `EditorialTypography.swift` risolve gli stili del libro e le modifiche locali. `PageArrangement.swift` definisce le composizioni della singola pagina. [Modelli](docs/templates.md) documenta le scelte visive.
- `FilmPipeline.swift` condivide sviluppo colore, LUT e grana tra editor e stampa.
- `PhotoAdjustments.swift` analizza la foto e applica le regolazioni prima del look pellicola. `PhotoAdjustmentsPanel.swift` espone gli stessi valori nell’ispettore.
- `FujifilmFilmLooks.swift` identifica le LUT Fujifilm incluse. Aggiorna catalogo, verifiche di integrità e [attribuzione](Resources/FujifilmFilmLooks/CREDITS.md) insieme alle risorse.
- `BookSettingsView.swift`, `PDFExportChooser.swift`, `PixartPrintProfile.swift` e `BookPDF.swift` gestiscono impostazioni, selezione del profilo, formato e stampa. [Architettura](docs/architecture.md) descrive i contratti fra questi componenti.

I sorgenti Swift sono in `Sources/PaperAndGrain/`. `scripts/build-app.sh` compila e prepara il bundle da collaudare e lo copia sempre in `~/Applications/Paper & Grain Redesign.app`. Indica all’utente quel percorso dopo ogni build.

## Lavorare per incrementi

Prima di modificare un flusso, leggi la parte pertinente della documentazione e guarda quali viste e file chiamano il codice. Mantieni compatibili i progetti salvati. Una modifica dello schema richiede una strategia di lettura dei progetti precedenti. Controlla gli ID delle pagine e il mantenimento degli elementi quando una foto si sposta o cambia l’impaginazione.

Usa i temi e le etichette come suggerimenti che l’autore può scegliere. L’analisi deve restare sul Mac. Usa immagini sintetiche o materiale di prova autorizzato per commit, screenshot e verifiche ripetibili. Apri gli album reali solo durante un collaudo in cui l’utente può scegliere le foto. Le copie private, i progetti locali e le bozze di testo restano fuori da Git.

Verifica ogni nuova etichetta visibile in IT e EN. Usa il catalogo `Resources/Localizable.xcstrings` quando integri nuovi testi condivisi e verifica anche le etichette di accessibilità. La prima build contiene anche traduzioni nelle viste.

## Verifica e documentazione

- Compila con `./scripts/build-app.sh`, esegui `swift test` e prova il percorso a cui appartiene il cambiamento. Usa il libro dimostrativo per i collaudi senza permessi Foto.
- Per una modifica all’esportazione, apri il PDF risultante e controlla dimensioni, testo lungo, foto a tutta pagina e continuità delle doppie pagine.
- Per una modifica ai gesti, prova una doppia pagina con un box di testo e due foto. Verifica trascinamento, selezione, ridimensionamento, riordino dal navigatore e riapertura del progetto.
- Per una modifica all’analisi, prova almeno un racconto italiano, uno inglese e un testo senza corrispondenze. Verifica che i match suggeriti siano spiegabili dalle etichette e che rimangano modificabili.
- Nello stesso commit di una modifica rilevante, aggiorna il README se cambiano avvio o percorso utente. Il README è in inglese e usa le etichette inglesi dell’app. La documentazione in `docs/` resta in italiano. Aggiorna architettura se cambia un contratto. In `docs/status.md` annota cosa hai verificato e che cosa resta da provare.
- Per il passaggio di consegne registra il risultato osservato e la prossima azione concreta. Inserisci nella documentazione i dettagli tecnici durevoli.

Dai ad Astra decisioni trasversali su modello, colore e stampa. Usa Sol per viste o integrazioni con contratti definiti e verifiche ripetibili.
