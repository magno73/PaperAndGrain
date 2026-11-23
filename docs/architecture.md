# Architettura

## Flusso

`AlbumPicker` seleziona foto e formato. `PhotoLibrary` chiede a PhotoKit la versione corrente delle immagini. L’import esplicito dal Finder passa per `LocalImages`. `Workspace` salva ogni risorsa in locale e crea il documento. Avvia l’analisi in serie dopo che l’editor è disponibile.

`EditorView` modifica il documento con binding SwiftUI. Un cambio nella foto o nel testo aggiorna la vista. Il salvataggio del manifest è ritardato di poco per evitare scritture ad ogni carattere. `BookPDF` lavora con una copia del documento per mantenere coerente ogni esportazione.

## Pacchetto di libro

Un progetto `.papergrain` ha `manifest.json` e una cartella `assets/` e, se necessario, `looks/`. I nuovi campi della 0.2 sono facoltativi nello schema v1.

| Dato | Responsabilità |
|---|---|
| Libro | ID, titolo, formato in mm, ordine delle pagine e versione dello schema |
| Foto | ID, nome, data di scatto, dimensioni orientate, filename locale e analisi facoltativa |
| Pagina | ID, tipo di composizione, foto nell’ordine di disposizione, titolo e racconto, posizione del testo e inquadratura facoltativa |
| Analisi | Lista di etichette Vision, chiavi stabili dei temi e revisione |
| Pellicola | Profilo del libro, eccezioni per foto e riferimento alla LUT inclusa nel progetto |
| Stampa | Abbondanza, margine, PPI, ordine delle facciate e copertina facoltativa |

Il manifest si sostituisce atomicamente. **Salva progetto** aggiorna il pacchetto esistente. Il primo salvataggio di una bozza e **Salva con nome** copiano il pacchetto nella destinazione scelta e la adottano dopo la scrittura. Il workspace verifica l’identità della cartella durante il salvataggio. Le risorse si risolvono sotto `assets/`. L’app conserva una bozza locale e riapre l’ultimo progetto idoneo quando parte. Cambi che aggiungono dati facoltativi devono poter decodificare i progetti salvati senza quei campi.

## Analisi e associazione dei racconti

`PhotoAnalyzer` usa ImageIO per normalizzare l’orientamento e Vision per classificare la scena. Dopo il filtro di confidenza, conserva le etichette più pertinenti. Associa quelle etichette a temi stabili come `desert`, `wildlife`, `water` e `people`. Le traduzioni dei temi servono all’interfaccia. Il matching usa etichette inglesi e sinonimi comuni in italiano e inglese, con punteggi positivi per le parole o espressioni riscontrate. Il tema descrive ciò che il modello riconosce e va trattato come una proposta. La classificazione corrente non stabilisce dove è stata scattata la foto o chi vi compare.

Le foto arrivate da PhotoKit possono provenire da iCloud. La copia richiede la versione corrente, incluse le modifiche visibili in Foto. La classificazione lavora sulla copia locale e memorizza l’analisi nel documento. Al cambio libro si interrompe la sequenza in corso.

Il pannello Foto riceve anche file trascinati e file promessi da Foto. Li copia in una cartella temporanea e aggiunge alla libreria del progetto le immagini lette correttamente. Il workspace verifica la sessione prima di trasferire gli asset e aggiorna il manifest in una sola scrittura.

L’ispettore calcola i suggerimenti fuori dal thread dell’interfaccia quando cambiano il racconto, gli scatti della pagina o le foto disponibili. Annulla la ricerca precedente se cambia uno di questi dati.

## Geometria e PDF

Le dimensioni del libro sono in millimetri. La geometria della galleria passa per `BookLayoutGeometry` e conserva proporzioni, ordine e interspazi. La prima bozza raggruppa per giorno di scatto. Il [confronto con Fotobuch](layout-comparison.md) documenta la decisione di tenere il layout interno nella 0.2.

Per una foto al vivo, `framing` va da 0 a 1 sull’asse che viene tagliato quando la foto riempie la pagina. Un valore assente equivale a 0,5. Questo campo continua a essere letto quando manca il nuovo ritaglio a due assi. La doppia pagina usa lo stesso rettangolo immagine per entrambi i lati. Il PDF disegna quel rettangolo attraverso due finestre di ritaglio e omette le guide. Core Text mantiene il testo selezionabile. Una foto mancante o un testo che eccede lo spazio interrompono l’export prima della sostituzione del file esistente.

`PageComposition` risolve righe automatiche, cornici manuali, testo e filetti in punti tipografici, dall’alto a sinistra. Le cornici manuali delle foto e dei box di testo usano coordinate normalizzate sul formato al taglio. Una foto posizionata manualmente non occupa uno spazio nella griglia automatica. Il primo spostamento di uno scatto dalla griglia fissa le altre cornici visibili. Lo zoom del canvas moltiplica solo le dimensioni a schermo, mentre il ritaglio della foto controlla l’ingrandimento nel riquadro e l’allineamento su entrambi gli assi, anche per il calcolo della risoluzione di stampa. L’ordine del navigatore corrisponde a `Book.pages`, con ogni panorama rappresentato da una sola voce.

Con un modello di pagina, `PageArrangement` assegna le cornici nell’ordine degli ID della pagina. `PageComposition` condivide i rettangoli con canvas, miniature e PDF. Le foto oltre la capienza rimangono nei dati della pagina. Applicare un modello ripristina le cornici e conserva i ritagli, il racconto e i box. Lo spostamento di una cornice lascia le altre nei rispettivi spazi.

I modelli al vivo distribuiscono le cornici sui bordi del formato e omettono filetti e folio. Il PDF estende in abbondanza le sole cornici che raggiungono il bordo esterno. I confini tra le foto restano condivisi.

I campi `BookPage.arrangement`, `BookPage.photoPlacements`, `BookPage.textBoxes` e `BookCover.backText` sono facoltativi. `BookCoverGeometry` risolve le due facce sia per l’editor sia per `Cover.pdf`. Il retro può contenere testo e foto. Il frontespizio è una pagina di testo interna che si inserisce in testa a `Book.pages`.

Il ritaglio apre una modifica temporanea direttamente sulla pagina. I gesti regolano la foto e la cornice. La conferma applica posizione e ritaglio assieme in una singola operazione annullabile. Le modifiche a schermo non attivano l’app e la messa a fuoco della tastiera resta quella naturale della finestra. I pannelli file si presentano come schede asincrone. Il workspace controlla l’identità del libro e la sua cartella prima di usare il risultato ricevuto da una scheda.

L’aggancio usa la posizione libera a ogni aggiornamento del trascinamento. Cerca bordi e centri delle altre foto e dei box sulla stessa pagina entro sei punti a schermo, indipendentemente dallo zoom, con una guida per asse. Le guide mostrano i riferimenti scelti e scompaiono quando termina l’aggancio. Il progetto conserva solo la posizione finale della cornice.

Lo scambio usa la posizione del puntatore nel canvas e si attiva all’interno di un’altra foto visibile sulla stessa pagina. Il comando scambia cornici e ordine, conserva i ritagli associati agli scatti e si annulla in una sola operazione. Nei modelli a posizioni fisse le cornici automatiche rimangono automatiche. Nelle griglie basate sulle proporzioni si fissano le cornici visibili prima dello scambio.

Il ridimensionamento conserva l’angolo opposto. Le foto mantengono le proporzioni e le maniglie del ritaglio possono agganciare un asse indipendentemente dall’altro. La scorciatoia di eliminazione è legata alla finestra del libro e alla selezione nel canvas. I controlli di testo ricevono i loro eventi di cancellazione. La selezione foto parte dal rilascio del pulsante nella finestra e risolve la posizione visibile nella libreria, sulla pagina o sulla copertina. L’ispettore resta nella modalità aperta.

Le LUT Fujifilm incluse sono risorse sRGB. Il catalogo distingue le LUT per contrasto lineare da quelle per immagini sviluppate con Provia. Alla selezione, il pacchetto riceve la copia CUBE con lo stesso meccanismo di denominazione delle LUT importate. Il render condiviso dell’editor e del PDF continua a leggere la LUT dal pacchetto.

Le miniature usano `PageComposition` per disegnare ogni foto nella cornice e con il ritaglio effettivi. Il navigatore mantiene le pagine affiancate anche in vista singola. Il trascinamento è associato al singolo `BookPage`, compresi i panorami che occupano due pagine fisiche.

I rettangoli delle foto supportano fino a quattro volte le dimensioni della pagina. Il modello conserva una parte raggiungibile della foto sul canvas e applica il taglio solo in visualizzazione e in stampa. I box di testo continuano a usare coordinate interne alla pagina. Il box in scrittura condivide il testo salvato con l’ispettore e con Core Text.

I campi facoltativi delle cornici di titolo, racconto e copertina usano coordinate normalizzate. L’editor offre il trascinamento e il ridimensionamento con maniglie negli angoli e sui lati. La prima modifica alle cornici di una pagina conserva la posizione dell’altro blocco. I campi assenti ricostruiscono le posizioni di partenza dal modello e dalla tipografia. Il rendering usa la larghezza intera delle cornici manuali. Il margine interno dei box indipendenti è configurabile.

Il trascinamento del racconto come gruppo applica lo stesso spostamento al titolo, al testo e alle eventuali cornici dello sfondo. Il riquadro complessivo limita lo spostamento ai bordi della pagina. Le cornici dello sfondo si salvano come coordinate normalizzate e mantengono la posizione durante i trascinamenti dei singoli testi. Le miniature e il PDF usano le stesse cornici.

`BookPhoto.adjustments` è facoltativo nei progetti esistenti. `PhotoAdjustments` misura una copia ridotta della foto per proporre modifiche ripetibili alla luce e al colore. La pipeline condivisa applica le regolazioni allo scatto prima del look pellicola e della grana. Il PDF, l’editor e le miniature usano gli stessi valori. Il file immagine importato resta il riferimento per il confronto.

`EditorPreviewLoader` condivide le richieste uguali e usa cache e code distinte per miniature e anteprime del canvas. Durante il movimento di un cursore, i valori provvisori aggiornano a intervalli la sola anteprima del canvas. Al rilascio, l’editor registra la regolazione nel progetto e carica la versione a piena risoluzione di anteprima.

L’ispettore osserva la propria navigazione. Le coordinate delle miniature in libreria sono rilevate all’interno dell’ispettore e lette al clic. I campioni del pannello Pellicola hanno una coda di render distinta dalle miniature del libro e della libreria.

L’esportazione di stampa usa TrimBox e BleedBox espliciti e incorpora sRGB come output intent. I fogli avviati a destra e i panorami possono richiedere pagine bianche di compensazione. La stampa produce interni e copertina in file separati. Abbondanza e dorso vanno impostati con le specifiche del prodotto scelto.

Il profilo Pixartprinting 21 × 21 cm usa un singolo PDF con la copertina rigida stesa in apertura. Sul piano della copertina, adegua le misure al dorso del preventivo e include cerniere e risvolti. Le facciate interne hanno 3 mm di abbondanza per lato, seguono l’ordine del progetto e restano singole anche nei panorami. L’esportatore mantiene la resa sRGB e la tipografia selezionabile.

## Pellicole

`FilmRenderer` legge l’immagine orientata con ImageIO, la normalizza in sRGB con ColorSync e applica il look o il CUBE 3D/HaldCLUT PNG. L’intensità miscela la resa del look con la scena, la grana aggiunge una variazione ripetibile alla luminanza. Il riquadro originale dell’editor è una modalità temporanea di visione. Il documento salva il look del libro e le eccezioni per foto. La cache di anteprima è limitata e usa immagine, dettaglio del look e risoluzione come chiave. Il PDF rilegge la copia alla risoluzione utile per il formato.

La 0.3 aggiunge il modello facoltativo del libro. Colore della pagina, tipografia, colonna del testo e interspazi escono dai parametri di `BookTemplate.swift`. La zona sicura di stampa imposta il margine minimo. [Modelli editoriali](templates.md) descrive l’applicazione e le anteprime.

Font PostScript, dimensione in punti e allineamento sono campi facoltativi e si ereditano singolarmente. Il modello editoriale dà i valori iniziali. Il libro può ridefinire quelli di titoli e testi. Una pagina può aggiungere modifiche al proprio titolo o racconto. Anche il fronte, il retro e i box possono ridefinire il tipo di testo corrispondente. Core Text applica lo stile risolto nel canvas, nelle miniature e nel PDF. La resa usa il carattere del modello quando il font scelto è assente sul Mac.
